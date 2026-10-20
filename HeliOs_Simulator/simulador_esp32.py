import streamlit as st
import paho.mqtt.client as mqtt
import json
import time
import os
import socket
from datetime import datetime

# --- CONFIGURACIÓN DE PÁGINA ---
st.set_page_config(
    page_title="HeliOs - Simulador ESP32 + PCA9685",
    page_icon="🤖",
    layout="wide"
)

NVS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "esp32_nvs_flash.json")

# ===========================================================
# CONSTANTES DE HARDWARE PCA9685 (50 Hz, 12-bit)
# ===========================================================
# Período de 50 Hz = 20,000 µs
# 4096 ticks = 20,000 µs  ==> ~4.8828 µs por tick
# -60° (Este)           -> 1000 µs (~205 ticks)
#   0° (Estiba Plana)   -> 1500 µs (~307 ticks)
# +60° (Oeste)          -> 2000 µs (~410 ticks)
SAT_MIN_ANGLE = -60.0
SAT_MAX_ANGLE = 60.0
SERVO_TICKS_MIN = 205
SERVO_TICKS_MAX = 410
SERVO_TICKS_CENTER = 307

FALLBACK_SSID = "HeliOs_Setup"
FALLBACK_BROKER = "192.168.4.1"

# ===========================================================
# FUNCIONES NVS FLASH (Simulación en disco)
# ===========================================================
def read_nvs() -> dict:
    if os.path.exists(NVS_FILE):
        try:
            with open(NVS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def write_nvs(data: dict):
    with open(NVS_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def erase_nvs():
    if os.path.exists(NVS_FILE):
        os.remove(NVS_FILE)

# ===========================================================
# INICIALIZACIÓN DE SESSION_STATE
# ===========================================================
if "current_angle" not in st.session_state:
    st.session_state["current_angle"] = 0.0
if "target_angle" not in st.session_state:
    st.session_state["target_angle"] = 0.0
if "is_stow" not in st.session_state:
    st.session_state["is_stow"] = False
if "manual_stow" not in st.session_state:
    st.session_state["manual_stow"] = False
if "mqtt_client" not in st.session_state:
    st.session_state["mqtt_client"] = None
if "mqtt_connected" not in st.session_state:
    st.session_state["mqtt_connected"] = False
if "last_broker_ip" not in st.session_state:
    st.session_state["last_broker_ip"] = "192.168.1.64"
if "auto_loop" not in st.session_state:
    st.session_state["auto_loop"] = True
if "event_logs" not in st.session_state:
    st.session_state["event_logs"] = []

def add_log(msg: str):
    timestamp = datetime.now().strftime("%H:%M:%S")
    st.session_state["event_logs"].insert(0, f"[{timestamp}] {msg}")
    if len(st.session_state["event_logs"]) > 20:
        st.session_state["event_logs"].pop()

# ===========================================================
# CALLBACKS MQTT
# ===========================================================
def on_mqtt_message(client, userdata, msg):
    topic = msg.topic
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        return

    # 1. Sincronización de Wi-Fi desde RPi
    if topic == "helios/esp32/wifi_config":
        ssid = payload.get("ssid", "")
        pwd = payload.get("pass", "")
        broker = payload.get("broker_ip", "")
        if ssid:
            nvs_data = read_nvs()
            nvs_data["ssid"] = ssid
            nvs_data["pass"] = pwd
            if broker:
                nvs_data["broker_ip"] = broker
            nvs_data["last_sync"] = datetime.now().isoformat()
            write_nvs(nvs_data)
            add_log(f"📥 NVS Actualizada por MQTT: SSID='{ssid}', Broker='{broker}'")

    # 2. Coordenadas astronómicas
    elif topic == "helios/spa/coordinates":
        if not st.session_state.get("manual_stow", False):
            if "target_angle" in payload:
                st.session_state["target_angle"] = float(payload["target_angle"])
            elif "motor_angle" in payload:
                st.session_state["target_angle"] = float(payload["motor_angle"])
            
            st.session_state["is_stow"] = bool(payload.get("is_stow", False))
            if st.session_state["is_stow"]:
                st.session_state["target_angle"] = 0.0

    # 3. Comandos de estiba manual
    elif topic == "helios/tracker/command":
        if "manual_stow" in payload:
            m_stow = bool(payload["manual_stow"])
            st.session_state["manual_stow"] = m_stow
            st.session_state["is_stow"] = m_stow
            if m_stow:
                st.session_state["target_angle"] = 0.0
                add_log("🛑 Comando recibido: ESTIBA MANUAL ACTIVADA (0.0°)")
            else:
                add_log("▶️ Comando recibido: ESTIBA MANUAL DESACTIVADA (Retomando seguimiento)")
        elif "target_angle" in payload and not st.session_state.get("is_stow", False):
            st.session_state["target_angle"] = float(payload["target_angle"])

def connect_mqtt(broker_ip: str):
    if (st.session_state["mqtt_client"] is not None
            and st.session_state["last_broker_ip"] == broker_ip
            and st.session_state["mqtt_connected"]):
        return st.session_state["mqtt_client"], True

    if st.session_state["mqtt_client"] is not None:
        try:
            st.session_state["mqtt_client"].loop_stop()
            st.session_state["mqtt_client"].disconnect()
        except Exception:
            pass

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="Simulador_ESP32_PCA9685")
    client.on_message = on_mqtt_message
    try:
        client.connect(broker_ip, 1883, keepalive=10)
        client.subscribe("helios/esp32/wifi_config", qos=1)
        client.subscribe("helios/spa/coordinates", qos=0)
        client.subscribe("helios/tracker/command", qos=1)
        client.loop_start()
        st.session_state["mqtt_client"] = client
        st.session_state["mqtt_connected"] = True
        st.session_state["last_broker_ip"] = broker_ip
        add_log(f"🔌 Conectado al broker MQTT {broker_ip}:1883")
        return client, True
    except Exception as e:
        st.session_state["mqtt_client"] = None
        st.session_state["mqtt_connected"] = False
        return None, False

# ===========================================================
# CÁLCULO DE PCA9685
# ===========================================================
def calculate_pca9685(angle: float):
    clamped = max(SAT_MIN_ANGLE, min(SAT_MAX_ANGLE, angle))
    # Mapeo: -60° -> 205 ticks, 0° -> 307 ticks, +60° -> 410 ticks
    factor = (clamped - SAT_MIN_ANGLE) / (SAT_MAX_ANGLE - SAT_MIN_ANGLE)
    ticks = int(round(SERVO_TICKS_MIN + factor * (SERVO_TICKS_MAX - SERVO_TICKS_MIN)))
    pulse_us = round((ticks / 4096.0) * 20000.0, 1)
    return clamped, ticks, pulse_us

# ===========================================================
# INTERFAZ STREAMLIT
# ===========================================================
st.title("🤖 HeliOs - Simulador Exclusivo ESP32 + PCA9685")
st.caption("Gemelo Digital de Hardware: Emulación NVS Flash, Cinemática de 1 Eje (SAT) y PWM I2C")
st.divider()

# Columnas Principales
col_left, col_right = st.columns([1, 1], gap="large")

# -----------------------------------------------------------
# COLUMNA IZQUIERDA: ESTADO DE RED, NVS Y CONEXIÓN
# -----------------------------------------------------------
with col_left:
    st.subheader("📶 Conexión y Memoria Flash NVS")
    
    nvs = read_nvs()
    has_nvs = bool(nvs.get("ssid"))
    
    if has_nvs:
        current_net_mode = f"Router de Planta: '{nvs['ssid']}'"
        current_broker = nvs.get("broker_ip", st.session_state["last_broker_ip"])
        st.success(f"🌐 **Modo de Red Activo:** {current_net_mode}")
    else:
        current_net_mode = f"Fallback Cautivo: '{FALLBACK_SSID}' (192.168.4.1)"
        current_broker = FALLBACK_BROKER
        st.warning(f"⚠️ **Modo de Red Activo:** {current_net_mode}")

    # Configuración de Broker
    broker_input = st.text_input(
        "Dirección IP del Broker Mosquitto",
        value=current_broker,
        help="Introduce la IP de la Raspberry Pi"
    )

    client, connected = connect_mqtt(broker_input)
    if connected:
        st.success(f"✅ Conectado a Mosquitto en `{broker_input}:1883`")
    else:
        st.error(f"❌ Desconectado de `{broker_input}:1883`. Verifique la IP o el servicio Mosquitto.")

    # Vista de Flash NVS
    st.markdown("#### 💾 Contenido de Flash NVS (`esp32_nvs_flash.json`):")
    st.json(nvs if nvs else {"estado": "MEMORIA FLASH VACÍA (Sin red de planta guardada)"})

    col_btn1, col_btn2 = st.columns([1, 1])
    with col_btn1:
        if st.button("🗑️ Restablecimiento de Fábrica (Borrar NVS)", type="secondary", use_container_width=True):
            erase_nvs()
            add_log("🧹 Memoria NVS borrada. El nodo cae a 'HeliOs_Setup' (192.168.4.1)")
            st.rerun()

    with col_btn2:
        if st.button("🔄 Refrescar NVS", use_container_width=True):
            st.rerun()

    st.divider()
    st.markdown("#### 📜 Registro de Eventos del Microcontrolador")
    st.text_area(
        "Logs en tiempo real",
        value="\n".join(st.session_state["event_logs"]) if st.session_state["event_logs"] else "Esperando eventos...",
        height=150,
        disabled=True
    )

# -----------------------------------------------------------
# COLUMNA DERECHA: ACTUACIÓN PCA9685 Y CINEMÁTICA DEL SAT
# -----------------------------------------------------------
with col_right:
    st.subheader("⚙️ Actuación de 1 Eje (SAT) y PCA9685 (0x40)")

    # Banner de Estado Estiba
    if st.session_state["is_stow"]:
        st.error("🛑 **MODO ESTIBA ACTIVO (0.0° Flat-Stow)** — Paneles en Posición Horizontal de Seguridad")
    else:
        st.info("☀️ **Seguimiento Solar Activo** — Orientando según cálculo astronómico")

    # Controles manuales de simulación
    col_c1, col_c2 = st.columns(2)
    with col_c1:
        sim_step = st.slider("Velocidad de Movimiento (° / paso)", 0.2, 5.0, 1.0, 0.2)
    with col_c2:
        manual_override = st.checkbox("Control Manual de Objetivo", value=False)

    if manual_override:
        nuevo_target = st.slider("Ángulo Objetivo Manual (°)", SAT_MIN_ANGLE, SAT_MAX_ANGLE, float(st.session_state["target_angle"]), 0.5)
        st.session_state["target_angle"] = nuevo_target

    # Cinemática: Mover current_angle hacia target_angle
    target = 0.0 if st.session_state["is_stow"] else st.session_state["target_angle"]
    diff = target - st.session_state["current_angle"]
    motor_moving = abs(diff) > 0.05

    if motor_moving:
        if abs(diff) <= sim_step:
            st.session_state["current_angle"] = target
        else:
            st.session_state["current_angle"] += sim_step if diff > 0 else -sim_step
        st.session_state["current_angle"] = round(st.session_state["current_angle"], 1)

    curr_angle, ticks, pulse_us = calculate_pca9685(st.session_state["current_angle"])
    tgt_angle, tgt_ticks, tgt_pulse = calculate_pca9685(target)

    # Métricas Visuales
    m1, m2, m3 = st.columns(3)
    m1.metric("Ángulo Actual", f"{curr_angle:.1f}°", delta=f"{diff:+.1f}° error" if motor_moving else "En posición")
    m2.metric("Ángulo Objetivo", f"{tgt_angle:.1f}°", delta="0.0° (Estiba)" if st.session_state["is_stow"] else "Seguimiento")
    m3.metric("Estado Motor", "En Movimiento..." if motor_moving else "Estabilizado", delta="PCA9685 OK")

    st.markdown("#### ⚡ Señales de Control PWM PCA9685 (I2C 0x40, Canal 0):")
    p1, p2 = st.columns(2)
    p1.metric("Ticks PWM (12 bits)", f"{ticks} / 4095", delta=f"{ticks - SERVO_TICKS_CENTER:+d} vs 0°")
    p2.metric("Ancho de Pulso", f"{pulse_us:.1f} µs", delta=f"{pulse_us - 1500.0:+.1f} µs vs 1500µs")

    # Barra visual de inclinación (-60° Este a +60° Oeste)
    progress_val = (curr_angle - SAT_MIN_ANGLE) / (SAT_MAX_ANGLE - SAT_MIN_ANGLE)
    st.progress(max(0.0, min(1.0, progress_val)), text=f"Orientación Física: {curr_angle:+.1f}° (Este -60° ── 0° ── +60° Oeste)")

    # Botones directos de estiba manual
    st.divider()
    col_b1, col_b2 = st.columns(2)
    with col_b1:
        if st.button("🛡️ Forzar Estiba Plana (0.0°)", type="primary", use_container_width=True):
            st.session_state["manual_stow"] = True
            st.session_state["is_stow"] = True
            st.session_state["target_angle"] = 0.0
            add_log("🛡️ Estiba forzada desde botones de la interfaz.")
            st.rerun()
    with col_b2:
        if st.button("▶️ Reanudar Seguimiento Solar", type="secondary", use_container_width=True):
            st.session_state["manual_stow"] = False
            st.session_state["is_stow"] = False
            add_log("▶️ Seguimiento normal reanudado.")
            st.rerun()

# ===========================================================
# PUBLICACIÓN DE ESTADO A HELIOS
# ===========================================================
if client and connected:
    status_payload = {
        "current_angle": round(curr_angle, 1),
        "target_angle": round(tgt_angle, 1),
        "is_stow": st.session_state["is_stow"],
        "motor_moving": motor_moving,
        "pca9685_connected": True,
        "pca_ticks": ticks,
        "pulse_us": pulse_us,
        "rssi": -55 if has_nvs else -42,
        "ip": broker_input,
        "network": nvs.get("ssid", FALLBACK_SSID)
    }
    try:
        client.publish("helios/tracker/status", json.dumps(status_payload), qos=0)
    except Exception:
        pass

# ===========================================================
# BUCLE CONTINUO DE SIMULACIÓN
# ===========================================================
st.divider()
col_loop, col_note = st.columns([1, 2])
with col_loop:
    auto_loop = st.toggle("🔄 Ejecución Continua en Tiempo Real", value=st.session_state["auto_loop"])
    st.session_state["auto_loop"] = auto_loop

with col_note:
    st.caption("Cuando la ejecución continua está activa, el simulador interpola la posición del motor y procesa mensajes MQTT cada 200 ms.")

if auto_loop:
    time.sleep(0.2)
    st.rerun()

import streamlit as st
import pandas as pd
import pvlib
import paho.mqtt.client as mqtt
import json
import time
from datetime import datetime

# --- CONFIGURACIÓN DE PÁGINA ---
st.set_page_config(page_title="HeliOs - Simulador HIL", page_icon="☀️", layout="centered")

# ===========================================================
# INICIALIZACIÓN DE SESSION_STATE (antes de cualquier widget)
# ===========================================================
if "simulacion_activa" not in st.session_state:
    st.session_state["simulacion_activa"] = False
if "mqtt_client" not in st.session_state:
    st.session_state["mqtt_client"] = None
if "mqtt_connected" not in st.session_state:
    st.session_state["mqtt_connected"] = False
if "spa_data" not in st.session_state:
    st.session_state["spa_data"] = {}
if "last_rpi_ip" not in st.session_state:
    st.session_state["last_rpi_ip"] = "192.168.1.64"

# Diccionario SunSpec para interfaz manual
SUNSPEC_ERRORS = {
    0:  "0: Operación Normal",
    1:  "1: Sobrevoltaje de Red",
    13: "13: Fuga a Tierra Detectada",
    14: "14: Sobrecalentamiento del Inversor"
}

# ===========================================================
# CLIENTE MQTT PERSISTENTE
# ===========================================================
def _on_spa_message(client, userdata, msg):
    """Captura el tópico helios/spa/expected para sincronizar valores esperados."""
    try:
        data = json.loads(msg.payload.decode('utf-8'))
        st.session_state["spa_data"] = data
    except Exception:
        pass

def get_or_create_mqtt_client(ip: str):
    """
    Devuelve el cliente MQTT persistente ya conectado,
    o crea uno nuevo si la IP cambió o aún no existe.
    """
    if (st.session_state["mqtt_client"] is not None
            and st.session_state["last_rpi_ip"] == ip
            and st.session_state["mqtt_connected"]):
        return st.session_state["mqtt_client"], True, ""

    # Desconectar cliente anterior si existe
    old = st.session_state.get("mqtt_client")
    if old is not None:
        try:
            old.loop_stop()
            old.disconnect()
        except Exception:
            pass

    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        client.on_message = _on_spa_message
        client.connect(ip, 1883, 10)
        client.subscribe("helios/spa/expected", 0)
        client.loop_start()
        st.session_state["mqtt_client"] = client
        st.session_state["mqtt_connected"] = True
        st.session_state["last_rpi_ip"] = ip
        return client, True, ""
    except OSError as e:
        st.session_state["mqtt_client"] = None
        st.session_state["mqtt_connected"] = False
        return None, False, f"Fallo de conexión MQTT ({ip}:1883): {e}"
    except Exception as e:
        st.session_state["mqtt_client"] = None
        st.session_state["mqtt_connected"] = False
        return None, False, f"Error MQTT inesperado: {e}"

def publish_telemetry(ip, payload):
    """Publica telemetría usando el cliente persistente."""
    client, connected, err = get_or_create_mqtt_client(ip)
    if not connected:
        return False, err
    try:
        msg = client.publish("helios/inverter/telemetry", json.dumps(payload))
        msg.wait_for_publish(timeout=5.0)
        return True, "Datos inyectados al Cerebro Energético."
    except Exception as e:
        st.session_state["mqtt_connected"] = False
        return False, f"Error publicando: {e}"

# --- INTERFAZ GRÁFICA INDUSTRIAL ---
st.title("☀️ Gemelo Digital: Inversor")
st.markdown("### Banco de Pruebas HIL - Planta C&I (5kW)")
st.divider()

st.subheader("📡 Conexión a la Red Local")
# IP predeterminada: 192.168.1.64
rpi_ip = st.text_input("Dirección IP de la Raspberry Pi",
                        value=st.session_state["last_rpi_ip"])

# Intento de conexión al cambiar IP
if rpi_ip != st.session_state["last_rpi_ip"]:
    st.session_state["last_rpi_ip"] = rpi_ip
    st.session_state["mqtt_connected"] = False

# Indicador de estado de conexión
_, ok, conn_err = get_or_create_mqtt_client(rpi_ip)
if ok:
    st.success(f"✅ Broker MQTT conectado en {rpi_ip}:1883")
else:
    st.warning(f"⚠️ {conn_err} — Verifica que Mosquitto esté corriendo en la RPi.")

st.divider()
st.subheader("⚙️ Parámetros de Operación")
modo = st.radio(
    "Seleccione el comportamiento de simulación:",
    ("Modo Automático Continuo (Clear Sky)", "Modo Manual (Inyección de Fallas)")
)

# ===========================================================
# MODO AUTOMÁTICO
# ===========================================================
if modo == "Modo Automático Continuo (Clear Sky)":
    st.info("Calculando irradiancia teórica y publicando telemetría automáticamente cada 2 segundos.")

    simulacion_activa = st.toggle(
        "▶️ INICIAR TRANSMISIÓN CONTINUA",
        value=st.session_state["simulacion_activa"],
        key="_toggle_auto"
    )
    st.session_state["simulacion_activa"] = simulacion_activa

    # Coordenadas locales de respaldo
    LAT, LON, TZ = 19.68, -99.01, 'America/Mexico_City'

    # --- Sincronizar con helios/spa/expected si está disponible ---
    spa_data = st.session_state.get("spa_data", {})
    if spa_data.get("ghi") is not None:
        ghi    = float(spa_data["ghi"])
        is_night = bool(spa_data.get("is_night", False))
    else:
        # Cálculo local con hora de México
        now = pd.Timestamp.now(tz=TZ)
        loc = pvlib.location.Location(LAT, LON, tz=TZ)
        cs  = loc.get_clearsky(pd.DatetimeIndex([now]))
        ghi = float(cs['ghi'].iloc[0])
        is_night = ghi <= 10.0

    # Escala Realista (~5000W)
    v_dc    = round(400.0 + (ghi / 1000.0) * 100.0, 2) if ghi > 0 else 0.0
    i_dc    = round((ghi / 1000.0) * 10.0,          2) if ghi > 0 else 0.0
    power_w = round(v_dc * i_dc, 2)

    # Muestra visual
    col1, col2, col3 = st.columns(3)
    col1.metric("Potencia (W)",  f"{power_w} W")
    col2.metric("Voltaje DC",    f"{v_dc} V")
    col3.metric("Corriente DC",  f"{i_dc} A")

    if is_night:
        st.info("🌙 Modo Nocturno detectado — enviando telemetría de estiba (0 W).")

    # BUCLE DE INYECCIÓN CONTINUA
    if simulacion_activa:
        temp_c    = round(25.0 + (ghi / 1000.0) * 35.0, 1) if ghi > 0 else 25.0
        yield_kwh = round(power_w * (2 / 3600000.0), 4)

        payload = {
            "inverter":  1,
            "v_dc":      v_dc,
            "i_dc":      i_dc,
            "power_w":   power_w,
            "temp_c":    temp_c,
            "yield_kwh": yield_kwh,
            "fault":     0,
        }

        success, msg_txt = publish_telemetry(rpi_ip, payload)

        if success:
            st.toast("📡 Transmitiendo telemetría en tiempo real...", icon="✅")
        else:
            st.error(msg_txt)

        # Simula el muestreo físico del hardware y recarga la UI
        time.sleep(2)
        st.rerun()

# ===========================================================
# MODO MANUAL
# ===========================================================
else:
    st.markdown("Utiliza los controles para simular sombras densas o estresar el Traductor SCADA.")
    # Asegurar que el modo automático quede detenido al cambiar de modo
    st.session_state["simulacion_activa"] = False

    v_dc    = st.slider("Voltaje DC (V)",   min_value=0.0, max_value=600.0, value=450.0, step=0.1)
    i_dc    = st.slider("Corriente DC (A)", min_value=0.0, max_value=20.0,  value=9.5,   step=0.1)
    power_w = round(v_dc * i_dc, 2)

    st.info(f"⚡ Potencia Activa Resultante: **{power_w} W**")

    st.divider()
    st.subheader("🚨 Inyección de Códigos Modbus")
    falla_seleccionada = st.selectbox(
        "Seleccione un error SunSpec para inyectar a la base de datos:",
        options=list(SUNSPEC_ERRORS.keys()),
        format_func=lambda x: SUNSPEC_ERRORS[x],
    )

    temp_c_manual = st.slider("Temperatura DC (°C)", min_value=20.0, max_value=90.0, value=45.0, step=0.5)

    payload = {
        "inverter":  1,
        "v_dc":      v_dc,
        "i_dc":      i_dc,
        "power_w":   power_w,
        "temp_c":    temp_c_manual,
        "yield_kwh": 0.0,
        "fault":     int(falla_seleccionada),
    }

    if st.button("🚀 Publicar Falla Manual", type="primary", use_container_width=True):
        success, msg_txt = publish_telemetry(rpi_ip, payload)
        if success:
            st.success("Trama Modbus inyectada exitosamente. Revisa el historial SQLite en tu Raspberry.")
        else:
            st.error(msg_txt)

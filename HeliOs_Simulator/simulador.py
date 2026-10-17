import streamlit as st
import pandas as pd
import pvlib
import paho.mqtt.client as mqtt
import json
import time
import random
from datetime import datetime, timezone, timedelta

# --- CONFIGURACIÓN DE PÁGINA ---
st.set_page_config(
    page_title="HeliOs - Simulador HIL",
    page_icon="☀️",
    layout="centered"
)

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
if "yield_kwh" not in st.session_state:
    st.session_state["yield_kwh"] = 125.40

# Diccionario SunSpec para interfaz manual
SUNSPEC_ERRORS = {
    0:  "0: Operación Normal",
    1:  "1: Sobrevoltaje de Red",
    13: "13: Fuga a Tierra Detectada",
    14: "14: Sobrecalentamiento del Inversor",
}

# Fallback de configuración de paneles
PANEL_FALLBACK = {
    "voc": 49.6, "isc": 14.0, "wp": 550.0,
    "serie": 18, "paralelo": 4,
    "latitud": 19.68, "longitud": -99.01,
}
TZ_OFFSET = timezone(timedelta(hours=-6))

# ===========================================================
# CLIENTE MQTT PERSISTENTE
# ===========================================================
def _on_spa_message(client, userdata, msg):
    """Captura helios/spa/expected para sincronizar valores del SPA."""
    try:
        data = json.loads(msg.payload.decode('utf-8'))
        st.session_state["spa_data"] = data
    except Exception:
        pass

def get_or_create_mqtt_client(ip: str):
    """
    Devuelve el cliente MQTT persistente ya conectado,
    o crea uno nuevo si la IP cambió o aún no existe.
    Solo suscribe a helios/spa/expected — NUNCA publica en helios/spa/#.
    """
    if (st.session_state["mqtt_client"] is not None
            and st.session_state["last_rpi_ip"] == ip
            and st.session_state["mqtt_connected"]):
        return st.session_state["mqtt_client"], True, ""

    # Desconectar cliente anterior
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
        # Solo lectura del SPA — el simulador NUNCA publica en helios/spa/#
        client.subscribe("helios/spa/expected", 0)
        client.loop_start()
        st.session_state["mqtt_client"]   = client
        st.session_state["mqtt_connected"] = True
        st.session_state["last_rpi_ip"]   = ip
        return client, True, ""
    except OSError as e:
        st.session_state["mqtt_client"]   = None
        st.session_state["mqtt_connected"] = False
        return None, False, f"Fallo de conexión MQTT ({ip}:1883): {e}"
    except Exception as e:
        st.session_state["mqtt_client"]   = None
        st.session_state["mqtt_connected"] = False
        return None, False, f"Error MQTT inesperado: {e}"

def publish_inverter_telemetry(ip: str, payload: dict):
    """Publica EXCLUSIVAMENTE en helios/inverter/telemetry."""
    client, connected, err = get_or_create_mqtt_client(ip)
    if not connected:
        return False, err
    try:
        msg = client.publish("helios/inverter/telemetry", json.dumps(payload))
        msg.wait_for_publish(timeout=5.0)
        return True, "Datos inyectados al broker."
    except Exception as e:
        st.session_state["mqtt_connected"] = False
        return False, f"Error publicando: {e}"

# ===========================================================
# CÁLCULO LOCAL DE IRRADIANCIA (fallback si no hay broker)
# ===========================================================
def calcular_ghi_local():
    """Cálculo astronómico local con hora de México UTC-6 sin dependencias externas."""
    now = pd.Timestamp(datetime.now(TZ_OFFSET))
    loc = pvlib.location.Location(
        PANEL_FALLBACK["latitud"], PANEL_FALLBACK["longitud"], tz=-6
    )
    cs  = loc.get_clearsky(pd.DatetimeIndex([now]))
    return float(cs['ghi'].iloc[0])

# ===========================================================
# INTERFAZ
# ===========================================================
st.title("☀️ Gemelo Digital: Inversor SunSpec")
st.markdown("### Banco de Pruebas HIL — Simulador de Inversor C&I (5 kW)")
st.divider()

st.subheader("📡 Conexión a la Red Local")
rpi_ip = st.text_input(
    "Dirección IP de la Raspberry Pi",
    value=st.session_state["last_rpi_ip"],
)

if rpi_ip != st.session_state["last_rpi_ip"]:
    st.session_state["last_rpi_ip"]    = rpi_ip
    st.session_state["mqtt_connected"] = False

_, ok, conn_err = get_or_create_mqtt_client(rpi_ip)
if ok:
    st.success(f"✅ Broker MQTT conectado en {rpi_ip}:1883")
else:
    st.warning(f"⚠️ {conn_err} — Verifica que Mosquitto esté corriendo en la RPi.")

st.divider()
st.subheader("⚙️ Parámetros de Operación")
modo = st.radio(
    "Seleccione el comportamiento de simulación:",
    ("Modo Automático Continuo (Clear Sky)", "Modo Manual (Inyección de Fallas)"),
)

# ===========================================================
# MODO AUTOMÁTICO
# ===========================================================
if modo == "Modo Automático Continuo (Clear Sky)":
    st.info(
        "Simula el inversor publicando en `helios/inverter/telemetry` al ~96 % "
        "de los valores esperados por la Raspberry Pi, cada 2 segundos."
    )

    simulacion_activa = st.toggle(
        "▶️ INICIAR TRANSMISIÓN CONTINUA",
        value=st.session_state["simulacion_activa"],
        key="_toggle_auto",
    )
    st.session_state["simulacion_activa"] = simulacion_activa

    # --- Obtener GHI: primero desde el SPA de la RPi, luego cálculo local ---
    spa_data = st.session_state.get("spa_data", {})

    if spa_data.get("ghi") is not None:
        ghi      = float(spa_data["ghi"])
        v_exp    = float(spa_data.get("v_exp", 0.0))
        i_exp    = float(spa_data.get("i_exp", 0.0))
        p_exp    = float(spa_data.get("p_exp", 0.0))
        is_night = bool(spa_data.get("is_night", False))
        fuente   = "🔗 Datos sincronizados con la Raspberry Pi"
    else:
        ghi      = calcular_ghi_local()
        is_night = ghi <= 10.0
        voc      = PANEL_FALLBACK["voc"]
        isc      = PANEL_FALLBACK["isc"]
        serie    = PANEL_FALLBACK["serie"]
        paralelo = PANEL_FALLBACK["paralelo"]
        v_exp    = voc * serie if ghi > 0 else 0.0
        i_exp    = isc * paralelo * (ghi / 1000.0) if ghi > 0 else 0.0
        p_exp    = v_exp * i_exp
        fuente   = "⚙️ Datos calculados localmente (RPi sin conexión)"

    st.caption(fuente)

    # Valores simulados del inversor al ~96 % con variación aleatoria ±1 %
    if not is_night and ghi > 0:
        factor = 0.96 * (1.0 + random.uniform(-0.01, 0.01))
        v_dc    = round(v_exp * factor, 2)
        i_dc    = round(i_exp * factor, 2)
        power_w = round(v_dc * i_dc,   2)
    else:
        v_dc    = 0.0
        i_dc    = 0.0
        power_w = 0.0

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Potencia Sim. (W)",  f"{power_w} W",
                delta=f"Esp: {round(p_exp, 0)} W")
    col2.metric("Voltaje DC Sim.",    f"{v_dc} V",
                delta=f"Esp: {round(v_exp, 1)} V")
    col3.metric("Corriente DC Sim.",  f"{i_dc} A",
                delta=f"Esp: {round(i_exp, 2)} A")
    col4.metric("Energía Acum.",      f"{st.session_state['yield_kwh']:.2f} kWh",
                delta="Dinámico")

    if is_night:
        st.info("🌙 Modo Nocturno — Enviando 0 W, 0 V, 0 A al broker.")

    if simulacion_activa:
        temp_c = round(25.0 + (ghi / 1000.0) * 35.0, 1) if ghi > 0 else 25.0
        
        # Incremento acumulativo visible para demostración de tesis
        if power_w > 0:
            incremento = (power_w * (2.0 / 3600.0) / 1000.0) + 0.01
            st.session_state["yield_kwh"] = round(st.session_state["yield_kwh"] + incremento, 2)

        payload = {
            "inverter":  1,
            "v_dc":      v_dc,
            "i_dc":      i_dc,
            "power_w":   power_w,
            "temp_c":    temp_c,
            "yield_kwh": round(st.session_state["yield_kwh"], 2),
            "fault":     0,
        }

        success, msg_txt = publish_inverter_telemetry(rpi_ip, payload)

        if success:
            st.toast(f"📡 Telemetría enviada: {power_w} W | {st.session_state['yield_kwh']:.2f} kWh", icon="✅")
        else:
            st.error(msg_txt)

        time.sleep(2)
        st.rerun()

# ===========================================================
# MODO MANUAL
# ===========================================================
else:
    st.markdown(
        "Inyecta valores específicos o códigos de falla SunSpec "
        "para probar el traductor SCADA."
    )
    st.session_state["simulacion_activa"] = False

    v_dc = st.slider("Voltaje DC (V)",   min_value=0.0, max_value=600.0, value=450.0, step=0.1)
    i_dc = st.slider("Corriente DC (A)", min_value=0.0, max_value=20.0,  value=9.5,   step=0.1)
    power_w = round(v_dc * i_dc, 2)

    st.info(f"⚡ Potencia Activa Resultante: **{power_w} W**")

    st.divider()
    st.subheader("🚨 Inyección de Códigos Modbus / SunSpec")
    falla_seleccionada = st.selectbox(
        "Seleccione un error SunSpec para inyectar:",
        options=list(SUNSPEC_ERRORS.keys()),
        format_func=lambda x: SUNSPEC_ERRORS[x],
    )

    temp_c_manual = st.slider(
        "Temperatura DC (°C)", min_value=20.0, max_value=90.0, value=45.0, step=0.5
    )

    kwh_manual = st.number_input(
        "Energía Acumulada (kWh) - Ajustable",
        min_value=0.0,
        max_value=100000.0,
        value=float(st.session_state["yield_kwh"]),
        step=0.1,
    )
    st.session_state["yield_kwh"] = round(kwh_manual, 2)

    if st.button("🚀 Publicar Falla Manual / Telemetría", type="primary", use_container_width=True):
        # En cada envío manual sumamos un incremento acumulativo
        st.session_state["yield_kwh"] = round(st.session_state["yield_kwh"] + 0.05, 2)

        payload = {
            "inverter":  1,
            "v_dc":      v_dc,
            "i_dc":      i_dc,
            "power_w":   power_w,
            "temp_c":    temp_c_manual,
            "yield_kwh": round(st.session_state["yield_kwh"], 2),
            "fault":     int(falla_seleccionada),
        }

        success, msg_txt = publish_inverter_telemetry(rpi_ip, payload)
        if success:
            st.success(
                f"Trama SunSpec inyectada: Falla {falla_seleccionada} | {power_w} W | {st.session_state['yield_kwh']:.2f} kWh. "
                "Revisa la HMI y el historial SQLite en la Raspberry Pi."
            )
        else:
            st.error(msg_txt)

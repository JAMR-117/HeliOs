import streamlit as st
import pandas as pd
import pvlib
import paho.mqtt.client as mqtt
import json
import time
from datetime import datetime

# --- CONFIGURACIÓN DE PÁGINA ---
st.set_page_config(page_title="HeliOs - Simulador HIL", page_icon="☀️", layout="centered")

# Diccionario SunSpec para interfaz manual
SUNSPEC_ERRORS = {
    0: "0: Operación Normal",
    1: "1: Sobrevoltaje de Red",
    13: "13: Fuga a Tierra Detectada",
    14: "14: Sobrecalentamiento del Inversor"
}

def publish_telemetry(ip, payload):
    """Función robusta de envío MQTT con confirmación (wait_for_publish)."""
    try:
        # Uso estricto de la API v1 para Paho-MQTT 2.0+
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
        client.connect(ip, 1883, 5)
        
        # Hilo de red en segundo plano para procesar la confirmación del broker
        client.loop_start() 
        
        msg = client.publish("helios/inverter/telemetry", json.dumps(payload))
        msg.wait_for_publish() # Candado para asegurar entrega
        
        client.loop_stop()
        client.disconnect()
        return True, "Datos inyectados al Cerebro Energético."
    except Exception as e:
        return False, f"Fallo de conexión MQTT: {str(e)}"

# --- INTERFAZ GRÁFICA INDUSTRIAL ---
st.title("☀️ Gemelo Digital: Inversor")
st.markdown("### Banco de Pruebas HIL - Planta C&I (5kW)")
st.divider()

st.subheader("📡 Conexión a la Red Local")
rpi_ip = st.text_input("Dirección IP de la Raspberry Pi", value="192.168.4.1")

st.divider()
st.subheader("⚙️ Parámetros de Operación")
modo = st.radio(
    "Seleccione el comportamiento de simulación:",
    ("Modo Automático Continuo (Clear Sky)", "Modo Manual (Inyección de Fallas)")
)

if modo == "Modo Automático Continuo (Clear Sky)":
    st.info("Calculando irradiancia teórica y publicando telemetría automáticamente cada 2 segundos.")
    
    simulacion_activa = st.toggle("▶️ INICIAR TRANSMISIÓN CONTINUA", value=False)
    
    # Coordenadas locales de respaldo
    LAT, LON, TZ = 19.68, -99.01, 'America/Mexico_City'
    now = pd.Timestamp(datetime.now(), tz=TZ)
    loc = pvlib.location.Location(LAT, LON, tz=TZ)
    
    # Cálculo astronómico en tiempo real
    cs = loc.get_clearsky(pd.DatetimeIndex([now]))
    ghi = cs['ghi'].iloc[0]
    
    # Carga Realista (~5000W): Escalamos el Voltaje DC a 500V max y la Corriente a 10A max.
    v_dc = round(400.0 + (ghi / 1000.0) * 100.0, 2) if ghi > 0 else 0.0
    i_dc = round((ghi / 1000.0) * 10.0, 2) if ghi > 0 else 0.0
    power_w = round(v_dc * i_dc, 2)
    
    # Muestra visual
    col1, col2, col3 = st.columns(3)
    col1.metric("Potencia (W)", f"{power_w} W")
    col2.metric("Voltaje DC", f"{v_dc} V")
    col3.metric("Corriente DC", f"{i_dc} A")
    
    # BUCLE DE INYECCIÓN CONTINUA
    if simulacion_activa:
        payload = {
            "inverter": 1,
            "power_w": power_w,
            "v_dc": v_dc,
            "i_dc": i_dc,
            "fault": 0
        }
        
        success, msg = publish_telemetry(rpi_ip, payload)
        
        if success:
            st.toast("📡 Transmitiendo telemetría en tiempo real...", icon="✅")
        else:
            st.error(msg)
            
        # Simula el muestreo físico del hardware y recarga la UI
        time.sleep(2)
        st.rerun()

else:
    st.markdown("Utiliza los controles para simular sombras densas o estresar el Traductor SCADA.")
    
    # Sliders para alteración manual
    v_dc = st.slider("Voltaje DC (V)", min_value=0.0, max_value=600.0, value=450.0, step=0.1)
    i_dc = st.slider("Corriente DC (A)", min_value=0.0, max_value=20.0, value=9.5, step=0.1)
    power_w = round(v_dc * i_dc, 2)
    
    st.info(f"⚡ Potencia Activa Resultante: **{power_w} W**")
    
    st.divider()
    st.subheader("🚨 Inyección de Códigos Modbus")
    falla_seleccionada = st.selectbox(
        "Seleccione un error SunSpec para inyectar a la base de datos:",
        options=list(SUNSPEC_ERRORS.keys()),
        format_func=lambda x: SUNSPEC_ERRORS[x]
    )
    
    payload = {
        "inverter": 1,
        "power_w": power_w,
        "v_dc": v_dc,
        "i_dc": i_dc,
        "fault": int(falla_seleccionada)
    }
    
    if st.button("🚀 Publicar Falla Manual", type="primary", use_container_width=True):
        success, msg = publish_telemetry(rpi_ip, payload)
        if success:
            st.success("Trama Modbus inyectada exitosamente. Revisa el historial SQLite en tu Raspberry.")
        else:
            st.error(msg)

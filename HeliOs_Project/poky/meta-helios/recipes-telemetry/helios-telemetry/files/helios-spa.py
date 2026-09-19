import time, json, sys, types
import requests
import pandas as pd

# 1. BYPASS DE INGENIERÍA: Engañar a pvlib creando módulos fantasma de scipy
sys.modules['scipy'] = types.ModuleType('scipy')
sys.modules['scipy.constants'] = types.ModuleType('scipy.constants')

# Ahora podemos importar pvlib de forma segura en nuestro Read-Only RootFS
import pvlib
import paho.mqtt.client as mqtt
from datetime import datetime, timezone

# 2. EXTRACCIÓN DE PARÁMETROS FÍSICOS (Fase 5)
def read_panel_config():
    """Lee el ADN de la planta guardado por el Portal Cautivo."""
    try:
        with open('/data/wifi_config.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        # Failsafe con los valores de la planta C&I simulada de 40kW
        print("Advertencia: JSON no encontrado. Usando valores fotovoltaicos de respaldo.")
        return {"voc": 49.6, "isc": 14.0, "wp": 550.0, "serie": 18, "paralelo": 4}

conf = read_panel_config()

# 3. GEOLOCALIZACIÓN DINÁMICA
def obtener_coordenadas():
    """Detecta la IP pública del módem industrial."""
    try:
        res = requests.get("http://ip-api.com/json/", timeout=5).json()
        print(f"Coordenadas auto-detectadas: {res['lat']}, {res['lon']}")
        return res['lat'], res['lon']
    except Exception:
        print("Fallo de red. Usando coordenadas locales de respaldo.")
        return 19.68, -99.01 # Ojo de Agua, Mex

LAT, LON = obtener_coordenadas()

# 4. INICIALIZACIÓN MQTT (API v1 para Paho 2.0+)
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
client.connect("127.0.0.1", 1883, 60)
client.loop_start()

# 5. BUCLE DE EDGE COMPUTING (Fase 3)
print("Iniciando motor analítico SPA y Clear Sky...")

while True:
    now = pd.Timestamp(datetime.now(timezone.utc))
    loc = pvlib.location.Location(LAT, LON)
    
    # Cálculos astronómicos y teóricos
    cs = loc.get_clearsky(pd.DatetimeIndex([now]))
    solpos = loc.get_solarposition(pd.DatetimeIndex([now]))
    
    ghi = cs['ghi'].iloc[0]
    azimuth = float(solpos['azimuth'].iloc[0])
    elevation = float(solpos['elevation'].iloc[0])
    
    # Inferencia matemática basada en la Irradiancia (GHI) y el arreglo de paneles
    v_exp = float(conf.get('voc', 49.6)) * int(conf.get('serie', 18)) if ghi > 0 else 0.0
    i_exp = float(conf.get('isc', 14.0)) * int(conf.get('paralelo', 4)) * (ghi / 1000.0) if ghi > 0 else 0.0
    p_exp = v_exp * i_exp
    
    # Empaquetado de la telemetría esperada
    payload = {
        "azimuth": round(azimuth, 2), 
        "elevation": round(elevation, 2),
        "v_exp": round(v_exp, 2), 
        "i_exp": round(i_exp, 2), 
        "p_exp": round(p_exp, 2)
    }
    
    print(f"Publicando expectativas: {payload}")
    client.publish("helios/spa/expected", json.dumps(payload))
    
    # Recalcular exactamente cada 60 segundos
    time.sleep(60)

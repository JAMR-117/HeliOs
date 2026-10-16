import sys
import types
from unittest.mock import MagicMock
import json
import time
import pandas as pd
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------
# 1. BYPASS DEFINITIVO DE DEPENDENCIAS PESADAS (MOCKING)
# ---------------------------------------------------------
sys.modules['h5py'] = MagicMock()

class PaqueteFantasma(types.ModuleType):
    def __init__(self, name):
        super().__init__(name)
        self.__path__ = []
        self.__version__ = '1.10.0'
    def __getattr__(self, name):
        return MagicMock()

scipy_mock = PaqueteFantasma('scipy')
sys.modules['scipy'] = scipy_mock

submodulos_scipy = [
    'constants', 'optimize', 'integrate', 'interpolate', 
    'spatial', 'spatial.transform', 'spatial.distance',
    'stats', 'sparse', 'special', 'linalg', 'ndimage', 'fft'
]

for sub in submodulos_scipy:
    nombre_completo = f"scipy.{sub}"
    mock_pkg = PaqueteFantasma(nombre_completo)
    sys.modules[nombre_completo] = mock_pkg
    partes = sub.split('.')
    if len(partes) == 1:
        setattr(scipy_mock, partes[0], mock_pkg)
    elif len(partes) == 2:
        padre_mock = getattr(scipy_mock, partes[0], None)
        if padre_mock:
            setattr(padre_mock, partes[1], mock_pkg)

# Importación segura post-mock
import pvlib
import paho.mqtt.client as mqtt

# ---------------------------------------------------------
# 2. ZONA HORARIA DE MÉXICO (CST / UTC-6)
# ---------------------------------------------------------
TZ_MEXICO = 'America/Mexico_City'

# ---------------------------------------------------------
# 3. LÓGICA PRINCIPAL (HELIOS SPA & FORECAST)
# ---------------------------------------------------------
def read_panel_config():
    # Toma los datos desde la red de aprovisionamiento de HeliOs
    try:
        with open('/data/wifi_config.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {"voc": 45.0, "isc": 9.0, "wp": 550.0, "serie": 10, "paralelo": 2, "latitud": 19.68, "longitud": -99.01}

def generar_pronostico_10_dias(loc, config):
    """Calcula la curva de irradiancia futura y la guarda como JSON para Flutter."""
    # Hora actual en México — evita el desfase UTC vs local
    ahora = pd.Timestamp.now(tz=TZ_MEXICO)
    # Iniciar desde la hora actual redondeada hacia abajo (hora completa)
    inicio = ahora.floor('h')
    # Vector de tiempo: 10 días (240 horas) en hora local de México
    tiempos_futuros = pd.date_range(start=inicio, periods=240, freq='1h', tz=TZ_MEXICO)
    cs_futuro = loc.get_clearsky(tiempos_futuros, model='haurwitz')
    
    pronostico = []
    for t, ghi in zip(tiempos_futuros, cs_futuro['ghi']):
        if ghi > 0:
            v = float(config.get('voc', 45)) * int(config.get('serie', 10))
            i = float(config.get('isc', 9)) * int(config.get('paralelo', 2)) * (ghi / 1000.0)
            p = v * i
        else:
            p = 0.0
            
        pronostico.append({
            # ISO con offset local (-06:00) para que Flutter muestre la hora real
            "hora": t.isoformat(),
            "p_exp": round(p, 2),
            "ghi": round(float(ghi), 2)
        })
        
    with open('/data/forecast.json', 'w') as f:
        json.dump(pronostico, f)
    print("Pronóstico de 10 días generado en /data/forecast.json")

def main():
    conf = read_panel_config()
    LAT = float(conf.get("latitud", 19.68))
    LON = float(conf.get("longitud", -99.01))
    
    # Location con zona horaria de México explícita
    loc = pvlib.location.Location(LAT, LON, tz=TZ_MEXICO)
    
    # 1. Generar la predicción inicial para el Dashboard
    generar_pronostico_10_dias(loc, conf)
    
    # 2. Configuración MQTT (API V2)
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    try:
        client.connect("127.0.0.1", 1883, 60)
        client.loop_start()
    except Exception as e:
        print(f"Error de conexión MQTT: {e}")
        return

    last_forecast_time = time.monotonic()
    prev_epoch = time.time()

    # 3. Bucle en tiempo real — cada 10s para respuesta rápida al arranque
    while True:
        try:
            now = pd.Timestamp.now(tz=TZ_MEXICO)
            cs = loc.get_clearsky(pd.DatetimeIndex([now]), model='haurwitz')
            solpos = loc.get_solarposition(pd.DatetimeIndex([now]))

            ghi      = float(cs['ghi'].iloc[0])
            azimuth   = float(solpos['azimuth'].iloc[0])
            elevation = float(solpos['elevation'].iloc[0])

            v_exp = float(conf.get('voc', 45)) * int(conf.get('serie', 10)) if ghi > 0 else 0.0
            i_exp = float(conf.get('isc', 9)) * int(conf.get('paralelo', 2)) * (ghi / 1000.0) if ghi > 0 else 0.0
            p_exp = v_exp * i_exp

            # --- Modo Estiba Nocturna (Flat-Stow) ---
            is_night = elevation <= 0 or ghi <= 10.0
            if is_night:
                motor_azimuth   = 180.0
                motor_elevation = 90.0
            else:
                motor_azimuth   = round(azimuth, 2)
                motor_elevation = round(elevation, 2)

            # Payload con campos de motor y bandera is_night
            payload_expected = {
                "azimuth":          round(azimuth, 2),
                "elevation":        round(elevation, 2),
                "v_exp":            round(v_exp, 2),
                "i_exp":            round(i_exp, 2),
                "p_exp":            round(p_exp, 2),
                "ghi":              round(ghi, 2),
                "is_night":         is_night,
                "motor_azimuth":    motor_azimuth,
                "motor_elevation":  motor_elevation,
            }
            # retain=True para que Flutter reciba datos al instante al conectarse
            client.publish("helios/spa/expected", json.dumps(payload_expected), retain=True)
            
            payload_coords = {
                "azimuth":         round(azimuth, 2),
                "elevation":       round(elevation, 2),
                "is_night":        is_night,
                "motor_azimuth":   motor_azimuth,
                "motor_elevation": motor_elevation,
            }
            client.publish("helios/spa/coordinates", json.dumps(payload_coords), retain=True)

        except Exception as e:
            print(f"Error en el ciclo principal: {e}")

        # --- Regeneración del pronóstico cada 15 minutos o si el reloj saltó > 2 min ---
        now_epoch = time.time()
        elapsed   = time.monotonic() - last_forecast_time
        clock_jump = abs(now_epoch - prev_epoch - 10) > 120  # salto > 2 min

        if elapsed >= 900 or clock_jump:
            try:
                generar_pronostico_10_dias(loc, conf)
                last_forecast_time = time.monotonic()
            except Exception as e:
                print(f"Error regenerando pronóstico: {e}")

        prev_epoch = now_epoch
        time.sleep(10)  # Ciclo rápido: 10 segundos

if __name__ == "__main__":
    main()

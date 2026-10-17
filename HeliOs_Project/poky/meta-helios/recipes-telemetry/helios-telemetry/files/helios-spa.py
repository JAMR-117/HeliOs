import sys
import types
from unittest.mock import MagicMock
import json
import time
import urllib.request
import subprocess
import email.utils
import traceback
import os
import pandas as pd
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------
# 1. BYPASS DEFINITIVO DE DEPENDENCIAS PESADAS (MOCKING)
# REGLA DE ORO: MANTENER INTACTO EL SISTEMA PaqueteFantasma
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
# 2. ZONA HORARIA Y UBICACIÓN BLINDADAS (SIN DEPENDER DE tzdata)
# ---------------------------------------------------------
# Offset matemático infalible de -6 horas (México Central / UTC-6)
TZ_OFFSET = timezone(timedelta(hours=-6))

# Caché de ubicación geográfica para no bloquear el bucle si no hay red
LOCATION_CACHE = {
    "lat": 19.68,
    "lon": -99.01,
    "synced": False
}

def get_location_coordinates(conf):
    """
    Obtiene coordenadas geográficas de forma resiliente:
    1. Si wifi_config.json tiene latitud/longitud válidas.
    2. Si no, intenta consultar ip-api.com con timeout=3s una sola vez y lo guarda en caché.
    3. Si falla o no hay conexión, fallback a Ojo de Agua, EdoMex (19.68, -99.01).
    """
    try:
        lat = float(conf.get("latitud") or conf.get("lat") or 0.0)
        lon = float(conf.get("longitud") or conf.get("lon") or 0.0)
        if lat != 0.0 and lon != 0.0:
            LOCATION_CACHE["lat"] = lat
            LOCATION_CACHE["lon"] = lon
            LOCATION_CACHE["synced"] = True
            return lat, lon
    except Exception:
        pass

    if LOCATION_CACHE["synced"]:
        return LOCATION_CACHE["lat"], LOCATION_CACHE["lon"]

    try:
        req = urllib.request.Request(
            "http://ip-api.com/json/",
            headers={"User-Agent": "HeliOs-SPA/1.0"}
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if data.get("status") == "success":
                lat = float(data.get("lat", 19.68))
                lon = float(data.get("lon", -99.01))
                LOCATION_CACHE["lat"] = lat
                LOCATION_CACHE["lon"] = lon
                LOCATION_CACHE["synced"] = True
                print(f"[HeliOs SPA] Coordenadas obtenidas via IP: lat={lat}, lon={lon}")
                return lat, lon
    except Exception as e:
        print(f"[HeliOs SPA] Fallback a coordenadas por defecto (19.68, -99.01): {e}")

    return LOCATION_CACHE["lat"], LOCATION_CACHE["lon"]

# ---------------------------------------------------------
# 3. SINCRONIZACIÓN DE RELOJ POR HTTP
# ---------------------------------------------------------
def sync_system_clock_if_needed():
    """
    Intenta sincronizar el reloj del sistema via header HTTP Date de Google o ip-api.
    Retorna True si el reloj fue actualizado. No lanza excepciones.
    """
    urls_to_try = [
        ('http://www.google.com', 3),
        ('http://ip-api.com/json/', 3)
    ]
    for url, t_out in urls_to_try:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "HeliOs-ClockSync/1.0"})
            with urllib.request.urlopen(req, timeout=t_out) as resp:
                date_header = resp.headers.get('Date', '')
                if date_header:
                    dt = email.utils.parsedate_to_datetime(date_header)
                    date_str = dt.strftime('%Y-%m-%d %H:%M:%S')
                    subprocess.run(
                        ['date', '-u', '-s', date_str],
                        check=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                    print(f"[HeliOs SPA] Reloj sincronizado exitosamente a {date_str} UTC via {url}")
                    return True
        except Exception:
            continue
    return False

# ---------------------------------------------------------
# 4. LECTURA DE CONFIGURACIÓN DE PANELES
# ---------------------------------------------------------
def read_panel_config():
    """
    Lee los datos desde /data/wifi_config.json con valores seguros por defecto.
    Valores por defecto de planta: voc: 49.6, isc: 14.0, wp: 550.0, serie: 18, paralelo: 4.
    """
    defaults = {
        "voc": 49.6,
        "isc": 14.0,
        "wp": 550.0,
        "serie": 18,
        "paralelo": 4,
        "latitud": 19.68,
        "longitud": -99.01
    }
    try:
        if os.path.exists('/data/wifi_config.json'):
            with open('/data/wifi_config.json', 'r') as f:
                loaded = json.load(f)
                if isinstance(loaded, dict):
                    for k, v in defaults.items():
                        if k not in loaded or loaded[k] is None or loaded[k] == 0:
                            loaded[k] = v
                    return loaded
    except Exception as e:
        print(f"[HeliOs SPA] Error leyendo /data/wifi_config.json: {e}")
    return defaults

# ---------------------------------------------------------
# 5. GENERACIÓN DEL PRONÓSTICO (10 DÍAS)
# ---------------------------------------------------------
def generar_pronostico_10_dias(loc, config):
    """
    Calcula la curva de irradiancia futura y la guarda como JSON para Flutter.
    Usa offset de -6 horas puro sin depender de tzdata de Linux.
    """
    try:
        os.makedirs('/data', exist_ok=True)
        ahora_mx = datetime.now(TZ_OFFSET)
        ahora_pd = pd.Timestamp(ahora_mx).floor('h')

        tiempos_futuros = pd.date_range(
            start=ahora_pd, periods=240, freq='1h'
        )
        cs_futuro = loc.get_clearsky(tiempos_futuros, model='haurwitz')

        voc = float(config.get('voc') or 49.6)
        isc = float(config.get('isc') or 14.0)
        serie = int(config.get('serie') or 18)
        paralelo = int(config.get('paralelo') or 4)

        pronostico = []
        for t, ghi in zip(tiempos_futuros, cs_futuro['ghi']):
            ghi_f = float(ghi)
            if ghi_f > 0:
                v = voc * serie
                i = isc * paralelo * (ghi_f / 1000.0)
                p = v * i
            else:
                p = 0.0

            t_dt = t.to_pydatetime()
            pronostico.append({
                "timestamp_epoch": int(t_dt.timestamp()),
                "hora": t_dt.isoformat(),
                "hora_str": t_dt.strftime("%H:00"),
                "fecha_str": t_dt.strftime("%d/%m"),
                "p_exp": round(p, 2),
                "ghi": round(ghi_f, 2),
            })

        with open('/data/forecast.json', 'w') as f:
            json.dump(pronostico, f)
        try:
            os.chmod('/data/forecast.json', 0o666)
        except Exception:
            pass
        print(f"[HeliOs SPA] Pronóstico de 10 días generado en /data/forecast.json ({len(pronostico)} horas)")
    except Exception as e:
        print(f"[HeliOs SPA] Error generando pronostico: {e}")
        traceback.print_exc()

# ---------------------------------------------------------
# 6. BUCLE PRINCIPAL BLINDADO
# ---------------------------------------------------------
def main():
    os.makedirs('/data', exist_ok=True)

    # Intento inicial de sincronización de reloj
    sync_system_clock_if_needed()

    conf = read_panel_config()
    LAT, LON = get_location_coordinates(conf)

    # Location con offset numérico explícito tz=-6
    loc = pvlib.location.Location(LAT, LON, tz=-6)

    # Generación inicial del pronóstico
    generar_pronostico_10_dias(loc, conf)

    # Configuración de cliente MQTT con reconexión robusta
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    mqtt_conectado = False
    for attempt in range(10):
        try:
            client.connect("127.0.0.1", 1883, 60)
            client.loop_start()
            mqtt_conectado = True
            print("[HeliOs SPA] Conectado a Mosquitto exitosamente.")
            break
        except Exception as e:
            print(f"[HeliOs SPA] Intento {attempt+1}/10 - Esperando a Mosquitto (127.0.0.1:1883): {e}")
            time.sleep(2)

    if not mqtt_conectado:
        # Si Mosquitto aún no inicia, client.connect_async o loop diferido
        try:
            client.connect_async("127.0.0.1", 1883, 60)
            client.loop_start()
        except Exception as e:
            print(f"[HeliOs SPA] Conexión asíncrona MQTT: {e}")

    last_forecast_time = time.monotonic()
    prev_epoch = time.time()

    # Bucle infinito protegido contra cualquier excepción
    while True:
        try:
            conf = read_panel_config()
            LAT, LON = get_location_coordinates(conf)
            loc = pvlib.location.Location(LAT, LON, tz=-6)

            ahora_mx = datetime.now(TZ_OFFSET)
            now = pd.Timestamp(ahora_mx)

            cs = loc.get_clearsky(pd.DatetimeIndex([now]), model='haurwitz')
            solpos = loc.get_solarposition(pd.DatetimeIndex([now]))

            ghi = float(cs['ghi'].iloc[0])
            azimuth = float(solpos['azimuth'].iloc[0])
            elevation = float(solpos['elevation'].iloc[0])

            voc = float(conf.get('voc') or 49.6)
            isc = float(conf.get('isc') or 14.0)
            serie = int(conf.get('serie') or 18)
            paralelo = int(conf.get('paralelo') or 4)

            # Cálculo de valores esperados
            if ghi > 0.0:
                v_exp = voc * serie
                i_exp = isc * paralelo * (ghi / 1000.0)
                p_exp = v_exp * i_exp
            else:
                v_exp = 0.0
                i_exp = 0.0
                p_exp = 0.0

            # Modo Estiba Nocturna (Flat-Stow)
            is_night = elevation <= 0 or ghi <= 10.0
            if is_night:
                motor_azimuth = 180.0
                motor_elevation = 90.0
            else:
                motor_azimuth = round(azimuth, 2)
                motor_elevation = round(elevation, 2)

            payload_expected = {
                "azimuth": round(azimuth, 2),
                "elevation": round(elevation, 2),
                "v_exp": round(v_exp, 2),
                "i_exp": round(i_exp, 2),
                "p_exp": round(p_exp, 2),
                "ghi": round(ghi, 2),
                "is_night": is_night,
                "motor_azimuth": motor_azimuth,
                "motor_elevation": motor_elevation,
                "system_time": ahora_mx.strftime("%H:%M"),
                "system_time_full": ahora_mx.strftime("%H:%M:%S"),
            }
            client.publish("helios/spa/expected", json.dumps(payload_expected), retain=True)

            payload_coords = {
                "azimuth": round(azimuth, 2),
                "elevation": round(elevation, 2),
                "is_night": is_night,
                "motor_azimuth": motor_azimuth,
                "motor_elevation": motor_elevation,
            }
            client.publish("helios/spa/coordinates", json.dumps(payload_coords), retain=True)

        except Exception as e:
            print(f"[HeliOs SPA] Error en el ciclo principal: {e}")
            traceback.print_exc()

        # Regenerar pronóstico cada 15 min o ante saltos bruscos de reloj
        try:
            now_epoch = time.time()
            elapsed = time.monotonic() - last_forecast_time
            clock_jump = abs(now_epoch - prev_epoch - 10) > 120

            if elapsed >= 900 or clock_jump:
                reloj_actualizado = sync_system_clock_if_needed()
                generar_pronostico_10_dias(loc, conf)
                last_forecast_time = time.monotonic()
                if reloj_actualizado:
                    print("[HeliOs SPA] Pronóstico actualizado tras sincronización horaria.")
            prev_epoch = now_epoch
        except Exception as e:
            print(f"[HeliOs SPA] Error en verificación de pronóstico: {e}")
            traceback.print_exc()

        time.sleep(10)

if __name__ == "__main__":
    main()

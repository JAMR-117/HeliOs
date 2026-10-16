import sys
import types
from unittest.mock import MagicMock
import json
import time
import urllib.request
import subprocess
import email.utils
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
# 2. ZONA HORARIA FIJA DE MÉXICO (UTC-6) — SIN depender de /etc/localtime
# ---------------------------------------------------------
TZ_MEXICO_OFFSET = timezone(timedelta(hours=-6))   # objeto timedelta puro
TZ_MEXICO_STR    = 'Etc/GMT+6'                     # string para pvlib/pandas

# ---------------------------------------------------------
# 3. SINCRONIZACIÓN DE RELOJ POR HTTP
# ---------------------------------------------------------
def sync_system_clock_if_needed():
    """
    Intenta sincronizar el reloj del sistema via header HTTP Date de Google.
    Retorna True si el reloj fue actualizado (para regenerar el pronóstico
    inmediatamente).  No lanza excepciones.
    """
    try:
        now_year = datetime.now(timezone.utc).year
        if now_year >= 2026:
            return False   # El reloj ya parece correcto
        resp = urllib.request.urlopen('http://www.google.com', timeout=5)
        date_header = resp.headers.get('Date', '')
        if not date_header:
            return False
        dt = email.utils.parsedate_to_datetime(date_header)
        date_str = dt.strftime('%Y-%m-%d %H:%M:%S')
        subprocess.run(['date', '-u', '-s', date_str], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(f"[HeliOs SPA] Reloj sincronizado a {date_str} UTC")
        return True
    except Exception as e:
        print(f"[HeliOs SPA] No se pudo sincronizar reloj: {e}")
        return False

# ---------------------------------------------------------
# 4. LECTURA DE CONFIGURACIÓN DE PANELES
# ---------------------------------------------------------
def read_panel_config():
    """Lee los datos desde la red de aprovisionamiento de HeliOs."""
    try:
        with open('/data/wifi_config.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {
            "voc": 45.0, "isc": 9.0, "wp": 550.0,
            "serie": 10, "paralelo": 2,
            "latitud": 19.68, "longitud": -99.01
        }

# ---------------------------------------------------------
# 5. GENERACIÓN DEL PRONÓSTICO 10 DÍAS
# ---------------------------------------------------------
def generar_pronostico_10_dias(loc, config):
    """
    Calcula la curva de irradiancia futura y la guarda como JSON para Flutter.
    Incluye campos pre-formateados en hora de México para que Flutter
    NO necesite .toLocal() (el OS Yocto está en UTC puro).
    """
    # Hora actual con offset fijo UTC-6 (no depende de /etc/localtime)
    ahora_mx = datetime.now(TZ_MEXICO_OFFSET)
    ahora_pd = pd.Timestamp(ahora_mx).floor('h')

    # Vector de tiempo: 240 horas desde ahora, con tz Etc/GMT+6
    tiempos_futuros = pd.date_range(
        start=ahora_pd, periods=240, freq='1h', tz=TZ_MEXICO_STR
    )
    cs_futuro = loc.get_clearsky(tiempos_futuros, model='haurwitz')

    pronostico = []
    for t, ghi in zip(tiempos_futuros, cs_futuro['ghi']):
        ghi_f = float(ghi)
        if ghi_f > 0:
            v = float(config.get('voc', 45)) * int(config.get('serie', 10))
            i = float(config.get('isc', 9)) * int(config.get('paralelo', 2)) * (ghi_f / 1000.0)
            p = v * i
        else:
            p = 0.0

        # t es un Timestamp con tz Etc/GMT+6 → convierte a datetime aware
        t_dt = t.to_pydatetime()
        pronostico.append({
            # epoch: número entero de segundos UTC — sin ambigüedad de zona horaria
            "timestamp_epoch": int(t_dt.timestamp()),
            # ISO con offset -06:00 incluido
            "hora":      t_dt.isoformat(),
            # Strings pre-formateados en hora local de México (para la UI de Flutter)
            "hora_str":  t_dt.strftime("%H:00"),
            "fecha_str": t_dt.strftime("%d/%m"),
            "p_exp":     round(p, 2),
            "ghi":       round(ghi_f, 2),
        })

    with open('/data/forecast.json', 'w') as f:
        json.dump(pronostico, f)
    print("[HeliOs SPA] Pronóstico de 10 días generado en /data/forecast.json")

# ---------------------------------------------------------
# 6. BUCLE PRINCIPAL
# ---------------------------------------------------------
def main():
    # Sincronizar reloj antes de cualquier cálculo astronómico
    sync_system_clock_if_needed()

    conf = read_panel_config()
    LAT = float(conf.get("latitud", 19.68))
    LON = float(conf.get("longitud", -99.01))

    # Location con zona horaria de México explícita
    loc = pvlib.location.Location(LAT, LON, tz=TZ_MEXICO_STR)

    # Generar la predicción inicial para el Dashboard
    generar_pronostico_10_dias(loc, conf)

    # Configuración MQTT (API V2)
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    try:
        client.connect("127.0.0.1", 1883, 60)
        client.loop_start()
    except Exception as e:
        print(f"[HeliOs SPA] Error de conexión MQTT: {e}")
        return

    last_forecast_time = time.monotonic()
    prev_epoch         = time.time()

    # Bucle en tiempo real — cada 10 s para respuesta rápida al arranque
    while True:
        try:
            # Re-leer config en cada ciclo (por si el usuario cambió paneles)
            conf = read_panel_config()
            LAT  = float(conf.get("latitud", 19.68))
            LON  = float(conf.get("longitud", -99.01))
            loc  = pvlib.location.Location(LAT, LON, tz=TZ_MEXICO_STR)

            now = pd.Timestamp(datetime.now(TZ_MEXICO_OFFSET))
            cs     = loc.get_clearsky(pd.DatetimeIndex([now]), model='haurwitz')
            solpos = loc.get_solarposition(pd.DatetimeIndex([now]))

            ghi       = float(cs['ghi'].iloc[0])
            azimuth   = float(solpos['azimuth'].iloc[0])
            elevation = float(solpos['elevation'].iloc[0])

            v_exp = float(conf.get('voc', 45)) * int(conf.get('serie', 10))  if ghi > 0 else 0.0
            i_exp = float(conf.get('isc', 9))  * int(conf.get('paralelo', 2)) * (ghi / 1000.0) if ghi > 0 else 0.0
            p_exp = v_exp * i_exp

            # --- Modo Estiba Nocturna (Flat-Stow) ---
            is_night = elevation <= 0 or ghi <= 10.0
            if is_night:
                motor_azimuth   = 180.0
                motor_elevation = 90.0
            else:
                motor_azimuth   = round(azimuth, 2)
                motor_elevation = round(elevation, 2)

            payload_expected = {
                "azimuth":         round(azimuth, 2),
                "elevation":       round(elevation, 2),
                "v_exp":           round(v_exp, 2),
                "i_exp":           round(i_exp, 2),
                "p_exp":           round(p_exp, 2),
                "ghi":             round(ghi, 2),
                "is_night":        is_night,
                "motor_azimuth":   motor_azimuth,
                "motor_elevation": motor_elevation,
            }
            # retain=True → Flutter recibe datos al instante al conectarse
            client.publish("helios/spa/expected",    json.dumps(payload_expected), retain=True)

            payload_coords = {
                "azimuth":         round(azimuth, 2),
                "elevation":       round(elevation, 2),
                "is_night":        is_night,
                "motor_azimuth":   motor_azimuth,
                "motor_elevation": motor_elevation,
            }
            client.publish("helios/spa/coordinates", json.dumps(payload_coords), retain=True)

        except Exception as e:
            print(f"[HeliOs SPA] Error en el ciclo principal: {e}")

        # --- Regenerar pronóstico cada 15 min, o si el reloj saltó > 2 min ---
        now_epoch  = time.time()
        elapsed    = time.monotonic() - last_forecast_time
        clock_jump = abs(now_epoch - prev_epoch - 10) > 120  # salto > 2 min

        if elapsed >= 900 or clock_jump:
            # Intentar re-sincronizar reloj si el año sigue siendo incorrecto
            reloj_actualizado = sync_system_clock_if_needed()
            try:
                generar_pronostico_10_dias(loc, conf)
                last_forecast_time = time.monotonic()
                if reloj_actualizado:
                    print("[HeliOs SPA] Pronóstico regenerado tras sincronización de reloj.")
            except Exception as e:
                print(f"[HeliOs SPA] Error regenerando pronóstico: {e}")

        prev_epoch = now_epoch
        time.sleep(10)  # Ciclo rápido: 10 segundos

if __name__ == "__main__":
    main()

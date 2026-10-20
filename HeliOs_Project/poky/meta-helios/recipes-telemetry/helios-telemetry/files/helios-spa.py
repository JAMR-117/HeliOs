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
import threading
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
# 2. ZONA HORARIA Y UBICACIÓN BLINDADAS
# ---------------------------------------------------------
TZ_OFFSET = timezone(timedelta(hours=-6))

LOCATION_CACHE = {
    "lat": 19.6800,
    "lon": -99.0100,
    "city": "Ojo de Agua, EdoMex",
    "synced": False
}

LOCATION_CACHE_FILE = '/data/location_cache.json'

def save_location_cache(lat, lon, city):
    """
    Persiste lat, lon y city en un archivo dedicado /data/location_cache.json
    mediante escritura atómica (tmp + os.replace).
    helios-spa.py NUNCA escribe ni modifica /data/wifi_config.json.
    """
    try:
        os.makedirs('/data', exist_ok=True)
        tmp_file = f"{LOCATION_CACHE_FILE}.tmp"
        data = {
            "lat": lat,
            "lon": lon,
            "latitud": lat,
            "longitud": lon,
            "city": city,
            "ubicacion": city
        }
        with open(tmp_file, 'w') as f:
            json.dump(data, f, indent=2)
        try:
            os.chmod(tmp_file, 0o666)
        except Exception:
            pass
        os.replace(tmp_file, LOCATION_CACHE_FILE)
        print(f"[HeliOs SPA] Coordenadas persistidas en caché: {lat}, {lon} ({city})")
    except Exception as e:
        print(f"[HeliOs SPA] Error al persistir location_cache: {e}")

def get_location_coordinates(conf, fetch_network_timeout=None):
    """
    Obtiene coordenadas geográficas de forma resiliente y 100% en modo lectura:
    1. Si conf (/data/wifi_config.json) tiene latitud/longitud válidas.
    2. Si no, busca en /data/location_cache.json.
    3. Si fetch_network_timeout > 0, consulta ip-api.com y guarda en /data/location_cache.json.
    4. Fallback a Ojo de Agua, EdoMex (19.6800, -99.0100).
    """
    try:
        lat_c = conf.get("lat") or conf.get("latitud")
        lon_c = conf.get("lon") or conf.get("longitud")
        city_c = conf.get("ubicacion") or conf.get("city")
        if lat_c is not None and lon_c is not None:
            lat = float(lat_c)
            lon = float(lon_c)
            if lat != 0.0 and lon != 0.0:
                LOCATION_CACHE["lat"] = lat
                LOCATION_CACHE["lon"] = lon
                if city_c:
                    LOCATION_CACHE["city"] = str(city_c)
                LOCATION_CACHE["synced"] = True
                if fetch_network_timeout is None:
                    return LOCATION_CACHE["lat"], LOCATION_CACHE["lon"], LOCATION_CACHE["city"]
    except Exception:
        pass

    # Si no están en conf, buscar en location_cache.json
    if not LOCATION_CACHE["synced"] and os.path.exists(LOCATION_CACHE_FILE):
        try:
            with open(LOCATION_CACHE_FILE, 'r') as f:
                l_data = json.load(f)
                lat_l = float(l_data.get("lat", 0.0))
                lon_l = float(l_data.get("lon", 0.0))
                city_l = l_data.get("city") or l_data.get("ubicacion")
                if lat_l != 0.0 and lon_l != 0.0:
                    LOCATION_CACHE["lat"] = lat_l
                    LOCATION_CACHE["lon"] = lon_l
                    if city_l:
                        LOCATION_CACHE["city"] = str(city_l)
                    LOCATION_CACHE["synced"] = True
                    if fetch_network_timeout is None:
                        return LOCATION_CACHE["lat"], LOCATION_CACHE["lon"], LOCATION_CACHE["city"]
        except Exception:
            pass

    if fetch_network_timeout is not None and fetch_network_timeout > 0:
        try:
            req = urllib.request.Request(
                "http://ip-api.com/json/",
                headers={"User-Agent": "HeliOs-SPA/1.0"}
            )
            with urllib.request.urlopen(req, timeout=fetch_network_timeout) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                if data.get("status") == "success":
                    lat = float(data.get("lat", 19.6800))
                    lon = float(data.get("lon", -99.0100))
                    city = data.get("city") or data.get("regionName") or "Ojo de Agua, EdoMex"
                    LOCATION_CACHE["lat"] = lat
                    LOCATION_CACHE["lon"] = lon
                    LOCATION_CACHE["city"] = city
                    LOCATION_CACHE["synced"] = True
                    save_location_cache(lat, lon, city)
                    print(f"[HeliOs SPA] Coordenadas obtenidas via IP: lat={lat}, lon={lon}, ubicacion={city}")
                    return lat, lon, city
        except Exception as e:
            print(f"[HeliOs SPA] ip-api no disponible ({e}). Usando coordenadas de caché o fallback.")

    return LOCATION_CACHE["lat"], LOCATION_CACHE["lon"], LOCATION_CACHE["city"]

# ---------------------------------------------------------
# 3. METEOROLOGÍA REAL (OPEN-METEO WMO)
# ---------------------------------------------------------
WEATHER_CACHE_FILE = '/data/weather_cache.json'
WEATHER_CACHE = {
    "current": {"weather_code": 0, "cloud_cover": 0, "wind_kmh": 12.0},
    "hourly": {},
    "timestamp": 0.0
}

def clasificar_clima(ghi, weather_code, cloud_cover):
    """
    Clasifica el clima en 7 estados para la interfaz:
    - sunny (Día despejado, WMO 0, 1)
    - partly_cloudy (Día parcialmente nublado, WMO 2)
    - cloudy (Nublado / Niebla, WMO 3, 45, 48)
    - rain (Llovizna / Lluvia, WMO 51–67, 80–82)
    - storm (Tormenta eléctrica / Granizo, WMO 95–99)
    - clear_night (Noche despejada)
    - cloudy_night (Noche nublada)
    """
    is_day = ghi > 10.0
    wmo = int(weather_code) if weather_code is not None else 0
    cc = int(cloud_cover) if cloud_cover is not None else 0

    if wmo in (95, 96, 99):
        return "storm"
    if (51 <= wmo <= 67) or (80 <= wmo <= 82) or (71 <= wmo <= 77) or (85 <= wmo <= 86):
        return "rain"

    if is_day:
        if wmo in (3, 45, 48) or cc >= 70:
            return "cloudy"
        elif wmo == 2 or (25 <= cc < 70):
            return "partly_cloudy"
        else:
            return "sunny"
    else:
        if wmo in (2, 3, 45, 48) or cc >= 30:
            return "cloudy_night"
        else:
            return "clear_night"

def fetch_open_meteo_weather(lat, lon, timeout=2, allow_network=True):
    """
    Consulta Open-Meteo con timeout=2s y caché en memoria y disco.
    Fallback limpio sin excepciones en caso de desconexión.
    Si allow_network=False, nunca realiza peticiones bloqueantes a internet.
    """
    global WEATHER_CACHE
    now_mono = time.monotonic()

    # Si la caché tiene menos de 15 minutos (900s), retornarla
    if WEATHER_CACHE["timestamp"] > 0 and (now_mono - WEATHER_CACHE["timestamp"] < 900):
        return WEATHER_CACHE["current"], WEATHER_CACHE["hourly"]

    # Intentar cargar de disco si memoria está vacía
    if WEATHER_CACHE["timestamp"] == 0 and os.path.exists(WEATHER_CACHE_FILE):
        try:
            with open(WEATHER_CACHE_FILE, 'r') as f:
                disk_cache = json.load(f)
                WEATHER_CACHE["current"] = disk_cache.get(
                    "current", {"weather_code": 0, "cloud_cover": 0, "wind_kmh": 12.0}
                )
                WEATHER_CACHE["hourly"] = disk_cache.get("hourly", {})
                WEATHER_CACHE["timestamp"] = now_mono
                if not allow_network:
                    return WEATHER_CACHE["current"], WEATHER_CACHE["hourly"]
        except Exception:
            pass

    if not allow_network:
        return WEATHER_CACHE["current"], WEATHER_CACHE["hourly"]

    # Consultar API Open-Meteo
    url = (
        f"https://api.open-meteo.com/v1/forecast?"
        f"latitude={lat}&longitude={lon}&current=weather_code,cloud_cover,wind_speed_10m"
        f"&hourly=weather_code,cloud_cover,wind_speed_10m&wind_speed_unit=kmh"
        f"&timezone=America%2FMexico_City&forecast_days=3"
    )
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "HeliOs-Meteo/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            current_data = data.get("current", {})
            hourly_data = data.get("hourly", {})

            cur = {
                "weather_code": current_data.get("weather_code", 0),
                "cloud_cover": current_data.get("cloud_cover", 0),
                "wind_kmh": float(current_data.get("wind_speed_10m", 12.0))
            }

            # Map hourly: {"2026-10-18T12:00": {"weather_code": ..., "cloud_cover": ..., "wind_kmh": ...}}
            h_map = {}
            times = hourly_data.get("time", [])
            w_codes = hourly_data.get("weather_code", [])
            c_covers = hourly_data.get("cloud_cover", [])
            w_winds = hourly_data.get("wind_speed_10m", [])
            for idx, t_str in enumerate(times):
                wc = w_codes[idx] if idx < len(w_codes) else 0
                cc = c_covers[idx] if idx < len(c_covers) else 0
                wk = float(w_winds[idx]) if idx < len(w_winds) else 12.0
                h_map[t_str] = {"weather_code": wc, "cloud_cover": cc, "wind_kmh": wk}

            WEATHER_CACHE["current"] = cur
            WEATHER_CACHE["hourly"] = h_map
            WEATHER_CACHE["timestamp"] = now_mono

            # Persistir caché en disco atómicamente
            try:
                tmp_w_file = f"{WEATHER_CACHE_FILE}.tmp"
                with open(tmp_w_file, 'w') as f:
                    json.dump({"current": cur, "hourly": h_map}, f)
                os.chmod(tmp_w_file, 0o666)
                os.replace(tmp_w_file, WEATHER_CACHE_FILE)
            except Exception:
                pass

            print(f"[HeliOs SPA] Clima Open-Meteo sincronizado: WMO={cur['weather_code']}, Nubes={cur['cloud_cover']}%, Viento={cur['wind_kmh']} km/h")
            return cur, h_map
    except Exception as e:
        print(f"[HeliOs SPA] Open-Meteo no disponible ({e}). Usando fallback de clima.")

    return WEATHER_CACHE["current"], WEATHER_CACHE["hourly"]

# ---------------------------------------------------------
# 4. SINCRONIZACIÓN DE RELOJ POR HTTP
# ---------------------------------------------------------
def sync_system_clock_if_needed(timeout=2):
    """
    Intenta sincronizar el reloj del sistema via header HTTP Date de Google o ip-api con timeout=2s.
    Retorna True si el reloj fue actualizado. No lanza excepciones.
    """
    urls_to_try = [
        ('http://www.google.com', timeout),
        ('http://ip-api.com/json/', timeout)
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
# 5. LECTURA DE CONFIGURACIÓN DE PANELES
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
        "latitud": 19.6800,
        "longitud": -99.0100,
        "lat": 19.6800,
        "lon": -99.0100,
        "city": "Ojo de Agua, EdoMex",
        "ubicacion": "Ojo de Agua, EdoMex"
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
# 6. GENERACIÓN DEL PRONÓSTICO (36 HORAS PARA ARRANQUE INSTANTÁNEO)
# ---------------------------------------------------------
def generar_pronostico(loc, config, lat, lon, horas=36, allow_network=False):
    """
    Calcula la curva de irradiancia futura y la guarda como JSON atómico para Flutter.
    Calcula 36 horas en lugar de 240, reduciendo el cómputo de Pandas/pvlib en ~85%.
    Usa offset de -6 horas puro sin depender de tzdata de Linux y modelo 'haurwitz'.
    allow_network=False garantiza cero bloqueos de red durante el arranque inmediato (segundo 0).
    """
    try:
        os.makedirs('/data', exist_ok=True)
        ahora_mx = datetime.now(TZ_OFFSET)
        ahora_pd = pd.Timestamp(ahora_mx).floor('h')

        tiempos_futuros = pd.date_range(
            start=ahora_pd, periods=horas, freq='1h'
        )
        cs_futuro = loc.get_clearsky(tiempos_futuros, model='haurwitz')

        voc = float(config.get('voc') or 49.6)
        isc = float(config.get('isc') or 14.0)
        serie = int(config.get('serie') or 18)
        paralelo = int(config.get('paralelo') or 4)

        _, hourly_weather = fetch_open_meteo_weather(lat, lon, timeout=2, allow_network=allow_network)

        pronostico = []
        for t, ghi in zip(tiempos_futuros, cs_futuro['ghi']):
            ghi_f = float(ghi)
            t_dt = t.to_pydatetime()
            t_str_iso_hour = t_dt.strftime("%Y-%m-%dT%H:00")

            w_info = hourly_weather.get(t_str_iso_hour, {})
            w_code = w_info.get("weather_code", 0)
            c_cover = w_info.get("cloud_cover", 0)
            w_wind = float(w_info.get("wind_kmh", 12.0))
            weather_state = clasificar_clima(ghi_f, w_code, c_cover)

            # Atenuación por nubosidad para generación esperada
            factor_nube = max(0.2, 1.0 - 0.75 * ((c_cover / 100.0) ** 2)) if ghi_f > 0 else 0.0
            ghi_efectivo = ghi_f * factor_nube if c_cover > 10 else ghi_f

            if ghi_f > 0:
                v = voc * serie
                i = isc * paralelo * (ghi_efectivo / 1000.0)
                p = v * i
            else:
                p = 0.0

            pronostico.append({
                "timestamp_epoch": int(t_dt.timestamp()),
                "hora": t_dt.isoformat(),
                "hora_str": t_dt.strftime("%H:00"),
                "fecha_str": t_dt.strftime("%d/%m"),
                "p_exp": round(p, 2),
                "ghi": round(ghi_f, 2),
                "wind_kmh": round(w_wind, 1),
                "weather_state": weather_state,
                "cloud_cover": c_cover,
            })

        tmp_forecast = '/data/forecast.json.tmp'
        with open(tmp_forecast, 'w') as f:
            json.dump(pronostico, f)
        try:
            os.chmod(tmp_forecast, 0o666)
        except Exception:
            pass
        os.replace(tmp_forecast, '/data/forecast.json')
        print(f"[HeliOs SPA] Pronóstico generado en /data/forecast.json ({len(pronostico)} horas)")
    except Exception as e:
        print(f"[HeliOs SPA] Error generando pronostico: {e}")
        traceback.print_exc()

# Alias por compatibilidad
generar_pronostico_10_dias = generar_pronostico

# ---------------------------------------------------------
# 7. ESTADO DE OVERRIDE TEMPORAL DE CLIMA Y EVENTO DE RECARGA
# ---------------------------------------------------------
reload_event = threading.Event()
OVERRIDE_WEATHER = {
    "active": False,
    "weather_state": None,
    "cloud_cover": 0,
    "until": 0.0
}

SENSOR_STATE = {
    "wind_kmh": None,
    "last_wind_ts": 0.0,
    "manual_stow": False,
}

def compute_tracker_angle(apparent_zenith, apparent_azimuth):
    """
    Calcula el ángulo de inclinación óptimo para un seguidor de un solo eje (SAT)
    orientado Norte-Sur con seguimiento Este-Oeste (-60.0° Este a +60.0° Oeste, 0.0° horizontal).
    Retorna 0.0° si el sol está bajo el horizonte o en caso de error.
    """
    try:
        try:
            axis = pvlib.tracking.singleaxis(
                apparent_zenith=pd.Series([apparent_zenith]),
                apparent_azimuth=pd.Series([apparent_azimuth]),
                axis_tilt=0,
                axis_azimuth=180,
                max_angle=60.0,
                backtrack=True
            )
        except TypeError:
            axis = pvlib.tracking.singleaxis(
                apparent_zenith=pd.Series([apparent_zenith]),
                solar_azimuth=pd.Series([apparent_azimuth]),
                axis_tilt=0,
                axis_azimuth=180,
                max_angle=60.0,
                backtrack=True
            )
        theta = axis['tracker_theta'].iloc[0]
        if pd.isna(theta):
            return 0.0
        return round(float(theta), 1)
    except Exception:
        return 0.0

def trigger_network_refresh(client):
    try:
        conf = read_panel_config()
        sync_system_clock_if_needed(timeout=2)
        n_lat, n_lon, n_city = get_location_coordinates(conf, fetch_network_timeout=2)
        n_loc = pvlib.location.Location(n_lat, n_lon, tz=-6)
        fetch_open_meteo_weather(n_lat, n_lon, timeout=2, allow_network=True)
        generar_pronostico(n_loc, conf, n_lat, n_lon, horas=36, allow_network=False)
        calcular_y_publicar_telemetria(client, n_loc, conf, n_lat, n_lon, n_city)
        print("[HeliOs SPA] Actualización por red ('net_ready') completada con éxito.")
    except Exception as err:
        print(f"[HeliOs SPA] Error en trigger_network_refresh: {err}")

def on_mqtt_message(client, userdata, msg):
    global OVERRIDE_WEATHER, SENSOR_STATE
    try:
        topic = msg.topic
        payload = msg.payload.decode('utf-8')
        if topic == "helios/config/reload":
            print("[HeliOs SPA] Mensaje recibido en helios/config/reload -> Recargando al instante.")
            try:
                data = json.loads(payload)
                if data.get("action") == "net_ready":
                    threading.Thread(target=trigger_network_refresh, args=(client,), daemon=True).start()
            except Exception:
                pass
            reload_event.set()
        elif topic == "helios/weather/override":
            data = json.loads(payload)
            st_weather = data.get("weather_state")
            dur = float(data.get("duration_sec", 20))
            cc = int(data.get("cloud_cover", 0))
            OVERRIDE_WEATHER["active"] = True
            OVERRIDE_WEATHER["weather_state"] = st_weather
            OVERRIDE_WEATHER["cloud_cover"] = cc
            OVERRIDE_WEATHER["until"] = time.time() + dur
            print(f"[HeliOs SPA] Override temporal de clima recibido: {st_weather} por {dur}s (nubes: {cc}%)")
            reload_event.set()
        elif topic == "helios/tracker/command":
            data = json.loads(payload)
            if "manual_stow" in data:
                SENSOR_STATE["manual_stow"] = bool(data["manual_stow"])
                print(f"[HeliOs SPA] Comando manual_stow recibido: {SENSOR_STATE['manual_stow']}")
                reload_event.set()
        elif topic in ("helios/environment/wind", "helios/inverter/telemetry"):
            data = json.loads(payload)
            if "wind_kmh" in data:
                SENSOR_STATE["wind_kmh"] = float(data["wind_kmh"])
                SENSOR_STATE["last_wind_ts"] = time.time()
                reload_event.set()
    except Exception as e:
        print(f"[HeliOs SPA] Error procesando mensaje MQTT ({msg.topic}): {e}")

# ---------------------------------------------------------
# 8. CÁLCULO Y PUBLICACIÓN DE TELEMETRÍA ESPERADA
# ---------------------------------------------------------
def calcular_y_publicar_telemetria(client, loc, conf, lat, lon, city):
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

    cur_weather = WEATHER_CACHE["current"]
    w_code = cur_weather.get("weather_code", 0)
    c_cover = cur_weather.get("cloud_cover", 0)
    weather_state = clasificar_clima(ghi, w_code, c_cover)

    # Verificar si hay override activo de clima desde el simulador
    now_time = time.time()
    if OVERRIDE_WEATHER["active"] and now_time < OVERRIDE_WEATHER["until"]:
        if OVERRIDE_WEATHER["weather_state"]:
            weather_state = OVERRIDE_WEATHER["weather_state"]
        c_cover = OVERRIDE_WEATHER["cloud_cover"]
        if weather_state in ("clear_night", "cloudy_night"):
            elevation = min(elevation, -5.0)
            ghi = 0.0
        elif weather_state in ("sunny", "partly_cloudy", "cloudy", "rain", "storm"):
            if elevation <= 0:
                elevation = 45.0
            if ghi <= 10.0:
                ghi = 650.0
    elif OVERRIDE_WEATHER["active"] and now_time >= OVERRIDE_WEATHER["until"]:
        OVERRIDE_WEATHER["active"] = False

    factor_nube = max(0.2, 1.0 - 0.75 * ((c_cover / 100.0) ** 2)) if ghi > 0 else 0.0
    ghi_efectivo = ghi * factor_nube if c_cover > 10 else ghi

    if ghi > 0.0:
        v_exp = voc * serie
        i_exp = isc * paralelo * (ghi_efectivo / 1000.0)
        p_exp = v_exp * i_exp
    else:
        v_exp = 0.0
        i_exp = 0.0
        p_exp = 0.0

    # Obtener viento efectivo (prioridad a sensor/simulador externo)
    if SENSOR_STATE["wind_kmh"] is not None and (now_time - SENSOR_STATE["last_wind_ts"] < 30.0):
        effective_wind = float(SENSOR_STATE["wind_kmh"])
    else:
        effective_wind = float(WEATHER_CACHE["current"].get("wind_kmh", 12.0))

    # Reglas del Seguidor SAT de Un Solo Eje y Modo Estiba (Flat-Stow a 0.0°)
    is_wind_dangerous = effective_wind >= 50.0
    is_manual_stow = bool(SENSOR_STATE.get("manual_stow", False))
    is_night = elevation <= 0 or ghi <= 10.0
    is_stow = is_night or is_wind_dangerous or is_manual_stow

    if is_stow:
        target_angle = 0.0
        motor_angle = 0.0
        motor_azimuth = 180.0
        motor_elevation = 90.0
    else:
        apparent_zenith = max(0.0, 90.0 - elevation)
        target_angle = compute_tracker_angle(apparent_zenith, azimuth)
        motor_angle = target_angle
        motor_azimuth = round(azimuth, 2)
        motor_elevation = round(elevation, 2)

    payload_expected = {
        "azimuth": round(azimuth, 2),
        "elevation": round(elevation, 2),
        "target_angle": target_angle,
        "motor_angle": motor_angle,
        "is_stow": is_stow,
        "wind_kmh": round(effective_wind, 1),
        "v_exp": round(v_exp, 2),
        "i_exp": round(i_exp, 2),
        "p_exp": round(p_exp, 2),
        "ghi": round(ghi, 2),
        "is_night": is_night,
        "motor_azimuth": motor_azimuth,
        "motor_elevation": motor_elevation,
        "system_time": ahora_mx.strftime("%H:%M"),
        "system_time_full": ahora_mx.strftime("%H:%M:%S"),
        "lat": round(lat, 4),
        "lon": round(lon, 4),
        "ubicacion": city,
        "weather_state": weather_state,
        "cloud_cover": c_cover,
    }
    client.publish("helios/spa/expected", json.dumps(payload_expected), retain=True)

    payload_coords = {
        "azimuth": round(azimuth, 2),
        "elevation": round(elevation, 2),
        "target_angle": target_angle,
        "motor_angle": motor_angle,
        "is_stow": is_stow,
        "is_night": is_night,
        "wind_kmh": round(effective_wind, 1),
        "motor_azimuth": motor_azimuth,
        "motor_elevation": motor_elevation,
    }
    client.publish("helios/spa/coordinates", json.dumps(payload_coords), retain=True)

# ---------------------------------------------------------
# 9. BUCLE PRINCIPAL CON FAST-PATH EN SEGUNDO 0
# ---------------------------------------------------------
def main():
    os.makedirs('/data', exist_ok=True)
    start_mono = time.monotonic()

    # Configuración de cliente MQTT con inicio inmediato
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_message = on_mqtt_message

    def on_connect_cb(c, userdata, flags, rc, properties=None):
        c.subscribe([
            ("helios/config/reload", 1),
            ("helios/weather/override", 1),
            ("helios/tracker/command", 1),
            ("helios/environment/wind", 0),
            ("helios/inverter/telemetry", 0),
        ])
        print("[HeliOs SPA] Suscrito a helios/config/reload, helios/weather/override, helios/tracker/command, helios/environment/wind, helios/inverter/telemetry")

    client.on_connect = on_connect_cb

    # Conexión resiliente rápida a Mosquitto
    connected = False
    for attempt in range(10):
        try:
            client.connect("127.0.0.1", 1883, 60)
            client.loop_start()
            connected = True
            print(f"[HeliOs SPA] Conectado a Mosquitto exitosamente en intento {attempt+1}.")
            break
        except Exception:
            time.sleep(0.1)

    if not connected:
        try:
            client.connect_async("127.0.0.1", 1883, 60)
            client.loop_start()
            print("[HeliOs SPA] Conexión MQTT en segundo plano.")
        except Exception as ex:
            print(f"[HeliOs SPA] Error inicializando MQTT: {ex}")

    # FAST-PATH SEGUNDO 0:
    # 1. Lectura inmediata de configuración de paneles y coordenadas locales (<3ms)
    conf = read_panel_config()
    lat, lon, city = get_location_coordinates(conf, fetch_network_timeout=None)
    loc = pvlib.location.Location(lat, lon, tz=-6)

    # 2. Publicación inmediata de telemetría y coordenadas en segundo 0 (<5ms)
    try:
        calcular_y_publicar_telemetria(client, loc, conf, lat, lon, city)
        print(f"[HeliOs SPA] FAST-PATH SEGUNDO 0: Telemetría publicada (lat={lat}, lon={lon}, ubicacion={city})")
    except Exception as e:
        print(f"[HeliOs SPA] Error en publicación inicial de segundo 0: {e}")

    # 3. Generación inmediata en segundo 0 del pronóstico de 36 horas en disco (no bloqueante, <40ms)
    try:
        generar_pronostico(loc, conf, lat, lon, horas=36, allow_network=False)
        print("[HeliOs SPA] FAST-PATH SEGUNDO 0: /data/forecast.json (36 horas) generado.")
    except Exception as e:
        print(f"[HeliOs SPA] Error generando pronóstico inicial: {e}")

    # 4. Tareas asíncronas de enriquecimiento (reloj, ip-api, Open-Meteo)
    threading.Thread(target=trigger_network_refresh, args=(client,), daemon=True).start()

    last_forecast_time = time.monotonic()
    prev_epoch = time.time()
    last_config_mtime = 0.0
    if os.path.exists('/data/wifi_config.json'):
        try:
            last_config_mtime = os.path.getmtime('/data/wifi_config.json')
        except Exception:
            pass

    # Bucle infinito protegido contra cualquier excepción
    while True:
        try:
            # Detección inmediata de cambios en /data/wifi_config.json
            current_mtime = 0.0
            if os.path.exists('/data/wifi_config.json'):
                try:
                    current_mtime = os.path.getmtime('/data/wifi_config.json')
                except Exception:
                    pass
            if current_mtime > 0 and current_mtime != last_config_mtime:
                last_config_mtime = current_mtime
                print("[HeliOs SPA] Detectado cambio en /data/wifi_config.json -> Recalculando inmediatamente.")
                reload_event.set()

            conf = read_panel_config()
            lat, lon, city = get_location_coordinates(conf, fetch_network_timeout=None)
            loc = pvlib.location.Location(lat, lon, tz=-6)
            calcular_y_publicar_telemetria(client, loc, conf, lat, lon, city)
        except Exception as e:
            print(f"[HeliOs SPA] Error en ciclo principal: {e}")
            traceback.print_exc()

        # Regenerar pronóstico periódicamente o ante señal de recarga
        try:
            now_epoch = time.time()
            elapsed_forecast = time.monotonic() - last_forecast_time
            clock_jump = abs(now_epoch - prev_epoch - 10) > 120

            if elapsed_forecast >= 900 or clock_jump or reload_event.is_set():
                generar_pronostico(loc, conf, lat, lon, horas=36, allow_network=False)
                last_forecast_time = time.monotonic()
            prev_epoch = now_epoch
        except Exception as e:
            print(f"[HeliOs SPA] Error en verificación de pronóstico: {e}")

        # Si reload_event fue activado, consumirlo y continuar sin esperar
        if reload_event.is_set():
            reload_event.clear()
            continue

        # Durante los primeros 60 segundos publica cada 3s; luego cada 10s
        elapsed_total = time.monotonic() - start_mono
        intervalo = 3 if elapsed_total < 60 else 10

        # Esperar intervalo o despertar de inmediato si llega mensaje MQTT
        reload_event.wait(timeout=intervalo)
        if reload_event.is_set():
            reload_event.clear()

if __name__ == "__main__":
    main()


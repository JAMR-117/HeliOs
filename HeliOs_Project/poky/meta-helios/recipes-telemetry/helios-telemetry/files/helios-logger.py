import sqlite3
import json
import os
import time
import threading
import paho.mqtt.client as mqtt
from datetime import datetime

DB_PATH = "/data/helios_history.db"

# Estado compartido en memoria
state = {
    "p_exp":           0.0,
    "is_night":        True,
    "last_inverter_ts": 0.0,   # epoch del último mensaje de inversor
    "last_alert_code": None,   # último código de alerta persistido (anti-duplicado)
}

def init_db():
    """Crea las tablas si no existen y asigna permisos 666."""
    os.makedirs('/data', exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS telemetry_log
                 (timestamp TEXT, p_real REAL, p_exp REAL, v_real REAL, i_real REAL)''')
    c.execute('''CREATE TABLE IF NOT EXISTS scada_errors
                 (timestamp TEXT, fault_code INTEGER, description TEXT)''')
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o666)
    print("[INFO] Base de datos SQLite inicializada con permisos 666.")

def insert_telemetry(now, p_real, p_exp, v_real, i_real):
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT INTO telemetry_log VALUES (?,?,?,?,?)",
            (now, p_real, p_exp, v_real, i_real)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[ERROR] insert_telemetry: {e}")

def insert_alert(now, code, description):
    """Inserta en scada_errors evitando duplicados consecutivos del mismo código."""
    if state["last_alert_code"] == code:
        return   # No saturar la tabla repitiendo el mismo error cada 10 s
    state["last_alert_code"] = code
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "INSERT INTO scada_errors VALUES (?,?,?)",
            (now, code, description)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[ERROR] insert_alert: {e}")

def on_connect(client, userdata, flags, reason_code, properties):
    """Callback compatible con paho-mqtt >= 2.0.0 (CallbackAPIVersion.VERSION2)."""
    if reason_code == 0:
        client.subscribe([
            ("helios/spa/expected",       0),
            ("helios/inverter/telemetry", 0),
            ("helios/scada/alerts",       0),
        ])
        print("[INFO] HeliOs Logger: suscrito a tópicos MQTT.")
    else:
        print(f"[WARN] helios-logger: Conexión rechazada, reason_code={reason_code}")

def on_message(client, userdata, msg):
    topic = msg.topic
    now   = datetime.now().isoformat()

    try:
        data = json.loads(msg.payload.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"[ERROR] Payload inválido en {topic}: {e}")
        return

    # --- Actualizar estado SPA ---
    if topic == "helios/spa/expected":
        state["p_exp"]    = float(data.get("p_exp",    0.0))
        state["is_night"] = bool(data.get("is_night",  True))
        return

    # --- Telemetría del inversor → persistir en telemetry_log ---
    if topic == "helios/inverter/telemetry":
        p_real = float(data.get("power_w", 0.0))
        v_real = float(data.get("v_dc",    0.0))
        i_real = float(data.get("i_dc",    0.0))
        fault  = int(data.get("fault",     0))

        insert_telemetry(now, p_real, state["p_exp"], v_real, i_real)

        # Registrar fallas hardware SunSpec en scada_errors
        if fault != 0:
            insert_alert(now, fault, f"Falla SunSpec código {fault}")

        state["last_inverter_ts"] = time.time()
        return

    # --- Alertas SCADA → persistir en scada_errors (sin duplicados consecutivos) ---
    if topic == "helios/scada/alerts":
        code = int(data.get("code", 0))
        if code != 0:
            desc = data.get("description", "Alerta SCADA")
            insert_alert(now, code, desc)
        else:
            # Alerta limpia: resetear anti-duplicado para que la próxima falla sí se persista
            state["last_alert_code"] = None
        return

def autonomous_telemetry_loop(mqtt_client):
    """
    Hilo secundario: si el inversor no envía datos por más de 15 s pero el SPA
    sí está activo, inserta una fila teórica en telemetry_log cada 30 s para
    que la curva esperada se grafique de forma autónoma.
    """
    while True:
        time.sleep(30)
        elapsed_since_inverter = time.time() - state["last_inverter_ts"]
        p_exp = state["p_exp"]
        if elapsed_since_inverter > 15.0 and p_exp > 0:
            now = datetime.now().isoformat()
            insert_telemetry(now, 0.0, p_exp, 0.0, 0.0)

if __name__ == "__main__":
    init_db()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect("127.0.0.1", 1883, 60)

    # Hilo de telemetría autónoma (curva esperada sin inversor)
    t = threading.Thread(target=autonomous_telemetry_loop, args=(client,), daemon=True)
    t.start()

    print("[INFO] HeliOs Logger Daemon ejecutándose...")
    client.loop_forever()

import json
import sqlite3
import os
import time
import paho.mqtt.client as mqtt
from datetime import datetime, timezone, timedelta

DB_PATH = "/data/helios_history.db"
TZ_OFFSET = timezone(timedelta(hours=-6))

def get_now_str():
    return datetime.now(TZ_OFFSET).strftime("%Y-%m-%d %H:%M:%S")

SUNSPEC_ERRORS = {
    0:   "Operación Normal",
    1:   "Sobrevoltaje de Red",
    13:  "Fuga a Tierra Detectada",
    14:  "Sobrecalentamiento del Inversor",
    101: "Pérdida de Panel en Serie Detectada",
    102: "Sombreo o Suciedad en Arreglo Fotovoltaico",
    103: "Alerta Térmica: Sobrecalentamiento en Inversor (>65°C)",
}

# Estado SPA compartido (actualizado por tópico helios/spa/expected)
latest_spa = {"ghi": 0.0, "v_exp": 0.0, "p_exp": 0.0, "is_night": True}

def init_db():
    try:
        os.makedirs('/data', exist_ok=True)
    except Exception:
        pass

    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS telemetry_log
                     (timestamp TEXT, p_real REAL, p_exp REAL, v_real REAL, i_real REAL)''')
        c.execute('''CREATE TABLE IF NOT EXISTS scada_errors
                     (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, code INTEGER, description TEXT)''')
        conn.commit()
        conn.close()
        try:
            os.chmod(DB_PATH, 0o666)
        except Exception:
            pass
    except Exception as e:
        print(f"[ERROR] helios-scada init_db: {e}")

def guardar_alerta(timestamp, code, description):
    """Inserta una alerta en SQLite para que ScadaErrorsScreen la muestre en historial."""
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("INSERT INTO scada_errors (timestamp, code, description) VALUES (?,?,?)",
                  (timestamp, int(code), str(description)))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[ERROR] guardar_alerta: {e}")

def on_connect(client, userdata, flags, reason_code, properties):
    """Callback compatible con paho-mqtt >= 2.0.0 (CallbackAPIVersion.VERSION2)."""
    if reason_code == 0:
        client.subscribe([
            ("helios/inverter/telemetry", 0),
            ("helios/spa/expected",       0),
        ])
        print("[INFO] helios-scada: suscrito a telemetría e SPA.")
    else:
        print(f"[WARN] helios-scada: Conexión rechazada, reason_code={reason_code}")

def on_message(client, userdata, msg):
    global latest_spa
    now_str = get_now_str()

    try:
        data = json.loads(msg.payload.decode('utf-8'))
    except json.JSONDecodeError:
        return

    # --- Actualizar estado SPA ---
    if msg.topic == "helios/spa/expected":
        latest_spa["ghi"]      = float(data.get("ghi",      0.0))
        latest_spa["v_exp"]    = float(data.get("v_exp",    0.0))
        latest_spa["p_exp"]    = float(data.get("p_exp",    0.0))
        latest_spa["is_night"] = bool(data.get("is_night",  True))
        return

    if msg.topic != "helios/inverter/telemetry":
        return

    # --- Procesar telemetría del inversor ---
    fault_code = int(data.get("fault",   0))
    v_dc       = float(data.get("v_dc",  0.0))
    power_w    = float(data.get("power_w", 0.0))
    temp_c     = float(data.get("temp_c", 0.0))

    ghi      = latest_spa["ghi"]
    v_exp    = latest_spa["v_exp"]
    p_exp    = latest_spa["p_exp"]
    is_night = latest_spa["is_night"]

    alert = None

    # Prioridad 1: Falla hardware SunSpec
    if fault_code != 0:
        alert = {
            "inverter":    data.get("inverter", 1),
            "code":        fault_code,
            "description": SUNSPEC_ERRORS.get(fault_code, "Error Desconocido"),
        }

    # Prioridad 2: Alerta Térmica (siempre activa, independiente de día/noche)
    elif temp_c > 65.0:
        alert = {
            "inverter":    data.get("inverter", 1),
            "code":        103,
            "description": SUNSPEC_ERRORS[103],
        }

    # Prioridad 3: Anomalías de planta — SOLO en modo DÍA
    elif not is_night and ghi > 20.0 and v_exp > 0:
        if v_dc < v_exp * 0.90:
            alert = {
                "inverter":    data.get("inverter", 1),
                "code":        101,
                "description": SUNSPEC_ERRORS[101],
            }
        elif p_exp > 50.0 and power_w < p_exp * 0.85:
            alert = {
                "inverter":    data.get("inverter", 1),
                "code":        102,
                "description": SUNSPEC_ERRORS[102],
            }

    if alert:
        # Publicar y persistir alerta activa
        client.publish("helios/scada/alerts", json.dumps(alert), retain=True)
        guardar_alerta(now_str, alert["code"], alert["description"])
    else:
        # Sin falla: publicar estado limpio
        if is_night and fault_code == 0:
            desc = "Modo Nocturno - Paneles en Estiba"
        else:
            desc = "Operación Normal"

        estado = {
            "inverter":    data.get("inverter", 1),
            "code":        0,
            "description": desc,
        }
        client.publish("helios/scada/alerts", json.dumps(estado), retain=True)

if __name__ == "__main__":
    init_db()
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_message = on_message

    while True:
        try:
            client.connect("127.0.0.1", 1883, 60)
            break
        except Exception as e:
            print(f"[helios-scada] Esperando broker MQTT: {e}")
            time.sleep(2)

    client.loop_forever()

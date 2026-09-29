import sqlite3
import json
import os
import paho.mqtt.client as mqtt
from datetime import datetime

DB_PATH = '/data/helios_history.db'
BROKER = '127.0.0.1'

def init_db():
    # Asegurar que el directorio exista
    os.makedirs('/data', exist_ok=True)
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS telemetry_log 
                 (timestamp TEXT, p_real REAL, p_exp REAL, v_real REAL, i_real REAL)''')
    c.execute('''CREATE TABLE IF NOT EXISTS scada_errors 
                 (timestamp TEXT, fault_code INTEGER, description TEXT)''')
    conn.commit()
    conn.close()
    
    # NUEVO: Dar permisos de lectura/escritura globales a la base de datos
    os.chmod(DB_PATH, 0o666)
    print("[INFO] Base de datos SQLite inicializada con permisos 666.")

def on_connect(client, userdata, flags, rc):
    print(f"[INFO] Conectado al Broker MQTT local con código: {rc}")
    client.subscribe("helios/telemetry")
    client.subscribe("helios/alarms")

def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode('utf-8'))
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        
        if msg.topic == "helios/telemetry":
            c.execute("INSERT INTO telemetry_log VALUES (?, ?, ?, ?, ?)",
                      (timestamp, payload.get('p_real', 0.0), payload.get('p_exp', 0.0), 
                       payload.get('v_real', 0.0), payload.get('i_real', 0.0)))
        elif msg.topic == "helios/alarms":
            c.execute("INSERT INTO scada_errors VALUES (?, ?, ?)",
                      (timestamp, payload.get('fault_code', 0), payload.get('description', '')))
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[ERROR] Error procesando mensaje MQTT: {e}")

if __name__ == "__main__":
    init_db()
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    
    try:
        client.connect(BROKER, 1883, 60)
        print("[INFO] HeliOs Logger Daemon ejecutándose...")
        client.loop_forever()
    except Exception as e:
        print(f"[ERROR] Fallo crítico en el Logger: {e}")


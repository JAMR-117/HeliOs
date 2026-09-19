import sqlite3, json
import paho.mqtt.client as mqtt
from datetime import datetime

DB_PATH = "/data/helios_history.db"
latest_expected = {"p_exp": 0.0}

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS telemetry_log 
                 (timestamp TEXT, p_real REAL, p_exp REAL, v_real REAL, i_real REAL)''')
    c.execute('''CREATE TABLE IF NOT EXISTS scada_errors 
                 (timestamp TEXT, fault_code INTEGER, description TEXT)''')
    conn.commit()
    conn.close()

def on_message(client, userdata, msg):
    global latest_expected
    topic = msg.topic
    now = datetime.now().isoformat()
    
    try:
        data = json.loads(msg.payload.decode('utf-8'))
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        
        if topic == "helios/spa/expected":
            latest_expected["p_exp"] = data.get("p_exp", 0.0)
            
        elif topic == "helios/inverter/telemetry":
            p_real = data.get("power_w", 0.0)
            v_real = data.get("v_dc", 0.0)
            i_real = data.get("i_dc", 0.0)
            fault = data.get("fault", 0)
            
            c.execute("INSERT INTO telemetry_log VALUES (?,?,?,?,?)", 
                      (now, p_real, latest_expected["p_exp"], v_real, i_real))
            
            if fault != 0:
                c.execute("INSERT INTO scada_errors VALUES (?,?,?)", 
                          (now, fault, "Falla SunSpec interceptada"))
        conn.commit()
        conn.close()
    except json.JSONDecodeError:
        pass

init_db()
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
client.on_message = on_message
client.connect("127.0.0.1", 1883, 60)
client.subscribe([("helios/spa/expected", 0), ("helios/inverter/telemetry", 0)])
client.loop_forever()

import json
import paho.mqtt.client as mqtt

SUNSPEC_ERRORS = {
    0: "Operacion Normal",
    1: "Sobrevoltaje de Red",
    13: "Fuga a Tierra Detectada",
    14: "Sobrecalentamiento del Inversor"
}

def on_connect(client, userdata, flags, rc, properties=None):
    client.subscribe("helios/inverter/telemetry")

def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload.decode('utf-8'))
        fault_code = data.get("fault", 0)
        
        if fault_code != 0:
            alert = {
                "inverter": data.get("inverter", 1),
                "code": fault_code,
                "description": SUNSPEC_ERRORS.get(fault_code, "Error Desconocido")
            }
            client.publish("helios/scada/alerts", json.dumps(alert))
            print(f"Alerta publicada: {alert}") # Print para depuracion en vivo
            
    except json.JSONDecodeError:
        pass

# SOLUCION: Declaracion explicita de la API v1 para Paho-MQTT 2.0+
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
client.on_connect = on_connect
client.on_message = on_message

client.connect("127.0.0.1", 1883, 60)
client.loop_forever()

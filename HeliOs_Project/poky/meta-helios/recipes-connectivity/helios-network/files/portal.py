import json
import subprocess
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

bloqueo_archivo = threading.Lock()
credenciales_guardadas = False

def get_wifi_networks():
    networks = set()
    try:
        scan_out = subprocess.check_output(['iw', 'dev', 'wlan0', 'scan', 'ap-force'], stderr=subprocess.STDOUT, text=True)
        for line in scan_out.split('\n'):
            line = line.strip()
            if line.startswith('SSID:'):
                ssid = line.split('SSID:')[1].strip()
                if ssid and '\\x00' not in ssid:
                    networks.add(ssid)
    except Exception:
        pass
    return list(networks)

def generate_html():
    networks = get_wifi_networks()
    if networks:
        options = "".join(f'<option value="{n}">{n}</option>' for n in networks)
    else:
        options = '<option value="" disabled selected>Escaneando redes...</option>'
        
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>HeliOs Setup</title>
    <style>
        :root {{ --bg: #121212; --card: #1e1e1e; --brand: #00bcd4; --text: #fff; --border: #333; }}
        body {{ font-family: sans-serif; background: var(--bg); color: var(--text); margin: 0; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; box-sizing: border-box; }}
        .card {{ background: var(--card); padding: 30px; border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); width: 100%; max-width: 450px; }}
        h2 {{ margin-top: 0; color: var(--brand); text-align: center; }}
        h3 {{ color: var(--brand); border-bottom: 1px solid var(--border); padding-bottom: 8px; margin-top: 25px; font-size: 16px; text-transform: uppercase; letter-spacing: 1px; }}
        p.subtitle {{ color: #b3b3b3; text-align: center; margin-bottom: 25px; }}
        select, input {{ width: 100%; padding: 14px; margin-bottom: 15px; border: 1px solid var(--border); border-radius: 8px; background: #2c2c2c; color: white; font-size: 15px; box-sizing: border-box; }}
        select {{ cursor: pointer; appearance: auto; }}
        select:focus, input:focus {{ outline: none; border-color: var(--brand); }}
        .grid-2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }}
        button {{ width: 100%; padding: 16px; margin-top: 10px; background: var(--brand); color: #000; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>HeliOs Network</h2>
        <p class="subtitle">Configuración SCADA y Parámetros</p>
        <form method="POST" action="/">
            
            <h3>1. Red Industrial</h3>
            <select name="ssid" required>
                <option value="" disabled selected>Seleccione la red Wi-Fi...</option>
                {options}
            </select>
            <input type="password" name="pass" placeholder="Contraseña WPA2 (Mín. 8 caracteres)" required minlength="8">
            
            <h3>2. Arreglo Fotovoltaico</h3>
            <div class="grid-2">
                <input type="number" step="0.1" name="voc" placeholder="Voc por Panel (V)" required>
                <input type="number" step="0.1" name="isc" placeholder="Isc por Panel (A)" required>
            </div>
            <input type="number" step="0.1" name="wp" placeholder="Potencia Pico Wp (W)" required>
            <div class="grid-2">
                <input type="number" step="1" name="paneles_serie" placeholder="Paneles en Serie" required>
                <input type="number" step="1" name="cadenas_paralelo" placeholder="Cadenas en Paralelo" required>
            </div>

            <button type="submit">Guardar y Reiniciar</button>
        </form>
    </div>
</body>
</html>"""

def reiniciar_sistema():
    # Retraso para enviar el HTML antes de apagar la red
    time.sleep(4)
    os.system("reboot")

class Portal(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_GET(self):
        try:
            content = generate_html().encode('utf-8')
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('Content-Length', str(len(content)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(content)
        except Exception:
            pass
        
    def do_POST(self):
        global credenciales_guardadas
        try:
            length = int(self.headers.get('Content-Length', 0))
            data = parse_qs(self.rfile.read(length).decode('utf-8'))
            
            # Estructuración unificada de los datos capturados
            config = {
                'ssid': data.get('ssid', [''])[0],
                'pass': data.get('pass', [''])[0],
                'voc': float(data.get('voc', ['0'])[0]),
                'isc': float(data.get('isc', ['0'])[0]),
                'wp': float(data.get('wp', ['0'])[0]),
                'paneles_serie': int(data.get('paneles_serie', ['0'])[0]),
                'cadenas_paralelo': int(data.get('cadenas_paralelo', ['0'])[0])
            }
            
            with bloqueo_archivo:
                if credenciales_guardadas:
                    self.send_response(409)
                    self.end_headers()
                    return
                credenciales_guardadas = True
                
                # Escritura en la partición inmutable /data
                with open('/data/wifi_config.json', 'w') as f:
                    json.dump(config, f)
            
            response_msg = b"<!DOCTYPE html><html><body style='background:#121212;color:#00bcd4;text-align:center;padding:50px;font-family:sans-serif;'><h2>Configuracion Aplicada</h2><p style='color:#fff;'>HeliOs procesara los parametros del arreglo solar y el Gateway se reiniciara.</p></body></html>"
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('Content-Length', str(len(response_msg)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(response_msg)
            
            threading.Thread(target=reiniciar_sistema).start()
        except Exception:
            pass

if __name__ == "__main__":
    ThreadingHTTPServer(('0.0.0.0', 80), Portal).serve_forever()

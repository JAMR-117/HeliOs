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
                if ssid and '\x00' not in ssid:
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
        :root {{ --bg: #121212; --card: #1e1e1e; --brand: #00bcd4; --text: #fff; }}
        body {{ font-family: sans-serif; background: var(--bg); color: var(--text); margin: 0; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; box-sizing: border-box; }}
        .card {{ background: var(--card); padding: 40px 30px; border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); width: 100%; max-width: 400px; text-align: center; }}
        h2 {{ margin-top: 0; color: var(--brand); }}
        h3 {{ color: #b3b3b3; font-size: 14px; text-align: left; margin-bottom: 10px; border-bottom: 1px solid #333; padding-bottom: 5px; }}
        select, input {{ width: 100%; padding: 12px; margin-bottom: 15px; border: 1px solid #333; border-radius: 8px; background: #2c2c2c; color: white; font-size: 14px; box-sizing: border-box; }}
        select {{ cursor: pointer; appearance: auto; }}
        select:focus, input:focus {{ outline: none; border-color: var(--brand); }}
        button {{ width: 100%; padding: 16px; background: var(--brand); color: #000; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; margin-top: 10px; }}
        .grid-2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }}
        .field-group {{ text-align: left; }}
        .field-group label {{ font-size: 12px; color: #888; }}
    </style>
</head>
<body>
    <div class="card">
        <h2>HeliOs Network</h2>
        <form method="POST" action="/">
            <h3>1. Red Industrial</h3>
            <select name="ssid" required>
                <option value="" disabled selected>Seleccione la red...</option>
                {options}
            </select>
            <input type="password" name="pass" placeholder="Contraseña" required minlength="8">
            
            <h3>2. Parámetros Fotovoltaicos</h3>
            <div class="grid-2">
                <div class="field-group"><label>Voc (V)</label><input type="number" step="0.1" name="voc" required></div>
                <div class="field-group"><label>Isc (A)</label><input type="number" step="0.1" name="isc" required></div>
                <div class="field-group"><label>Potencia (Wp)</label><input type="number" step="0.1" name="wp" required></div>
                <div class="field-group"><label>Paneles Serie</label><input type="number" step="1" name="serie" required></div>
                <div class="field-group" style="grid-column: span 2;"><label>Cadenas Paralelo</label><input type="number" step="1" name="paralelo" required></div>
            </div>
            <button type="submit">Guardar y Conectar</button>
        </form>
    </div>
</body>
</html>"""

def reiniciar_sistema():
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
            
            config = {
                'ssid': data.get('ssid', [''])[0],
                'pass': data.get('pass', [''])[0],
                'voc': float(data.get('voc', [0.0])[0]),
                'isc': float(data.get('isc', [0.0])[0]),
                'wp': float(data.get('wp', [0.0])[0]),
                'serie': int(data.get('serie', [0])[0]),
                'paralelo': int(data.get('paralelo', [0])[0])
            }
            
            with bloqueo_archivo:
                if credenciales_guardadas:
                    self.send_response(409)
                    self.end_headers()
                    return
                credenciales_guardadas = True
                
                with open('/data/wifi_config.json', 'w') as f:
                    json.dump(config, f)
            
            response_msg = b"<!DOCTYPE html><html><body style='background:#121212;color:#00bcd4;text-align:center;padding:50px;font-family:sans-serif;'><h2>Configuracion Guardada</h2><p style='color:#fff;'>El Cerebro Energetico se reiniciara.</p></body></html>"
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('Content-Length', str(len(response_msg)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(response_msg)
            self.wfile.flush()
            
            threading.Thread(target=reiniciar_sistema).start()
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"Error procesando datos: {str(e)}".encode('utf-8'))

if __name__ == "__main__":
    ThreadingHTTPServer(('0.0.0.0', 80), Portal).serve_forever()

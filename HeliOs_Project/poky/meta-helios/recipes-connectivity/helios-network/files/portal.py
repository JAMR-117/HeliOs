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
        .field-group {{ text-align: left; }}
        .field-group label {{ font-size: 12px; color: #888; display: block; margin-bottom: 5px; }}
        
        button {{ width: 100%; padding: 16px; margin-top: 10px; background: var(--brand); color: #000; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; }}
        button:hover {{ opacity: 0.8; }}
        
        /* Estilos para el campo de contraseña con botón visible */
        .password-container {{ position: relative; width: 100%; }}
        .password-container input {{ width: 100%; padding-right: 45px; box-sizing: border-box; }}
        .toggle-icon {{ position: absolute; right: 15px; top: 14px; cursor: pointer; font-size: 18px; user-select: none; filter: grayscale(100%); opacity: 0.7; }}
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
            
            <div class="password-container">
                <input type="password" id="passInput" name="pass" placeholder="Contraseña WPA2 (Mín. 8 caracteres)" required minlength="8">
                <span class="toggle-icon" id="togglePassword" onclick="togglePass()">👁️</span>
            </div>
            
            <h3>2. Arreglo Fotovoltaico</h3>
            <div class="grid-2">
                <div class="field-group">
                    <label>Voc por Panel (V)</label>
                    <input type="number" step="0.1" name="voc" value="49.6" required>
                </div>
                <div class="field-group">
                    <label>Isc por Panel (A)</label>
                    <input type="number" step="0.1" name="isc" value="14.0" required>
                </div>
                <div class="field-group">
                    <label>Potencia Pico (Wp)</label>
                    <input type="number" step="0.1" name="wp" value="550.0" required>
                </div>
                <div class="field-group">
                    <label>Paneles en Serie</label>
                    <input type="number" step="1" name="serie" value="18" required>
                </div>
                <div class="field-group" style="grid-column: span 2;">
                    <label>Cadenas en Paralelo</label>
                    <input type="number" step="1" name="paralelo" value="4" required>
                </div>
            </div>

            <button type="submit">Guardar y Reiniciar</button>
        </form>
    </div>
    
    <script>
        function togglePass() {{
            var passInput = document.getElementById("passInput");
            var toggleIcon = document.getElementById("togglePassword");
            
            if (passInput.type === "password") {{
                passInput.type = "text";
                toggleIcon.textContent = "🙈"; 
            }} else {{
                passInput.type = "password";
                toggleIcon.textContent = "👁️"; 
            }}
        }}
    </script>
</body>
</html>"""

def reiniciar_sistema():
    time.sleep(2)
    os.system("sync && reboot")

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
            
            voc_val = float(data.get('voc', ['49.6'])[0] or 49.6)
            isc_val = float(data.get('isc', ['14.0'])[0] or 14.0)
            wp_val = float(data.get('wp', ['550.0'])[0] or 550.0)
            serie_val = int(data.get('serie', ['18'])[0] or 18)
            paralelo_val = int(data.get('paralelo', ['4'])[0] or 4)

            config = {
                'ssid': data.get('ssid', [''])[0].strip(),
                'pass': data.get('pass', [''])[0],
                'voc': voc_val,
                'isc': isc_val,
                'wp': wp_val,
                'serie': serie_val,
                'paralelo': paralelo_val,
                'lat': 19.6800,
                'lon': -99.0100,
                'city': 'Ojo de Agua, EdoMex'
            }
            
            with bloqueo_archivo:
                if credenciales_guardadas:
                    self.send_response(409)
                    self.end_headers()
                    return
                credenciales_guardadas = True
                
                os.makedirs('/data', exist_ok=True)
                tmp_path = '/data/wifi_config.json.tmp'
                final_path = '/data/wifi_config.json'
                with open(tmp_path, 'w') as f:
                    json.dump(config, f, indent=2)
                
                os.chmod(tmp_path, 0o666)
                os.replace(tmp_path, final_path)

                # Sincronización automática de credenciales Wi-Fi hacia los nodos ESP32
                try:
                    esp_data = json.dumps({
                        'ssid': config['ssid'],
                        'pass': config['pass'],
                        'timestamp': time.time()
                    })
                    tmp_esp = '/data/esp32_wifi_sync.json.tmp'
                    with open(tmp_esp, 'w') as f_esp:
                        f_esp.write(esp_data)
                    os.chmod(tmp_esp, 0o666)
                    os.replace(tmp_esp, '/data/esp32_wifi_sync.json')

                    subprocess.run([
                        'mosquitto_pub', '-h', '127.0.0.1', '-t', 'helios/esp32/wifi_config',
                        '-r', '-q', '1', '-m', esp_data
                    ], timeout=3, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    print("[portal.py] Credenciales Wi-Fi publicadas en helios/esp32/wifi_config para aprovisionamiento de nodos ESP32.")
                except Exception as e_esp:
                    print(f"[portal.py] Error publicando sincronización Wi-Fi hacia ESP32: {e_esp}")
            
            response_msg = b"<!DOCTYPE html><html><body style='background:#121212;color:#00bcd4;text-align:center;padding:50px;font-family:sans-serif;'><h2>Configuracion Aplicada</h2><p style='color:#fff;'>HeliOs procesara los parametros del arreglo solar y el Gateway se reiniciara.</p></body></html>"
            
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

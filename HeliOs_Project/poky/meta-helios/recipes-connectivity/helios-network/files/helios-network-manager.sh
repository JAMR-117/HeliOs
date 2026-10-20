#!/bin/sh
# =============================================================================
# HeliOs Network Manager — Auto-Connect & Captive Portal Daemon
# =============================================================================
CONFIG_FILE="/data/wifi_config.json"
WPA_CONF="/tmp/wpa_supplicant.conf"
FORCE_RECONNECT=0

if [ "$1" = "--force-reconnect" ] || [ "$1" = "-f" ]; then
    FORCE_RECONNECT=1
fi

iniciar_portal() {
    echo "[HeliOs Network] Iniciando Modo Aprovisionamiento (Portal Cautivo HeliOs_Setup)..."
    rm -f "$CONFIG_FILE" 2>/dev/null || true
    killall wpa_supplicant udhcpc 2>/dev/null || true
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    pkill -f portal.py 2>/dev/null || true

    rfkill unblock wlan 2>/dev/null || true
    ip addr flush dev wlan0 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    sleep 2
    ip link set wlan0 up 2>/dev/null || true
    ip addr add 192.168.4.1/24 dev wlan0 2>/dev/null || true

    hostapd /etc/helios-network/hostapd.conf &
    dnsmasq -C /etc/helios-network/dnsmasq.conf -d &
    exec python3 /etc/helios-network/portal.py
}

# 1. Si NO se fuerza reconexión, verificar si wlan0 YA tiene una IP válida local
if [ $FORCE_RECONNECT -eq 0 ]; then
    if ip -4 a show wlan0 2>/dev/null | grep "inet " | grep -v "192.168.4.1" | grep -qv "169.254"; then
        echo "[HeliOs Network] wlan0 ya cuenta con IP asignada por DHCP. Manteniendo enlace activo."
        chmod 777 /data 2>/dev/null || true
        chmod 666 "$CONFIG_FILE" 2>/dev/null || true
        RPI_IP=$(ip -4 a show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1)
        if [ -f "$CONFIG_FILE" ] && [ -n "$RPI_IP" ]; then
            SSID=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('ssid', ''))" 2>/dev/null || true)
            PASS=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('pass', ''))" 2>/dev/null || true)
            if [ -n "$SSID" ]; then
                ESP_PAYLOAD=$(python3 -c "import json, time; print(json.dumps({'ssid':'$SSID', 'pass':'$PASS', 'broker_ip':'$RPI_IP', 'timestamp':time.time()}))" 2>/dev/null || true)
                mosquitto_pub -h 127.0.0.1 -t "helios/esp32/wifi_config" -r -q 1 -m "$ESP_PAYLOAD" 2>/dev/null || true
                echo "$ESP_PAYLOAD" > /data/esp32_wifi_sync.json 2>/dev/null || true
                chmod 666 /data/esp32_wifi_sync.json 2>/dev/null || true
            fi
        fi
        exit 0
    fi
fi

# 2. Detener servicios previos para iniciar intento de conexión
systemctl stop hostapd dnsmasq 2>/dev/null || true
pkill -f portal.py 2>/dev/null || true
killall wpa_supplicant udhcpc 2>/dev/null || true

# 3. Validar si existe el archivo de configuración con un SSID válido
if [ -f "$CONFIG_FILE" ]; then
    SSID=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('ssid', ''))" 2>/dev/null || true)
    PASS=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('pass', ''))" 2>/dev/null || true)

    if [ -z "$SSID" ]; then
        echo "[HeliOs Network] Archivo $CONFIG_FILE sin SSID válido. Iniciando portal..."
        iniciar_portal
        exit 0
    fi

    echo "[HeliOs Network] Intentando conectar a la red Wi-Fi: '$SSID'..."
    rfkill unblock wlan 2>/dev/null || true
    ip addr flush dev wlan0 2>/dev/null || true
    ip link set wlan0 up 2>/dev/null || true
    sleep 2

    # Generar configuración de wpa_supplicant
    if [ -n "$PASS" ]; then
        wpa_passphrase "$SSID" "$PASS" > "$WPA_CONF" 2>/dev/null || true
    else
        cat << EOF > "$WPA_CONF"
network={
    ssid="$SSID"
    key_mgmt=NONE
}
EOF
    fi

    wpa_supplicant -B -i wlan0 -c "$WPA_CONF" 2>/dev/null || true
    udhcpc -i wlan0 -b -R 2>/dev/null || udhcpc -i wlan0 -b 2>/dev/null || true

    # 4. Esperar hasta 25 segundos para obtener IP válida por DHCP
    CONECTADO=0
    for i in $(seq 1 25); do
        if ip -4 a show wlan0 2>/dev/null | grep "inet " | grep -v "192.168.4.1" | grep -qv "169.254"; then
            CONECTADO=1
            break
        fi
        sleep 1
    done

    if [ $CONECTADO -eq 1 ]; then
        echo "[HeliOs Network] Conexión Wi-Fi establecida exitosamente en wlan0."
        chmod 777 /data 2>/dev/null || true
        chmod 666 "$CONFIG_FILE" 2>/dev/null || true

        # Sincronización horaria (no bloqueante para el estado del servicio)
        echo "[HeliOs Network] Sincronizando reloj del sistema via HTTP..."
        python3 -c "
import urllib.request, subprocess, email.utils
try:
    h = urllib.request.urlopen('http://www.google.com', timeout=4).headers['Date']
    dt = email.utils.parsedate_to_datetime(h)
    subprocess.run(['date', '-u', '-s', dt.strftime('%Y-%m-%d %H:%M:%S')], check=True)
    print('[HeliOs Network] Reloj sincronizado:', dt.strftime('%Y-%m-%d %H:%M:%S UTC'))
except Exception as e:
    print('[HeliOs Network] No se pudo sincronizar reloj HTTP:', e)
" 2>/dev/null || true

        # Sincronización Wi-Fi hacia ESP32 con la IP real del broker en la LAN
        RPI_IP=$(ip -4 a show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1)
        if [ -n "$SSID" ] && [ -n "$RPI_IP" ]; then
            echo "[HeliOs Network] Publicando sincronización Wi-Fi para ESP32 (broker IP: $RPI_IP)..."
            ESP_PAYLOAD=$(python3 -c "import json, time; print(json.dumps({'ssid':'$SSID', 'pass':'$PASS', 'broker_ip':'$RPI_IP', 'timestamp':time.time()}))" 2>/dev/null || true)
            if [ -n "$ESP_PAYLOAD" ]; then
                mosquitto_pub -h 127.0.0.1 -t "helios/esp32/wifi_config" -r -q 1 -m "$ESP_PAYLOAD" 2>/dev/null || true
                echo "$ESP_PAYLOAD" > /data/esp32_wifi_sync.json 2>/dev/null || true
                chmod 666 /data/esp32_wifi_sync.json 2>/dev/null || true
            fi
        fi

        # Notificar a los daemons activos por MQTT para recargar reloj y efemérides en caliente
        echo "[HeliOs Network] Notificando recarga de efemérides solares vía MQTT..."
        mosquitto_pub -h 127.0.0.1 -t "helios/config/reload" -m '{"action":"net_ready"}' 2>/dev/null || true

        exit 0
    else
        echo "[HeliOs Network] Timeout de 25s agotado sin IP válida. Fallo de autenticación o red no disponible."
        iniciar_portal
        exit 0
    fi
else
    echo "[HeliOs Network] Archivo $CONFIG_FILE no encontrado. Iniciando modo aprovisionamiento..."
    iniciar_portal
    exit 0
fi

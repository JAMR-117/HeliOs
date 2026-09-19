#!/bin/sh
CONFIG_FILE="/data/wifi_config.json"
WPA_CONF="/tmp/wpa_supplicant.conf"

systemctl stop wpa_supplicant hostapd dnsmasq 2>/dev/null
pkill -f portal.py 2>/dev/null
killall wpa_supplicant udhcpc 2>/dev/null

iniciar_portal() {
    echo "Iniciando Modo Aprovisionamiento..."
    rfkill unblock wlan 2>/dev/null
    
    # PURGA OBLIGATORIA
    ip addr flush dev wlan0
    ip link set wlan0 down
    sleep 2
    ip link set wlan0 up
    
    ip addr add 192.168.4.1/24 dev wlan0
    hostapd /etc/helios-network/hostapd.conf &
    dnsmasq -C /etc/helios-network/dnsmasq.conf -d &
    python3 /etc/helios-network/portal.py
}

if [ -f "$CONFIG_FILE" ]; then
    SSID=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('ssid', ''))" 2>/dev/null)
    PASS=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('pass', ''))" 2>/dev/null)
    
    if [ -z "$SSID" ]; then
        rm -f "$CONFIG_FILE"
        iniciar_portal
        exit 0
    fi

    ip link set wlan0 up
    sleep 2
    
    wpa_passphrase "$SSID" "$PASS" > $WPA_CONF
    wpa_supplicant -B -i wlan0 -c $WPA_CONF
    udhcpc -i wlan0 -b > /dev/null 2>&1
    
    CONECTADO=0
    for i in $(seq 1 30); do
        # Busca una IP, pero que NO sea la del portal ni la de APIPA
        if ip a show wlan0 | grep "inet " | grep -v "192.168.4.1" | grep -qv "169.254"; then
            CONECTADO=1
            break
        fi
        sleep 1
    done
    
    if [ $CONECTADO -eq 1 ]; then
        exit 0
    else
        rm -f "$CONFIG_FILE"
        killall wpa_supplicant udhcpc
        iniciar_portal
    fi
else
    iniciar_portal
fi

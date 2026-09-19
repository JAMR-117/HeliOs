SUMMARY = "HeliOs Network Manager and Captive Portal"
DESCRIPTION = "Manages Wi-Fi connection or launches a Captive Portal based on saved credentials"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://helios-network-manager.sh \
    file://helios-network.service \
    file://hostapd.conf \
    file://dnsmasq.conf \
    file://portal.py \
"

S = "${WORKDIR}"

# Heredar clase systemd
inherit systemd

# Configurar el servicio para que se active automaticamente (systemctl enable)
SYSTEMD_SERVICE:${PN} = "helios-network.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Dependencias en tiempo de ejecucion
RDEPENDS:${PN} += "bash python3 hostapd dnsmasq wpa-supplicant busybox-udhcpc"

do_install() {
    # 1. Instalar el script gestor en /usr/bin/
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/helios-network-manager.sh ${D}${bindir}/

    # 2. Instalar las configuraciones y portal en un directorio seguro /etc/helios-network/
    install -d ${D}${sysconfdir}/helios-network
    install -m 0644 ${WORKDIR}/hostapd.conf ${D}${sysconfdir}/helios-network/
    install -m 0644 ${WORKDIR}/dnsmasq.conf ${D}${sysconfdir}/helios-network/
    install -m 0755 ${WORKDIR}/portal.py ${D}${sysconfdir}/helios-network/

    # 3. Instalar el servicio systemd en la ruta de unidades
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/helios-network.service ${D}${systemd_system_unitdir}/
    
    # 4. SOLUCIÓN AL CHOQUE FATAL: Crear el punto de montaje vacío
    install -d ${D}/data
}

# 2. Empaquetar la carpeta para que Yocto la inyecte en el RootFS
FILES:${PN} += "/data"

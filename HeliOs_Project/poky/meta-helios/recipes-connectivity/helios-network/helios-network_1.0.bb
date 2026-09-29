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

inherit systemd

SYSTEMD_SERVICE:${PN} = "helios-network.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} += "bash python3 hostapd dnsmasq wpa-supplicant busybox-udhcpc rfkill"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/helios-network-manager.sh ${D}${bindir}/

    install -d ${D}${sysconfdir}/helios-network
    install -m 0644 ${WORKDIR}/hostapd.conf ${D}${sysconfdir}/helios-network/
    install -m 0644 ${WORKDIR}/dnsmasq.conf ${D}${sysconfdir}/helios-network/
    install -m 0755 ${WORKDIR}/portal.py ${D}${sysconfdir}/helios-network/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/helios-network.service ${D}${systemd_system_unitdir}/
    
    # 1. SOLUCIÓN AL CHOQUE FATAL: Crear el punto de montaje vacío
    install -d ${D}/data
}

# 2. Empaquetar la carpeta para que Yocto la inyecte en el RootFS
FILES:${PN} += "/data"

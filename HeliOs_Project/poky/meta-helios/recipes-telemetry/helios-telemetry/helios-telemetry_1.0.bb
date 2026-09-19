SUMMARY = "HeliOs Telemetry, Edge Logic and Data Logger Daemons"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://helios-scada.py \
    file://helios-spa.py \
    file://helios-logger.py \
    file://helios-scada.service \
    file://helios-spa.service \
    file://helios-logger.service \
"
S = "${WORKDIR}"

inherit systemd

# Habilitar los tres servicios en el arranque
SYSTEMD_SERVICE:${PN} = "helios-scada.service helios-spa.service helios-logger.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Dependencias actualizadas para soportar pvlib y el logger
RDEPENDS:${PN} += "python3-core python3-paho-mqtt python3-requests python3-json python3-datetime python3-pvlib python3-pandas"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/helios-scada.py ${D}${bindir}/
    install -m 0755 ${WORKDIR}/helios-spa.py ${D}${bindir}/
    install -m 0755 ${WORKDIR}/helios-logger.py ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/helios-scada.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/helios-spa.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/helios-logger.service ${D}${systemd_system_unitdir}/
}

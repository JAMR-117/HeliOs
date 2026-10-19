FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://mosquitto.conf"

do_install:append() {
    # Sobrescribir el archivo maestro original de la receta base
    install -d ${D}${sysconfdir}/mosquitto
    install -m 0644 ${WORKDIR}/mosquitto.conf ${D}${sysconfdir}/mosquitto/mosquitto.conf

    # Blindaje: asegurar que escuche en todas las interfaces (0.0.0.0) desde el arranque
    grep -q "listener 1883 0.0.0.0" ${D}${sysconfdir}/mosquitto/mosquitto.conf || echo "listener 1883 0.0.0.0" >> ${D}${sysconfdir}/mosquitto/mosquitto.conf
    grep -q "allow_anonymous true" ${D}${sysconfdir}/mosquitto/mosquitto.conf || echo "allow_anonymous true" >> ${D}${sysconfdir}/mosquitto/mosquitto.conf
}

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://weston.ini"

do_install:append() {
    install -d ${D}${sysconfdir}/xdg/weston
    install -m 0644 ${WORKDIR}/weston.ini ${D}${sysconfdir}/xdg/weston/weston.ini

    # Hack Industrial: Forzar a Weston y Flutter a correr como Root
    if [ -f ${D}${systemd_system_unitdir}/weston.service ]; then
        sed -i 's/User=weston/User=root/g' ${D}${systemd_system_unitdir}/weston.service
        sed -i 's/Group=weston/Group=root/g' ${D}${systemd_system_unitdir}/weston.service
    fi
}

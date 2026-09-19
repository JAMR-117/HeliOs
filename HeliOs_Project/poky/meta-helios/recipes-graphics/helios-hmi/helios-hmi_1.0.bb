SUMMARY = "HeliOs Industrial Solar Tracking HMI Application"
DESCRIPTION = "Interfaz de usuario industrial desarrollada en Flutter sobre Wayland/Weston Kiosk"
LICENSE = "CLOSED"

inherit flutter-app

PUBSPEC_APPNAME = "helios_hmi"

SRC_URI = " \
    file:///home/jm/Flutter-HeliOs/helios_hmi.tar.gz \
"

S = "${WORKDIR}/helios_hmi"

RDEPENDS:${PN} += " \
    sqlite3 \
    libsqlite3 \
    wayland \
    mesa-megadriver \
    mesa-vulkan-drivers \
    libgbm \
    libdrm \
    libinput \
    weston \
    weston-init \
"

FLUTTER_APPLICATION_INSTALL_PREFIX = "/usr/share"
do_compile[network] = "1"

do_install:append() {
    install -d ${D}${bindir}

    # Wrapper corregido: Apuntando a la ruta exacta generada por PUBSPEC_APPNAME
    cat << 'EOF' > ${D}${bindir}/helios-hmi
#!/bin/sh
cd /usr/share/helios_hmi
exec ./helios_hmi "$@"
EOF
    chmod 0755 ${D}${bindir}/helios-hmi
}

FILES:${PN} += "${bindir}/helios-hmi"

SUMMARY = "HeliOs HMI Flutter Application"
DESCRIPTION = "Interfaz gráfica Kiosco para HeliOs usando Wayland y Flutter"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi.tar.gz"

S = "${WORKDIR}/helios_hmi"

inherit flutter-app

# Declaración obligatoria para validar el pubspec.yaml
PUBSPEC_APPNAME = "helios_hmi"

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
    fontconfig \
    ttf-dejavu-sans \
    ttf-dejavu-common \
    flutter-wayland-client \
    flutter-engine \
"

do_install:append() {
    install -d ${D}${bindir}

    # Wrapper blindado que enruta la librería libflutter_engine.so oculta
    cat << 'EOF' > ${D}${bindir}/helios-hmi
#!/bin/sh
BUNDLE_DIR=$(find /usr/share/flutter/helios_hmi -type d -name "release" | head -n 1)
export LD_LIBRARY_PATH="$BUNDLE_DIR/lib:/usr/lib:$LD_LIBRARY_PATH"
exec flutter-client -b "$BUNDLE_DIR" "$@"
EOF
    
    chmod 0755 ${D}${bindir}/helios-hmi
}

FILES:${PN} += "${bindir}/helios-hmi"

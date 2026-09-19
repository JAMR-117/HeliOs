SUMMARY = "Simulación de sistemas de energía fotovoltaica"
HOMEPAGE = "https://pvlib-python.readthedocs.io/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=cbd0b2c815d9022f6334c18c7b7cbb15"

SRC_URI[sha256sum] = "88b31c44dc07f0435af1e2d5ddcac067e6ce15917251a9f270366f61e9bd015b"

# Heredar clases de PyPI y setuptools3 para compatibilidad moderna
inherit pypi setuptools3

# Dependencias obligatorias en tiempo de ejecución
RDEPENDS:${PN} += " \
    python3-pandas \
    python3-numpy \
    python3-requests \
    python3-pytz \
"

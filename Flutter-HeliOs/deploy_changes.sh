#!/usr/bin/env bash
# =============================================================================
# deploy_changes.sh — HeliOs HMI Packaging & BitBake Deploy Script
# Empaqueta la aplicación Flutter HMI y muestra los pasos para Yocto.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colores
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }
log_cmd()     { echo -e "  ${YELLOW}→${RESET} $*"; }

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HMI_DIR="${SCRIPT_DIR}/helios_hmi"
TARBALL="${SCRIPT_DIR}/helios_hmi.tar.gz"

YOCTO_BUILD_DIR="/home/jm/HeliOs/HeliOs_Project/poky/build-helios/build"
META_HELIOS_DIR="/home/jm/HeliOs/HeliOs_Project/poky/meta-helios"

# ---------------------------------------------------------------------------
# Paso 1: Verificar que el directorio del proyecto existe
# ---------------------------------------------------------------------------
log_header "Paso 1: Verificación del workspace"
if [[ ! -d "${HMI_DIR}" ]]; then
    echo -e "${RED}[ERROR]${RESET} No se encontró el directorio: ${HMI_DIR}"
    exit 1
fi
log_info "Directorio HMI encontrado: ${HMI_DIR}"

# ---------------------------------------------------------------------------
# Paso 2: Flutter analyze (si flutter está disponible en PATH)
# ---------------------------------------------------------------------------
log_header "Paso 2: Análisis estático Flutter"
if command -v flutter &>/dev/null; then
    log_info "Ejecutando flutter analyze..."
    cd "${HMI_DIR}"
    if flutter analyze --no-fatal-warnings; then
        log_info "flutter analyze: sin errores."
    else
        log_warn "flutter analyze reportó advertencias. Revisa antes de continuar."
    fi
    cd "${SCRIPT_DIR}"
else
    log_warn "flutter no encontrado en PATH — omitiendo análisis estático."
    log_warn "Ejecuta manualmente: cd ${HMI_DIR} && flutter analyze"
fi

# ---------------------------------------------------------------------------
# Paso 3: Empaquetar helios_hmi en tarball
# ---------------------------------------------------------------------------
log_header "Paso 3: Empaquetando helios_hmi.tar.gz"

# Archivos y carpetas a EXCLUIR del tarball
EXCLUDES=(
    --exclude='helios_hmi/.dart_tool'
    --exclude='helios_hmi/.pub-cache'
    --exclude='helios_hmi/build'
    --exclude='helios_hmi/.flutter-plugins'
    --exclude='helios_hmi/.flutter-plugins-dependencies'
    --exclude='helios_hmi/ios/Flutter/ephemeral'
    --exclude='helios_hmi/macos/Flutter/ephemeral'
    --exclude='helios_hmi/linux/flutter/ephemeral'
    --exclude='helios_hmi/windows/runner/*.obj'
    --exclude='*.pyc'
    --exclude='__pycache__'
)

log_info "Creando tarball: ${TARBALL}"
tar -czf "${TARBALL}" \
    "${EXCLUDES[@]}" \
    -C "${SCRIPT_DIR}" \
    helios_hmi/

TARBALL_SIZE=$(du -sh "${TARBALL}" | cut -f1)
log_info "Tarball creado exitosamente. Tamaño: ${TARBALL_SIZE}"

# ---------------------------------------------------------------------------
# Paso 4: Verificar integridad del tarball
# ---------------------------------------------------------------------------
log_header "Paso 4: Verificación del tarball"
FILE_COUNT=$(tar -tzf "${TARBALL}" | wc -l)
log_info "Archivos empaquetados: ${FILE_COUNT}"
tar -tzf "${TARBALL}" | grep "lib/ui/dashboard.dart"   && log_info "✓ dashboard.dart incluido"
tar -tzf "${TARBALL}" | grep "lib/services/mqtt_service.dart" && log_info "✓ mqtt_service.dart incluido"
tar -tzf "${TARBALL}" | grep "lib/ui/scada_errors_screen.dart" && log_info "✓ scada_errors_screen.dart incluido"

# ---------------------------------------------------------------------------
# Paso 5: Mostrar comandos BitBake para el usuario
# ---------------------------------------------------------------------------
log_header "Paso 5: Comandos BitBake (ejecutar en la máquina Yocto)"

echo -e "${BOLD}Scripts Python de telemetría actualizados:${RESET}"
log_cmd "cp ${META_HELIOS_DIR}/recipes-telemetry/helios-telemetry/files/helios-scada.py  <destino-en-RPI>"
log_cmd "cp ${META_HELIOS_DIR}/recipes-telemetry/helios-telemetry/files/helios-logger.py <destino-en-RPI>"

echo ""
echo -e "${BOLD}Reconstruir imagen Yocto con todos los cambios:${RESET}"
echo ""
echo -e "  ${YELLOW}# 1. Inicializar entorno BitBake${RESET}"
log_cmd "source ${YOCTO_BUILD_DIR}/../oe-init-build-env ${YOCTO_BUILD_DIR}"
echo ""
echo -e "  ${YELLOW}# 2. Limpiar recetas modificadas${RESET}"
log_cmd "bitbake -c cleanall helios-telemetry helios-hmi"
echo ""
echo -e "  ${YELLOW}# 3. Reconstruir la imagen completa${RESET}"
log_cmd "bitbake core-image-base"
echo ""
echo -e "  ${YELLOW}# (Alternativa) Solo reconstruir las recetas afectadas:${RESET}"
log_cmd "bitbake helios-telemetry helios-hmi"
echo ""

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
log_header "Resumen de cambios empaquetados"
echo -e "  ${GREEN}✓${RESET} T1: paho-mqtt API v2 (helios-scada.py, helios-logger.py, simulador.py)"
echo -e "  ${GREEN}✓${RESET} T2: Contrato JSON estandarizado (v_dc, i_dc, power_w, temp_c, yield_kwh, fault)"
echo -e "  ${GREEN}✓${RESET} T3: Timer adaptativo 10s→5min en _loadForecast() (dashboard.dart)"
echo -e "  ${GREEN}✓${RESET} T4: MultimodalChartContainer → solo Histórico SCADA con auto-refresh 15s"
echo -e "  ${GREEN}✓${RESET} T4: Eliminados mock data y banner en dashboard.dart y scada_errors_screen.dart"
echo -e "  ${GREEN}✓${RESET} T5: Tarball generado en ${TARBALL}"
echo ""
log_info "¡Listo para desplegar en la Raspberry Pi 5!"

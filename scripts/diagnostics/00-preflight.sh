#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 00: COMPROBACIONES PREVIAS DEL SISTEMA (00-preflight.sh)
# Objetivo: Auditar SO Debian 13, kernel, arquitectura, recursos y conectividad
# Nodo de Ejecución: [ALL NODES] o [ESTACIÓN DEVOPS]
# Sección README: Requisitos Técnicos y Compatibilidad en Debian 13 (Trixie)
# Uso: sudo ./00-preflight.sh [--dry-run] [--force]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
elif [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/scripts/lib/common.sh" ]]; then
    source "${REPO_DIR}/scripts/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró scripts/lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
load_config
require_root

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   00: AUDITORÍA PREVIA DE COMPATIBILIDAD Y REQUISITOS (PREFLIGHT) ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

FAILED_CHECKS=0
WARNING_CHECKS=0

pass() { echo -e "  [${COLOR_GREEN}PASS${COLOR_NC}] $*"; }
warn() { echo -e "  [${COLOR_YELLOW}WARN${COLOR_NC}] $*"; (( WARNING_CHECKS += 1 )); }
fail() { echo -e "  [${COLOR_RED}FAIL${COLOR_NC}] $*"; (( FAILED_CHECKS += 1 )); }

# 1. Verificación de Sistema Operativo Debian 13 (Trixie)
log_info "1. Verificando Distribución y Versión del Sistema Operativo..."
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "debian" ]]; then
        if [[ "${VERSION_CODENAME:-}" == "trixie" ]] || [[ "${VERSION_ID:-}" == "13" ]] || [[ "${PRETTY_NAME:-}" =~ [Tt]rixie|[Tt]esting ]]; then
            pass "Sistema Operativo validado: Debian 13 (Trixie)."
        else
            warn "Distribución Debian detectada pero versión '${VERSION_CODENAME:-desconocida}' en lugar de Trixie (13)."
        fi
    else
        fail "Distribución no soportada: '${ID:-desconocida}'. Se requiere Debian GNU/Linux."
    fi
else
    fail "/etc/os-release no encontrado."
fi

# 2. Verificación de Arquitectura de CPU
log_info "2. Verificando Arquitectura de CPU..."
ARCH="$(uname -m)"
if [[ "${ARCH}" == "x86_64" ]]; then
    pass "Arquitectura de CPU soportada: x86_64 (amd64)."
else
    fail "Arquitectura '${ARCH}' no soportada. Se requiere x86_64."
fi

# 3. Verificación de Kernel Linux
log_info "3. Verificando Versión del Kernel Linux..."
KERNEL_VER="$(uname -r)"
pass "Versión de Kernel en ejecución: ${KERNEL_VER}."
if [[ "${KERNEL_VER}" =~ ^6\.(1[2-9]|[2-9][0-9]) ]] || [[ "${KERNEL_VER}" =~ ^[7-9]\. ]]; then
    pass "Kernel 6.12+ oficial confirmado (soporte eBPF y cgroups v2 óptimo)."
else
    warn "Kernel inferior a 6.12. Cilium eBPF requiere características modernas del kernel."
fi

# 4. Verificación de Recursos de Hardware (RAM y Disco NVMe 128 GB)
log_info "4. Verificando Capacidad de Memoria RAM y Disco..."
TOTAL_RAM_MB="$(free -m | awk '/^Mem:/{print $2}')"
TOTAL_DISK_GB="$(df -BG / | awk 'NR==2{print $2}' | tr -d 'G')"

if (( TOTAL_RAM_MB >= 15000 )); then
    pass "Memoria RAM: ${TOTAL_RAM_MB} MB (~16 GB) - Apto para Nexus, PXE/Ironic o K8s Control Plane."
elif (( TOTAL_RAM_MB >= 7500 )); then
    pass "Memoria RAM: ${TOTAL_RAM_MB} MB (~8 GB) - Apto para Bastion o K8s Worker."
else
    fail "Memoria RAM insuficiente: ${TOTAL_RAM_MB} MB. Mínimo requerido: 8192 MB (8 GB)."
fi

if (( TOTAL_DISK_GB >= 100 )); then
    pass "Almacenamiento en disco raíz (/): ${TOTAL_DISK_GB} GB (~128 GB hardware base)."
else
    warn "Disco raíz inferior a 100 GB (${TOTAL_DISK_GB} GB detectados). Revise particionado."
fi

# 5. Verificación de Herramientas Esenciales
log_info "5. Verificando Disponibilidad de Binarios del Sistema..."
REQUIRED_BINS=("ip" "ss" "curl" "wget" "grep" "awk" "sed" "systemctl")
for bin in "${REQUIRED_BINS[@]}"; do
    if command -v "${bin}" >/dev/null 2>&1; then
        pass "Binario presente: ${bin}"
    else
        fail "Binario ausente: ${bin}. Instalar mediante apt-get install -y ${bin}."
    fi
done

# 6. Verificación de Conectividad de Red y Gateway
log_info "6. Verificando Interfaces de Red y Enrutamiento..."
DEFAULT_GW="$(ip route show default | awk '{print $3}' | head -n1 || echo "")"
if [[ -n "${DEFAULT_GW}" ]]; then
    pass "Puerta de enlace predeterminada configurada: ${DEFAULT_GW}"
    if ping -c 1 -W 2 "${DEFAULT_GW}" >/dev/null 2>&1; then
        pass "Puerta de enlace responde a ICMP ping."
    else
        warn "La puerta de enlace ${DEFAULT_GW} no responde a ping (puede ser restricción de firewall)."
    fi
else
    warn "No se detectó puerta de enlace predeterminada en este nodo."
fi

# 7. Resumen de Preflight
echo -e "\n${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   RESUMEN FINAL DE PREFLIGHT AUDIT                               ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "  Fallas Críticas : ${FAILED_CHECKS}"
echo -e "  Advertencias    : ${WARNING_CHECKS}"

if (( FAILED_CHECKS == 0 )); then
    log_success "Auditoría Preflight completada con éxito. El nodo es apto para continuar."
    exit 0
else
    log_error "Auditoría Preflight detectó ${FAILED_CHECKS} errores críticos. Corrija los problemas antes de instalar."
    exit 1
fi

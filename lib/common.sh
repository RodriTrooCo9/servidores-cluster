#!/usr/bin/env bash
# ==============================================================================
# BIBLIOTECA COMÚN DE FUNCIONES (lib/common.sh)
# Funciones compartidas de logging, respaldo, comprobaciones y control de flujo
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# 1. CÓDIGOS DE COLOR ANSI Y ESTILOS
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_BOLD='\033[1m'
    COLOR_NC='\033[0m' # No Color
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_BOLD=''
    COLOR_NC=''
fi

# ------------------------------------------------------------------------------
# 2. CONFIGURACIÓN DE LOGS Y TRAP DE ERRORES
# ------------------------------------------------------------------------------
LOG_DIR="/var/log/infra-setup"
SCRIPT_NAME="$(basename "${0}" .sh)"

# Si no tiene permisos sobre /var/log, escribe temporalmente en /tmp
if [[ ${EUID} -eq 0 ]]; then
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
else
    LOG_FILE="/tmp/${SCRIPT_NAME}.log"
fi

_log() {
    local level="$1"
    local color="$2"
    shift 2
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # Terminal legible
    echo -e "${color}[${level}]${COLOR_NC} ${message}"
    # Archivo sin códigos de color
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

log_info()    { _log "INFO"    "${COLOR_BLUE}"   "$@"; }
log_success() { _log "OK"      "${COLOR_GREEN}"  "$@"; }
log_warn()    { _log "WARN"    "${COLOR_YELLOW}" "$@"; }
log_error()   { _log "ERROR"   "${COLOR_RED}"    "$@"; }
log_debug()   { _log "DEBUG"   "${COLOR_CYAN}"   "$@"; }

trap_error() {
    local lineno="$1"
    local command="$2"
    local code="$3"
    log_error "Fallo en la línea ${lineno}: Comando '${command}' finalizó con código de error ${code}."
    exit "${code}"
}
trap 'trap_error ${LINENO} "$BASH_COMMAND" $?' ERR

# ------------------------------------------------------------------------------
# 3. CONTROL DE PRIVILEGIOS Y BANDERAS GLOBALES
# ------------------------------------------------------------------------------
DRY_RUN=false
FORCE=false
AUTO_CONFIRM=false

parse_common_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                log_warn "Modo --dry-run activado: No se aplicarán cambios reales al sistema."
                shift
                ;;
            --force)
                FORCE=true
                log_warn "Modo --force activado: Se omiten las comprobaciones estrictas de host/rol."
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -h|--help)
                if declare -f show_help >/dev/null; then
                    show_help
                    exit 0
                else
                    echo "Uso: $0 [--dry-run] [--force] [-y|--yes] [-h|--help]"
                    exit 0
                fi
                ;;
            *)
                # Permite que el script anfitrión parsee sus propios argumentos
                shift
                ;;
        esac
    done
}

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        if [[ "${DRY_RUN}" = true ]]; then
            log_warn "Ejecución sin privilegios de root permitida únicamente debido a --dry-run."
        else
            log_error "Este script requiere privilegios de superusuario (root) o ejecución con sudo."
            exit 1
        fi
    fi
}

confirm_action() {
    local prompt="$1"
    if [[ "${AUTO_CONFIRM}" = true ]]; then
        return 0
    fi
    if [[ "${DRY_RUN}" = true ]]; then
        return 0
    fi
    echo -ne "${COLOR_YELLOW}[CONFIRMACIÓN] ${prompt} [s/N]: ${COLOR_NC}"
    read -r response
    case "${response}" in
        [sS][iI]|[sS])
            return 0
            ;;
        *)
            log_warn "Operación cancelada por el usuario."
            exit 0
            ;;
    esac
}

run_cmd() {
    if [[ "${DRY_RUN}" = true ]]; then
        echo -e "${COLOR_CYAN}[DRY-RUN] Ejecutaría:${COLOR_NC} $*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# 4. CARGA DE CONFIGURACIÓN Y MAPEO DE INVENTARIO
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_config() {
    local env_file="${SCRIPT_DIR}/config/env"
    local env_example="${SCRIPT_DIR}/config/env.example"

    if [[ -f "${env_file}" ]]; then
        log_info "Cargando archivo de entorno oficial: ${env_file}"
        # shellcheck disable=SC1090
        source "${env_file}"
    elif [[ -f "${env_example}" ]]; then
        log_warn "No se encontró config/env; cargando valores predeterminados de config/env.example."
        # shellcheck disable=SC1090
        source "${env_example}"
    else
        log_error "No se encontró ni config/env ni config/env.example."
        exit 1
    fi

    # Validación de inventario CSV
    NODES_CSV="${SCRIPT_DIR}/config/nodes.csv"
    if [[ ! -f "${NODES_CSV}" ]]; then
        log_error "Archivo de inventario no encontrado: ${NODES_CSV}"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 5. VALIDACIÓN DEL ROL / NODO ACTUAL
# ------------------------------------------------------------------------------
validate_current_node() {
    local expected_role="$1"
    if [[ "${FORCE}" = true ]]; then
        log_warn "Omitiendo validación de nodo debido a bandera --force."
        return 0
    fi

    local current_hostname
    current_hostname="$(hostname -s)"
    local current_macs
    current_macs="$(ip -br link | awk '{print tolower($3)}' | tr '\n' ' ')"
    local current_ips
    current_ips="$(ip -br addr | awk '{print $3}' | cut -d/ -f1 | tr '\n' ' ')"

    local match_found=false

    # Comprueba en nodes.csv
    while IFS=',' read -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        if [[ "${role}" == *"${expected_role}"* ]] || [[ "${expected_role}" == "all" ]]; then
            if [[ "${current_hostname}" == "${hostname}" ]] || \
               [[ " ${current_macs} " == *" ${mac} "* ]] || \
               [[ " ${current_ips} " == *" ${ip} "* ]]; then
                match_found=true
                log_success "Validación de nodo correcta: Ejecutando en ID ${id} (${hostname} / ${role})."
                break
            fi
        fi
    done < "${NODES_CSV}"

    if [[ "${match_found}" = false ]]; then
        log_error "Este script está destinado a nodos con rol '${expected_role}'."
        log_error "El nodo actual (hostname: ${current_hostname}, MACs: ${current_macs}) no coincide."
        log_error "Use --force si desea forzar la ejecución bajo su propia responsabilidad."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 6. UTILIDADES DE SISTEMA, RESPALDO Y GESTIÓN DE PAQUETES
# ------------------------------------------------------------------------------
backup_file() {
    local target="$1"
    if [[ -f "${target}" ]]; then
        local timestamp
        timestamp="$(date '+%Y%m%d_%H%M%S')"
        local backup_path="${target}.bak.${timestamp}"
        log_info "Creando respaldo de seguridad: ${backup_path}"
        run_cmd cp -a "${target}" "${backup_path}"
    fi
}

apt_install() {
    if [[ "${DRY_RUN}" = true ]]; then
        log_info "[DRY-RUN] apt-get install -y $*"
        return 0
    fi
    log_info "Instalando paquetes: $*"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

check_service() {
    local service="$1"
    if systemctl is-active --quiet "${service}"; then
        log_success "Servicio '${service}' activo y en ejecución."
        return 0
    else
        log_error "Servicio '${service}' inactivo o en estado fallido."
        return 1
    fi
}

check_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local flag="-t"
    [[ "${proto}" == "udp" ]] && flag="-u"

    if ss "${flag}"ln | grep -q ":${port} "; then
        log_success "Puerto ${proto^^} ${port} en escucha."
        return 0
    else
        log_error "Puerto ${proto^^} ${port} NO se encuentra en escucha."
        return 1
    fi
}

retry() {
    local max_attempts="$1"
    local delay_secs="$2"
    shift 2
    local attempt=1

    while true; do
        if "$@"; then
            return 0
        fi
        if (( attempt >= max_attempts )); then
            log_error "Comando falló tras ${max_attempts} intentos: $*"
            return 1
        fi
        log_warn "Intento ${attempt}/${max_attempts} falló. Reintentando en ${delay_secs}s..."
        sleep "${delay_secs}"
        (( attempt += 1 ))
    done
}

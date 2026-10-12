#!/usr/bin/env bash
# ==============================================================================
# SCRIPT MAESTRO: DESPLIEGUE MASIVO "UN SOLO BOTÓN" (deploy-masivo.sh)
# Objetivo: Enrolar y aprovisionar en paralelo la flota bare-metal según su MAC
# Soporta: --all, --nodes <lista>, --rebuild, --power-method [wol|ipmi|redfish|manual]
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.100.29.30 | MAC: 64:00:6a:2a:62:42)
# Fase README: FASE 8: Despliegue Masivo por Red Privada "Un Solo Botón"
# Uso: sudo ./deploy-masivo.sh [--all] [--nodes 314,315] [--rebuild] [--dry-run]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DEPLOY_ALL=false
FILTER_NODES=""
REBUILD=false
CLI_POWER_METHOD="${POWER_METHOD:-wol}"

show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones de Despliegue:
  --all                   Despliega todos los nodos del inventario (o los 5 nodos K8s)
  --nodes <id1,id2,...>   Despliega nodos específicos por ID o Hostname (ej. --nodes 314,315 o --nodes k8s-worker-01)
  --rebuild               Ejecuta un ciclo de reinstalación limpia (undeploy + deploy)
  --power-method <metodo> Método de encendido: wol, ipmi, redfish, manual (por defecto: ${CLI_POWER_METHOD})
  --dry-run               Muestra las órdenes que se emitirían sin encender ni desplegar
  --force                 Omite la validación de nodo controlador
  -y, --yes               Omite confirmaciones interactivas
  -h, --help              Muestra esta ayuda

Ejemplos:
  sudo ./deploy-masivo.sh --all
  sudo ./deploy-masivo.sh --nodes 321,279 --rebuild
  sudo ./deploy-masivo.sh --nodes k8s-cp-01 --power-method ipmi
EOF
}

# Parseo de banderas
parse_common_flags "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            DEPLOY_ALL=true
            shift
            ;;
        --nodes)
            FILTER_NODES="$2"
            shift 2
            ;;
        --rebuild)
            REBUILD=true
            log_warn "Modo --rebuild activado: Los nodos seleccionados serán desinstalados y reinstalados desde cero."
            shift
            ;;
        --power-method)
            CLI_POWER_METHOD="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

load_config
require_root
validate_current_node "pxe"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   DESPLIEGUE MASIVO BARE-METAL CERO-INTERVENCIÓN (ZERO-TOUCH)   ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

# ------------------------------------------------------------------------------
# 1. VERIFICACIÓN DE SERVICIOS PREVIOS EN EL CONTROLADOR PXE
# ------------------------------------------------------------------------------
log_info "1. Verificando servicios de aprovisionamiento en ${PXE_IP}..."
if [[ "${DRY_RUN}" = false ]]; then
    check_port "${HTTPBOOT_PORT}" "tcp"
    check_port "67" "udp"
    check_port "${IRONIC_API_PORT}" "tcp"
fi
log_success "Servicios HTTP Nginx, dnsmasq e Ironic API activos."

# ------------------------------------------------------------------------------
# 2. SELECCIÓN Y FILTRADO DE LA FLOTA OBJETIVO
# ------------------------------------------------------------------------------
TARGET_IDS=()
TARGET_NAMES=()
TARGET_MACS=()
TARGET_IPS=()
TARGET_ROLES=()
TARGET_BMCS=()

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    
    INCLUDE=false
    if [[ "${DEPLOY_ALL}" = true ]]; then
        INCLUDE=true
    elif [[ -n "${FILTER_NODES}" ]]; then
        IFS=',' read -ra ADDR <<< "${FILTER_NODES}"
        for item in "${ADDR[@]}"; do
            if [[ "${item}" == "${id}" ]] || [[ "${item}" == "${hostname}" ]]; then
                INCLUDE=true
                break
            fi
        done
    else
        # Si no se especifica, por defecto despliega los 5 nodos Kubernetes
        if [[ "${role}" =~ ^(k8s-control-plane-leader|k8s-control-plane|k8s-worker)$ ]]; then
            INCLUDE=true
        fi
    fi

    if [[ "${INCLUDE}" = true ]]; then
        TARGET_IDS+=("${id}")
        TARGET_NAMES+=("${hostname}")
        TARGET_MACS+=("${mac}")
        TARGET_IPS+=("${ip}")
        TARGET_ROLES+=("${role}")
        TARGET_BMCS+=("${bmc}")
    fi
done < "${NODES_CSV}"

if (( ${#TARGET_NAMES[@]} == 0 )); then
    log_error "No se seleccionó ningún nodo para despliegue. Especifique --all o --nodes <id>."
    exit 1
fi

log_info "Nodos seleccionados para despliegue (${#TARGET_NAMES[@]} equipos):"
for i in "${!TARGET_NAMES[@]}"; do
    printf "  • ID: %-4s | Hostname: %-15s | MAC: %-18s | IP: %s\n" "${TARGET_IDS[$i]}" "${TARGET_NAMES[$i]}" "${TARGET_MACS[$i]}" "${TARGET_IPS[$i]}"
done

confirm_action "¿Desea iniciar el despliegue bare-metal para estos nodos?"

# ------------------------------------------------------------------------------
# 3. CONTROL DE ENERGÍA Y ENCENDIDO DE HARDWARE
# ------------------------------------------------------------------------------
log_info "2. Gestionando control de energía mediante método: ${CLI_POWER_METHOD^^}..."

for i in "${!TARGET_NAMES[@]}"; do
    node="${TARGET_NAMES[$i]}"
    mac="${TARGET_MACS[$i]}"
    bmc="${TARGET_BMCS[$i]}"

    case "${CLI_POWER_METHOD}" in
        wol)
            log_info "Enviando Magic Packet WoL a ${node} (${mac})..."
            if [[ "${DRY_RUN}" = false ]]; then
                wakeonlan "${mac}" >/dev/null 2>&1 || true
            fi
            ;;
        ipmi)
            log_info "Enviando orden IPMI power on a ${node} (BMC: ${bmc})..."
            if [[ "${DRY_RUN}" = false ]] && [[ -n "${bmc}" ]] && [[ "${bmc}" != *"<"* ]]; then
                ipmitool -I lanplus -H "${bmc}" -U "${BMC_USER}" -P "${BMC_PASSWORD}" chassis power on || true
            fi
            ;;
        redfish)
            log_info "Enviando orden Redfish Reset a ${node} (BMC: ${bmc})..."
            if [[ "${DRY_RUN}" = false ]] && [[ -n "${bmc}" ]] && [[ "${bmc}" != *"<"* ]]; then
                curl -k -s -u "${BMC_USER}:${BMC_PASSWORD}" -X POST \
                    "https://${bmc}/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
                    -H "Content-Type: application/json" \
                    -d '{"ResetType": "On"}' || true
            fi
            ;;
        manual)
            # Procedimiento de contingencia manual
            ;;
    esac
done

if [[ "${CLI_POWER_METHOD}" == "manual" ]]; then
    echo -e "\n${COLOR_YELLOW}--> [CONTINGENCIA MANUAL]: Presione el botón de encendido físico en el rack${COLOR_NC}"
    echo -e "${COLOR_YELLOW}    para los nodos seleccionados. Luego presione ENTER para continuar...${COLOR_NC}"
    [[ "${DRY_RUN}" = false ]] && read -r
fi

# ------------------------------------------------------------------------------
# 4. TRANSICIÓN DE ESTADOS EN IRONIC Y DISPARO EN PARALELO
# ------------------------------------------------------------------------------
export OS_AUTH_TYPE=none
export OS_ENDPOINT="http://${PXE_IP}:${IRONIC_API_PORT}"

baremetal_cli() {
    if command -v openstack >/dev/null 2>&1; then
        openstack baremetal "$@"
    else
        podman exec ironic-conductor baremetal "$@"
    fi
}

check_port_open() {
    local host="$1"
    local port="$2"
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "${host}" "${port}" >/dev/null 2>&1
    else
        timeout 2 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
    fi
}

log_info "3. Preparando estados en Ironic..."
for node in "${TARGET_NAMES[@]}"; do
    if [[ "${DRY_RUN}" = false ]]; then
        CURRENT_STATE=$(baremetal_cli node show "${node}" -f value -c provision_state 2>/dev/null || echo "not_found")
        
        if [[ "${REBUILD}" = true ]] && [[ "${CURRENT_STATE}" =~ ^(active|deploy failed|error)$ ]]; then
            log_warn "Undeploy de ${node} para reinstalación limpia..."
            baremetal_cli node undeploy "${node}" || true
            sleep 3
            CURRENT_STATE=$(baremetal_cli node show "${node}" -f value -c provision_state 2>/dev/null || echo "unknown")
        fi

        if [[ "${CURRENT_STATE}" == "enroll" ]]; then
            baremetal_cli node manage "${node}" || true
        fi
        if [[ "${CURRENT_STATE}" == "manageable" ]]; then
            baremetal_cli node provide "${node}" || true
        fi
    fi
done

log_info "4. Disparando comando de despliegue en paralelo..."
for node in "${TARGET_NAMES[@]}"; do
    log_info "Lanzando orden de deploy sobre ${node}..."
    if [[ "${DRY_RUN}" = false ]]; then
        baremetal_cli node deploy "${node}" &
    fi
done

# Esperar a que terminen los procesos de envío en segundo plano
[[ "${DRY_RUN}" = false ]] && wait
log_success "Órdenes de despliegue transmitidas al agente de Ironic."

# ------------------------------------------------------------------------------
# 5. MONITORIZACIÓN DE PROGRESO EN TIEMPO REAL HASTA SSH DISPONIBLE
# ------------------------------------------------------------------------------
log_info "5. Iniciando ciclo de supervisión de la flota (Timeout: 15 minutos)..."

if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Simulación de monitoreo completada con éxito."
    exit 0
fi

TIMEOUT=900
INTERVAL=15
ELAPSED=0

while (( ELAPSED < TIMEOUT )); do
    ALL_READY=true
    echo -e "\n--- Progreso del Despliegue Masivo (Tiempo: ${ELAPSED}s / ${TIMEOUT}s) ---"
    
    for i in "${!TARGET_NAMES[@]}"; do
        node="${TARGET_NAMES[$i]}"
        ip="${TARGET_IPS[$i]}"
        
        STATE=$(baremetal_cli node show "${node}" -f value -c provision_state 2>/dev/null || echo "error")
        SSH_STATUS="ESPERANDO_BOOT"
        
        if [[ "${STATE}" == "active" ]]; then
            if check_port_open "${ip}" 22; then
                SSH_STATUS="${COLOR_GREEN}SSH_ONLINE${COLOR_NC}"
            else
                SSH_STATUS="${COLOR_YELLOW}BOOT_LOCAL${COLOR_NC}"
                ALL_READY=false
            fi
        else
            ALL_READY=false
        fi
        
        printf "  Nodo: %-15s | Estado Ironic: %-16s | IP: %-12s | Red: %b\n" "${node}" "${STATE}" "${ip}" "${SSH_STATUS}"
    done

    if [[ "${ALL_READY}" = true ]]; then
        echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
        echo -e "${COLOR_GREEN}   ¡DESPLIEGUE MASIVO EXITOSO! TODOS LOS NODOS ESTÁN EN LÍNEA   ${COLOR_NC}"
        echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"
        exit 0
    fi

    sleep "${INTERVAL}"
    (( ELAPSED += INTERVAL ))
done

log_error "Tiempo límite agotado (${TIMEOUT}s). Uno o más nodos no alcanzaron estado activo."
exit 1

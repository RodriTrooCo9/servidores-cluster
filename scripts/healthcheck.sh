#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE AUDITORÍA Y SALUD OPERATIVA (healthcheck.sh)
# Objetivo: Comprobar red, recursos, disco (128GB), NTP, Nexus, Ironic y K8s
# Nodo de Ejecución: [BASTION] o [ESTACIÓN DEVOPS]
# Salida: Tabla formateada en terminal con métricas de salud de la flota
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
load_config

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   AUDITORÍA INTEGRAL DE SALUD: FLOTA BARE-METAL Y KUBERNETES HA ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

# ------------------------------------------------------------------------------
# 1. TABLA DE ESTADO GENERAL DE LA FLOTA (8 NODOS)
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BOLD}ESTADO DE CONECTIVIDAD Y RECURSOS POR NODO:${COLOR_NC}"
printf "+------+-----------------+---------------+--------+--------+----------+------------+-------------------------+\n"
printf "| %-4s | %-15s | %-13s | %-6s | %-6s | %-8s | %-10s | %-23s |\n" "ID" "HOSTNAME" "IP" "PING" "SSH:22" "RAM LIBRE" "DISCO (/)" "ROL"
printf "+------+-----------------+---------------+--------+--------+----------+------------+-------------------------+\n"

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue

    TARGET_IP="${ip}"
    case "${id}" in
        306) SSH_USER="n306"; FALLBACK_IP="192.168.29.25" ;;
        314) SSH_USER="aget-ic"; FALLBACK_IP="192.168.21.107" ;;
        315) SSH_USER="io"; FALLBACK_IP="192.168.21.163" ;;
        321) SSH_USER="debian"; FALLBACK_IP="192.168.21.9" ;;
        *)   SSH_USER="${ADMIN_USER}"; FALLBACK_IP="" ;;
    esac

    PING_STATUS="${COLOR_RED}FAIL${COLOR_NC}"
    ACTIVE_IP="${ip}"
    if ping -c 1 -W 1 "${ip}" >/dev/null 2>&1; then
        PING_STATUS="${COLOR_GREEN}OK${COLOR_NC}  "
    elif [[ -n "${FALLBACK_IP}" ]] && ping -c 1 -W 1 "${FALLBACK_IP}" >/dev/null 2>&1; then
        PING_STATUS="${COLOR_GREEN}OK${COLOR_NC}  "
        ACTIVE_IP="${FALLBACK_IP}"
    fi

    SSH_STATUS="${COLOR_RED}DOWN${COLOR_NC}"
    RAM_FREE="N/A     "
    DISK_USAGE="N/A       "

    # Probar socket SSH
    if nc -z -w 1 "${ACTIVE_IP}" 22 >/dev/null 2>&1 || nc -z -w 1 "${ACTIVE_IP}" 2222 >/dev/null 2>&1; then
        SSH_STATUS="${COLOR_GREEN}UP${COLOR_NC}  "
        
        # Consultar métricas si hay llaves SSH
        METRICS=$(ssh -n -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=2 "${SSH_USER}@${ACTIVE_IP}" \
            "free -h | awk '/^Mem:/{print \$7}'; df -h / | awk 'NR==2{print \$5}'" 2>/dev/null || echo "")
        
        if [[ -n "${METRICS}" ]]; then
            RAM_VAL=$(echo "${METRICS}" | sed -n '1p')
            DISK_VAL=$(echo "${METRICS}" | sed -n '2p')
            [[ -n "${RAM_VAL}" ]] && RAM_FREE=$(printf "%-8s" "${RAM_VAL}")
            
            # Alerta si disco > 75% (límite 128 GB)
            NUM_DISK=$(echo "${DISK_VAL}" | tr -d '%')
            if [[ -n "${NUM_DISK}" ]] && (( NUM_DISK > 75 )); then
                DISK_USAGE="${COLOR_YELLOW}${DISK_VAL} (!)${COLOR_NC}  "
            else
                DISK_USAGE=$(printf "%-10s" "${DISK_VAL}")
            fi
        fi
    fi

    DISPLAY_IP="${ip}"
    [[ "${ACTIVE_IP}" != "${ip}" ]] && DISPLAY_IP="${ACTIVE_IP}"

    printf "| %-4s | %-15s | %-13s | %b | %b | %-8s | %b | %-23s |\n" \
        "${id}" "${hostname}" "${DISPLAY_IP}" "${PING_STATUS}" "${SSH_STATUS}" "${RAM_FREE}" "${DISK_USAGE}" "${role:0:23}"
done < "${NODES_CSV}"
printf "+------+-----------------+---------------+--------+--------+----------+------------+-------------------------+\n"

# ------------------------------------------------------------------------------
# 2. ESTADO DE LOS SERVICIOS DE INFRAESTRUCTURA
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BOLD}ESTADO DE SERVICIOS CENTRALES:${COLOR_NC}"

# Sonatype Nexus
NEXUS_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://${NEXUS_IP}:${NEXUS_PORT}/service/rest/v1/status" 2>/dev/null || true)
[[ -z "${NEXUS_CODE}" ]] && NEXUS_CODE="000"
if [[ "${NEXUS_CODE}" == "200" ]]; then
    echo -e "  • Sonatype Nexus 3 OSS (:8081)       : [${COLOR_GREEN}SALUDABLE (200 OK)${COLOR_NC}]"
else
    echo -e "  • Sonatype Nexus 3 OSS (:8081)       : [${COLOR_RED}DEGRADADO (HTTP ${NEXUS_CODE})${COLOR_NC}]"
fi

# PXE HTTP
HTTPBOOT_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://${PXE_IP}:${HTTPBOOT_PORT}/boot.ipxe" 2>/dev/null || true)
[[ -z "${HTTPBOOT_CODE}" ]] && HTTPBOOT_CODE="000"
if [[ "${HTTPBOOT_CODE}" == "200" ]]; then
    echo -e "  • Servidor HTTP Bootloader (:8089)   : [${COLOR_GREEN}ACTIVO (200 OK)${COLOR_NC}]"
else
    echo -e "  • Servidor HTTP Bootloader (:8089)   : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# Ironic API
IRONIC_STATUS=$(curl -s --connect-timeout 2 "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes" 2>/dev/null || echo "")
if [[ -n "${IRONIC_STATUS}" ]]; then
    echo -e "  • OpenStack Ironic Standalone (:6385): [${COLOR_GREEN}ACTIVO (API ONLINE)${COLOR_NC}]"
else
    echo -e "  • OpenStack Ironic Standalone (:6385): [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# ------------------------------------------------------------------------------
# 3. ESTADO DEL CLÚSTER KUBERNETES (RKE2)
# ------------------------------------------------------------------------------
KUBECONFIG_FILE="${KUBECONFIG:-/root/.kube/config}"
[[ -f "$HOME/.kube/config" ]] && KUBECONFIG_FILE="$HOME/.kube/config"

if command -v kubectl >/dev/null 2>&1 && [[ -f "${KUBECONFIG_FILE}" ]]; then
    echo -e "\n${COLOR_BOLD}ESTADO DEL CLÚSTER KUBERNETES:${COLOR_NC}"
    kubectl --kubeconfig="${KUBECONFIG_FILE}" --request-timeout=3s get nodes -o wide 2>/dev/null || {
        echo -e "  • [${COLOR_YELLOW}AVISO${COLOR_NC}] No se pudo conectar al API Server de Kubernetes en ${KUBECONFIG_FILE}."
    }
    echo ""
    kubectl --kubeconfig="${KUBECONFIG_FILE}" --request-timeout=3s get pods -A -l k8s-app=cilium 2>/dev/null || true
fi

echo -e "\n${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   AUDITORÍA FINALIZADA                                           ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

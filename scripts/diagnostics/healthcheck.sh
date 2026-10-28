#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE AUDITORÍA Y SALUD OPERATIVA (healthcheck.sh)
# Objetivo: Comprobar red, recursos, disco (128GB), NTP, Nexus, Ironic, Monitoreo y K8s
# Nodo de Ejecución: [ESTACIÓN DEVOPS] o [BASTION] o [NODO 306]
# Salida: Tabla formateada en terminal con métricas de salud de la flota
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   AUDITORÍA INTEGRAL DE SALUD: FLOTA BARE-METAL Y KUBERNETES HA ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

get_node_ssh_alias() {
    local node_id="$1"
    local hostname="$2"
    case "${node_id}" in
        314) echo "bastion" ;;
        315) echo "nexus-repo" ;;
        306) echo "pxe-controller" ;;
        269) echo "cp-01" ;;
        280) echo "cp-02" ;;
        320) echo "cp-03" ;;
        321) echo "worker-01" ;;
        279) echo "worker-02" ;;
        *)   echo "${hostname}" ;;
    esac
}

# ------------------------------------------------------------------------------
# 1. TABLA DE ESTADO GENERAL DE LA FLOTA (8 NODOS)
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BOLD}ESTADO DE CONECTIVIDAD Y RECURSOS POR NODO:${COLOR_NC}"
printf "+------+-----------------+---------------+--------+--------+----------+------------+-------------------------+\n"
printf "| %-4s | %-15s | %-13s | %-6s | %-6s | %-8s | %-10s | %-23s |\n" "ID" "HOSTNAME" "IP" "PING" "SSH:22" "RAM LIBRE" "DISCO (/)" "ROL"
printf "+------+-----------------+---------------+--------+--------+----------+------------+-------------------------+\n"

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue

    SSH_ALIAS="$(get_node_ssh_alias "${id}" "${hostname}")"
    case "${id}" in
        306) SSH_USER="n306"; FALLBACK_IP="192.168.29.25" ;;
        314) SSH_USER="aget-ic"; FALLBACK_IP="192.168.21.107" ;;
        315) SSH_USER="io"; FALLBACK_IP="192.168.21.163" ;;
        321) SSH_USER="debian"; FALLBACK_IP="192.168.21.9" ;;
        *)   SSH_USER="${ADMIN_USER}"; FALLBACK_IP="" ;;
    esac

    PING_STATUS="${COLOR_RED}FAIL${COLOR_NC}"
    ACTIVE_IP="${ip}"

    # 1. Probar ping directo
    if ping -c 1 -W 1 "${ip}" >/dev/null 2>&1; then
        PING_STATUS="${COLOR_GREEN}OK${COLOR_NC}  "
    # 2. Probar ping vía ProxyJump (Nodo 306) si la máquina actual está en otra subred
    elif ssh -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "ping -c 1 -W 1 ${ip}" >/dev/null 2>&1; then
        PING_STATUS="${COLOR_GREEN}OK${COLOR_NC}  "
    # 3. Probar fallback IP
    elif [[ -n "${FALLBACK_IP}" ]] && ping -c 1 -W 1 "${FALLBACK_IP}" >/dev/null 2>&1; then
        PING_STATUS="${COLOR_GREEN}OK${COLOR_NC}  "
        ACTIVE_IP="${FALLBACK_IP}"
    fi

    SSH_STATUS="${COLOR_RED}DOWN${COLOR_NC}"
    RAM_FREE="N/A     "
    DISK_USAGE="N/A       "

    # Probar conexión SSH vía alias o IP directa
    TARGET_SSH=""
    if ssh -n -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=2 "${SSH_ALIAS}" "true" 2>/dev/null; then
        TARGET_SSH="${SSH_ALIAS}"
    elif nc -z -w 1 "${ACTIVE_IP}" 22 >/dev/null 2>&1 || nc -z -w 1 "${ACTIVE_IP}" 2222 >/dev/null 2>&1; then
        TARGET_SSH="${SSH_USER}@${ACTIVE_IP}"
    elif [[ -n "${FALLBACK_IP}" ]] && nc -z -w 1 "${FALLBACK_IP}" 22 >/dev/null 2>&1; then
        TARGET_SSH="${SSH_USER}@${FALLBACK_IP}"
    fi

    if [[ -n "${TARGET_SSH}" ]]; then
        SSH_STATUS="${COLOR_GREEN}UP${COLOR_NC}  "
        METRICS=$(ssh -n -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=2 "${TARGET_SSH}" \
            "free -h | awk '/^Mem:/{print \$7}'; df -h / | awk 'NR==2{print \$5}'" 2>/dev/null || echo "")

        if [[ -n "${METRICS}" ]]; then
            RAM_VAL=$(echo "${METRICS}" | sed -n '1p')
            DISK_VAL=$(echo "${METRICS}" | sed -n '2p')
            [[ -n "${RAM_VAL}" ]] && RAM_FREE=$(printf "%-8s" "${RAM_VAL}")

            NUM_DISK=$(echo "${DISK_VAL}" | tr -d '%')
            if [[ -n "${NUM_DISK}" ]] && (( NUM_DISK > 75 )); then
                DISK_USAGE="${COLOR_YELLOW}${DISK_VAL} (!)${COLOR_NC}  "
            elif [[ -n "${DISK_VAL}" ]]; then
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
if [[ -z "${NEXUS_CODE}" || "${NEXUS_CODE}" == "000" ]]; then
    NEXUS_CODE=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s --connect-timeout 2 -o /dev/null -w '%{http_code}' http://${NEXUS_IP}:${NEXUS_PORT}/service/rest/v1/status" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "000")
fi
NEXUS_CODE=$(echo "${NEXUS_CODE:-000}" | grep -oE '[0-9]{3}' | tail -n1)

if [[ "${NEXUS_CODE}" == "200" ]]; then
    echo -e "  • Sonatype Nexus 3 OSS (:8081)       : [${COLOR_GREEN}SALUDABLE (200 OK)${COLOR_NC}]"
else
    echo -e "  • Sonatype Nexus 3 OSS (:8081)       : [${COLOR_RED}DEGRADADO (HTTP ${NEXUS_CODE})${COLOR_NC}]"
fi

# PXE HTTP Bootloader
HTTPBOOT_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://${PXE_IP}:${HTTPBOOT_PORT}/boot.ipxe" 2>/dev/null || true)
if [[ -z "${HTTPBOOT_CODE}" || "${HTTPBOOT_CODE}" == "000" ]]; then
    HTTPBOOT_CODE=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s --connect-timeout 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:${HTTPBOOT_PORT}/boot.ipxe" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "000")
fi
[[ -z "${HTTPBOOT_CODE}" ]] && HTTPBOOT_CODE="000"

if [[ "${HTTPBOOT_CODE}" == "200" ]]; then
    echo -e "  • Servidor HTTP Bootloader (:8089)   : [${COLOR_GREEN}ACTIVO (200 OK)${COLOR_NC}]"
else
    echo -e "  • Servidor HTTP Bootloader (:8089)   : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# Ironic API
IRONIC_STATUS=$(curl -s --connect-timeout 2 "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes" 2>/dev/null || true)
if [[ -z "${IRONIC_STATUS}" ]]; then
    IRONIC_STATUS=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s --connect-timeout 2 http://127.0.0.1:${IRONIC_API_PORT}/v1/nodes" 2>/dev/null | tail -n1 || echo "")
fi

if [[ -n "${IRONIC_STATUS}" ]]; then
    echo -e "  • OpenStack Ironic Standalone (:6385): [${COLOR_GREEN}ACTIVO (API ONLINE)${COLOR_NC}]"
else
    echo -e "  • OpenStack Ironic Standalone (:6385): [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# ------------------------------------------------------------------------------
# 3. ESTADO DEL STACK DE MONITOREO (FASE 10)
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BOLD}ESTADO DEL STACK DE MONITOREO (PROMETHEUS / GRAFANA):${COLOR_NC}"

# Prometheus
PROM_STATUS=$(curl -s --connect-timeout 2 "http://localhost:9090/-/ready" 2>/dev/null || ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s http://127.0.0.1:9090/-/ready" 2>/dev/null | tail -n1 || echo "")
if [[ "${PROM_STATUS}" == *"Ready"* ]]; then
    echo -e "  • Prometheus Time-Series (:9090)     : [${COLOR_GREEN}ACTIVO (Ready)${COLOR_NC}]"
else
    echo -e "  • Prometheus Time-Series (:9090)     : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# Grafana
GRAF_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://localhost:3000/login" 2>/dev/null || true)
if [[ -z "${GRAF_CODE}" || "${GRAF_CODE}" == "000" ]]; then
    GRAF_CODE=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/login" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "000")
fi
[[ -z "${GRAF_CODE}" ]] && GRAF_CODE="000"
if [[ "${GRAF_CODE}" =~ ^(200|302)$ ]]; then
    echo -e "  • Grafana Dashboard (:3000)          : [${COLOR_GREEN}ACTIVO (HTTP ${GRAF_CODE})${COLOR_NC}]"
else
    echo -e "  • Grafana Dashboard (:3000)          : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# Alertmanager
ALERT_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://localhost:9093/-/ready" 2>/dev/null || true)
if [[ -z "${ALERT_CODE}" || "${ALERT_CODE}" == "000" ]]; then
    ALERT_CODE=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9093/-/ready" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "000")
fi
[[ -z "${ALERT_CODE}" ]] && ALERT_CODE="000"
if [[ "${ALERT_CODE}" == "200" ]]; then
    echo -e "  • Prometheus Alertmanager (:9093)    : [${COLOR_GREEN}ACTIVO (200 OK)${COLOR_NC}]"
else
    echo -e "  • Prometheus Alertmanager (:9093)    : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# Blackbox Exporter
BB_CODE=$(curl -s --connect-timeout 2 -o /dev/null -w "%{http_code}" "http://localhost:9115" 2>/dev/null || true)
if [[ -z "${BB_CODE}" || "${BB_CODE}" == "000" ]]; then
    BB_CODE=$(ssh -q -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9115" 2>/dev/null | grep -oE '[0-9]{3}' | tail -n1 || echo "000")
fi
[[ -z "${BB_CODE}" ]] && BB_CODE="000"
if [[ "${BB_CODE}" =~ ^(200|302)$ ]]; then
    echo -e "  • Blackbox Exporter ICMP (:9115)     : [${COLOR_GREEN}ACTIVO (200 OK)${COLOR_NC}]"
else
    echo -e "  • Blackbox Exporter ICMP (:9115)     : [${COLOR_RED}INACCESIBLE${COLOR_NC}]"
fi

# ------------------------------------------------------------------------------
# 4. ESTADO DEL CLÚSTER KUBERNETES (RKE2)
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BOLD}ESTADO DEL CLÚSTER KUBERNETES (RKE2 + CILIUM):${COLOR_NC}"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
K8S_NODES=""

if command -v kubectl >/dev/null 2>&1 && [[ -f "${KUBECONFIG_FILE}" ]]; then
    K8S_NODES=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" --request-timeout=3s get nodes -o wide 2>/dev/null || echo "")
fi

if [[ -z "${K8S_NODES}" ]]; then
    K8S_NODES=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 bastion "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide" 2>/dev/null || echo "")
fi

if [[ -n "${K8S_NODES}" ]]; then
    echo "${K8S_NODES}"
    echo ""
    CILIUM_PODS=""
    if command -v kubectl >/dev/null 2>&1 && [[ -f "${KUBECONFIG_FILE}" ]]; then
        CILIUM_PODS=$(kubectl --kubeconfig="${KUBECONFIG_FILE}" --request-timeout=3s get pods -n kube-system -l k8s-app=cilium 2>/dev/null || echo "")
    fi
    if [[ -z "${CILIUM_PODS}" ]]; then
        CILIUM_PODS=$(ssh -n -o BatchMode=yes -o ConnectTimeout=3 bastion "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=cilium" 2>/dev/null || echo "")
    fi
    [[ -n "${CILIUM_PODS}" ]] && echo "${CILIUM_PODS}"
else
    echo -e "  • [${COLOR_YELLOW}AVISO${COLOR_NC}] No se pudo conectar al API Server de Kubernetes (Verificar Bastion o tunel 6443)."
fi

echo -e "\n${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   AUDITORÍA FINALIZADA                                           ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

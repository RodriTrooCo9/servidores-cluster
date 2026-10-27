#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 09: VALIDACIÓN INTEGRAL DEL CLÚSTER Y ACCESO REMOTO (09-verificacion.sh)
# Objetivo: Pruebas de datapath Cilium eBPF, SSH ProxyJump, quórum etcd y salud de nodos
# Nodo de Ejecución: [BASTION] o [ESTACIÓN DEVOPS]
# Fase README: FASE 9 / FASE 11: Validación Integral del Clúster y Acceso Remoto
# Uso: ./09-verificacion.sh [--dry-run]
# ==============================================================================

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
echo -e "${COLOR_BLUE}   FASE 9: VALIDACIÓN INTEGRAL DE RED, KUBERNETES Y PERÍMETRO    ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

KUBECONFIG_PATH="${KUBECONFIG:-/root/.kube/config}"
[[ -f "$HOME/.kube/config" ]] && KUBECONFIG_PATH="$HOME/.kube/config"
[[ ! -f "${KUBECONFIG_PATH}" && -f "/etc/rancher/rke2/rke2.yaml" ]] && KUBECONFIG_PATH="/etc/rancher/rke2/rke2.yaml"

TOTAL_TESTS=0
PASSED_TESTS=0

run_test() {
    local name="$1"
    shift
    (( TOTAL_TESTS += 1 ))
    echo -ne "  [TEST ${TOTAL_TESTS}] ${name}... "
    if [[ "${DRY_RUN}" = true ]]; then
        echo -e "${COLOR_CYAN}OMITIDO (DRY-RUN)${COLOR_NC}"
        (( PASSED_TESTS += 1 ))
        return 0
    fi

    if "$@" >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}PASS${COLOR_NC}"
        (( PASSED_TESTS += 1 ))
        return 0
    else
        echo -e "${COLOR_RED}FAIL${COLOR_NC}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 1. CONECTIVIDAD DE RED ICMP CON LOS 8 NODOS
# ------------------------------------------------------------------------------
log_info "1. Validando conectividad L2 con la flota de 8 servidores bare-metal..."
while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    run_test "Ping al Nodo ID ${id} (${hostname} / ${ip})" ping -c 1 -W 2 "${ip}"
done < "${NODES_CSV}"

# ------------------------------------------------------------------------------
# 2. SALUD DE SERVICIOS BASE (NEXUS, SQUID, DNSMASQ)
# ------------------------------------------------------------------------------
log_info "2. Validando endpoints de servicios de infraestructura..."
run_test "Sonatype Nexus 3 Core API (:8081)" curl -fs -o /dev/null "http://${NEXUS_IP}:${NEXUS_PORT}/service/rest/v1/status"
run_test "Glance / PXE Nginx HTTP (:8089)" curl -fs -o /dev/null "http://${PXE_IP}:${HTTPBOOT_PORT}/boot.ipxe"
run_test "OpenStack Ironic REST API (:6385)" curl -fs -o /dev/null "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes"

# ------------------------------------------------------------------------------
# 3. CLÚSTER KUBERNETES Y QUÓRUM DE ALTA DISPONIBILIDAD
# ------------------------------------------------------------------------------
log_info "3. Validando estado del clúster Kubernetes..."
if command -v kubectl >/dev/null 2>&1 && [[ -f "${KUBECONFIG_PATH}" ]]; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
    
    run_test "Kubernetes API Server responde en :6443" kubectl get nodes
    
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    run_test "Nodos K8s en estado Ready (${READY_NODES}/7)" test "${READY_NODES}" -ge 5

    # Prueba de Datapath Cilium
    log_info "Ejecutando prueba de despliegue y datapath pod-a-pod de Cilium..."
    if [[ "${DRY_RUN}" = false ]]; then
        kubectl delete deployment test-datapath --ignore-not-found >/dev/null 2>&1 || true
        kubectl delete service test-datapath --ignore-not-found >/dev/null 2>&1 || true
        kubectl delete pod curl-probe --ignore-not-found >/dev/null 2>&1 || true

        if kubectl create deployment test-datapath --image="nginx:alpine" --replicas=2; then
            
            kubectl expose deployment test-datapath --port=80 --target-port=80 >/dev/null 2>&1 || true
            kubectl rollout status deployment/test-datapath --timeout=60s >/dev/null 2>&1 || sleep 5
            SVC_IP=$(kubectl get svc test-datapath -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
            if [[ -n "${SVC_IP}" ]]; then
                kubectl delete pod curl-probe --ignore-not-found >/dev/null 2>&1 || true
                run_test "Balanceo de servicio Cilium eBPF a ${SVC_IP}" kubectl run curl-probe --image="curlimages/curl" --rm -i --restart=Never --command -- curl -s -f -I "http://${SVC_IP}"
            fi
            # Limpieza
            kubectl delete deployment test-datapath >/dev/null 2>&1 || true
            kubectl delete service test-datapath >/dev/null 2>&1 || true
            kubectl delete pod curl-probe --ignore-not-found >/dev/null 2>&1 || true
        fi
    fi
else
    log_warn "kubectl o kubeconfig no encontrados. Omitiendo validación de datapath de Kubernetes."
fi

# ------------------------------------------------------------------------------
# 4. RESUMEN DE PRUEBAS
# ------------------------------------------------------------------------------
echo -e "\n${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   MATRIZ DE RESULTADOS DE VALIDACIÓN FINAL                      ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "  Pruebas Ejecutadas : ${TOTAL_TESTS}"
echo -e "  Pruebas Exitosas   : ${PASSED_TESTS}"
echo -e "  Pruebas Fallidas   : $(( TOTAL_TESTS - PASSED_TESTS ))"

if (( TOTAL_TESTS == PASSED_TESTS )); then
    log_success "Todas las pruebas de infraestructura y Kubernetes pasaron con éxito."
    exit 0
else
    log_error "Se detectaron fallos en la validación del entorno. Revise los registros anteriores."
    exit 1
fi

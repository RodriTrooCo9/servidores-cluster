#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 08: DESINSTALACIÓN DE KUBERNETES RKE2 (rollback-08-kubernetes.sh)
# Objetivo: Desinstalar RKE2, detener servicios, limpiar directorios y CNI Cilium
# Nodo de Ejecución: [CONTROL-PLANE] / [WORKER]
# Uso: sudo ./rollback-08-kubernetes.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 8 (DESINSTALACIÓN TOTAL DE RKE2)    ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de desinstalar Kubernetes RKE2 y purgar sus datos en este nodo?"

# 1. Ejecutar scripts oficiales de desinstalación de RKE2 si están disponibles
if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
    log_info "Ejecutando script oficial /usr/local/bin/rke2-uninstall.sh..."
    /usr/local/bin/rke2-uninstall.sh || true
elif [[ -f /usr/local/bin/rke2-agent-uninstall.sh ]]; then
    log_info "Ejecutando script oficial /usr/local/bin/rke2-agent-uninstall.sh..."
    /usr/local/bin/rke2-agent-uninstall.sh || true
else
    log_info "Deteniendo y purgando manualmente servicios rke2..."
    systemctl stop rke2-server rke2-agent 2>/dev/null || true
    systemctl disable rke2-server rke2-agent 2>/dev/null || true
fi

# 2. Limpieza de directorios de estado
log_info "Limpiando directorios de configuración y base etcd local..."
rm -rf /etc/rancher/rke2 /var/lib/rancher/rke2 /var/lib/kubelet 2>/dev/null || true

# 3. Limpieza de interfaces virtuales de Cilium si persisten
log_info "Limpiando interfaces virtuales de Cilium..."
for iface in cilium_host cilium_net cilium_vxlan; do
    ip link delete "${iface}" 2>/dev/null || true
done

log_success "Reversión de Kubernetes RKE2 completada."

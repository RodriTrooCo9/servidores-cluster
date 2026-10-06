#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 06: REVERSIÓN DE IRONIC STANDALONE (rollback-06-openstack-glance-bifrost.sh)
# Objetivo: Detener y eliminar contenedor Podman de Ironic y limpiar inventario
# Nodo de Ejecución: [PXE]
# Uso: sudo ./rollback-06-openstack-glance-bifrost.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 6 (OPENSTACK IRONIC STANDALONE)     ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de detener y eliminar el contenedor de Ironic Standalone?"

# 1. Detener y remover contenedor
log_info "Deteniendo y eliminando contenedor Podman 'ironic-conductor'..."
podman stop ironic-conductor 2>/dev/null || true
podman rm ironic-conductor 2>/dev/null || true

# 2. Limpiar inventario y base de datos local
rm -f /opt/ironic/baremetal.yml
log_warn "NOTA: Las imágenes en /httpboot/images y /httpboot/ipa se conservan por precaución."

log_success "Reversión de Fase 6 completada."

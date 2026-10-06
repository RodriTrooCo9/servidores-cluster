#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 07: REVERSIÓN DE ARTEFACTOS CLOUD-INIT (rollback-07-cloud-init.sh)
# Objetivo: Limpiar volúmenes temporales de ConfigDrive y plantillas
# Nodo de Ejecución: [PXE]
# Uso: sudo ./rollback-07-cloud-init.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 7 (ARTEFACTOS CLOUD-INIT Y CONFIGDRIVE)${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de eliminar las imágenes generadas de ConfigDrive?"

log_info "Limpiando directorio /opt/infra/configdrive/..."
rm -rf /opt/infra/configdrive/* 2>/dev/null || true

log_success "Reversión de Fase 7 completada."

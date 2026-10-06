#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 03: REVERSIÓN DE SONATYPE NEXUS 3 (rollback-03-nexus.sh)
# Objetivo: Detener Nexus, desmantelar unidad systemd y purgar base de datos
# Nodo de Ejecución: [NEXUS]
# Uso: sudo ./rollback-03-nexus.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 3 (SONATYPE NEXUS Y POSTGRESQL 16)  ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de detener y desmantelar Sonatype Nexus 3 en este servidor?"

# 1. Detener y deshabilitar Nexus
log_info "Deteniendo servicio systemd 'nexus'..."
systemctl stop nexus 2>/dev/null || true
systemctl disable nexus 2>/dev/null || true
rm -f /etc/systemd/system/nexus.service
systemctl daemon-reload

# 2. Eliminar guardia de disco
rm -f /etc/cron.hourly/nexus-disk-guard

# 3. Purgar base de datos PostgreSQL
load_config
log_info "Eliminando base de datos y usuario de Nexus en PostgreSQL..."
sudo -u postgres psql << EOF 2>/dev/null || true
DROP DATABASE IF EXISTS ${POSTGRES_NEXUS_DB};
DROP USER IF EXISTS ${POSTGRES_NEXUS_USER};
EOF

log_warn "NOTA: Los archivos binarios y blobs en /opt/sonatype se conservan por precaución."
log_warn "Para eliminarlos manualmente ejecute: rm -rf /opt/sonatype"
log_success "Reversión de Fase 3 completada."

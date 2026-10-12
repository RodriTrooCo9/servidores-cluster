#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 10: REVERSIÓN DEL STACK DE MONITOREO (rollback-10-monitoreo.sh)
# Objetivo: Detener y desinstalar Node Exporter, Prometheus, Grafana,
#           Alertmanager y Blackbox Exporter restaurando el estado original.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 10 (STACK DE MONITOREO)            ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de desinstalar los componentes de monitoreo de este nodo?"

# 1. Detener y deshabilitar servicios si existen
log_info "Deteniendo y deshabilitando servicios de monitoreo..."
for svc in node_exporter prometheus alertmanager blackbox_exporter grafana-server; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        systemctl stop "${svc}" || true
    fi
    if systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
        systemctl disable "${svc}" || true
    fi
    rm -f "/etc/systemd/system/${svc}.service"
done

# 2. Eliminar binarios instalados
log_info "Eliminando binarios..."
rm -f /usr/local/bin/{node_exporter,prometheus,promtool,alertmanager,amtool,blackbox_exporter}

# 3. Eliminar directorios de configuración y datos
log_info "Eliminando directorios de configuración y base de datos TSDB..."
rm -rf /etc/prometheus /var/lib/prometheus /etc/alertmanager /var/lib/alertmanager /etc/blackbox_exporter

# 4. Purgar Grafana si está presente
if dpkg -l | grep -q grafana; then
    log_info "Purgando paquete Grafana..."
    apt-get purge -y grafana || true
    rm -rf /etc/grafana /var/lib/grafana /var/log/grafana
fi

# 5. Eliminar usuarios de sistema
for usr in node_exporter prometheus alertmanager; do
    if id -u "${usr}" &>/dev/null; then
        userdel -r "${usr}" 2>/dev/null || userdel "${usr}" 2>/dev/null || true
    fi
done

systemctl daemon-reload
log_success "Rollback de la Fase 10 completado con éxito."

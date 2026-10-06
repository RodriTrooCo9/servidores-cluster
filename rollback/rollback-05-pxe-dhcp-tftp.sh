#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 05: REVERSIÓN DE PXE, DHCP Y TFTP (rollback-05-pxe-dhcp-tftp.sh)
# Objetivo: Detener dnsmasq, remover reservas de red y deshabilitar Nginx HTTP :8089
# Nodo de Ejecución: [PXE]
# Uso: sudo ./rollback-05-pxe-dhcp-tftp.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 5 (PXE, DHCP dnsmasq Y TFTP)        ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de detener dnsmasq y deshabilitar el servidor PXE?"

# 1. Detener dnsmasq
log_info "Deteniendo y deshabilitando dnsmasq..."
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

# 2. Restaurar dnsmasq.conf
LATEST_DNS_BAK=$(ls -t /etc/dnsmasq.conf.bak.* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_DNS_BAK}" ]]; then
    log_info "Restaurando dnsmasq.conf desde: ${LATEST_DNS_BAK}"
    cp -a "${LATEST_DNS_BAK}" /etc/dnsmasq.conf
fi

# 3. Remover sitio Nginx HTTP
rm -f /etc/nginx/sites-enabled/httpboot
rm -f /etc/nginx/sites-available/httpboot
systemctl reload nginx 2>/dev/null || true

log_success "Reversión de Fase 5 completada."

#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 02: REVERSIÓN DE BASTION HOST (rollback-02-bastion.sh)
# Objetivo: Revertir endurecimiento SSH, detener Squid y restablecer nftables
# Nodo de Ejecución: [BASTION]
# Uso: sudo ./rollback-02-bastion.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 2 (BASTION HOST, SQUID Y NFTABLES)  ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de revertir el endurecimiento perimetral de este Bastion Host?"

# 1. Revertir SSH Drop-in
SSH_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
if [[ -f "${SSH_DROPIN}" ]]; then
    log_info "Eliminando ${SSH_DROPIN}..."
    rm -f "${SSH_DROPIN}"
    if sshd -t; then
        systemctl reload ssh || systemctl restart ssh
        log_success "SSH restablecido a su configuración predeterminada."
    fi
fi

# 2. Detener y deshabilitar Squid
log_info "Deteniendo y deshabilitando servicio Squid..."
systemctl stop squid 2>/dev/null || true
systemctl disable squid 2>/dev/null || true

# 3. Restablecer Firewall nftables
log_info "Limpiando reglas de cortafuegos nftables..."
if command -v nft >/dev/null 2>&1; then
    nft flush ruleset 2>/dev/null || true
fi
systemctl stop nftables 2>/dev/null || true
systemctl disable nftables 2>/dev/null || true

log_success "Reversión de Fase 2 completada."

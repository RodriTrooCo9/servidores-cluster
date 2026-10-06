#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 01: REVERSIÓN DE CONFIGURACIÓN BASE (rollback-01-base-servidores.sh)
# Objetivo: Restaurar /etc/hosts, configuración de red y Chrony desde respaldos
# Nodo de Ejecución: [ALL NODES]
# Uso: sudo ./rollback-01-base-servidores.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 1 (CONFIGURACIÓN BASE DEL NODO)     ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de revertir la configuración de red y hosts a sus respaldos?"

# 1. Restaurar /etc/hosts
LATEST_HOSTS_BAK=$(ls -t /etc/hosts.bak.* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_HOSTS_BAK}" ]]; then
    log_info "Restaurando /etc/hosts desde: ${LATEST_HOSTS_BAK}"
    cp -a "${LATEST_HOSTS_BAK}" /etc/hosts
else
    log_warn "No se encontró respaldo /etc/hosts.bak.*. Manteniendo archivo actual."
fi

# 2. Restaurar systemd-networkd
NETWORK_CONF="/etc/systemd/network/10-lan-static.network"
LATEST_NET_BAK=$(ls -t /etc/systemd/network/10-lan-static.network.bak.* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_NET_BAK}" ]]; then
    log_info "Restaurando configuración de red desde: ${LATEST_NET_BAK}"
    cp -a "${LATEST_NET_BAK}" "${NETWORK_CONF}"
else
    log_warn "Eliminando ${NETWORK_CONF}..."
    rm -f "${NETWORK_CONF}"
fi
systemctl restart systemd-networkd 2>/dev/null || true

# 3. Restaurar Chrony
CHRONY_CONF="/etc/chrony/chrony.conf"
LATEST_CHRONY_BAK=$(ls -t /etc/chrony/chrony.conf.bak.* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_CHRONY_BAK}" ]]; then
    log_info "Restaurando Chrony desde: ${LATEST_CHRONY_BAK}"
    cp -a "${LATEST_CHRONY_BAK}" "${CHRONY_CONF}"
    systemctl restart chrony 2>/dev/null || true
fi

log_success "Reversión de Fase 1 completada."

#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 02: CONFIGURACIÓN Y ENDURECIMIENTO DEL BASTION HOST (02-bastion.sh)
# Objetivo: SSH en puerto 2222, Squid Proxy Egress (:3128) y Firewall nftables
# Nodo de Ejecución: [BASTION] (Nodo 314 | IP: 10.0.1.10 | MAC: 64:00:6a:2a:60:62)
# Fase README: FASE 2: Bastion Host (Seguridad Perimetral, SSH ProxyJump y nftables)
# Uso: sudo ./02-bastion.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
load_config
require_root
validate_current_node "bastion"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 2: ENDURECIMIENTO DE BASTION HOST, SQUID Y NFTABLES      ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

confirm_action "¿Desea aplicar el endurecimiento perimetral en este Bastion Host?"

# ------------------------------------------------------------------------------
# 2.1 ENDURECIMIENTO DE SSHD (PUERTO 2222)
# ------------------------------------------------------------------------------
log_info "2.1 Configurando endurecimiento de OpenSSH en puerto ${BASTION_SSH_PORT}..."
SSH_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
backup_file "${SSH_DROPIN}"

if [[ "${DRY_RUN}" = false ]]; then
    mkdir -p /etc/ssh/sshd_config.d
    cat > "${SSH_DROPIN}" << EOF
Port ${BASTION_SSH_PORT}
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${ADMIN_USER}
EOF

    # PROTOCOLO DE SEGURIDAD DEL README: Validar sintaxis antes de reiniciar
    log_info "Validando sintaxis de configuración sshd con 'sshd -t'..."
    if sshd -t; then
        log_success "Sintaxis de SSH válida. Recargando servicio ssh..."
        systemctl reload ssh || systemctl restart ssh
    else
        log_error "Error crítico en sintaxis de sshd. Revertiendo configuración..."
        rm -f "${SSH_DROPIN}"
        exit 1
    fi
fi
log_success "Servidor OpenSSH asegurado en puerto ${BASTION_SSH_PORT}."

# ------------------------------------------------------------------------------
# 2.2 CONFIGURACIÓN DE SQUID PROXY EGRESS (PUERTO 3128)
# ------------------------------------------------------------------------------
log_info "2.2 Instalando y asegurando Squid Proxy Egress..."
apt_install squid

SQUID_CONF="/etc/squid/squid.conf"
backup_file "${SQUID_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${SQUID_CONF}" << EOF
http_port ${BASTION_LAN_IP}:${SQUID_PORT}

acl localnet src ${INTERNAL_SUBNET}
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost
http_access allow localnet
http_access deny all

cache_mem 512 MB
maximum_object_size 1024 MB
access_log daemon:/var/log/squid/access.log squid
EOF

    systemctl restart squid
    systemctl enable squid
fi
log_success "Squid Proxy configurado en ${BASTION_LAN_IP}:${SQUID_PORT}."

# ------------------------------------------------------------------------------
# 2.3 CORTAFUEGOS NFTABLES DE ALTO RENDIMIENTO
# ------------------------------------------------------------------------------
log_info "2.3 Configurando cortafuegos perimetral nftables..."
apt_install nftables

NFT_CONF="/etc/nftables.conf"
backup_file "${NFT_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${NFT_CONF}" << EOF
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state established,related accept

        # Acceso SSH de administración externo
        tcp dport ${BASTION_SSH_PORT} accept

        # Servicios habilitados para la subred privada LAN (${BASTION_LAN_IFACE})
        iif "${BASTION_LAN_IFACE}" tcp dport { 22, ${SQUID_PORT} } accept
        iif "${BASTION_LAN_IFACE}" udp dport { ${CHRONY_NTP_PORT} } accept
        iif "${BASTION_LAN_IFACE}" ip protocol icmp accept
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF

    # PROTOCOLO DE SEGURIDAD: Probar compilación de reglas antes de aplicar
    log_info "Validando sintaxis de reglas nftables con 'nft -c -f'..."
    if nft -c -f "${NFT_CONF}"; then
        log_success "Sintaxis nftables correcta. Aplicando reglas de cortafuegos..."
        systemctl enable --now nftables
        systemctl restart nftables
    else
        log_error "Error en sintaxis de nftables. Cancelando activación para evitar bloqueo."
        exit 1
    fi
fi
log_success "Reglas de firewall nftables activadas y persistentes."

# ------------------------------------------------------------------------------
# 2.4 VALIDACIÓN DE FASE 2
# ------------------------------------------------------------------------------
log_info "2.4 Ejecutando validación de puertos y servicios en Bastion..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

check_port "${BASTION_SSH_PORT}" "tcp"
check_port "${SQUID_PORT}" "tcp"
check_port "${CHRONY_NTP_PORT}" "udp"
check_service "squid"
check_service "nftables"

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 2 COMPLETADA CON ÉXITO: BASTION HOST ASEGURADO            ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

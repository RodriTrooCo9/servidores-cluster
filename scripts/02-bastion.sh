#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 02: CONFIGURACIÓN Y ENDURECIMIENTO DEL BASTION HOST (02-bastion.sh)
# Objetivo: SSH en puerto 2222, Squid Proxy Egress (:3128) y Firewall nftables
# Nodo de Ejecución: [BASTION] (Nodo 314 | IP: 10.100.29.10 | MAC: 64:00:6a:2a:60:62)
# Fase README: FASE 2: Bastion Host (Seguridad Perimetral, SSH ProxyJump y nftables)
# Uso: sudo ./02-bastion.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró lib/common.sh" >&2
    exit 1
fi

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
AllowUsers ${ADMIN_USER} aget-ic
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
# 2.2.1 ENRUTAMIENTO DEL KERNEL (SYSCTL IP FORWARDING & HARDENING)
# ------------------------------------------------------------------------------
log_info "2.2.1 Configurando enrutamiento del kernel y protección anti-spoofing..."
SYSCTL_CONF="/etc/sysctl.d/99-bastion-router.conf"
backup_file "${SYSCTL_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${SYSCTL_CONF}" << 'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF
    sysctl --system >/dev/null 2>&1 || true
fi
log_success "Enrutamiento IPv4 y mitigaciones de kernel activadas."

# ------------------------------------------------------------------------------
# 2.3 CORTAFUEGOS NFTABLES DE ALTO RENDIMIENTO (AISLAMIENTO, NAT Y PROXYJUMP)
# ------------------------------------------------------------------------------
log_info "2.3 Configurando cortafuegos perimetral nftables con NAT Masquerade..."
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

        # 1. Tráfico local en loopback
        iif "lo" accept

        # 2. Conexiones establecidas y relacionadas
        ct state established,related accept
        ct state invalid drop

        # 3. Tráfico total desde la red interna del clúster (LAN)
        iif "${BASTION_LAN_IFACE}" accept

        # 4. Acceso SSH desde la red/IP de administración externa (WAN)
        iif "${BASTION_WAN_IFACE}" ip saddr { ${ADMIN_ALLOWED_IPS} } tcp dport { 22, ${BASTION_SSH_PORT} } ct state new accept

        # 5. Ping ICMP permitido solo desde administración
        iif "${BASTION_WAN_IFACE}" ip saddr { ${ADMIN_ALLOWED_IPS} } icmp type echo-request accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        # 1. Tráfico de retorno establecido
        ct state established,related accept

        # 2. Salida de los nodos del clúster (LAN) hacia la red corporativa/internet (WAN)
        iif "${BASTION_LAN_IFACE}" oif "${BASTION_WAN_IFACE}" accept

        # 3. Tráfico SSH directo o ProxyJump desde Laptop Admin hacia nodos del clúster
        iif "${BASTION_WAN_IFACE}" oif "${BASTION_LAN_IFACE}" ip saddr { ${ADMIN_ALLOWED_IPS} } tcp dport 22 accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type filter hook postrouting priority 100; policy accept;

        # Enmascarar (NAT) el tráfico del clúster al salir a la oficina
        oif "${BASTION_WAN_IFACE}" masquerade
    }
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
log_success "Reglas de firewall nftables y NAT Masquerade activadas y persistentes."

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

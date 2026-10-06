#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 05: SERVICIOS DE ARRANQUE POR RED PXE/TFTP Y DHCP (05-pxe-dhcp-tftp.sh)
# Objetivo: Instalar dnsmasq con reservas por MAC, bootloader iPXE y Nginx HTTP :8089
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.0.1.30 | MAC: 64:00:6a:2a:62:42)
# Fase README: FASE 5: Servicios de Arranque por Red PXE / iPXE con Reservas por MAC
# Uso: sudo ./05-pxe-dhcp-tftp.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
load_config
require_root
validate_current_node "pxe"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 5: CONFIGURACIÓN DE DHCP (dnsmasq), TFTP Y NGINX HTTP     ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

confirm_action "¿Desea configurar los servicios de arranque por red PXE e iPXE en este nodo?"

# ------------------------------------------------------------------------------
# 5.1 INSTALACIÓN DE PAQUETES
# ------------------------------------------------------------------------------
log_info "5.1 Instalando dnsmasq, ipxe y Nginx..."
apt_install dnsmasq ipxe nginx

# ------------------------------------------------------------------------------
# 5.2 CONFIGURACIÓN DE dnsmasq.conf CON RESERVAS POR MAC LEÍDAS DE nodes.csv
# ------------------------------------------------------------------------------
log_info "5.2 Generando configuración /etc/dnsmasq.conf con reservas de los 8 nodos..."
DNSMASQ_CONF="/etc/dnsmasq.conf"
backup_file "${DNSMASQ_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${DNSMASQ_CONF}" << EOF
interface=${PXE_IFACE}
bind-interfaces

# Gateway y DNS predeterminado (Bastión)
dhcp-option=3,${INTERNAL_GATEWAY}
dhcp-option=6,${INTERNAL_DNS}

# Rango dinámico efímero para inspección o nodos desconocidos
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${INTERNAL_NETMASK},${DHCP_LEASE_TIME}

# ==============================================================================
# RESERVAS ESTÁTICAS DE IP POR DIRECCIÓN MAC (DESDE config/nodes.csv)
# ==============================================================================
EOF

    # Generación dinámica línea por línea desde nodes.csv
    while IFS=',' read -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        echo "# Nodo ID ${id}: ${hostname} (${role})" >> "${DNSMASQ_CONF}"
        echo "dhcp-host=${mac},${ip},${hostname},infinite" >> "${DNSMASQ_CONF}"
    done < "${NODES_CSV}"

    cat >> "${DNSMASQ_CONF}" << 'EOF'

# Servidor TFTP Integrado
enable-tftp
tftp-root=/tftpboot

# Bootloaders según arquitectura del firmware
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,undionly.kpxe

dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-boot=tag:efi-x86_64,ipxe.efi
EOF
fi
log_success "Archivo /etc/dnsmasq.conf generado con reservas de la flota completa."

# ------------------------------------------------------------------------------
# 5.3 ESTRUCTURA DE TFTPBOOT, BOOTLOADERS Y SCRIPT DE ARRANQUE iPXE
# ------------------------------------------------------------------------------
log_info "5.3 Preparando directorios y binarios de arranque iPXE..."
run_cmd mkdir -p /tftpboot /httpboot/ipa /httpboot/images

if [[ "${DRY_RUN}" = false ]]; then
    if [[ -f /usr/lib/ipxe/undionly.kpxe ]]; then
        cp /usr/lib/ipxe/undionly.kpxe /tftpboot/
    fi
    if [[ -f /usr/lib/ipxe/ipxe.efi ]]; then
        cp /usr/lib/ipxe/ipxe.efi /tftpboot/
    elif [[ -f /usr/lib/ipxe/ipxe-x86_64.efi ]]; then
        cp /usr/lib/ipxe/ipxe-x86_64.efi /tftpboot/ipxe.efi
    fi

    # Script maestro de booteo iPXE
    cat > /tftpboot/boot.ipxe << EOF
#!ipxe
echo ==========================================================
echo   Aprovisionamiento Bare-Metal: Servidores 128GB NVMe
echo ==========================================================
kernel http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.kernel ipa-api-url=http://${PXE_IP}:${IRONIC_API_PORT} boot=live console=tty0 initrd=ipa.initramfs
initrd http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.initramfs
boot
EOF
fi
log_success "Binarios de arranque y script /tftpboot/boot.ipxe listos."

# ------------------------------------------------------------------------------
# 5.4 SERVIDOR HTTP NGINX EN PUERTO 8089 PARA STREAMING DE IMÁGENES
# ------------------------------------------------------------------------------
log_info "5.4 Configurando Nginx HTTP en puerto ${HTTPBOOT_PORT} para /httpboot..."
NGINX_SITE="/etc/nginx/sites-available/httpboot"
backup_file "${NGINX_SITE}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${NGINX_SITE}" << EOF
server {
    listen ${HTTPBOOT_PORT};
    server_name _;
    root /httpboot;
    autoindex on;
    sendfile on;
}
EOF

    ln -sf "${NGINX_SITE}" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    systemctl restart nginx
    systemctl enable --now dnsmasq
    systemctl restart dnsmasq
fi
log_success "Servidores dnsmasq y Nginx reiniciados."

# ------------------------------------------------------------------------------
# 5.5 VALIDACIÓN DE FASE 5
# ------------------------------------------------------------------------------
log_info "5.5 Validando puertos de escucha y descarga de boot.ipxe..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

check_port "67" "udp"
check_port "${TFTP_PORT}" "udp"
check_port "${HTTPBOOT_PORT}" "tcp"

log_info "Probando descarga de script de arranque HTTP..."
if curl -fsI "http://${PXE_IP}:${HTTPBOOT_PORT}/boot.ipxe" | grep -q "200 OK"; then
    log_success "Descarga HTTP de boot.ipxe exitosa (200 OK)."
else
    log_error "Fallo al consultar http://${PXE_IP}:${HTTPBOOT_PORT}/boot.ipxe."
    exit 1
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 5 COMPLETADA CON ÉXITO: PXE/DHCP/TFTP/HTTP EN LÍNEA       ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

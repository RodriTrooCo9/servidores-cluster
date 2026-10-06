#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 01: PREPARACIÓN BASE DEL SISTEMA OPERATIVO (01-base-servidores.sh)
# Objetivo: Hostname, /etc/hosts, red systemd-networkd, Chrony NTP y usuario admin
# Nodo de Ejecución: [ALL NODES] (Nodos 1 al 8)
# Fase README: FASE 1: Preparación Base del Sistema Operativo en Debian 13
# Uso: sudo ./01-base-servidores.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
load_config
require_root

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 1: PREPARACIÓN BASE DEL SISTEMA OPERATIVO EN DEBIAN 13   ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

# Detectar nodo actual en nodes.csv
CURRENT_HOSTNAME="$(hostname -s)"
CURRENT_MACS="$(ip -br link | awk '{print tolower($3)}' | tr '\n' ' ')"
CURRENT_IPS="$(ip -br addr | awk '{print $3}' | cut -d/ -f1 | tr '\n' ' ')"

NODE_ID=""
NODE_NAME=""
NODE_IP=""
NODE_ROLE=""
NODE_MAC=""

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    if [[ "${CURRENT_HOSTNAME}" == "${hostname}" ]] || \
       [[ " ${CURRENT_MACS} " == *" ${mac} "* ]] || \
       [[ " ${CURRENT_IPS} " == *" ${ip} "* ]]; then
        NODE_ID="${id}"
        NODE_NAME="${hostname}"
        NODE_IP="${ip}"
        NODE_ROLE="${role}"
        NODE_MAC="${mac}"
        break
    fi
done < "${NODES_CSV}"

if [[ -z "${NODE_ID}" ]]; then
    if [[ "${FORCE}" = true ]]; then
        log_warn "Nodo no encontrado en ${NODES_CSV}. Usando valores por defecto debido a --force."
        NODE_ID="999"
        NODE_NAME="${CURRENT_HOSTNAME}"
        NODE_IP="10.0.1.99"
        NODE_ROLE="custom"
    else
        log_error "El nodo actual no coincide con ningún registro en ${NODES_CSV}."
        log_error "Hostname: ${CURRENT_HOSTNAME} | MACs: ${CURRENT_MACS}"
        log_error "Use --force para omitir esta verificación."
        exit 1
    fi
fi

log_info "Configurando Nodo Físico ID ${NODE_ID} (${NODE_NAME} / IP: ${NODE_IP} / Rol: ${NODE_ROLE})"
confirm_action "¿Desea aplicar la configuración base a este nodo?"

# ------------------------------------------------------------------------------
# 1.1 CONFIGURAR HOSTNAME Y /etc/hosts
# ------------------------------------------------------------------------------
log_info "1.1 Configurando Hostname oficial y tabla /etc/hosts..."
FULL_HOSTNAME="${NODE_NAME}.${DOMAIN}"
run_cmd hostnamectl set-hostname "${FULL_HOSTNAME}"
log_success "Hostname fijado a: ${FULL_HOSTNAME}"

backup_file "/etc/hosts"
if [[ "${DRY_RUN}" = false ]]; then
    cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 ${FULL_HOSTNAME} ${NODE_NAME}

# ==============================================================================
# FLOTA BARE-METAL COMPLETA (INVENTARIO AUTOMATIZADO)
# ==============================================================================
EOF
    while IFS=',' read -r id mac hname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        printf "%-15s %-30s %s\n" "${ip}" "${hname}.${DOMAIN}" "${hname}" >> /etc/hosts
    done < "${NODES_CSV}"
fi
log_success "Archivo /etc/hosts actualizado con la flota de 8 nodos."

# ------------------------------------------------------------------------------
# 1.2 CONFIGURAR RED ESTÁTICA CON systemd-networkd
# ------------------------------------------------------------------------------
log_info "1.2 Configurando interfaz de red LAN con systemd-networkd..."
LAN_IFACE="eth0"
# En Bastion se usa eth1 para LAN interna
[[ "${NODE_ID}" == "314" ]] && LAN_IFACE="${BASTION_LAN_IFACE:-eth1}"

NETWORK_CONF="/etc/systemd/network/10-lan-static.network"
backup_file "${NETWORK_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    MATCH_DIRECTIVE="Name=${LAN_IFACE}"
    if [[ -n "${NODE_MAC}" ]] && [[ "${NODE_MAC}" != *"<"* ]]; then
        MATCH_DIRECTIVE="MACAddress=${NODE_MAC}"
    fi

    if [[ "${NODE_ID}" == "314" ]]; then
        # Salvaguarda del README: En el Bastión NO se define Gateway en LAN
        cat > "${NETWORK_CONF}" << EOF
[Match]
${MATCH_DIRECTIVE}

[Network]
Address=${NODE_IP}/24
EOF
        log_warn "Bastion (Nodo 314): Se omite Gateway en ${LAN_IFACE} para evitar conflictos de ruta WAN."
    else
        cat > "${NETWORK_CONF}" << EOF
[Match]
${MATCH_DIRECTIVE}

[Network]
Address=${NODE_IP}/24
Gateway=${INTERNAL_GATEWAY}
DNS=${INTERNAL_DNS}
EOF
    fi

    systemctl enable --now systemd-networkd
    systemctl restart systemd-networkd
fi
log_success "Red interna configurada en ${LAN_IFACE} (${NODE_IP}/24)."

# ------------------------------------------------------------------------------
# 1.3 CONFIGURACIÓN DE HORA CHRONY NTP
# ------------------------------------------------------------------------------
log_info "1.3 Configurando sincronización horaria con Chrony..."
run_cmd timedatectl set-timezone "${TIMEZONE}"
apt_install chrony

CHRONY_CONF="/etc/chrony/chrony.conf"
backup_file "${CHRONY_CONF}"

if [[ "${DRY_RUN}" = false ]]; then
    if [[ "${NODE_ID}" == "314" ]]; then
        # Bastión actúa como servidor NTP para la subred LAN
        if ! grep -q "allow ${INTERNAL_SUBNET}" "${CHRONY_CONF}"; then
            echo "allow ${INTERNAL_SUBNET}" >> "${CHRONY_CONF}"
        fi
    else
        # Nodos 2 al 8 se sincronizan contra el Bastión
        if ! grep -q "server ${INTERNAL_GATEWAY} iburst" "${CHRONY_CONF}"; then
            sed -i "1i server ${INTERNAL_GATEWAY} iburst" "${CHRONY_CONF}"
        fi
    fi
    systemctl restart chrony
fi
log_success "Servicio Chrony NTP configurado y reiniciado."

# ------------------------------------------------------------------------------
# 1.4 USUARIO ADMINISTRATIVO Y PRIVILEGIOS SUDO
# ------------------------------------------------------------------------------
log_info "1.4 Verificando usuario administrativo: ${ADMIN_USER}..."
if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    run_cmd useradd -m -s /bin/bash -G sudo "${ADMIN_USER}"
    log_success "Usuario '${ADMIN_USER}' creado."
else
    log_info "Usuario '${ADMIN_USER}' ya existe."
fi

SUDOERS_FILE="/etc/sudoers.d/99-${ADMIN_USER}"
if [[ "${DRY_RUN}" = false ]]; then
    echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_FILE}"
    chmod 0440 "${SUDOERS_FILE}"
fi
log_success "Regla sudo NOPASSWD establecida en ${SUDOERS_FILE}."

# ------------------------------------------------------------------------------
# 1.5 VALIDACIÓN DE FASE 1
# ------------------------------------------------------------------------------
log_info "1.5 Ejecutando pruebas de validación de Fase 1..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

# Validar dirección IP
if ip -brief addr show | grep -q "${NODE_IP}"; then
    log_success "Validación de IP: Asignada correctamente (${NODE_IP})."
else
    log_error "Validación de IP: ${NODE_IP} NO se encuentra activa en las interfaces."
    exit 1
fi

# Validar Chrony
if chronyc tracking | grep -qE "Reference ID|Leap status"; then
    log_success "Validación de NTP: Chrony respondiendo adecuadamente."
else
    log_warn "Chrony activo pero aún estabilizando la sincronización de reloj."
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 1 COMPLETADA CON ÉXITO EN EL NODO ${NODE_NAME}           ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

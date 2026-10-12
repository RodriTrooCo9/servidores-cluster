#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 04: CONFIGURACIÓN DE CLIENTES HACIA NEXUS (04-clientes-nexus.sh)
# Objetivo: Redirigir APT, registries containerd y variables NO_PROXY hacia Nexus
# Nodo de Ejecución: [NODOS 3 AL 8] (PXE, CPs y Workers; NO en Bastion ni Nexus)
# Fase README: FASE 4: Configuración de Clientes para Consumir Nexus
# Uso: sudo ./04-clientes-nexus.sh [--dry-run] [--force] [-y]
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

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 4: CONFIGURACIÓN DE CLIENTES APT Y REGISTROS DE NEXUS     ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

# Validación: Este script no debe ejecutarse en el Bastión (314) ni en Nexus (315)
CURRENT_HOSTNAME="$(hostname -s)"
if [[ "${FORCE}" = false ]]; then
    if [[ "${CURRENT_HOSTNAME}" =~ ^(bastion|nexus-repo)$ ]]; then
        log_error "Este script NO debe ejecutarse en el Bastión ni en el propio servidor Nexus."
        log_error "Use --force si desea forzar la ejecución bajo su propio criterio."
        exit 1
    fi
fi

confirm_action "¿Desea redirigir las descargas de APT y registros OCI hacia Nexus (${NEXUS_IP})?"

# ------------------------------------------------------------------------------
# 4.1 FUENTES APT HACIA NEXUS EN DEBIAN 13 (TRIXIE)
# ------------------------------------------------------------------------------
log_info "4.1 Redirigiendo fuentes APT hacia el proxy local de Nexus..."
SOURCES_LIST="/etc/apt/sources.list"
backup_file "${SOURCES_LIST}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${SOURCES_LIST}" << EOF
# Configuración generada por automatización: Consumo de caché local Nexus
deb http://${NEXUS_IP}:${NEXUS_PORT}/repository/debian-proxy/ trixie main contrib non-free non-free-firmware
deb http://${NEXUS_IP}:${NEXUS_PORT}/repository/debian-proxy/ trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
fi
log_success "Archivo /etc/apt/sources.list configurado hacia ${NEXUS_IP}:${NEXUS_PORT}."

# ------------------------------------------------------------------------------
# 4.2 CONFIGURACIÓN DE REGISTROS DE CONTENEDORES PARA RKE2 / containerd
# ------------------------------------------------------------------------------
log_info "4.2 Configurando mirrors de Docker Hub hacia Nexus en /etc/rancher/rke2/registries.yaml..."
REGISTRIES_YAML="/etc/rancher/rke2/registries.yaml"
backup_file "${REGISTRIES_YAML}"

if [[ "${DRY_RUN}" = false ]]; then
    mkdir -p /etc/rancher/rke2
    cat > "${REGISTRIES_YAML}" << EOF
mirrors:
  "docker.io":
    endpoint:
      - "http://${NEXUS_IP}:${NEXUS_DOCKER_GROUP_PORT}"
  "${NEXUS_IP}:${NEXUS_DOCKER_GROUP_PORT}":
    endpoint:
      - "http://${NEXUS_IP}:${NEXUS_DOCKER_GROUP_PORT}"
configs:
  "${NEXUS_IP}:${NEXUS_DOCKER_GROUP_PORT}":
    tls:
      insecure_skip_verify: true
EOF
fi
log_success "Mirrors de containerd configurados hacia Nexus (:8082)."

# ------------------------------------------------------------------------------
# 4.3 VARIABLES DE ENTORNO DE PROXY Y NO_PROXY
# ------------------------------------------------------------------------------
log_info "4.3 Configurando variables de red y exclusión NO_PROXY en /etc/environment..."
ENV_FILE="/etc/environment"
backup_file "${ENV_FILE}"

if [[ "${DRY_RUN}" = false ]]; then
    sed -i '/_proxy=/d' "${ENV_FILE}" 2>/dev/null || true
    if command -v nc >/dev/null 2>&1 && nc -z -w 2 "${BASTION_LAN_IP}" "${SQUID_PORT}" 2>/dev/null; then
        log_info "Proxy Squid activo en ${BASTION_LAN_IP}:${SQUID_PORT}. Configurando http_proxy..."
        cat >> "${ENV_FILE}" << EOF
http_proxy="http://${BASTION_LAN_IP}:${SQUID_PORT}"
https_proxy="http://${BASTION_LAN_IP}:${SQUID_PORT}"
no_proxy="localhost,127.0.0.1,${INTERNAL_SUBNET},10.42.0.0/16,10.43.0.0/16,.svc,.cluster.local"
EOF
    else
        log_warn "Proxy Squid no detectado en ${BASTION_LAN_IP}:${SQUID_PORT}. Omitiendo variables de proxy externas."
        cat >> "${ENV_FILE}" << EOF
no_proxy="localhost,127.0.0.1,${INTERNAL_SUBNET},10.42.0.0/16,10.43.0.0/16,.svc,.cluster.local"
EOF
    fi
fi
log_success "Variables de entorno aplicadas preservando el tráfico interno del clúster."

# ------------------------------------------------------------------------------
# 4.4 VALIDACIÓN DE FASE 4
# ------------------------------------------------------------------------------
log_info "4.4 Ejecutando prueba de descarga APT desde la caché local de Nexus..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

if apt-get update -qq; then
    log_success "apt-get update ejecutado correctamente a través de Nexus."
else
    log_error "Error al conectar con el proxy APT de Nexus en ${NEXUS_IP}:${NEXUS_PORT}."
    log_warn "Verifique que Sonatype Nexus tenga habilitado el 'Anonymous Access' en la UI."
    exit 1
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 4 COMPLETADA CON ÉXITO: CLIENTE CONECTADO A NEXUS         ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

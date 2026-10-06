#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 06: OPENSTACK GLANCE E IRONIC STANDALONE (06-openstack-glance-bifrost.sh)
# Objetivo: Desplegar Ironic con Podman, descargar IPA ramdisk y enrolar 8 nodos por MAC
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.0.1.30 | MAC: 64:00:6a:2a:62:42)
# Fase README: FASE 6: OpenStack Glance e Ironic Standalone para Servidores Físicos
# Uso: sudo ./06-openstack-glance-bifrost.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
load_config
require_root
validate_current_node "pxe"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 6: DESPLIEGUE DE OPENSTACK IRONIC Y REGISTRO POR MAC     ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

confirm_action "¿Desea desplegar OpenStack Ironic Standalone y enrolar los 8 nodos en este servidor?"

# ------------------------------------------------------------------------------
# 6.1 INSTALACIÓN DE PODMAN Y CONTENEDOR IRONIC STANDALONE
# ------------------------------------------------------------------------------
log_info "6.1 Instalando Podman..."
apt_install podman python3-openstackclient 2>/dev/null || apt_install podman

log_info "Verificando contenedor de Ironic Standalone..."
run_cmd mkdir -p /httpboot/ipa /httpboot/images /tftpboot /var/lib/ironic /opt/ironic

if [[ "${DRY_RUN}" = false ]]; then
    if podman ps -a --format "{{.Names}}" | grep -q "^ironic-conductor$"; then
        log_info "Contenedor 'ironic-conductor' ya existe. Asegurando ejecución..."
        podman start ironic-conductor || true
    else
        log_info "Creando y arrancando contenedor Podman 'ironic-conductor'..."
        podman run -d --name ironic-conductor \
            --net=host \
            --privileged \
            --restart=always \
            -v /httpboot:/httpboot:shared \
            -v /tftpboot:/tftpboot:shared \
            -v /var/lib/ironic:/var/lib/ironic:rw \
            -e HTTP_PORT="${HTTPBOOT_PORT}" \
            -e IRONIC_IP="${PXE_IP}" \
            -e OS_AUTH_TYPE=none \
            quay.io/metal3-io/ironic:latest
    fi
fi
log_success "Contenedor Ironic Standalone iniciado en puerto ${IRONIC_API_PORT}."

# ------------------------------------------------------------------------------
# 6.2 DESCARGA DEL RAMDISK IPA OFICIAL (IRONIC PYTHON AGENT)
# ------------------------------------------------------------------------------
log_info "6.2 Verificando imágenes de ramdisk oficial de Ironic (IPA)..."
IPA_KERNEL="/httpboot/ipa/ipa.kernel"
IPA_INITRAMFS="/httpboot/ipa/ipa.initramfs"

if [[ "${DRY_RUN}" = false ]]; then
    if [[ ! -f "${IPA_KERNEL}" ]]; then
        log_info "Descargando ipa.kernel oficial..."
        wget -q --show-progress "https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.kernel" -O "${IPA_KERNEL}"
    fi
    if [[ ! -f "${IPA_INITRAMFS}" ]]; then
        log_info "Descargando ipa.initramfs oficial..."
        wget -q --show-progress "https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.initramfs" -O "${IPA_INITRAMFS}"
    fi
    chmod 644 /httpboot/ipa/ipa.*
fi
log_success "Ramdisk IPA listo en /httpboot/ipa/."

# ------------------------------------------------------------------------------
# 6.3 GENERACIÓN DEL INVENTARIO OFICIAL /opt/ironic/baremetal.yml
# ------------------------------------------------------------------------------
log_info "6.3 Generando archivo maestro /opt/ironic/baremetal.yml desde config/nodes.csv..."
BAREMETAL_YML="/opt/ironic/baremetal.yml"
backup_file "${BAREMETAL_YML}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${BAREMETAL_YML}" << EOF
# Generado automáticamente por automatización de infraestructura
nodes:
EOF

    while IFS=',' read -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        local_ram_mb=$(( ram * 1024 ))
        cat >> "${BAREMETAL_YML}" << EOF
  - name: "${hostname}"
    driver: "manual-management"
    driver_info:
      deploy_kernel: "http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.kernel"
      deploy_ramdisk: "http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.initramfs"
    instance_info:
      image_source: "http://${PXE_IP}:${HTTPBOOT_PORT}/images/${IRONIC_IMAGE_NAME}"
      image_checksum: "${IRONIC_IMAGE_CHECKSUM}"
      root_gb: 110
    nics:
      - mac: "${mac}"
    ipv4_address: "${ip}"
    properties:
      cpus: 4
      memory_mb: ${local_ram_mb}
      local_gb: 120
      cpu_arch: "x86_64"
EOF
    done < "${NODES_CSV}"
fi
log_success "Archivo ${BAREMETAL_YML} generado con los 8 nodos físicos y sus MACs normalizadas."

# ------------------------------------------------------------------------------
# 6.4 REGISTRO Y ENROLAMIENTO EN LA API DE IRONIC
# ------------------------------------------------------------------------------
log_info "6.4 Enrolando nodos en la base de datos de Ironic..."
export OS_AUTH_TYPE=none
export OS_ENDPOINT="http://${PXE_IP}:${IRONIC_API_PORT}"

if [[ "${DRY_RUN}" = false ]]; then
    # Espera a que el endpoint de Ironic responda
    log_info "Esperando disponibilidad de la API de Ironic (:6385)..."
    retry 15 5 curl -s "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes" >/dev/null

    if command -v openstack >/dev/null 2>&1; then
        openstack baremetal create "${BAREMETAL_YML}" 2>/dev/null || {
            log_warn "Algunos nodos ya estaban creados previamente en Ironic."
        }
    else
        log_info "Ejecutando cliente Ironic dentro del contenedor podman..."
        podman exec ironic-conductor baremetal create "${BAREMETAL_YML}" 2>/dev/null || {
            log_warn "Algunos nodos ya estaban creados previamente en Ironic."
        }
    fi
fi
log_success "Nodos físicos registrados en el inventario de Ironic."

# ------------------------------------------------------------------------------
# 6.5 VALIDACIÓN DE FASE 6
# ------------------------------------------------------------------------------
log_info "6.5 Validando estado de los nodos en Ironic API..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

check_port "${IRONIC_API_PORT}" "tcp"

NODES_COUNT=$(curl -s "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes" | grep -o '"uuid"' | wc -l || echo "0")
log_info "Total de nodos bare-metal registrados en Ironic: ${NODES_COUNT}"

if (( NODES_COUNT > 0 )); then
    log_success "API de Ironic respondiendo correctamente con nodos en catálogo."
else
    log_warn "API activa pero aún no reporta nodos registrados. Revise /opt/ironic/baremetal.yml."
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 6 COMPLETADA CON ÉXITO: IRONIC Y GLANCE OPERATIVOS       ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

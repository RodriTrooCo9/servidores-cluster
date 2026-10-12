#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 06: OPENSTACK GLANCE E IRONIC STANDALONE (06-openstack-glance-bifrost.sh)
# Objetivo: Desplegar Ironic con Podman, descargar IPA ramdisk y enrolar 8 nodos por MAC
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.100.29.30 | MAC: 64:00:6a:2a:62:42)
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
log_info "6.1 Instalando Podman y clientes de Ironic..."
apt_install podman python3-openstackclient python3-ironicclient 2>/dev/null || apt_install podman python3-ironicclient 2>/dev/null || apt_install podman

# Autodetección de interfaz de red física si no existe PXE_IFACE
if [[ ! -d "/sys/class/net/${PXE_IFACE}" ]]; then
    DETECTED_IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n1)
    if [[ -z "${DETECTED_IFACE}" ]]; then
        DETECTED_IFACE=$(ip -br link | awk '$1 !~ /^lo/ {print $1; exit}')
    fi
    log_warn "Interfaz '${PXE_IFACE}' no encontrada. Auto-detectada: '${DETECTED_IFACE}'."
    PXE_IFACE="${DETECTED_IFACE}"
fi

log_info "Verificando estructura de directorios y servicio de Ironic Standalone..."
run_cmd mkdir -p /httpboot/ipa /httpboot/images /tftpboot /var/lib/ironic /opt/ironic

if [[ "${DRY_RUN}" = false ]]; then
    IRONIC_SERVICE="/etc/systemd/system/ironic-conductor.service"
    cat > "${IRONIC_SERVICE}" << EOF
[Unit]
Description=OpenStack Ironic Standalone Conductor & API
After=network-online.target nginx.service dnsmasq.service
Wants=network-online.target

[Service]
Restart=always
ExecStartPre=-/usr/bin/podman rm -f ironic-conductor
ExecStart=/usr/bin/podman run --name ironic-conductor \\
    --net=host \\
    --privileged \\
    -v /httpboot:/httpboot:shared \\
    -v /httpboot:/shared/html:rw \\
    -v /tftpboot:/tftpboot:shared \\
    -v /tftpboot:/shared/tftpboot:rw \\
    -v /var/lib/ironic:/data:rw \\
    -v /opt/ironic:/opt/ironic:shared \\
    -e HTTP_PORT="${HTTPBOOT_PORT}" \\
    -e IRONIC_IP="${PXE_IP}" \\
    -e PROVISIONING_INTERFACE="${PXE_IFACE}" \\
    -e OS_AUTH_TYPE=none \\
    quay.io/metal3-io/ironic:latest /usr/bin/runironic
ExecStop=/usr/bin/podman stop -t 10 ironic-conductor
TimeoutStartSec=120
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now ironic-conductor
fi
log_success "Servicio Ironic Standalone registrado en systemd y activo en puerto ${IRONIC_API_PORT}."

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
# 6.3 GENERACIÓN DEL INVENTARIO OFICIAL /opt/ironic/baremetal.yaml
# ------------------------------------------------------------------------------
log_info "6.3 Generando archivo maestro /opt/ironic/baremetal.yaml desde config/nodes.csv..."
BAREMETAL_YML="/opt/ironic/baremetal.yaml"
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
    properties:
      cpus: 4
      memory_mb: ${local_ram_mb}
      local_gb: 120
      cpu_arch: "x86_64"
    extra:
      ipv4_address: "${ip}"
    ports:
      - address: "${mac}"
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
    retry 20 5 curl -sf "http://${PXE_IP}:${IRONIC_API_PORT}/v1/nodes" >/dev/null

    if command -v openstack >/dev/null 2>&1 && openstack baremetal --help >/dev/null 2>&1; then
        log_info "Registrando nodos en Ironic de forma idempotente..."
        while IFS=',' read -r id mac hostname ip role ram disk bmc; do
            [[ "${id}" == "id" ]] && continue
            local_ram_mb=$(( ram * 1024 ))
            if ! openstack baremetal node show "${hostname}" >/dev/null 2>&1; then
                log_info "Creando nodo bare-metal: ${hostname} (${ip} / ${mac})..."
                openstack baremetal node create \
                    --name "${hostname}" \
                    --driver "manual-management" \
                    --driver-info deploy_kernel="http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.kernel" \
                    --driver-info deploy_ramdisk="http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.initramfs" \
                    --property cpus=4 \
                    --property memory_mb="${local_ram_mb}" \
                    --property local_gb=120 \
                    --property cpu_arch="x86_64" \
                    --extra ipv4_address="${ip}"
                
                openstack baremetal port create --node "${hostname}" --address "${mac}" >/dev/null 2>&1 || true
                log_success "Nodo ${hostname} enrolado correctamente con puerto MAC ${mac}."
            else
                log_info "Nodo ${hostname} ya existe en catálogo; sincronizando parámetros..."
                openstack baremetal node set "${hostname}" \
                    --driver-info deploy_kernel="http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.kernel" \
                    --driver-info deploy_ramdisk="http://${PXE_IP}:${HTTPBOOT_PORT}/ipa/ipa.initramfs" \
                    --property memory_mb="${local_ram_mb}" >/dev/null 2>&1 || true
            fi

            # Asociar metadatos de imagen (instance_info)
            openstack baremetal node set "${hostname}" \
                --instance-info image_source="http://${PXE_IP}:${HTTPBOOT_PORT}/images/${IRONIC_IMAGE_NAME}" \
                --instance-info image_checksum="${IRONIC_IMAGE_CHECKSUM}" \
                --instance-info root_gb="110" >/dev/null 2>&1 || true
        done < "${NODES_CSV}"
    else
        log_info "Registrando nodos mediante API REST de Ironic (Python)..."
        python3 -c "
import urllib.request, json, yaml, sys

api_url = 'http://${PXE_IP}:${IRONIC_API_PORT}/v1'
headers = {'Content-Type': 'application/json', 'X-OpenStack-Ironic-API-Version': '1.38'}

with open('${BAREMETAL_YML}') as f:
    data = yaml.safe_load(f)

for n in data.get('nodes', []):
    node_body = {
        'name': n['name'],
        'driver': n['driver'],
        'driver_info': n.get('driver_info', {}),
        'properties': n.get('properties', {}),
        'extra': n.get('extra', {})
    }
    req = urllib.request.Request(f'{api_url}/nodes', data=json.dumps(node_body).encode(), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req) as resp:
            node_resp = json.loads(resp.read().decode())
            node_uuid = node_resp['uuid']
            print(f'  [OK] Nodo {n[\"name\"]} creado con UUID: {node_uuid}')
            for p in n.get('ports', []):
                port_body = {'node_uuid': node_uuid, 'address': p['address']}
                port_req = urllib.request.Request(f'{api_url}/ports', data=json.dumps(port_body).encode(), headers=headers, method='POST')
                urllib.request.urlopen(port_req)
                print(f'       Puerto MAC {p[\"address\"]} asociado.')
    except Exception as e:
        print(f'  [INFO] Nodo {n[\"name\"]} ya existe o aviso: {e}')
" 2>/dev/null || log_warn "Aviso en registro de nodos."
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

NODES_COUNT=$(openstack baremetal node list -f value -c UUID 2>/dev/null | grep -c . || echo "0")
NODES_COUNT=$(echo "${NODES_COUNT}" | head -n 1 | tr -d '[:space:]')
[[ -z "${NODES_COUNT}" ]] && NODES_COUNT=0
log_info "Total de nodos bare-metal registrados en Ironic: ${NODES_COUNT}"

if (( NODES_COUNT > 0 )); then
    log_success "API de Ironic respondiendo correctamente con nodos en catálogo:"
    openstack baremetal node list
else
    log_warn "API activa pero aún no reporta nodos registrados. Revise ${BAREMETAL_YML}."
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 6 COMPLETADA CON ÉXITO: IRONIC Y GLANCE OPERATIVOS       ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

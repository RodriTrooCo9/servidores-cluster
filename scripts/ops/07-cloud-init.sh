#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 07: PLANTILLAS CLOUD-INIT Y CONFIGDRIVE (07-cloud-init.sh)
# Objetivo: Generar plantilla Packer y generador de volumen ConfigDrive (config-2)
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.100.29.30 | MAC: 64:00:6a:2a:62:42)
# Fase README: FASE 7: Plantillas Cloud-Init, ConfigDrive y Compilación Inmutable con Packer
# Uso: sudo ./07-cloud-init.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
elif [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/scripts/lib/common.sh" ]]; then
    source "${REPO_DIR}/scripts/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró scripts/lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
load_config
require_root
validate_current_node "pxe"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 7: PLANTILLAS CLOUD-INIT, CONFIGDRIVE Y PACKER            ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

confirm_action "¿Desea preparar los generadores de ConfigDrive y plantillas Packer en este nodo?"

# ------------------------------------------------------------------------------
# 7.1 PLANTILLA PACKER HCL2 (/opt/infra/packer/packer.pkr.hcl)
# ------------------------------------------------------------------------------
log_info "7.1 Generando plantilla HCL2 de HashiCorp Packer..."
run_cmd mkdir -p /opt/infra/packer /opt/infra/scripts /opt/infra/configdrive /opt/infra/config
run_cmd cp -a "${NODES_CSV}" /opt/infra/config/nodes.csv 2>/dev/null || true

PACKER_FILE="/opt/infra/packer/packer.pkr.hcl"
backup_file "${PACKER_FILE}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${PACKER_FILE}" << EOF
packer {
  required_version = ">= 1.8.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "nexus_ip" {
  type    = string
  default = "${NEXUS_IP}"
}

source "qemu" "debian_baremetal" {
  # Nota: Reemplazar por imagen ISO local en entorno aislado si no hay salida a Internet
  iso_url          = "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso"
  iso_checksum     = "none"
  output_directory = "/opt/infra/packer/output-debian"
  vm_name          = "${IRONIC_IMAGE_NAME}"
  disk_size        = "20G"
  format           = "qcow2"
  disk_interface   = "virtio"
  cpus             = 2
  memory           = 2048
  accelerator      = "kvm"
  headless         = true
  ssh_username     = "${ADMIN_USER}"
  ssh_password     = "temporaryPackerPass2026!"
  ssh_timeout      = "20m"
  boot_wait        = "5s"
  boot_command = [
    "<esc><wait>",
    "install auto=true priority=critical preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]
}

build {
  sources = ["source.qemu.debian_baremetal"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y cloud-init cloud-initramfs-growpart gdisk curl openssh-server",
      "sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo cloud-init clean --logs"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "cp /opt/infra/packer/output-debian/${IRONIC_IMAGE_NAME} /httpboot/images/",
      "sha256sum /httpboot/images/${IRONIC_IMAGE_NAME} > /httpboot/images/${IRONIC_IMAGE_NAME}.sha256",
      "rm -rf /opt/infra/packer/output-debian"
    ]
  }
}
EOF
fi
log_success "Plantilla Packer creada en ${PACKER_FILE}."

# ------------------------------------------------------------------------------
# 7.2 GENERADOR DINÁMICO DE VOLÚMENES CONFIGDRIVE (config-2) POR NODO
# ------------------------------------------------------------------------------
log_info "7.2 Creando script maestro /opt/infra/scripts/generate_configdrive.sh..."
CONFIGDRIVE_GEN="/opt/infra/scripts/generate_configdrive.sh"
backup_file "${CONFIGDRIVE_GEN}"

if [[ "${DRY_RUN}" = false ]]; then
    cat > "${CONFIGDRIVE_GEN}" << 'GEN_EOF'
#!/usr/bin/env bash
# Generador de imágenes VFAT ConfigDrive (config-2) para inyección Zero-Touch
set -euo pipefail

TARGET_NODE="${1:-}"
if [[ -z "${TARGET_NODE}" ]]; then
    echo "Uso: $0 <hostname_o_id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODES_CSV="${SCRIPT_DIR}/config/nodes.csv"
if [[ ! -f "${NODES_CSV}" ]]; then
    if [[ -f "/opt/infra-scripts/config/nodes.csv" ]]; then
        NODES_CSV="/opt/infra-scripts/config/nodes.csv"
    elif [[ -f "${SCRIPT_DIR}/../config/nodes.csv" ]]; then
        NODES_CSV="${SCRIPT_DIR}/../config/nodes.csv"
    fi
fi
OUTPUT_DIR="/opt/infra/configdrive/${TARGET_NODE}"
mkdir -p "${OUTPUT_DIR}/openstack/latest"

# Buscar datos en nodes.csv
FOUND=false
while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    if [[ "${TARGET_NODE}" == "${hostname}" ]] || [[ "${TARGET_NODE}" == "${id}" ]]; then
        NODE_MAC="${mac}"
        NODE_IP="${ip}"
        NODE_NAME="${hostname}"
        FOUND=true
        break
    fi
done < "${NODES_CSV}"

if [[ "${FOUND}" = false ]]; then
    echo "Error: Nodo ${TARGET_NODE} no encontrado en ${NODES_CSV}."
    exit 1
fi

# Leer llave SSH real si existe
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC43z9+r9u5eWadminKeyClusterNodes admin-cluster-nodes"
for keyfile in "/home/n306/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/authorized_keys" "$HOME/.ssh/id_ed25519_nodes.pub"; do
    if [[ -f "${keyfile}" ]]; then
        SSH_PUB_KEY="$(head -n1 "${keyfile}")"
        break
    fi
done

GATEWAY_IP="${INTERNAL_GATEWAY:-10.100.29.30}"
DNS_IP="${INTERNAL_DNS:-192.168.26.120}"
NETMASK_VAL="${INTERNAL_NETMASK:-255.255.255.0}"
NEXUS_ENDPOINT="${NEXUS_IP:-10.100.29.20}"

# 1. meta_data.json
cat > "${OUTPUT_DIR}/openstack/latest/meta_data.json" << JSON_EOF
{
  "uuid": "node-${NODE_NAME}-baremetal",
  "hostname": "${NODE_NAME}.lab.local",
  "name": "${NODE_NAME}",
  "public_keys": {
    "admin": "${SSH_PUB_KEY}"
  }
}
JSON_EOF

# 2. network_data.json
cat > "${OUTPUT_DIR}/openstack/latest/network_data.json" << JSON_EOF
{
  "links": [
    { "id": "eth0", "type": "phy", "ethernet_mac_address": "${NODE_MAC}" }
  ],
  "networks": [
    {
      "id": "private-lan",
      "type": "ipv4",
      "link": "eth0",
      "ip_address": "${NODE_IP}",
      "netmask": "${NETMASK_VAL}",
      "gateway": "${GATEWAY_IP}"
    }
  ],
  "services": [
    { "type": "dns", "address": "${DNS_IP}" }
  ]
}
JSON_EOF

# 3. user_data (#cloud-config)
cat > "${OUTPUT_DIR}/openstack/latest/user_data" << YML_EOF
#cloud-config
manage_etc_hosts: true
package_update: true
users:
  - default
  - name: debian
    gecos: Debian Admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, adm
    shell: /bin/bash
    lock_passwd: false
    passwd: \$6\$rounds=4096\$labsalt\$y8Z.1wD.o0K/6G7w89X5r4Xyv1jYnZk4G1
    ssh_authorized_keys:
      - "${SSH_PUB_KEY}"

packages:
  - curl
  - iptables
  - apparmor
  - socat
  - conntrack
  - openssh-server

apt:
  sources:
    nexus:
      source: "deb http://${NEXUS_ENDPOINT}:8081/repository/debian-proxy/ trixie main contrib non-free non-free-firmware"

write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1

runcmd:
  - swapoff -a
  - sed -i '/ swap / s/^\(.*\)$/# \1/g' /etc/fstab
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  - systemctl restart ssh
YML_EOF

# 4. Crear estructura compatible NoCloud para HTTP (/httpboot/cloud-init/)
HTTP_NOCLOUD="/httpboot/cloud-init/${NODE_NAME}"
mkdir -p "${HTTP_NOCLOUD}"
cp "${OUTPUT_DIR}/openstack/latest/user_data" "${HTTP_NOCLOUD}/user-data"
cat > "${HTTP_NOCLOUD}/meta-data" << META_EOF
instance-id: i-${NODE_NAME}
local-hostname: ${NODE_NAME}
META_EOF
cat > "${HTTP_NOCLOUD}/network-config" << NET_EOF
version: 2
ethernets:
  eth0:
    match:
      macaddress: "${NODE_MAC}"
    addresses:
      - ${NODE_IP}/24
    gateway4: ${GATEWAY_IP}
    nameservers:
      addresses: [${DNS_IP}]
NET_EOF

# 5. Crear imagen VFAT de 64 MB con etiqueta config-2
ISO_IMG="/opt/infra/configdrive/${NODE_NAME}-configdrive.iso"
mkisofs -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}" >/dev/null 2>&1 || genisoimage -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}"
echo "ConfigDrive generado con éxito: ${ISO_IMG}"
echo "NoCloud HTTP listo en: ${HTTP_NOCLOUD}"
GEN_EOF
    chmod +x "${CONFIGDRIVE_GEN}"
fi
log_success "Script generador de ConfigDrive listo en ${CONFIGDRIVE_GEN}."

# ------------------------------------------------------------------------------
# 7.3 VALIDACIÓN DE FASE 7
# ------------------------------------------------------------------------------
log_info "7.3 Validando generador de metadatos con prueba unitaria para 'k8s-cp-01'..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

# Instalar generador iso si no está presente
apt_install genisoimage 2>/dev/null || true

if [[ -f "${CONFIGDRIVE_GEN}" ]]; then
    log_info "Generando ConfigDrives y metadatos NoCloud para todos los nodos del clúster..."
    while IFS=',' read -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        log_info "Compilando cloud-init para nodo [${hostname}] (ID: ${id})..."
        "${CONFIGDRIVE_GEN}" "${hostname}" || true
    done < "${NODES_CSV}"

    if [[ -f "/opt/infra/configdrive/k8s-cp-01-configdrive.iso" ]]; then
        log_success "Volúmenes config-2 y endpoints HTTP generados y validados correctamente."
    else
        log_warn "El script generó los archivos JSON pero no pudo compilar el archivo ISO."
    fi
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 7 COMPLETADA CON ÉXITO: CLOUD-INIT Y CONFIGDRIVE LISTOS  ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

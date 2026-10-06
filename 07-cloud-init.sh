#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 07: PLANTILLAS CLOUD-INIT Y CONFIGDRIVE (07-cloud-init.sh)
# Objetivo: Generar plantilla Packer y generador de volumen ConfigDrive (config-2)
# Nodo de Ejecución: [PXE] (Nodo 306 | IP: 10.0.1.30 | MAC: 64:00:6a:2a:62:42)
# Fase README: FASE 7: Plantillas Cloud-Init, ConfigDrive y Compilación Inmutable con Packer
# Uso: sudo ./07-cloud-init.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

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
run_cmd mkdir -p /opt/infra/packer /opt/infra/scripts /opt/infra/configdrive

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
  iso_url          = "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso" --cambiar iso por local
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
    cat > "${CONFIGDRIVE_GEN}" << 'EOF'
#!/usr/bin/env bash
# Generador de imágenes VFAT ConfigDrive (config-2) para inyección Zero-Touch
set -euo pipefail

TARGET_NODE="${1:-}"
if [[ -z "${TARGET_NODE}" ]]; then
    echo "Uso: $0 <hostname_o_id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODES_CSV="${SCRIPT_DIR}/../config/nodes.csv"
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

# Leer llave SSH si existe
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC43z9+r9u5eWadminKeyClusterNodes admin-cluster-nodes"
if [[ -f "$HOME/.ssh/id_ed25519_nodes.pub" ]]; then
    SSH_PUB_KEY="$(cat "$HOME/.ssh/id_ed25519_nodes.pub")"
fi

# 1. meta_data.json
cat > "${OUTPUT_DIR}/openstack/latest/meta_data.json" << JSON
{
  "uuid": "node-${NODE_NAME}-baremetal",
  "hostname": "${NODE_NAME}.lab.local",
  "name": "${NODE_NAME}",
  "public_keys": {
    "admin": "${SSH_PUB_KEY}"
  }
}
JSON

# 2. network_data.json
cat > "${OUTPUT_DIR}/openstack/latest/network_data.json" << JSON
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
      "netmask": "255.255.255.0",
      "gateway": "10.0.1.10"
    }
  ],
  "services": [
    { "type": "dns", "address": "10.0.1.10" }
  ]
}
JSON

# 3. user_data (#cloud-config)
cat > "${OUTPUT_DIR}/openstack/latest/user_data" << 'YML'
#cloud-config
manage_etc_hosts: true
package_update: true
packages:
  - curl
  - iptables
  - apparmor
  - socat
  - conntrack

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
YML

# Crear imagen VFAT de 64 MB con etiqueta config-2
ISO_IMG="/opt/infra/configdrive/${NODE_NAME}-configdrive.iso"
mkisofs -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}" >/dev/null 2>&1 || genisoimage -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}"
echo "ConfigDrive generado con éxito: ${ISO_IMG}"
EOF
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
    "${CONFIGDRIVE_GEN}" "k8s-cp-01"
    if [[ -f "/opt/infra/configdrive/k8s-cp-01-configdrive.iso" ]]; then
        log_success "Volumen config-2 generado y validado correctamente."
    else
        log_warn "El script generó los archivos JSON pero no pudo compilar el archivo ISO (genisoimage requerido)."
    fi
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 7 COMPLETADA CON ÉXITO: CLOUD-INIT Y CONFIGDRIVE LISTOS  ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

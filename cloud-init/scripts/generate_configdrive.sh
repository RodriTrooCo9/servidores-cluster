#!/usr/bin/env bash
# ==============================================================================
# SCRIPT GENERADOR DE CONFIGDRIVE (config-2) Y NOCLOUD
# Genera volúmenes VFAT / ISO con metadatos para inyección Zero-Touch bare-metal.
#
# Uso: ./cloud-init/scripts/generate_configdrive.sh <HOSTNAME_O_ID>
# ==============================================================================

set -Eeuo pipefail

TARGET_NODE="${1:-}"
if [[ -z "${TARGET_NODE}" ]]; then
    echo "Uso: $0 <hostname_o_id>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NODES_CSV="${REPO_DIR}/inventory/nodes.csv"

if [[ ! -f "${NODES_CSV}" ]]; then
    echo "ERROR: No se encontró inventario físico en ${NODES_CSV}" >&2
    exit 1
fi

OUTPUT_DIR="/tmp/configdrive/${TARGET_NODE}"
mkdir -p "${OUTPUT_DIR}/openstack/latest"

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
    echo "ERROR: Nodo ${TARGET_NODE} no encontrado en ${NODES_CSV}" >&2
    exit 1
fi

SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC43z9+r9u5eWadminKeyClusterNodes admin-cluster-nodes"
for keyfile in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/authorized_keys"; do
    if [[ -f "${keyfile}" ]]; then
        SSH_PUB_KEY="$(head -n1 "${keyfile}")"
        break
    fi
done

GATEWAY_IP="10.100.29.30"
DNS_IP="192.168.26.120"
NEXUS_ENDPOINT="10.100.29.20"

# 1. meta_data.json
cat > "${OUTPUT_DIR}/openstack/latest/meta_data.json" << EOF
{
  "uuid": "node-${NODE_NAME}-baremetal",
  "hostname": "${NODE_NAME}.lab.local",
  "name": "${NODE_NAME}",
  "public_keys": {
    "admin": "${SSH_PUB_KEY}"
  }
}
EOF

# 2. network_data.json
cat > "${OUTPUT_DIR}/openstack/latest/network_data.json" << EOF
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
      "gateway": "${GATEWAY_IP}"
    }
  ],
  "services": [
    { "type": "dns", "address": "${DNS_IP}" }
  ]
}
EOF

# 3. user_data (#cloud-config)
cat > "${OUTPUT_DIR}/openstack/latest/user_data" << EOF
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
EOF

# 4. NoCloud HTTP (/httpboot/cloud-init/<nodo>)
HTTP_NOCLOUD="/httpboot/cloud-init/${NODE_NAME}"
if [[ -d "/httpboot" ]]; then
    mkdir -p "${HTTP_NOCLOUD}"
    cp "${OUTPUT_DIR}/openstack/latest/user_data" "${HTTP_NOCLOUD}/user-data"
    cat > "${HTTP_NOCLOUD}/meta-data" << EOF
instance-id: i-${NODE_NAME}
local-hostname: ${NODE_NAME}
EOF
    cat > "${HTTP_NOCLOUD}/network-config" << EOF
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
EOF
fi

# 5. Generar imagen ISO VFAT con etiqueta config-2
ISO_IMG="/tmp/configdrive/${NODE_NAME}-configdrive.iso"
if command -v mkisofs >/dev/null 2>&1; then
    mkisofs -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}" >/dev/null 2>&1
elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -R -V config-2 -o "${ISO_IMG}" "${OUTPUT_DIR}" >/dev/null 2>&1
else
    echo "ERROR: Instale mkisofs o genisoimage." >&2
    exit 1
fi
[[ -s "${ISO_IMG}" ]] || { echo "ERROR: No se generó la ISO." >&2; exit 1; }

echo "[OK] ConfigDrive generado exitosamente para ${NODE_NAME}: ${ISO_IMG}"

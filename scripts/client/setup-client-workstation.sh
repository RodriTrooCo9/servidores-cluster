#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/setup-client-workstation.sh
# Objetivo: Configurar automáticamente cualquier nueva PC o Laptop (Linux/WSL2/macOS)
#           para administrar todo el clúster con Ansible, OpenStack, Kubernetes y SSH.
#
# Uso en la nueva PC/Laptop:
#   chmod +x scripts/setup-client-workstation.sh
#   ./scripts/setup-client-workstation.sh
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

CONTROLLER_IP="192.168.29.25"
CONTROLLER_USER="n306"
SSH_KEY="${REPO_DIR}/ansible/keys/cluster_key"

# 1. Comprobar conectividad básica por WiFi/LAN con el nodo controlador
log_info "1. Verificando conectividad de red con el controlador (192.168.29.25)..."
if ping -c 1 -W 2 "${CONTROLLER_IP}" >/dev/null 2>&1; then
    log_ok "Conexión con el controlador 192.168.29.25 exitosa."
else
    log_warn "No responde ping a ${CONTROLLER_IP}. Asegúrate de estar conectado a la misma red WiFi/LAN."
fi

# 2. Ajustar permisos de llaves y secretos en el repositorio
log_info "2. Asegurando permisos restrictivos en llaves SSH y secretos Vault..."
if [[ -f "${SSH_KEY}" ]]; then
    chmod 600 "${SSH_KEY}"
    log_ok "Permisos de llave SSH corregidos (chmod 600 ${SSH_KEY})."
else
    log_warn "No se encontró ${SSH_KEY}. Asegúrate de copiar cluster_key a ansible/keys/ o ~/.ssh/id_ed25519"
fi

if [[ -f "${REPO_DIR}/.vault_pass" ]]; then
    chmod 600 "${REPO_DIR}/.vault_pass"
    log_ok "Permisos de .vault_pass corregidos."
fi

# 3. Comprobar binarios necesarios en la máquina local
log_info "3. Comprobando herramientas instaladas (git, ssh, python3, ansible)..."
for tool in git ssh python3; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        log_err "Falta la herramienta requerida: ${tool}. Por favor instálala (ej: sudo apt install ${tool})."
        exit 1
    fi
done

if ! command -v ansible >/dev/null 2>&1; then
    log_warn "Ansible no está instalado en el sistema global. Creando entorno virtual o instalando..."
    if command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
        log_info "Instalando Ansible en entorno de usuario..."
        python3 -m pip install --user ansible || true
    else
        log_warn "pip3 no detectado. Instala ansible con: sudo apt install ansible (o pipx install ansible)"
    fi
else
    log_ok "Ansible está instalado ($(ansible --version | head -n1))."
fi

# 4. Instalar colecciones requeridas de Ansible Galaxy
log_info "4. Instalando colecciones de Ansible del proyecto..."
if [[ -f "${REPO_DIR}/ansible/requirements.yml" ]]; then
    ansible-galaxy install -r "${REPO_DIR}/ansible/requirements.yml" || true
    log_ok "Colecciones Galaxy verificadas."
fi

# 5. Configurar accesos directos en ~/.ssh/config para comandos rápidos
log_info "5. Configurando accesos directos y ProxyJump en ~/.ssh/config..."
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
SSH_CONFIG="${HOME}/.ssh/config"

cat << EOF >> "${SSH_CONFIG}.tmp"
# --- Clúster Bare-Metal Dell OptiPlex (Generado por setup-client-workstation.sh) ---
Host nodo-306 controller
    HostName 192.168.29.25
    User n306
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host nodo-314 bastion
    HostName 10.100.29.10
    User aget-ic
    ProxyJump n306@192.168.29.25
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host nodo-315 nexus
    HostName 10.100.29.20
    User io
    ProxyJump n306@192.168.29.25
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host k8s-cp-01 nodo-269
    HostName 10.100.29.101
    User debian
    ProxyJump n306@192.168.29.25
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host k8s-cp-02 nodo-280
    HostName 10.100.29.102
    User debian
    ProxyJump n306@192.168.29.25
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no

Host k8s-worker-02 nodo-279
    HostName 10.100.29.112
    User debian
    ProxyJump n306@192.168.29.25
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no
EOF

# Unir limpiamente sin duplicados
if [[ -f "${SSH_CONFIG}" ]]; then
    sed -i '/--- Clúster Bare-Metal Dell OptiPlex/,+35d' "${SSH_CONFIG}" 2>/dev/null || true
fi
cat "${SSH_CONFIG}.tmp" >> "${SSH_CONFIG}"
rm -f "${SSH_CONFIG}.tmp"
chmod 600 "${SSH_CONFIG}"
log_ok "Accesos SSH configurados. Ahora puedes escribir: 'ssh nodo-306', 'ssh nexus', 'ssh k8s-cp-01', etc."

# 6. Descargar y configurar Kubeconfig para kubectl local
log_info "6. Configurando kubeconfig para acceso directo a Kubernetes..."
mkdir -p "${HOME}/.kube"
if ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_IP}" "ssh -i /home/n306/.ssh/cluster_key -o StrictHostKeyChecking=no debian@10.100.29.101 'cat /etc/rancher/rke2/rke2.yaml'" > "${HOME}/.kube/config.tmp" 2>/dev/null; then
    sed -i 's/127.0.0.1:6443/10.100.29.101:6443/g' "${HOME}/.kube/config.tmp"
    mv "${HOME}/.kube/config.tmp" "${HOME}/.kube/config_cluster"
    chmod 600 "${HOME}/.kube/config_cluster"
    log_ok "Kubeconfig descargado exitosamente en: ~/.kube/config_cluster"
    echo -e "   Uso con kubectl: export KUBECONFIG=~/.kube/config_cluster && kubectl get nodes"
else
    rm -f "${HOME}/.kube/config.tmp"
    log_warn "No se pudo descargar kubeconfig en este momento. Puede obtenerse después con tunnels.sh activo."
fi

# 7. Ejecutar Ping de prueba con Ansible
log_info "7. Probando conectividad global con Ansible..."
cd "${REPO_DIR}"
if ansible baremetal -m ping -o 2>/dev/null; then
    log_ok "¡Prueba de Ansible exitosa en todos los nodos activos!"
else
    log_warn "Algunos nodos físicos están apagados o no respondieron, pero la configuración base está lista."
fi

echo -e "\n${GREEN}==================================================================${NC}"
echo -e "${GREEN}   ¡PC/LAPTOP CONFIGURADA CON ÉXITO PARA ADMINISTRAR EL CLÚSTER!  ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo "Pasos útiles a partir de ahora:"
echo "  1. Levantar servicios o verificar salud:"
echo "     ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/09_healthcheck.yml"
echo "  2. Abrir túneles web a Horizon, Nexus, Grafana y Kubernetes:"
echo "     ./scripts/tunnels.sh"
echo "  3. Re-aprovisionar un nodo físico si falla su disco:"
echo "     ./scripts/disaster-recovery.sh --reprovision <nodo>"
echo "=================================================================="

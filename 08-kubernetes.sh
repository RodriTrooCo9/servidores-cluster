#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 08: DESPLIEGUE DEL CLÚSTER KUBERNETES HA (08-kubernetes.sh)
# Objetivo: RKE2 Server (CPs 269, 280, 320) con etcd HA y Workers (321, 279) con Cilium
# Nodo de Ejecución: [CONTROL-PLANE] / [WORKER] / [BASTION]
# Fase README: FASE 8/9: Clúster Kubernetes de Alta Disponibilidad (RKE2 + Cilium eBPF)
# Uso: sudo ./08-kubernetes.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
load_config
require_root

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 8: CLÚSTER KUBERNETES DE ALTA DISPONIBILIDAD (RKE2)      ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

CURRENT_HOSTNAME="$(hostname -s)"
CURRENT_IPS="$(ip -br addr | awk '{print $3}' | cut -d/ -f1 | tr '\n' ' ')"

NODE_ROLE="unknown"
NODE_IP=""

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    if [[ "${CURRENT_HOSTNAME}" == "${hostname}" ]] || [[ " ${CURRENT_IPS} " == *" ${ip} "* ]]; then
        NODE_ROLE="${role}"
        NODE_IP="${ip}"
        break
    fi
done < "${NODES_CSV}"

log_info "Detectado nodo: ${CURRENT_HOSTNAME} (Rol: ${NODE_ROLE} | IP: ${NODE_IP})"

# Caso especial: Si corre en Bastión, asume rol de gestor/cliente kubeconfig
if [[ "${CURRENT_HOSTNAME}" =~ ^(bastion)$ ]] || [[ "${NODE_ROLE}" == "bastion" ]]; then
    log_info "Ejecución en Bastion Host: Extrayendo y configurando cliente kubectl..."
    confirm_action "¿Desea configurar kubeconfig y kubectl en este Bastión?"

    mkdir -p "$HOME/.kube" /root/.kube
    K8S_LEADER_IP="10.0.1.101"
    
    if [[ "${DRY_RUN}" = false ]]; then
        apt_install curl
        if ! command -v kubectl >/dev/null 2>&1; then
            log_info "Instalando binario oficial kubectl..."
            curl -fsSL https://dl.k8s.io/release/v1.30.2/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl
            chmod +x /usr/local/bin/kubectl
        fi

        log_info "Extrayendo kubeconfig desde el nodo líder (${K8S_LEADER_IP})..."
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${ADMIN_USER}@${K8S_LEADER_IP}" "sudo cat /etc/rancher/rke2/rke2.yaml" > /root/.kube/config 2>/dev/null; then
            sed -i "s/127.0.0.1/${K8S_LEADER_IP}/g" /root/.kube/config
            chmod 0600 /root/.kube/config
            cp /root/.kube/config "/home/${ADMIN_USER}/.kube/config" 2>/dev/null || true
            chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.kube" 2>/dev/null || true
            log_success "Kubeconfig configurado en /root/.kube/config y en ~/.kube/config de ${ADMIN_USER}."
        else
            log_warn "No se pudo extraer kubeconfig de ${K8S_LEADER_IP}. Verifique que k8s-cp-01 esté en línea."
        fi
    fi

    log_info "Validando convergencia del clúster..."
    if command -v kubectl >/dev/null 2>&1 && [[ -f /root/.kube/config ]]; then
        kubectl --kubeconfig=/root/.kube/config get nodes -o wide || true
    fi
    exit 0
fi

# Validar que es un nodo Kubernetes
if [[ ! "${NODE_ROLE}" =~ ^(k8s-control-plane-leader|k8s-control-plane|k8s-worker)$ ]]; then
    if [[ "${FORCE}" = false ]]; then
        log_error "Este nodo (${CURRENT_HOSTNAME}) no está registrado como parte de Kubernetes en nodes.csv."
        log_error "Use --force si desea desplegar RKE2 en este host."
        exit 1
    fi
fi

confirm_action "¿Desea desplegar y configurar Kubernetes RKE2 en este nodo físico?"

# ------------------------------------------------------------------------------
# 8.1 PREPARACIÓN DEL SISTEMA OPERATIVO Y KERNEL PARA KUBERNETES
# ------------------------------------------------------------------------------
log_info "8.1 Aplicando configuración de kernel y desactivando memoria Swap..."
run_cmd swapoff -a
if [[ "${DRY_RUN}" = false ]]; then
    sed -i '/ swap / s/^\(.*\)$/# \1/g' /etc/fstab 2>/dev/null || true

    # Módulos del kernel
    cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
    modprobe overlay || true
    modprobe br_netfilter || true

    # Sysctl de red
    cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sysctl --system >/dev/null 2>&1 || true
fi
log_success "Kernel y sysctl ajustados para Cilium eBPF y cgroups v2."

# ------------------------------------------------------------------------------
# 8.2 CONFIGURACIÓN SEGÚN EL ROL DE KUBERNETES
# ------------------------------------------------------------------------------
RKE2_DIR="/etc/rancher/rke2"
RKE2_CONFIG="${RKE2_DIR}/config.yaml"
run_cmd mkdir -p "${RKE2_DIR}"
backup_file "${RKE2_CONFIG}"

K8S_LEADER_IP="10.0.1.101"

if [[ "${NODE_ROLE}" == "k8s-control-plane-leader" ]] || [[ "${CURRENT_HOSTNAME}" == "k8s-cp-01" ]]; then
    log_info "Configurando Control Plane Líder (k8s-cp-01)..."
    if [[ "${DRY_RUN}" = false ]]; then
        cat > "${RKE2_CONFIG}" << EOF
write-kubeconfig-mode: "0644"
tls-san:
  - "${NODE_IP}"
  - "${CURRENT_HOSTNAME}.${DOMAIN}"
  - "k8s-api.${DOMAIN}"

token: "${RKE2_CLUSTER_TOKEN}"

# Red eBPF Cilium nativa
cni: ${RKE2_CNI}
disable-kube-proxy: true

# Mitigación estricta para almacenamiento NVMe de 128 GB
etcd-arg:
  - "auto-compaction-retention=${ETCD_COMPACTION_RETENTION}"
  - "quota-backend-bytes=${ETCD_QUOTA_BACKEND_BYTES}"
EOF
    fi

    log_info "Instalando e iniciando servicio rke2-server (versión ${RKE2_VERSION:-latest})..."
    if [[ "${DRY_RUN}" = false ]]; then
        [[ -f /etc/environment ]] && export $(grep -E '^(http_proxy|https_proxy|no_proxy)=' /etc/environment | xargs -r) 2>/dev/null || true
        curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -
        systemctl enable --now rke2-server.service
    fi
    log_success "Primer nodo Control Plane desplegado exitosamente."

elif [[ "${NODE_ROLE}" == "k8s-control-plane" ]]; then
    log_info "Configurando Control Plane Secundario (${CURRENT_HOSTNAME})..."
    if [[ "${DRY_RUN}" = false ]]; then
        cat > "${RKE2_CONFIG}" << EOF
server: https://${K8S_LEADER_IP}:9345
token: "${RKE2_CLUSTER_TOKEN}"
write-kubeconfig-mode: "0644"
tls-san:
  - "${NODE_IP}"
  - "k8s-api.${DOMAIN}"

cni: ${RKE2_CNI}
disable-kube-proxy: true

etcd-arg:
  - "auto-compaction-retention=${ETCD_COMPACTION_RETENTION}"
  - "quota-backend-bytes=${ETCD_QUOTA_BACKEND_BYTES}"
EOF
    fi

    log_info "Instalando e iniciando servicio rke2-server secundario (versión ${RKE2_VERSION:-latest})..."
    if [[ "${DRY_RUN}" = false ]]; then
        [[ -f /etc/environment ]] && export $(grep -E '^(http_proxy|https_proxy|no_proxy)=' /etc/environment | xargs -r) 2>/dev/null || true
        curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -
        systemctl enable --now rke2-server.service
    fi
    log_success "Nodo Control Plane secundario unido al clúster."

elif [[ "${NODE_ROLE}" == "k8s-worker" ]]; then
    log_info "Configurando Worker Node (${CURRENT_HOSTNAME})..."
    if [[ "${DRY_RUN}" = false ]]; then
        cat > "${RKE2_CONFIG}" << EOF
server: https://${K8S_LEADER_IP}:9345
token: "${RKE2_CLUSTER_TOKEN}"
node-name: "${CURRENT_HOSTNAME}"
kubelet-arg:
  - "image-gc-high-threshold=75"
  - "image-gc-low-threshold=60"
EOF
    fi

    log_info "Instalando e iniciando servicio rke2-agent (versión ${RKE2_VERSION:-latest})..."
    if [[ "${DRY_RUN}" = false ]]; then
        [[ -f /etc/environment ]] && export $(grep -E '^(http_proxy|https_proxy|no_proxy)=' /etc/environment | xargs -r) 2>/dev/null || true
        curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -
        systemctl enable --now rke2-agent.service
    fi
    log_success "Nodo Worker configurado y unido al clúster."
fi

# ------------------------------------------------------------------------------
# 8.3 VALIDACIÓN DE FASE 8
# ------------------------------------------------------------------------------
log_info "8.3 Validando estado del servicio local de Kubernetes..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

if [[ "${NODE_ROLE}" =~ ^(k8s-control-plane-leader|k8s-control-plane)$ ]]; then
    check_service "rke2-server"
    check_port "6443" "tcp"
    check_port "9345" "tcp"
    log_success "Socket de API Server (6443) y Supervisor (9345) activos."
else
    check_service "rke2-agent"
    log_success "Agente rke2-agent activo y enlazado al plano de control."
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 8 COMPLETADA CON ÉXITO EN ${CURRENT_HOSTNAME}            ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

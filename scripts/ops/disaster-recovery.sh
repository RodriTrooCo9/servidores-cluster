#!/usr/bin/env bash
# ==============================================================================
# ORQUESTADOR DE RECUPERACIÓN ANTE DESASTRES Y AUTO-SANACIÓN (disaster-recovery.sh)
#
# Casos de Uso:
#   1. Fallo de disco SSD / Hardware en Nodo Físico Dell OptiPlex (Ironic + WoL)
#   2. Pérdida de Quórum o sustitución de nodo Control Plane en Kubernetes (RKE2 etcd)
#   3. Respaldo y Restauración de Base de Datos OpenStack MariaDB y configs Kolla
#
# Uso:
#   ./scripts/disaster-recovery.sh --audit
#   ./scripts/disaster-recovery.sh --reprovision <nombre_nodo_o_id> [--new-mac <AA:BB:CC:DD:EE:FF>]
#   ./scripts/disaster-recovery.sh --heal-etcd <cp_node_caido>
#   ./scripts/disaster-recovery.sh --backup-all
#   ./scripts/disaster-recovery.sh --backup-openstack
#   ./scripts/disaster-recovery.sh --backup-etcd
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

SSH_KEY="${REPO_DIR}/ansible/keys/cluster_key"
CONTROLLER_IP="192.168.29.25"
CONTROLLER_USER="n306"
OS_VIP="${OS_VIP:-10.100.29.5}"
OS_AUTH_URL="http://${OS_VIP}:5000/v3"
OS_PASS="${OS_PASSWORD:-}"
printf -v OS_PASS_QUOTED %q "${OS_PASS}"
export ANSIBLE_CONFIG="${REPO_DIR}/ansible.cfg"

OS_CMD="sudo docker exec kolla_toolbox openstack --os-auth-url ${OS_AUTH_URL} --os-user-domain-name Default --os-project-domain-name Default --os-project-name admin --os-username admin --os-password ${OS_PASS_QUOTED} --os-identity-api-version 3"
OS_SYS="sudo docker exec kolla_toolbox openstack --os-auth-url ${OS_AUTH_URL} --os-user-domain-name Default --os-system-scope all --os-username admin --os-password ${OS_PASS_QUOTED} --os-identity-api-version 3"

show_help() {
    cat << EOF
Uso: $0 [OPCIÓN]

Opciones de Recuperación ante Desastres (Disaster Recovery):
  --audit                     Auditar estado de la flota física, OpenStack Ironic y etcd
  --reprovision <nodo>        Re-aprovisionar desde cero un nodo físico con fallo de SSD
                              (Escribe la imagen Glance por red mediante Wake-on-LAN e iPXE)
  --new-mac <mac>             (Opcional con --reprovision) Actualizar MAC si se cambió la máquina
  --heal-etcd <nodo_cp>       Eliminar miembro muerto en etcd para permitir auto-sanación de CP
  --backup-all                Ejecutar respaldo completo (MariaDB OpenStack + configs + etcd)
  --backup-openstack          Respaldar bases de datos MariaDB y configuraciones /etc/kolla
  --backup-etcd               Respaldar snapshot de etcd del clúster Kubernetes RKE2
  -h, --help                  Mostrar esta ayuda

Ejemplos:
  $0 --audit
  $0 --backup-all
  $0 --reprovision k8s-worker-02
  $0 --reprovision nodo-279
  $0 --reprovision k8s-cp-02 --new-mac 64:00:6a:2a:60:99
  $0 --heal-etcd k8s-cp-02
EOF
}

run_on_controller() {
    local cmd="$1"
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_IP}" "${cmd}"
}

run_on_node() {
    local target_ip="$1"
    local cmd="$2"
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ProxyJump="${CONTROLLER_USER}@${CONTROLLER_IP}" -o ConnectTimeout=4 "debian@${target_ip}" "${cmd}"
}

scp_from_node() {
    local target_ip="$1"
    local remote_path="$2"
    local local_path="$3"
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ProxyJump="${CONTROLLER_USER}@${CONTROLLER_IP}" "debian@${target_ip}:${remote_path}" "${local_path}"
}

resolve_node_info() {
    local target="$1"
    local hosts_file="${REPO_DIR}/inventory/lab/hosts.yml"

    NODE_NAME=""
    NODE_HOST=""
    NODE_IP=""
    NODE_MAC=""
    NODE_RAM=""
    NODE_DISK=""
    NODE_ROLE=""

    case "${target}" in
        269|nodo-269|k8s-cp-01)
            NODE_HOST="nodo-269"; NODE_NAME="k8s-cp-01"; NODE_IP="10.100.29.101"
            NODE_MAC="64:00:6a:2a:5f:f9"; NODE_RAM="16384"; NODE_DISK="120"; NODE_ROLE="control-plane"
            ;;
        280|nodo-280|k8s-cp-02)
            NODE_HOST="nodo-280"; NODE_NAME="k8s-cp-02"; NODE_IP="10.100.29.102"
            NODE_MAC="64:00:6a:2a:60:63"; NODE_RAM="16384"; NODE_DISK="120"; NODE_ROLE="control-plane"
            ;;
        320|nodo-320|k8s-cp-03)
            NODE_HOST="nodo-320"; NODE_NAME="k8s-cp-03"; NODE_IP="10.100.29.103"
            NODE_MAC="64:00:6a:2a:2c:75"; NODE_RAM="16384"; NODE_DISK="120"; NODE_ROLE="control-plane"
            ;;
        321|nodo-321|k8s-worker-01)
            NODE_HOST="nodo-321"; NODE_NAME="k8s-worker-01"; NODE_IP="10.100.29.111"
            NODE_MAC="64:00:6a:2a:62:a4"; NODE_RAM="8192"; NODE_DISK="120"; NODE_ROLE="worker"
            ;;
        279|nodo-279|k8s-worker-02)
            NODE_HOST="nodo-279"; NODE_NAME="k8s-worker-02"; NODE_IP="10.100.29.112"
            NODE_MAC="64:00:6a:2a:2f:cb"; NODE_RAM="8192"; NODE_DISK="120"; NODE_ROLE="worker"
            ;;
        *)
            log_error "Nodo desconocido: '${target}'. Nodos válidos: k8s-cp-01, k8s-cp-02, k8s-cp-03, k8s-worker-01, k8s-worker-02 (o IDs: 269, 280, 320, 321, 279)"
            exit 1
            ;;
    esac
}

cmd_audit() {
    log_info "=== 1. AUDITORÍA DE CONECTIVIDAD FÍSICA (ANSIBLE PING) ==="
    cd "${REPO_DIR}"
    ansible baremetal -m ping -o || true

    log_info "=== 2. ESTADO DE LOS NODOS FÍSICOS EN OPENSTACK IRONIC ==="
    run_on_controller "${OS_SYS} baremetal node list"

    log_info "=== 3. HIPERVISORES BARE-METAL EN NOVA ==="
    run_on_controller "${OS_CMD} hypervisor list"

    log_info "=== 4. CATÁLOGO DE IMÁGENES GLANCE PARA RECUPERACIÓN ==="
    run_on_controller "${OS_CMD} image list"
}

run_backup_playbook() {
    local tag="$1"
    cd "${REPO_DIR}"
    ansible-playbook -i "${REPO_DIR}/inventory/lab/hosts.yml" \
        "${REPO_DIR}/ansible/playbooks/90-operations/01_disaster_recovery.yml" --tags "${tag}"
    log_success "Respaldo y transferencia completados en ${REPO_DIR}/backups/"
}

cmd_backup_openstack() { run_backup_playbook backup_openstack; }
cmd_backup_etcd() { run_backup_playbook backup_etcd; }

cmd_heal_etcd() {
    local failed_node="$1"
    resolve_node_info "${failed_node}"

    if [[ "${NODE_ROLE}" != "control-plane" ]]; then
        log_info "El nodo ${NODE_NAME} es un Worker; no participa en el quórum etcd. No requiere --heal-etcd."
        return 0
    fi

    log_info "Iniciando saneamiento de quórum etcd para remover miembro muerto: ${NODE_NAME} (${NODE_IP})..."
    
    local surviving_host=""
    for cp_ip in "10.100.29.101" "10.100.29.102" "10.100.29.103"; do
        if [[ "${cp_ip}" != "${NODE_IP}" ]]; then
            if run_on_node "${cp_ip}" "true" 2>/dev/null; then
                surviving_host="${cp_ip}"
                break
            fi
        fi
    done

    if [[ -z "${surviving_host}" ]]; then
        log_error "No se encontró ningún nodo Control Plane sobreviviente accesible por SSH para sanar etcd."
        exit 1
    fi

    log_info "Nodo Control Plane activo detectado: ${surviving_host}"
    
    local member_id
    member_id=$(run_on_node "${surviving_host}" \
        "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key member list | grep '${NODE_IP}' | awk -F',' '{print \$1}'" 2>/dev/null || true)

    if [[ -n "${member_id}" ]]; then
        log_warn "Miembro etcd detectado con ID: ${member_id}. Procediendo a retirarlo del quórum..."
        run_on_node "${surviving_host}" \
            "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key member remove ${member_id}"
        log_success "Miembro etcd ${member_id} eliminado exitosamente. El quórum está listo para admitir el nodo nuevo."
    else
        log_info "No se encontró ningún miembro registrado con la IP ${NODE_IP} en etcd. Procediendo con seguridad."
    fi
}

cmd_reprovision() {
    local target="$1"
    local new_mac="${2:-}"

    resolve_node_info "${target}"

    if [[ -n "${new_mac}" ]]; then
        log_warn "Se especificó una nueva dirección MAC: ${new_mac} (Reemplazo total de placa/equipo)."
        NODE_MAC="${new_mac}"
    fi

    echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
    echo -e "${COLOR_YELLOW}   ADVERTENCIA DE RECUPERACIÓN ANTE DESASTRES BARE-METAL         ${COLOR_NC}"
    echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
    echo -e "Nodo Destino : ${COLOR_BOLD}${NODE_NAME}${COLOR_NC} (${NODE_HOST})"
    echo -e "IP Asignada  : ${COLOR_BOLD}${NODE_IP}${COLOR_NC}"
    echo -e "MAC Address  : ${COLOR_BOLD}${NODE_MAC}${COLOR_NC}"
    echo -e "Rol Clúster  : ${COLOR_BOLD}${NODE_ROLE}${COLOR_NC}"
    echo -e "\nEsta operación enviará un paquete Wake-on-LAN al equipo físico,"
    echo -e "arrancará por red iPXE, ${COLOR_RED}SOBRESCRIBIRÁ SU DISCO SSD CON DEBIAN 13${COLOR_NC}"
    echo -e "y lo reincorporará automáticamente al clúster."
    echo -e "=================================================================="

    confirm_action "¿Confirma que desea iniciar la re-instalación y recuperación de ${NODE_NAME}?"

    if [[ "${NODE_ROLE}" == "control-plane" ]]; then
        cmd_heal_etcd "${target}"
    fi

    log_info "1. Verificando UUID del nodo en OpenStack Ironic..."
    local node_uuid
    node_uuid=$(run_on_controller "${OS_SYS} baremetal node show ${NODE_NAME} -c uuid -f value")
    log_info "UUID en Ironic: ${node_uuid}"

    if [[ -n "${new_mac}" ]]; then
        log_info "Actualizando puerto MAC a ${new_mac}..."
        local port_uuid
        port_uuid=$(run_on_controller "${OS_SYS} baremetal port list --node ${node_uuid} -c UUID -f value | head -n1")
        run_on_controller "${OS_SYS} baremetal port set --address ${new_mac} ${port_uuid}"
    fi

    log_info "2. Asegurando que el nodo esté en estado 'available'..."
    local state
    state=$(run_on_controller "${OS_SYS} baremetal node show ${node_uuid} -c provision_state -f value")
    if [[ "${state}" == "enroll" ]]; then
        run_on_controller "${OS_SYS} baremetal node manage ${node_uuid} && ${OS_SYS} baremetal node provide ${node_uuid}"
    elif [[ "${state}" == "manageable" ]]; then
        run_on_controller "${OS_SYS} baremetal node provide ${node_uuid}"
    elif [[ "${state}" == "active" ]]; then
        log_warn "El nodo figura como 'active'. Eliminando asignación previa para permitir re-provisión limpia..."
        run_on_controller "${OS_SYS} baremetal node undeploy ${node_uuid} || true"
        sleep 5
        run_on_controller "${OS_SYS} baremetal node manage ${node_uuid} && ${OS_SYS} baremetal node provide ${node_uuid}"
    fi

    log_info "3. Generando archivo User-Data Cloud-Init para inyección Zero-Touch..."
    local user_data_file="/tmp/userdata_${NODE_NAME}.yml"
    local pub_key
    pub_key="$(cat "${SSH_KEY}.pub" 2>/dev/null || cat ~/.ssh/id_ed25519.pub)"

    cat > "${user_data_file}" << EOF
#cloud-config
hostname: ${NODE_NAME}
fqdn: ${NODE_NAME}.lab.local
manage_etc_hosts: true

users:
  - name: debian
    gecos: Debian Admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, adm
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - "${pub_key}"

write_files:
  - path: /etc/systemd/network/10-lan.network
    content: |
      [Match]
      MACAddress=${NODE_MAC}
      [Network]
      Address=${NODE_IP}/24
      Gateway=10.100.29.30
      DNS=192.168.26.120
  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

runcmd:
  - swapoff -a
  - sed -i '/ swap / s/^\(.*\)$/# \1/g' /etc/fstab
  - systemctl restart systemd-networkd
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
EOF

    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${user_data_file}" "${CONTROLLER_USER}@${CONTROLLER_IP}:/tmp/userdata_${NODE_NAME}.yml"
    rm -f "${user_data_file}"

    log_info "4. Despachando aprovisionamiento bare-metal con Wake-on-LAN..."
    run_on_controller "${OS_CMD} server create \
      --flavor baremetal.optiplex \
      --image debian-13-baremetal \
      --nic net-id=88fb6003-0b79-4784-8a63-100419ce237f \
      --user-data /tmp/userdata_${NODE_NAME}.yml \
      --config-drive true \
      ${NODE_NAME}"

    log_success "Orden de despliegue enviada a OpenStack Ironic."
    log_info "El nodo ${NODE_NAME} se está encendiendo por Wake-on-LAN y flasheando su SSD por red."
    log_info "Esperando a que el sistema operativo arranque y responda en ${NODE_IP}:22 (esto toma aprox 2-3 minutos)..."

    local retries=30
    local success=false
    while (( retries > 0 )); do
        if run_on_node "${NODE_IP}" "true" 2>/dev/null; then
            success=true
            break
        fi
        echo -ne "  Esperando inicialización de hardware... (${retries} intentos restantes)\r"
        sleep 10
        retries=$((retries - 1))
    done
    echo ""

    if [[ "${success}" = true ]]; then
        log_success "¡El nodo ${NODE_NAME} ha arrancado su nuevo disco SSD y responde por SSH!"
        log_info "5. Ejecutando incorporación final al clúster mediante Ansible..."
        cd "${REPO_DIR}"
        ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml --limit "${NODE_HOST}"
        log_success "=================================================================="
        log_success "   RECUPERACIÓN COMPLETADA CON ÉXITO: NODO ${NODE_NAME} OPERATIVO "
        log_success "=================================================================="
    else
        log_warn "El nodo no respondió en el tiempo límite. Puede estar formateando el disco o requirió encendido manual si WoL estaba suspendido en BIOS."
        log_info "Compruebe el estado del despliegue en Horizon o con:"
        echo "ssh -i ${SSH_KEY} ${CONTROLLER_USER}@${CONTROLLER_IP} 'sudo docker exec kolla_toolbox openstack baremetal node show ${NODE_NAME}'"
    fi
}

# Leer opciones completas antes de realizar cualquier acción.
[[ $# -gt 0 ]] || { show_help; exit 0; }
NEW_MAC_ARG=""
ACTION=""
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --audit|--backup-all|--backup-openstack|--backup-etcd|--heal-etcd|--reprovision)
            [[ -z "${ACTION}" ]] || { log_error "Use una sola acción por ejecución"; exit 2; }
            ACTION="$1"; shift
            if [[ "${ACTION}" == --heal-etcd || "${ACTION}" == --reprovision ]]; then
                [[ $# -gt 0 && "$1" != -* ]] || { log_error "Falta el nodo destino"; exit 2; }
                TARGET="$1"; shift
            fi ;;
        --new-mac)
            [[ $# -ge 2 && "$2" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { log_error "MAC inválida"; exit 2; }
            NEW_MAC_ARG="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "Opción no reconocida: $1"; exit 2 ;;
    esac
done
[[ -n "${ACTION}" ]] || { log_error "Indique una acción"; exit 2; }
[[ -z "${NEW_MAC_ARG}" || "${ACTION}" == --reprovision ]] || { log_error "--new-mac requiere --reprovision"; exit 2; }
if [[ "${ACTION}" == --audit || "${ACTION}" == --reprovision ]]; then
    [[ -n "${OS_PASS}" ]] || { log_error "Cargue OS_PASSWORD desde su OpenRC antes de continuar"; exit 2; }
fi
case "${ACTION}" in
    --audit) cmd_audit ;;
    --backup-all) run_backup_playbook backup ;;
    --backup-openstack) cmd_backup_openstack ;;
    --backup-etcd) cmd_backup_etcd ;;
    --heal-etcd) cmd_heal_etcd "${TARGET}" ;;
    --reprovision) cmd_reprovision "${TARGET}" "${NEW_MAC_ARG}" ;;
esac

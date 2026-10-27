#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ORQUESTACIÓN REMOTA DESDE LAPTOP (ejecutar-desde-laptop.sh)
# Motor Modernizado: Orquestación Ansible Core (Paralelo, Seguro e Idempotente)
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ANSIBLE_DIR="${REPO_DIR}/ansible"
INVENTORY="${REPO_DIR}/inventory/lab/hosts.yml"
SITE_PLAYBOOK="${ANSIBLE_DIR}/site.yml"

# shellcheck source=scripts/lib/common.sh
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
elif [[ -f "${REPO_DIR}/scripts/lib/common.sh" ]]; then
    source "${REPO_DIR}/scripts/lib/common.sh"
fi

load_config 2>/dev/null || true

DRY_RUN_ARGS=()
export ANSIBLE_CONFIG="${REPO_DIR}/ansible.cfg"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   ORQUESTADOR DEVOPS: DESPLIEGUE REMOTO CON ANSIBLE CORE        ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

show_help() {
    cat << EOF
Uso: $0 [COMANDO / FASE] [OPCIONES]

Comandos Principales (Motor Ansible Core):
  --check               Auditar conectividad SSH y ping paralelo a todos los 8 nodos
  --fase <num>          Ejecutar una fase específica mediante roles de Ansible:
                          1 -> Configuración Base OS (roles/common en toda la flota)
                          2 -> Bastión Gateway, SSH :22, Squid y nftables (roles/bastion)
                          3 -> Sonatype Nexus 3 OSS y PostgreSQL 16 (roles/nexus)
                          4 -> Clientes APT apuntando a Nexus local (roles/common)
                          5 -> Servidor PXE, DHCP dnsmasq e iPXE HTTP (roles/pxe_controller)
                          6 -> OpenStack Ironic Standalone y Gestión Bare-Metal (roles/ironic)
                          8 -> Clúster Kubernetes HA con RKE2 y Cilium eBPF (roles/rke2_ha)
                          9 -> Auditoría integral de puertos y servicios (playbooks/09_healthcheck.yml)
                          10 -> Suite de Monitoreo Prometheus, Grafana y Node Exporter (roles/monitoring)
  --health              Ejecutar auditoría de salud visual rápida en vivo
  --all                 Ejecutar todas las fases de manera ordenada y secuencial
  --dry-run             Simular ejecución con verificación Ansible (--check --diff)
  -h, --help            Mostrar esta ayuda

Ejemplos:
  $0 --check
  $0 --fase 1
  $0 --fase 8
  $0 --all
  $0 --all --dry-run
EOF
}

run_ansible() {
    local playbook="$1"
    shift
    local extra_args=("$@")
    
    cd "${REPO_DIR}"
    log_info "Ejecutando: ansible-playbook -i ${INVENTORY} ${playbook} ${extra_args[*]} ${DRY_RUN_ARGS[*]}"
    ansible-playbook -i "${INVENTORY}" "${playbook}" "${extra_args[@]}" "${DRY_RUN_ARGS[@]}"
}

cmd_check() {
    log_info "Verificando conectividad y autenticación SSH en paralelo (8 nodos)..."
    cd "${REPO_DIR}"
    if ansible baremetal -i "${INVENTORY}" -m ping; then
        log_success "Todos los nodos bare-metal respondieron exitosamente."
    else
        log_warn "Algunos nodos físicos no respondieron (comportamiento normal si están apagados a la espera de PXE o mantenimiento)."
    fi
}

cmd_fase() {
    local fase="$1"
    case "${fase}" in
        1)
            log_info "FASE 1: Configuración Base del Sistema Operativo en la flota..."
            run_ansible "${SITE_PLAYBOOK}" --tags "base,common"
            ;;
        2)
            log_info "FASE 2: Configuración de Bastion Gateway, NAT y Firewall nftables..."
            run_ansible "${SITE_PLAYBOOK}" --tags "bastion"
            ;;
        3)
            log_info "FASE 3: Despliegue de Nexus OSS y PostgreSQL 16..."
            run_ansible "${SITE_PLAYBOOK}" --tags "nexus"
            ;;
        4)
            log_info "FASE 4: Apuntar Clientes APT hacia Nexus Local..."
            run_ansible "${SITE_PLAYBOOK}" --tags "common" --limit "baremetal:!bastion:!nexus"
            ;;
        5)
            log_info "FASE 5: Configurar Servidor PXE / TFTP / dnsmasq en Nodo 306..."
            run_ansible "${SITE_PLAYBOOK}" --tags "pxe"
            ;;
        6)
            log_info "FASE 6: Configurar OpenStack Ironic Standalone en Nodo 306..."
            run_ansible "${SITE_PLAYBOOK}" --tags "ironic"
            ;;
        7)
            log_info "FASE 7: Generar Plantillas Cloud-Init, ConfigDrive y Packer en Nodo 306..."
            if [[ "${DRY_RUN}" == true ]]; then
                log_info "[DRY-RUN] Prepararía Cloud-Init en el controlador PXE."
            else
                bash "${REPO_DIR}/scripts/ops/07-cloud-init.sh" -y
            fi
            ;;
        8)
            log_info "FASE 8: Despliegue de Kubernetes HA (RKE2 + Cilium eBPF)..."
            run_ansible "${SITE_PLAYBOOK}" --tags "k8s"
            ;;
        9)
            log_info "FASE 9: Validación Integral del Clúster..."
            run_ansible "${SITE_PLAYBOOK}" --tags "healthcheck"
            ;;
        10)
            log_info "FASE 10: Despliegue de Suite de Monitoreo (Node Exporter, Prometheus, Grafana)..."
            run_ansible "${SITE_PLAYBOOK}" --tags "monitoring"
            ;;
        *)
            log_error "Fase desconocida: ${fase}. Fases disponibles: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10."
            exit 1
            ;;
    esac
}

# Validar toda la línea antes de ejecutar acciones.
[[ $# -gt 0 ]] || { show_help; exit 0; }
ACTIONS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|--health|--all) ACTIONS+=("$1"); shift ;;
        --fase)
            [[ $# -ge 2 && "$2" =~ ^([1-9]|10)$ ]] || { log_error "--fase requiere un número entre 1 y 10"; exit 2; }
            ACTIONS+=("fase:$2"); shift 2 ;;
        --dry-run) DRY_RUN=true; DRY_RUN_ARGS=(--check --diff); shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "Opción no reconocida: $1"; exit 2 ;;
    esac
done
[[ ${#ACTIONS[@]} -gt 0 ]] || { log_error "Indique una acción"; exit 2; }
for action in "${ACTIONS[@]}"; do
    case "${action}" in
        --check) cmd_check ;;
        --health) bash "${REPO_DIR}/scripts/diagnostics/healthcheck.sh" ;;
        --all)
            cmd_check
            confirm_action "¿Desea iniciar el despliegue secuencial de todas las fases con Ansible?"
            run_ansible "${SITE_PLAYBOOK}" ;;
        fase:*) cmd_fase "${action#fase:}" ;;
    esac
done

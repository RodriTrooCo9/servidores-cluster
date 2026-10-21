#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ORQUESTACIÓN REMOTA DESDE LAPTOP (ejecutar-desde-laptop.sh)
# Motor Modernizado: Orquestación Ansible Core (Paralelo, Seguro e Idempotente)
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory/hosts.yml"
SITE_PLAYBOOK="${ANSIBLE_DIR}/site.yml"

# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
fi

load_config 2>/dev/null || true

DRY_RUN_ARG=""
USE_LEGACY=false

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
  --legacy              Forzar ejecución mediante scripts Bash secuenciales antiguos
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
    
    cd "${ANSIBLE_DIR}"
    log_info "Ejecutando: ansible-playbook -i ${INVENTORY} ${playbook} ${extra_args[*]} ${DRY_RUN_ARG}"
    ansible-playbook -i "${INVENTORY}" "${playbook}" "${extra_args[@]}" ${DRY_RUN_ARG}
}

cmd_check() {
    log_info "Verificando conectividad y autenticación SSH en paralelo (8 nodos)..."
    cd "${ANSIBLE_DIR}"
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
            if [[ -f "${SCRIPT_DIR}/scripts/07-cloud-init.sh" ]]; then
                bash "${SCRIPT_DIR}/scripts/07-cloud-init.sh" -y
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

# Parseo de argumentos
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            cmd_check
            shift
            ;;
        --fase)
            cmd_fase "$2"
            shift 2
            ;;
        --health)
            if [[ -f "${SCRIPT_DIR}/scripts/healthcheck.sh" ]]; then
                "${SCRIPT_DIR}/scripts/healthcheck.sh"
            else
                "${SCRIPT_DIR}/healthcheck.sh"
            fi
            shift
            ;;
        --all)
            log_info "Iniciando orquestación de la flota completa mediante Ansible Core..."
            cmd_check
            confirm_action "¿Desea iniciar el despliegue secuencial de todas las fases con Ansible?"
            run_ansible "${SITE_PLAYBOOK}"
            shift
            ;;
        --dry-run)
            DRY_RUN_ARG="--check --diff"
            log_warn "Modo Dry-Run activado (--check --diff en Ansible)."
            shift
            ;;
        --legacy)
            USE_LEGACY=true
            log_warn "Modo Legacy activado. Usando scripts imperativos secuenciales."
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Opción no reconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

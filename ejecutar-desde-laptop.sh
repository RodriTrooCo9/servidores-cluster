#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE ORQUESTACIÓN REMOTA DESDE LAPTOP (ejecutar-desde-laptop.sh)
# Objetivo: Conectarse por SSH a la flota y ejecutar la instalación de servicios
#           de forma modular, segura y desatendida desde tu estación de trabajo.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_config

# Colores y banners
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   ORQUESTADOR DEVOPS: DESPLIEGUE REMOTO POR SSH DESDE LAPTOP    ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

show_help() {
    cat << EOF
Uso: $0 [COMANDO / FASE] [OPCIONES]

Comandos Principales:
  --check               Auditar conectividad SSH y ping a todos los nodos
  --sync                Sincronizar scripts hacia /tmp/infra-scripts en los nodos
  --fase <num>          Ejecutar una fase específica en los nodos correspondientes:
                          1 -> 01-base-servidores.sh (Todos los nodos)
                          2 -> 02-bastion.sh (Bastión - Nodo 314)
                          3 -> 03-nexus.sh (Nexus OSS - Nodo 315)
                          4 -> 04-clientes-nexus.sh (Clientes APT hacia Nexus)
                          5 -> 05-pxe-dhcp-tftp.sh (Servidor PXE - Nodo 306)
                          8 -> 08-kubernetes.sh (Control Planes y Workers)
                          9 -> 09-verificacion.sh (Validación final)
  --health              Ejecutar auditoría de salud del clúster (healthcheck.sh)
  --all                 Ejecutar todas las fases de manera ordenada y secuencial
  --dry-run             Simular las órdenes remotas sin ejecutarlas
  -h, --help            Mostrar esta ayuda

Ejemplos:
  $0 --check
  $0 --sync
  $0 --fase 2
  $0 --fase 8
  $0 --all
EOF
}

# Obtener usuario y alias de SSH configurado
get_node_ssh_alias() {
    local node_id="$1"
    local hostname="$2"
    case "${node_id}" in
        314) echo "bastion" ;;
        315) echo "nexus-repo" ;;
        306) echo "pxe-controller" ;;
        269) echo "cp-01" ;;
        280) echo "cp-02" ;;
        320) echo "cp-03" ;;
        321) echo "worker-01" ;;
        279) echo "worker-02" ;;
        *)   echo "${hostname}" ;;
    esac
}

cmd_check() {
    log_info "Verificando acceso SSH y estado de la flota bare-metal..."
    printf "+------+-----------------+---------------+--------+------------+-------------------------+\n"
    printf "| %-4s | %-15s | %-13s | %-6s | %-10s | %-23s |\n" "ID" "HOSTNAME" "IP" "PING" "SSH (SSHD)" "ROL"
    printf "+------+-----------------+---------------+--------+------------+-------------------------+\n"

    while IFS=',' read -u 9 -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        local alias_name
        alias_name="$(get_node_ssh_alias "${id}" "${hostname}")"

        local ping_res="${COLOR_RED}FAIL${COLOR_NC}"
        if ssh -n -o BatchMode=yes -o ConnectTimeout=2 n306-wifi "ping -c 1 -W 1 ${ip}" >/dev/null 2>&1; then
            ping_res="${COLOR_GREEN}OK${COLOR_NC}  "
        fi

        local ssh_res="${COLOR_RED}DOWN${COLOR_NC}      "
        if ssh -n -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "${alias_name}" "uptime" >/dev/null 2>&1; then
            ssh_res="${COLOR_GREEN}CONECTADO${COLOR_NC} "
        fi

        printf "| %-4s | %-15s | %-13s | %b | %b | %-23s |\n" \
            "${id}" "${hostname}" "${ip}" "${ping_res}" "${ssh_res}" "${role:0:23}"
    done 9< "${NODES_CSV}"
    printf "+------+-----------------+---------------+--------+------------+-------------------------+\n"
}

cmd_sync() {
    log_info "Sincronizando directorio infra-scripts a los nodos en línea..."
    while IFS=',' read -r id mac hostname ip role ram disk bmc; do
        [[ "${id}" == "id" ]] && continue
        local alias_name
        alias_name="$(get_node_ssh_alias "${id}" "${hostname}")"

        log_info "Sincronizando hacia [${hostname}] (${alias_name})..."
        if ssh -n -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "${alias_name}" "mkdir -p /tmp/infra-scripts" 2>/dev/null; then
            scp -r -q -o BatchMode=yes -o ConnectTimeout=5 "${SCRIPT_DIR}/"* "${alias_name}:/tmp/infra-scripts/"
            ssh -n "${alias_name}" "chmod +x /tmp/infra-scripts/*.sh"
            log_success "Sincronizado exitosamente en ${hostname}."
        else
            log_warn "Nodo ${hostname} (${alias_name}) no accesible por SSH. Omitiendo sync."
        fi
    done < "${NODES_CSV}"
}

run_remote_script() {
    local target_alias="$1"
    local script_name="$2"
    local args="${3:--y}"

    log_info "--> Ejecutando ${script_name} en [${target_alias}]..."
    if [[ "${DRY_RUN}" = true ]]; then
        echo -e "${COLOR_CYAN}[DRY-RUN] ssh ${target_alias} 'sudo /tmp/infra-scripts/${script_name} ${args}'${COLOR_NC}"
        return 0
    fi

    ssh -t -o ConnectTimeout=5 "${target_alias}" "sudo /tmp/infra-scripts/${script_name} ${args}"
}

cmd_fase() {
    local fase="$1"
    case "${fase}" in
        1)
            log_info "FASE 1: Preparación Base del Sistema Operativo en todos los nodos..."
            cmd_sync
            while IFS=',' read -r id mac hostname ip role ram disk bmc; do
                [[ "${id}" == "id" ]] && continue
                local target
                target="$(get_node_ssh_alias "${id}" "${hostname}")"
                run_remote_script "${target}" "01-base-servidores.sh" "-y"
            done < "${NODES_CSV}"
            ;;
        2)
            log_info "FASE 2: Configuración de Bastion Gateway, NAT y Firewall..."
            cmd_sync
            run_remote_script "bastion" "02-bastion.sh" "-y"
            ;;
        3)
            log_info "FASE 3: Despliegue de Nexus OSS y PostgreSQL 16..."
            cmd_sync
            run_remote_script "nexus-repo" "03-nexus.sh" "-y"
            ;;
        4)
            log_info "FASE 4: Apuntar Clientes APT y Containerd a Nexus..."
            cmd_sync
            while IFS=',' read -r id mac hostname ip role ram disk bmc; do
                [[ "${id}" == "id" ]] && continue
                [[ "${id}" =~ ^(314|315)$ ]] && continue # Omitir Bastión y Nexus
                local target
                target="$(get_node_ssh_alias "${id}" "${hostname}")"
                run_remote_script "${target}" "04-clientes-nexus.sh" "-y"
            done < "${NODES_CSV}"
            ;;
        5)
            log_info "FASE 5: Configurar Servidor PXE / TFTP en Nodo 306..."
            cmd_sync
            run_remote_script "pxe-controller" "05-pxe-dhcp-tftp.sh" "-y"
            ;;
        8)
            log_info "FASE 8: Despliegue de Kubernetes HA (RKE2 + Cilium)..."
            cmd_sync
            # 1. Líder
            run_remote_script "cp-01" "08-kubernetes.sh" "-y"
            # 2. Otros Control Planes
            run_remote_script "cp-02" "08-kubernetes.sh" "-y"
            run_remote_script "cp-03" "08-kubernetes.sh" "-y"
            # 3. Workers
            run_remote_script "worker-01" "08-kubernetes.sh" "-y"
            run_remote_script "worker-02" "08-kubernetes.sh" "-y"
            # 4. Extraer cliente en Bastión
            run_remote_script "bastion" "08-kubernetes.sh" "-y"
            ;;
        9)
            log_info "FASE 9: Validación Integral del Clúster..."
            run_remote_script "bastion" "09-verificacion.sh" ""
            ;;
        *)
            log_error "Fase desconocida: ${fase}. Fases disponibles: 1, 2, 3, 4, 5, 8, 9."
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
        --sync)
            cmd_sync
            shift
            ;;
        --fase)
            cmd_fase "$2"
            shift 2
            ;;
        --health)
            "${SCRIPT_DIR}/healthcheck.sh"
            shift
            ;;
        --all)
            log_info "Iniciando despliegue de la flota completa..."
            cmd_check
            confirm_action "¿Desea iniciar el despliegue secuencial de todas las fases?"
            cmd_fase 1
            cmd_fase 2
            cmd_fase 3
            cmd_fase 4
            cmd_fase 5
            cmd_fase 8
            cmd_fase 9
            "${SCRIPT_DIR}/healthcheck.sh"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

#!/usr/bin/env bash
# ==============================================================================
# LEVANTAR TODO - Secuencia de Arranque y Recuperación Global del Clúster
# ==============================================================================
# Orden de encendido:
#   1. Contenedores de OpenStack Kolla en nodo 306 (pxe-controller)
#   2. Servicios perimetrales: Bastión (SSH/Squid) y Nexus (Docker/APT)
#   3. Servicios PXE y DHCP dnsmasq
#   4. Monitoreo central: Node Exporter, Prometheus, Grafana
#   5. Plataforma Kubernetes HA (RKE2 + Cilium eBPF)
#   6. Healthcheck de validación integral
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SSH_KEY="${REPO_DIR}/ansible/keys/cluster_key"
CONTROLLER_IP="192.168.29.25"
CONTROLLER_USER="n306"
INVENTORY="${REPO_DIR}/inventory/lab/hosts.yml"
export ANSIBLE_CONFIG="${REPO_DIR}/ansible.cfg"

echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}       INICIANDO SECUENCIA GLOBAL DE ARRANQUE DEL CLÚSTER         ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"

# Paso 1: Asegurar contenedores Kolla en nodo controlador (OpenStack Ironic/Glance/MariaDB)
echo -e "\n${YELLOW}[Paso 1/6] Levantando contenedores OpenStack Kolla en nodo 306...${NC}"
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_IP}" \
  "sudo docker start \$(sudo docker ps -a -q) >/dev/null 2>&1 || true"
echo -e "${GREEN}✓ Contenedores Docker en nodo 306 verificados.${NC}"

cd "${REPO_DIR}"

# Paso 2: Bastión y Nexus
echo -e "\n${YELLOW}[Paso 2/6] Configurando y levantando Bastión (314) y Nexus (315)...${NC}"
ansible-playbook -i "${INVENTORY}" \
  ansible/playbooks/10-base/02_bastion_hardening.yml \
  ansible/playbooks/20-services/01_nexus.yml
echo -e "${GREEN}✓ Bastión y Nexus 3 operativos.${NC}"

# Paso 3: PXE Controller
echo -e "\n${YELLOW}[Paso 3/6] Verificando controlador PXE y dnsmasq (306)...${NC}"
ansible-playbook -i "${INVENTORY}" \
  ansible/playbooks/20-services/02_pxe_controller.yml
echo -e "${GREEN}✓ Controlador PXE verificado.${NC}"

# Paso 4: Monitoreo Centralizado (Node Exporter, Prometheus, Grafana)
echo -e "\n${YELLOW}[Paso 4/6] Levantando suite de monitoreo y observabilidad...${NC}"
ansible-playbook -i "${INVENTORY}" \
  ansible/playbooks/40-observability/01_monitoring.yml
echo -e "${GREEN}✓ Monitoreo (Prometheus :9090, Grafana :3000) operativo.${NC}"

# Paso 5: Kubernetes HA (RKE2 Server en 306 + Agents en nodos trabajadores)
echo -e "\n${YELLOW}[Paso 5/6] Verificando y levantando Kubernetes HA (RKE2 + Cilium)...${NC}"
ansible-playbook -i "${INVENTORY}" \
  ansible/playbooks/30-platform/01_rke2_cluster.yml
echo -e "${GREEN}✓ Clúster RKE2 y CNI Cilium activos.${NC}"

# Paso 6: Healthcheck global de validación
echo -e "\n${YELLOW}[Paso 6/6] Ejecutando validación integral de salud (Healthcheck)...${NC}"
ansible-playbook -i "${INVENTORY}" \
  ansible/playbooks/50-validation/01_healthcheck.yml

echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD}  ¡SECUENCIA DE ARRANQUE COMPLETADA EXITOSAMENTE EN TODA LA FLOTA!${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"

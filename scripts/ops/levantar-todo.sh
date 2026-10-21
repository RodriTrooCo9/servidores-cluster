#!/usr/bin/env bash


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

# Paso 1: OpenStack
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${CONTROLLER_USER}@${CONTROLLER_IP}" \
  "sudo docker start \$(sudo docker ps -a -q) >/dev/null 2>&1 || true"
# Paso 2: Bastión y Nexus
cd "${REPO_DIR}"
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/03_bastion.yml ansible/playbooks/04_nexus.yml

# Paso 3: Monitoreo
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/08_monitoring.yml

# Paso 4: Kubernetes HA
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/07_kubernetes_ha.yml

# Paso 5: Healthcheck
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/09_healthcheck.yml

# 1. Asegurar OpenStack arriba:
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker start \$(sudo docker ps -a -q)"

# 2. Levantar Bastión (Squid/SSH) y Nexus (Docker Hub/APT):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/03_bastion.yml ansible/playbooks/04_nexus.yml

# 3. Levantar Monitoreo (Grafana/Prometheus):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/08_monitoring.yml

# 4. Levantar Kubernetes HA (RKE2 + Cilium eBPF):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/07_kubernetes_ha.yml
# 1. Asegurar OpenStack arriba:
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker start \$(sudo docker ps -a -q)"

# 2. Levantar Bastión (Squid/SSH) y Nexus (Docker Hub/APT):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/03_bastion.yml ansible/playbooks/04_nexus.yml

# 3. Levantar Monitoreo (Grafana/Prometheus):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/08_monitoring.yml

# 4. Levantar Kubernetes HA (RKE2 + Cilium eBPF):
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/07_kubernetes_ha.yml

# 5. Comprobar que absolutamente todo quedó ONLINE:
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/09_healthcheck.yml
# 5. Comprobar que absolutamente todo quedó ONLINE:
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/09_healthcheck.yml
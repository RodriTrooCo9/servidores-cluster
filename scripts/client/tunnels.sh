#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/tunnels.sh
# Objetivo: Abrir túneles SSH automáticos para acceder a todos los dashboards web
#           y APIs del clúster desde cualquier laptop conectada por WiFi.
#
# Servicios mapeados a localhost:
#   - OpenStack Horizon : http://localhost:8080/auth/login/
#   - Sonatype Nexus 3  : http://localhost:8081/
#   - Nexus Docker Pull : localhost:8082
#   - Nexus Docker Push : localhost:8083
#   - Grafana Metrics   : http://localhost:3000/
#   - Prometheus TSDB   : http://localhost:9090/
#   - Kubernetes API    : https://localhost:6443/
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SSH_KEY="${REPO_DIR}/ansible/keys/cluster_key"
if [[ ! -f "${SSH_KEY}" ]]; then
    SSH_KEY="${HOME}/.ssh/id_ed25519"
fi

CONTROLLER_IP="192.168.29.25"
CONTROLLER_USER="n306"

exec ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -N \
    -L 8080:10.100.29.30:80 \
    -L 8081:10.100.29.20:8081 \
    -L 8082:10.100.29.20:8082 \
    -L 8083:10.100.29.20:8083 \
    -L 3000:10.100.29.30:3000 \
    -L 9090:10.100.29.30:9090 \
    -L 6443:10.100.29.101:6443 \
    "${CONTROLLER_USER}@${CONTROLLER_IP}"

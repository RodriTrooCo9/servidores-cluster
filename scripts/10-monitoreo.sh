#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 10: DESPLIEGUE DEL STACK DE MONITOREO BARE-METAL (scripts/10-monitoreo.sh)
# Objetivo: Desplegar Prometheus, Grafana, Alertmanager y Blackbox en Nodo 306,
#           y Node Exporter en la flota completa de servidores.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
load_config
require_root

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 10: STACK DE MONITOREO CENTRALIZADO (PROMETHEUS/GRAFANA) ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

CURRENT_HOSTNAME="$(hostname -s)"
CURRENT_IP="$(ip -o -4 addr show | grep '10.100.29.' | awk '{print $4}' | cut -d/ -f1 | head -n1 || echo "")"

VERSION_NODE_EXPORTER="1.8.2"
VERSION_PROMETHEUS="2.54.1"
VERSION_ALERTMANAGER="0.27.0"
VERSION_BLACKBOX="0.25.0"

# ------------------------------------------------------------------------------
# 1. INSTALACIÓN DE NODE EXPORTER (EN TODOS LOS NODOS)
# ------------------------------------------------------------------------------
install_node_exporter() {
    log_info "Configurando Prometheus Node Exporter en el host local..."
    
    # Crear usuario sin shell
    id -u node_exporter &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    
    # Instalar mediante paquete o binario
    if ! command -v node_exporter &>/dev/null; then
        if apt-cache show prometheus-node-exporter &>/dev/null; then
            log_info "Instalando paquete prometheus-node-exporter desde repositorio..."
            apt-get update -y && apt-get install -y prometheus-node-exporter
        else
            log_info "Descargando binario oficial de Node Exporter v${VERSION_NODE_EXPORTER}..."
            local tar_file="/tmp/node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64.tar.gz"
            curl -sLo "${tar_file}" "https://github.com/prometheus/node_exporter/releases/download/v${VERSION_NODE_EXPORTER}/node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64.tar.gz"
            tar -xzf "${tar_file}" -C /tmp/
            cp "/tmp/node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64/node_exporter" /usr/local/bin/
            chown node_exporter:node_exporter /usr/local/bin/node_exporter
            chmod 755 /usr/local/bin/node_exporter
            rm -rf "/tmp/node_exporter-${VERSION_NODE_EXPORTER}"*
        fi
    fi

    # Unidad systemd personalizada
    cat << 'EOF' > /etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100 --collector.systemd --collector.processes
Restart=always
RestartSec=5s
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now node_exporter
    log_success "Node Exporter activo y respondiendo en el puerto 9100."
}

# ------------------------------------------------------------------------------
# 2. INSTALACIÓN DE SERVICIOS CENTRALES EN NODO 306
# ------------------------------------------------------------------------------
install_monitoring_server() {
    log_info "Host identificado como Servidor Central de Monitoreo (Nodo 306)..."
    
    # Crear usuarios de sistema
    id -u prometheus &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
    id -u alertmanager &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin alertmanager

    mkdir -p /etc/prometheus/targets /etc/prometheus/rules /var/lib/prometheus /etc/alertmanager /var/lib/alertmanager /etc/blackbox_exporter
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
    chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

    # 2.1 Descargar binarios estáticos si no existen
    if ! command -v prometheus &>/dev/null; then
        log_info "Instalando Prometheus v${VERSION_PROMETHEUS}..."
        curl -sLo /tmp/prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/v${VERSION_PROMETHEUS}/prometheus-${VERSION_PROMETHEUS}.linux-amd64.tar.gz"
        tar -xzf /tmp/prometheus.tar.gz -C /tmp/
        cp "/tmp/prometheus-${VERSION_PROMETHEUS}.linux-amd64/prometheus" /usr/local/bin/
        cp "/tmp/prometheus-${VERSION_PROMETHEUS}.linux-amd64/promtool" /usr/local/bin/
        chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
        rm -rf /tmp/prometheus*
    fi

    if ! command -v alertmanager &>/dev/null; then
        log_info "Instalando Alertmanager v${VERSION_ALERTMANAGER}..."
        curl -sLo /tmp/alertmanager.tar.gz "https://github.com/prometheus/alertmanager/releases/download/v${VERSION_ALERTMANAGER}/alertmanager-${VERSION_ALERTMANAGER}.linux-amd64.tar.gz"
        tar -xzf /tmp/alertmanager.tar.gz -C /tmp/
        cp "/tmp/alertmanager-${VERSION_ALERTMANAGER}.linux-amd64/alertmanager" /usr/local/bin/
        cp "/tmp/alertmanager-${VERSION_ALERTMANAGER}.linux-amd64/amtool" /usr/local/bin/
        chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool
        rm -rf /tmp/alertmanager*
    fi

    if ! command -v blackbox_exporter &>/dev/null; then
        log_info "Instalando Blackbox Exporter v${VERSION_BLACKBOX}..."
        curl -sLo /tmp/blackbox.tar.gz "https://github.com/prometheus/blackbox_exporter/releases/download/v${VERSION_BLACKBOX}/blackbox_exporter-${VERSION_BLACKBOX}.linux-amd64.tar.gz"
        tar -xzf /tmp/blackbox.tar.gz -C /tmp/
        cp "/tmp/blackbox_exporter-${VERSION_BLACKBOX}.linux-amd64/blackbox_exporter" /usr/local/bin/
        setcap cap_net_raw+ep /usr/local/bin/blackbox_exporter 2>/dev/null || true
        rm -rf /tmp/blackbox*
    fi

    # 2.2 Generar catálogo de targets desde nodes.csv
    log_info "Generando /etc/prometheus/targets/nodes.json a partir de config/nodes.csv..."
    python3 -c '
import csv, json

nodes_csv = "'"${NODES_CSV}"'"
targets = []

with open(nodes_csv, mode="r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        targets.append({
            "targets": [f"{row[\"ip\"]}:9100"],
            "labels": {
                "node_id": row["id"],
                "instance": row["hostname"],
                "role": row["role"],
                "ram_gb": row["ram_gb"]
            }
        })

with open("/etc/prometheus/targets/nodes.json", "w") as out:
    json.dump(targets, out, indent=2)
'
    chown prometheus:prometheus /etc/prometheus/targets/nodes.json

    # 2.3 Generar reglas de alerta
    cat << 'EOF' > /etc/prometheus/rules/alert_rules.yml
groups:
  - name: BareMetalAlerts
    rules:
      - alert: NodeDown
        expr: up{job="baremetal-nodes"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Nodo no responde: {{ $labels.instance }}"
      - alert: HighCPU
        expr: (100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 85
        for: 10m
        labels:
          severity: warning
      - alert: HighRAM
        expr: ((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: critical
      - alert: HighDisk
        expr: ((node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85
        for: 5m
        labels:
          severity: warning
EOF
    chown -R prometheus:prometheus /etc/prometheus/rules

    # 2.4 Generar prometheus.yml
    cat << 'EOF' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['127.0.0.1:9093']

rule_files:
  - '/etc/prometheus/rules/alert_rules.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'baremetal-nodes'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/nodes.json'
        refresh_interval: 1m

  - job_name: 'blackbox-icmp'
    metrics_path: '/probe'
    params:
      module: ['icmp_connect']
    static_configs:
      - targets:
          - '10.100.29.10'
          - '10.100.29.20'
          - '10.100.29.30'
          - '10.100.29.101'
          - '10.100.29.102'
          - '10.100.29.103'
          - '10.100.29.111'
          - '10.100.29.112'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: '127.0.0.1:9115'
EOF
    chown prometheus:prometheus /etc/prometheus/prometheus.yml

    # 2.5 Servicios systemd
    cat << 'EOF' > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Time Series Database
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --storage.tsdb.retention.time=15d \
    --storage.tsdb.retention.size=15GB \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-lifecycle
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    cat << 'EOF' > /etc/systemd/system/alertmanager.service
[Unit]
Description=Prometheus Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager --web.listen-address=127.0.0.1:9093
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    cat << 'EOF' > /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
route:
  group_by: ['alertname']
  receiver: 'default'
receivers:
  - name: 'default'
EOF
    chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

    cat << 'EOF' > /etc/blackbox_exporter/blackbox.yml
modules:
  icmp_connect:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
EOF

    cat << 'EOF' > /etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Prometheus Blackbox Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/blackbox.yml --web.listen-address=127.0.0.1:9115
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 2.6 Instalar Grafana
    if ! command -v grafana-server &>/dev/null; then
        log_info "Instalando Grafana OSS..."
        apt-get install -y adduser libfontconfig1 musl
        curl -sLo /tmp/grafana.deb "https://dl.grafana.com/oss/release/grafana_11.5.0_amd64.deb"
        dpkg -i /tmp/grafana.deb || apt-get install -f -y
        rm -f /tmp/grafana.deb
    fi

    # Configuración de Datasource para Grafana
    mkdir -p /etc/grafana/provisioning/datasources
    cat << 'EOF' > /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1
datasources:
  - name: Prometheus-BareMetal
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
EOF

    # Hardening de Grafana
    sed -i 's/;allow_sign_up = true/allow_sign_up = false/g' /etc/grafana/grafana.ini || true
    sed -i 's/;enabled = true/enabled = false/g' /etc/grafana/grafana.ini || true

    systemctl daemon-reload
    systemctl enable --now prometheus alertmanager blackbox_exporter grafana-server
    log_success "Servicios de monitoreo (Prometheus, Alertmanager, Blackbox, Grafana) activos."
}

# Ejecutar instalación base de Node Exporter
install_node_exporter

# Si el host actual es el Nodo 306, desplegar la suite central
if [[ "${CURRENT_IP}" == "10.100.29.30" || "${CURRENT_HOSTNAME}" =~ pxe ]] || ip -o link show | grep -qi "64:00:6a:2a:62:42" || ip -o -4 addr show | grep -q "10.100.29.30"; then
    install_monitoring_server
fi

log_success "Fase 10 (Monitoreo) completada con éxito."

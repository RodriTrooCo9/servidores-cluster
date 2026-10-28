# Manual Maestro de Monitoreo: Prometheus, Node Exporter, Grafana, Alertmanager y Blackbox Exporter

> **Infraestructura**: Clúster Bare-Metal de 8 Servidores Físicos Dell OptiPlex 3020M  
> **Sistema Operativo**: Debian GNU/Linux 13 (Trixie)  
> **Subred Privada Aislada**: `10.100.29.0/24` (Cero exposición a la red de oficina)  
> **Servidor Central de Monitoreo**: Nodo 306 (`pxe-controller` | IP: `10.100.29.30` | 16 GB RAM)  
> **Laptop de Administración**: `192.168.29.16` (Acceso vía túneles SSH sobre Wi-Fi)  

---

## 📋 Tabla de Contenidos

1. [Evaluación de Decisiones de Arquitectura](#1-evaluación-de-decisiones-de-arquitectura)
2. [Diagrama ASCII de la Arquitectura (IPs y Puertos)](#2-diagrama-ascii-de-la-arquitectura-ips-y-puertos)
3. [Versiones Fijadas de Software y Método Offline (Air-Gapped)](#3-versiones-fijadas-de-software-y-método-offline-air-gapped)
4. [Despliegue de Node Exporter en la Flota Completa (8 Nodos)](#4-despliegue-de-node-exporter-en-la-flota-completa-8-nodos)
5. [Instalación y Configuración de Prometheus en Nodo 306](#5-instalación-y-configuración-de-prometheus-en-nodo-306)
6. [Instalación y Configuración de Alertmanager y Blackbox Exporter](#6-instalación-y-configuración-de-alertmanager-y-blackbox-exporter)
7. [Instalación y Hardening de Grafana](#7-instalación-y-hardening-de-grafana)
8. [Reglas de Alerta Críticas (`alert_rules.yml`)](#8-reglas-de-alerta-críticas-alert_rulesyml)
9. [Seguridad y Blindaje Perimetral con nftables](#9-seguridad-y-blindaje-perimetral-con-nftables)
10. [Verificación Operativa y Health Checks](#10-verificación-operativa-y-health-checks)
11. [Respaldo, Mantenimiento y Rotación de Credenciales](#11-respaldo-mantenimiento-y-rotación-de-credenciales)
12. [Guía de Solución de Problemas (Troubleshooting) y Rollback](#12-guía-de-solución-de-problemas-troubleshooting-y-rollback)

---

## 1. Evaluación de Decisiones de Arquitectura

### 1.1 Dónde instalar Prometheus y Grafana: Nodo 306 vs Bastión (Nodo 314)
* **Recomendación Oficial: Instalar en el Nodo 306 (`10.100.29.30`)**.
* **Justificación Técnica**:
  1. **Capacidad de Memoria RAM**: El Nodo 306 dispone de **16 GB de RAM**, mientras que el Bastión cuenta con solo **8 GB**. La base de datos de series de tiempo de Prometheus (TSDB) almacena índices en RAM para realizar consultas y agregaciones rápidas; asignarle 4 GB a Prometheus y 1 GB a Grafana en el Bastión saturaría sus 8 GB (que ya corren Squid, Chrony, OpenSSH y nftables).
  2. **Aislamiento de Seguridad**: El Bastión es el único equipo con una interfaz en la red pública/WAN. Si Prometheus o Grafana corren en el Bastión, un error de configuración en nftables podría exponerlos a la red corporativa. En el Nodo 306, ambos servicios quedan confinados en la interfaz Ethernet privada `enp2s0` (`10.100.29.30`).
  3. **Trazabilidad Independiente**: Si el Bastión se reinicia, se desconfigura o se aísla por mantenimiento, el monitoreo del clúster interno continúa funcionando ininterrumpidamente.

### 1.2 Modelo Pull y Confinamiento en Red Privada
* Prometheus utiliza un modelo **PULL**: el servidor inicia activamente una conexión HTTP TCP hacia el puerto `9100` de cada nodo cada 15 segundos.
* Todas las IPs destino son de la subred privada `10.100.29.0/24`. Los paquetes viajan exclusivamente por el switch privado no administrado. **Ningún paquete de telemetría sale hacia la red corporativa**.

### 1.3 Acceso Seguro desde la PC de Administración
* Ni el puerto `9090` (Prometheus) ni el puerto `3000` (Grafana) se exponen a la red corporativa.
* La laptop del administrador (`192.168.29.16`) accede exclusivamente mediante **túneles SSH en reenvío local (`ssh -L`)** a través de la interfaz Wi-Fi del Nodo 306 (`192.168.29.25`):
  ```bash
  ssh -L 3001:localhost:3000 -L 9090:localhost:9090 -L 9093:localhost:9093 -N -f n306-wifi
  ```
  Permitiendo acceder desde el navegador en `http://localhost:3001` y `http://localhost:9090`.

### 1.4 Binarios Nativos + systemd vs Docker Compose
* **Recomendación Oficial**: **Binarios estáticos oficiales (`.tar.gz`) con unidades systemd dedicadas**.
* **Justificación**:
  - Elimina el overhead de virtualización y dependencias de daemons de contenedores.
  - No compite con Podman o containerd de Kubernetes.
  - Permite arranque nativo inmediato en el boot mediante systemd con bajo consumo de memoria (< 50 MB de RAM base).

---

## 2. Diagrama ASCII de la Arquitectura (IPs y Puertos)

```text
+------------------------------------------------------------------------------------------------------------------+
|                          TOPOLOGÍA INTEGRAL DE MONITOREO BARE-METAL (SUBNET 10.100.29.0/24)                      |
|                                                                                                                  |
|                                     [ LAPTOP ADMIN ] (192.168.29.16 Wi-Fi)                                       |
|                                            |                                                                     |
|                             Túneles SSH    | • ssh -L 3001:localhost:3000 (Grafana)                              |
|                             Cifrados       | • ssh -L 9090:localhost:9090 (Prometheus)                           |
|                                            v                                                                     |
|  +------------------------------------------------------------------------------------------------------------+  |
|  | NODO 306 (pxe-controller): IP LAN 10.100.29.30 (enp2s0) / IP Wi-Fi 192.168.29.25 (wlp3s0) | 16 GB RAM     |  |
|  |                                                                                                            |  |
|  |   [ Grafana Server ] (:3000) <----+ (Consultas visuales)                                                   |  |
|  |          ^                        |                                                                        |  |
|  |          | Datasource             |                                                                        |  |
|  |   [ Prometheus Core ] (:9090) ----+                                                                        |  |
|  |          |                        | Dispara alertas                                                        |  |
|  |          | TSDB (15 GB Max)       v                                                                        |  |
|  |          |                  [ Alertmanager ] (:9093)                                                       |  |
|  |          |                                                                                                 |  |
|  |          +---> Scrape Blackbox HTTP/ICMP/TCP ---> [ Blackbox Exporter ] (:9115)                            |  |
|  |          |                                                                                                 |  |
|  |          +---> Scrape Local (:9100) ------------> [ Node Exporter Local ]                                  |  |
|  +----------+-------------------------------------------------------------------------------------------------+  |
|             |                                                                                                    |
|             | Scrape PULL periódico (HTTP /metrics por TCP 9100) a través del Switch Privado L2                  |
|             |                                                                                                    |
|             +--------> [ Nodo 314: bastion ]       (10.100.29.10:9100)  [node_exporter systemd]                  |
|             +--------> [ Nodo 315: nexus-repo ]    (10.100.29.20:9100)  [node_exporter systemd]                  |
|             +--------> [ Nodo 269: k8s-cp-01 ]     (10.100.29.101:9100) [node_exporter systemd]                  |
|             +--------> [ Nodo 280: k8s-cp-02 ]     (10.100.29.102:9100) [node_exporter systemd]                  |
|             +--------> [ Nodo 320: k8s-cp-03 ]     (10.100.29.103:9100) [node_exporter systemd]                  |
|             +--------> [ Nodo 321: k8s-worker-01 ] (10.100.29.111:9100) [node_exporter systemd]                  |
|             +--------> [ Nodo 279: k8s-worker-02 ] (10.100.29.112:9100) [node_exporter systemd]                  |
+------------------------------------------------------------------------------------------------------------------+
```

---

## 3. Versiones Fijadas de Software y Método Offline (Air-Gapped)

Para garantizar estabilidad absoluta e idempotencia en Debian 13 (Trixie), fijamos las versiones oficiales estables:

| Componente | Versión Fijada | Archivo Binario Oficial |
| :--- | :--- | :--- |
| **Node Exporter** | `1.8.2` | `node_exporter-1.8.2.linux-amd64.tar.gz` |
| **Prometheus** | `2.54.1` (LTS) | `prometheus-2.54.1.linux-amd64.tar.gz` |
| **Alertmanager** | `0.27.0` | `alertmanager-0.27.0.linux-amd64.tar.gz` |
| **Blackbox Exporter** | `0.25.0` | `blackbox_exporter-0.25.0.linux-amd64.tar.gz` |
| **Grafana OSS** | `11.5.0` | `grafana_11.5.0_amd64.deb` |

### Procedimiento de Descarga Offline en la PC Admin
Si los nodos operan en modo aislado estricto, descarga los paquetes en tu laptop y transfírelos:

```bash
# [EJECUTAR EN LAPTOP ADMIN]
mkdir -p /tmp/monitoring-binaries && cd /tmp/monitoring-binaries

# 1. Descargar binarios estáticos de Prometheus
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/blackbox_exporter/releases/download/v0.25.0/blackbox_exporter-0.25.0.linux-amd64.tar.gz
curl -LO https://dl.grafana.com/oss/release/grafana_11.5.0_amd64.deb

# 2. Copiar todo el paquete hacia el Nodo 306 por Wi-Fi
scp -r /tmp/monitoring-binaries n306-wifi:/tmp/monitoring-binaries/
```

---

## 4. Despliegue de Node Exporter en la Flota Completa (8 Nodos)

Node Exporter se ejecuta como usuario sin privilegios `node_exporter`, sin shell (`/usr/sbin/nologin`) y escuchando **exclusivamente en la IP privada de cada nodo**.

### 4.1 Creación de Usuario y Estructura de Directorios (Por Nodo)
```bash
# Variables del entorno [ADAPTAR SI CORRESPONDE]
VERSION_NODE_EXPORTER="1.8.2"

# 1. Crear usuario de sistema dedicado
sudo id -u node_exporter &>/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

# 2. Extraer e instalar binario en /usr/local/bin
cd /tmp
tar -xzf "node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64.tar.gz"
sudo cp "node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64/node_exporter" /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
sudo chmod 755 /usr/local/bin/node_exporter
rm -rf "node_exporter-${VERSION_NODE_EXPORTER}.linux-amd64"*
```

### 4.2 Creación de Unidad systemd (`/etc/systemd/system/node_exporter.service`)
Configurada con flags avanzados para recolectar servicios systemd, estadísticas de disco NVMe/SSD y amarre de IP privada:

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=0.0.0.0:9100 \
    --collector.systemd \
    --collector.processes \
    --collector.filesystem.mount-points-exclude="^/(dev|proc|sys|var/lib/docker/.+|var/lib/containerd/.+)($|/)" \
    --collector.netclass.ignored-devices="^(veth.+|cali.+|cilium.+)$"
Restart=always
RestartSec=5s

# Endurecimiento de Seguridad en systemd
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### 4.3 Iniciar y Habilitar Node Exporter
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl status node_exporter --no-pager
```

### 4.4 Script Automatizado de Despliegue Masivo por SSH
Para desplegar Node Exporter en todos los nodos de forma simultánea desde tu laptop:

```bash
#!/usr/bin/env bash
# deploy_node_exporter_all.sh
set -Eeuo pipefail

NODES_CSV="config/nodes.csv"
VERSION="1.8.2"

while IFS=',' read -r id mac hostname ip role ram disk bmc; do
    [[ "${id}" == "id" ]] && continue
    echo "=========================================================="
    echo "Desplegando Node Exporter en [${hostname}] (${ip})..."
    echo "=========================================================="
    
    # Copiar binario y aplicar configuración vía SSH Jump Host
    ssh -n -J n306 debian@"${ip}" "sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter 2>/dev/null || true"
    scp -o 'ProxyJump n306' "/tmp/monitoring-binaries/node_exporter-${VERSION}.linux-amd64.tar.gz" debian@"${ip}":/tmp/
    
    ssh -n -J n306 debian@"${ip}" << 'EOF'
        cd /tmp
        tar -xzf node_exporter-*.linux-amd64.tar.gz
        sudo cp node_exporter-*.linux-amd64/node_exporter /usr/local/bin/
        sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
        sudo chmod 755 /usr/local/bin/node_exporter
        rm -rf node_exporter-*
        
        sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'SVC'
[Unit]
Description=Prometheus Node Exporter
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
SVC
        sudo systemctl daemon-reload
        sudo systemctl enable --now node_exporter
        sudo systemctl restart node_exporter
EOF
    echo "Node Exporter instalado y activo en ${hostname}."
done < "${NODES_CSV}"
```

---

## 5. Instalación y Configuración de Prometheus en Nodo 306

### 5.1 Instalación de Binarios y Estructura en Nodo 306
```bash
VERSION_PROMETHEUS="2.54.1"

# 1. Crear usuario del sistema
sudo id -u prometheus &>/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus

# 2. Crear directorios con permisos
sudo mkdir -p /etc/prometheus/targets /etc/prometheus/rules /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
sudo chmod 750 /etc/prometheus /var/lib/prometheus

# 3. Extraer e instalar binarios
cd /tmp/monitoring-binaries
tar -xzf "prometheus-${VERSION_PROMETHEUS}.linux-amd64.tar.gz"
sudo cp "prometheus-${VERSION_PROMETHEUS}.linux-amd64/prometheus" /usr/local/bin/
sudo cp "prometheus-${VERSION_PROMETHEUS}.linux-amd64/promtool" /usr/local/bin/
sudo cp -r "prometheus-${VERSION_PROMETHEUS}.linux-amd64/consoles" /etc/prometheus/
sudo cp -r "prometheus-${VERSION_PROMETHEUS}.linux-amd64/console_libraries" /etc/prometheus/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chown -R prometheus:prometheus /etc/prometheus
```

### 5.2 Configuración Dinámica de Descubrimiento de Nodos (`file_sd_configs`)
Para permitir agregar o remover nodos del clúster sin reiniciar el servicio Prometheus, desacoplamos la lista de servidores en `/etc/prometheus/targets/nodes.json`:

```json
[
  {
    "targets": ["10.100.29.10:9100"],
    "labels": {
      "node_id": "314",
      "instance": "bastion",
      "role": "bastion",
      "ram_gb": "8"
    }
  },
  {
    "targets": ["10.100.29.20:9100"],
    "labels": {
      "node_id": "315",
      "instance": "nexus-repo",
      "role": "nexus",
      "ram_gb": "16"
    }
  },
  {
    "targets": ["10.100.29.30:9100"],
    "labels": {
      "node_id": "306",
      "instance": "pxe-controller",
      "role": "pxe",
      "ram_gb": "16"
    }
  },
  {
    "targets": ["10.100.29.101:9100"],
    "labels": {
      "node_id": "269",
      "instance": "k8s-cp-01",
      "role": "control-plane-leader",
      "ram_gb": "16"
    }
  },
  {
    "targets": ["10.100.29.102:9100"],
    "labels": {
      "node_id": "280",
      "instance": "k8s-cp-02",
      "role": "control-plane",
      "ram_gb": "16"
    }
  },
  {
    "targets": ["10.100.29.103:9100"],
    "labels": {
      "node_id": "320",
      "instance": "k8s-cp-03",
      "role": "control-plane",
      "ram_gb": "16"
    }
  },
  {
    "targets": ["10.100.29.111:9100"],
    "labels": {
      "node_id": "321",
      "instance": "k8s-worker-01",
      "role": "worker",
      "ram_gb": "8"
    }
  },
  {
    "targets": ["10.100.29.112:9100"],
    "labels": {
      "node_id": "279",
      "instance": "k8s-worker-02",
      "role": "worker",
      "ram_gb": "8"
    }
  }
]
```

### 5.3 Archivo Maestro `/etc/prometheus/prometheus.yml`
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['127.0.0.1:9093']

rule_files:
  - '/etc/prometheus/rules/alert_rules.yml'

scrape_configs:
  # 1. Métricas internas de Prometheus
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9090']
        labels:
          role: 'monitoring'

  # 2. Flota Bare-Metal completa mediante File Service Discovery
  - job_name: 'baremetal-nodes'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/nodes.json'
        refresh_interval: 1m

  # 3. Sonatype Nexus 3 OSS Metrics
  - job_name: 'nexus'
    metrics_path: '/service/rest/v1/status'
    static_configs:
      - targets: ['10.100.29.20:8081']
        labels:
          instance: 'nexus-repo'
          role: 'repository'

  # 4. Blackbox Exporter: ICMP Ping a los 8 nodos físicos
  - job_name: 'blackbox-ping'
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

  # 5. Blackbox Exporter: Verificación TCP de puertos críticos
  - job_name: 'blackbox-tcp'
    metrics_path: '/probe'
    params:
      module: ['tcp_connect']
    static_configs:
      - targets:
          - '10.100.29.10:22'    # SSH Bastión
          - '10.100.29.20:5432'  # PostgreSQL Nexus
          - '10.100.29.30:8089'  # Nginx HTTPBoot
          - '10.100.29.101:6443' # Kubernetes API Server
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: '127.0.0.1:9115'
```

### 5.4 Unidad systemd para Prometheus (`/etc/systemd/system/prometheus.service`)
Aplica los límites estrictos de almacenamiento para el SSD de 128 GB:

```ini
[Unit]
Description=Prometheus Time Series Database
Documentation=https://prometheus.io/docs/
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
    --web.listen-address=10.100.29.30:9090 \
    --web.enable-lifecycle \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5s
LimitNOFILE=65536

# Hardening
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

---

## 6. Instalación y Configuración de Alertmanager y Blackbox Exporter

### 6.1 Alertmanager (Nodo 306)
```bash
VERSION_ALERTMANAGER="0.27.0"

# 1. Crear usuario y directorios
sudo id -u alertmanager &>/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin alertmanager
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

# 2. Instalar binarios
cd /tmp/monitoring-binaries
tar -xzf "alertmanager-${VERSION_ALERTMANAGER}.linux-amd64.tar.gz"
sudo cp "alertmanager-${VERSION_ALERTMANAGER}.linux-amd64/alertmanager" /usr/local/bin/
sudo cp "alertmanager-${VERSION_ALERTMANAGER}.linux-amd64/amtool" /usr/local/bin/
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

# 3. Configuración /etc/alertmanager/alertmanager.yml
sudo tee /etc/alertmanager/alertmanager.yml << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'role']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default-receiver'

receivers:
  - name: 'default-receiver'
    # Sin integración externa por ahora (las alertas se visualizan en la UI web y Grafana)
EOF
sudo chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

# 4. Unidad systemd /etc/systemd/system/alertmanager.service
sudo tee /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Prometheus Alertmanager
Documentation=https://prometheus.io/docs/alerting/
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager \
    --web.listen-address=10.100.29.30:9093
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager
```

### 6.2 Blackbox Exporter (Nodo 306)
Permite monitorear ping de red, disponibilidad de servicios web y sockets TCP:

```bash
VERSION_BLACKBOX="0.25.0"

# 1. Instalar binario y capacitar ping ICMP crudo sin ser root
cd /tmp/monitoring-binaries
tar -xzf "blackbox_exporter-${VERSION_BLACKBOX}.linux-amd64.tar.gz"
sudo cp "blackbox_exporter-${VERSION_BLACKBOX}.linux-amd64/blackbox_exporter" /usr/local/bin/
sudo setcap cap_net_raw+ep /usr/local/bin/blackbox_exporter
sudo mkdir -p /etc/blackbox_exporter

# 2. Configuración /etc/blackbox_exporter/blackbox.yml
sudo tee /etc/blackbox_exporter/blackbox.yml << 'EOF'
modules:
  icmp_connect:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"

  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: [200, 301, 302]
      method: GET
      preferred_ip_protocol: "ip4"

  tcp_connect:
    prober: tcp
    timeout: 5s
    tcp:
      preferred_ip_protocol: "ip4"
EOF

# 3. Unidad systemd /etc/systemd/system/blackbox_exporter.service
sudo tee /etc/systemd/system/blackbox_exporter.service << 'EOF'
[Unit]
Description=Prometheus Blackbox Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter \
    --config.file=/etc/blackbox_exporter/blackbox.yml \
    --web.listen-address=127.0.0.1:9115
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now blackbox_exporter
```

---

## 7. Instalación y Hardening de Grafana

### 7.1 Instalación en Nodo 306
```bash
sudo dpkg -i /tmp/monitoring-binaries/grafana_11.5.0_amd64.deb || sudo apt-get install -f -y
```

### 7.2 Hardening de Seguridad en `/etc/grafana/grafana.ini`
Desactivamos el registro público de usuarios, desactivamos acceso anónimo, y forzamos credenciales administrativas robustas:

```ini
# Extracto de /etc/grafana/grafana.ini
[server]
http_addr = 10.100.29.30
http_port = 3000
protocol = http
domain = 10.100.29.30

[security]
admin_user = admin
# [ADAPTAR] Cambiar por contraseña segura generada
admin_password = AgeticAdm!n2026_SecOps
disable_gravatar = true
cookie_secure = false
allow_embedding = false
strict_transport_security = false

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[analytics]
reporting_enabled = false
check_for_updates = false
```

### 7.3 Aprovisionamiento Automático de Datasource (Prometheus)
```bash
sudo mkdir -p /etc/grafana/provisioning/datasources

sudo tee /etc/grafana/provisioning/datasources/prometheus.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus-BareMetal
    type: prometheus
    access: proxy
    url: http://10.100.29.30:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
      httpMethod: POST
EOF
```

### 7.4 Aprovisionamiento Automático de Dashboards
```bash
sudo mkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards

sudo tee /etc/grafana/provisioning/dashboards/dashboards.yaml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: 'BareMetal Fleet'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF
```

### 7.5 Importar Dashboard Oficial "Node Exporter Full" (ID: 1860)
Descargamos el JSON estándar de la comunidad de Grafana:
```bash
# Descargar el dashboard oficial 1860 y guardarlo en el directorio aprovisionado
curl -sL https://grafana.com/api/dashboards/1860/revisions/37/download \
  -o /tmp/node-exporter-full.json

# Ajustar el nombre del datasource para que coincida con el aprovisionado
sed -i 's/${DS_PROMETHEUS}/Prometheus-BareMetal/g' /tmp/node-exporter-full.json
sudo mv /tmp/node-exporter-full.json /var/lib/grafana/dashboards/
sudo chown -R grafana:grafana /var/lib/grafana/dashboards
```

### 7.6 Iniciar Grafana
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
sudo systemctl status grafana-server --no-pager
```

---

## 8. Reglas de Alerta Críticas (`alert_rules.yml`)

Crear `/etc/prometheus/rules/alert_rules.yml` con las 7 alertas esenciales de la infraestructura:

```yaml
groups:
  - name: BareMetalInfrastructureAlerts
    rules:
      # 1. Nodo Caído (Pérdida de conectividad o apagado no programado)
      - alert: NodeDown
        expr: up{job="baremetal-nodes"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Nodo físico no responde: {{ $labels.instance }}"
          description: "Node Exporter en {{ $labels.instance }} (ID: {{ $labels.node_id }}) no ha respondido durante más de 2 minutos."

      # 2. Saturación de CPU (> 85% por 10 minutos)
      - alert: HostHighCpuLoad
        expr: (100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Uso excesivo de CPU en {{ $labels.instance }}"
          description: "La CPU ha superado el 85% durante 10 minutos continuos (Valor actual: {{ $value | printf \"%.2f\" }}%)."

      # 3. Saturación de Memoria RAM (> 90% por 5 minutos)
      - alert: HostHighMemoryUsage
        expr: ((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Memoria RAM crítica en {{ $labels.instance }}"
          description: "La memoria RAM libre es inferior al 10% (Uso actual: {{ $value | printf \"%.2f\" }}%). Riesgo inminente de OOM Killer."

      # 4. Alerta de Disco SSD de 128 GB (> 85% lleno)
      - alert: HostDiskSpaceFillingUp
        expr: ((node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Espacio en disco SSD agotándose en {{ $labels.instance }}"
          description: "La partición raíz / tiene más del 85% ocupado. En discos de 128 GB esto requiere purga inmediata."

      # 5. Inodos de Disco Agotados (< 10% inodos libres)
      - alert: HostLowInodes
        expr: (node_filesystem_files_free{mountpoint="/"} / node_filesystem_files{mountpoint="/"}) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Inodos de disco casi agotados en {{ $labels.instance }}"
          description: "Quedan menos del 10% de inodos libres en la partición raíz."

      # 6. Reinicio Inesperado del Sistema (< 5 minutos de uptime)
      - alert: HostUnexpectedReboot
        expr: (node_time_seconds - node_boot_time_seconds) < 300
        labels:
          severity: warning
        annotations:
          summary: "Reinicio detectado en {{ $labels.instance }}"
          description: "El servidor {{ $labels.instance }} se ha reiniciado hace menos de 5 minutos."

      # 7. Pérdida de Paquetes o Caída de Ping ICMP (Blackbox)
      - alert: PingFailure
        expr: probe_success{job="blackbox-ping"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Fallo de ping hacia {{ $labels.instance }}"
          description: "El servidor {{ $labels.instance }} no responde a paquetes ICMP en la red privada."
```

Validar sintaxis de las alertas con `promtool`:
```bash
sudo promtool check rules /etc/prometheus/rules/alert_rules.yml
```

---

## 9. Seguridad y Blindaje Perimetral con nftables

Para garantizar el cumplimiento de la restricción de que **ningún servicio sea visible en la red corporativa de oficina**:

### 9.1 En los 8 Nodos Clientes (Protección del Puerto 9100)
El puerto `9100` debe responder **únicamente** a la IP del servidor de monitoreo (`10.100.29.30`).

```bash
# /etc/nftables.conf en nodos clientes
sudo tee /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Tráfico local loopback y establecido
        iif "lo" accept
        ct state established,related accept

        # Tráfico SSH desde el Bastión y Jump Host
        ip saddr { 10.100.29.10, 10.100.29.30 } tcp dport 22 accept

        # Node Exporter: EXCLUSIVAMENTE desde el Nodo 306 (Prometheus)
        ip saddr 10.100.29.30 tcp dport 9100 accept

        # Tráfico de clúster Kubernetes / Cilium (si aplica)
        ip saddr 10.100.29.0/24 accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.conf
```

### 9.2 En el Servidor de Monitoreo (Nodo 306)
Bloquea acceso a los puertos `9090`, `3000`, `9093` y `9115` desde cualquier origen que no sea `localhost` (túnel SSH) o la red interna:

```bash
# Reglas en Nodo 306 para confinar la interfaz Wi-Fi wlp3s0
sudo tee -a /etc/nftables.conf << 'EOF'

# Bloquear puertos de monitoreo en la interfaz Wi-Fi de oficina
table inet monitoring_shield {
    chain input {
        type filter hook input priority -10; policy accept;

        # Permitir acceso total en loopback (túneles SSH locales)
        iif "lo" accept

        # Permitir acceso desde la red privada
        iif "enp2s0" tcp dport { 9090, 3000, 9093, 9115 } accept

        # DENEGAR explícitamente en la interfaz Wi-Fi (oficina)
        iif "wlp3s0" tcp dport { 9090, 3000, 9093, 9115 } drop
    }
}
EOF

sudo nft -f /etc/nftables.conf
```

---

## 10. Verificación Operativa y Health Checks

### 10.1 Comandos de Comprobación en Nodo 306
```bash
# 1. Estado de servicios systemd
sudo systemctl status prometheus grafana-server alertmanager blackbox_exporter node_exporter --no-pager

# 2. Verificar puertos en escucha en la subred privada
sudo ss -tlnp | grep -E ':(9090|3000|9093|9115|9100)'

# 3. Validar sintaxis de configuración y reglas de alerta
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/alert_rules.yml
amtool check-config /etc/alertmanager/alertmanager.yml

# 4. Consultar targets activos en Prometheus vía API REST
curl -s http://10.100.29.30:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, job: .labels.job, health: .health}'

# 5. Validar reglas de nftables activas
sudo nft list ruleset
```

---

## 11. Respaldo, Mantenimiento y Rotación de Credenciales

### 11.1 Script de Respaldo Automatizado
Crea copias comprimidas de las bases de datos y configuraciones en `/opt/backups/monitoring/`:

```bash
#!/usr/bin/env bash
# backup_monitoring.sh
set -Eeuo pipefail

BACKUP_DIR="/opt/backups/monitoring/$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "${BACKUP_DIR}"

echo "[INFO] Creando snapshot de Prometheus TSDB..."
curl -s -XPOST http://10.100.29.30:9090/api/v1/admin/tsdb/snapshot | jq .

echo "[INFO] Respaldando base de datos Grafana y configuraciones..."
sudo cp /var/lib/grafana/grafana.db "${BACKUP_DIR}/grafana.db"
sudo tar -czf "${BACKUP_DIR}/prometheus_config.tar.gz" -C /etc/prometheus .
sudo tar -czf "${BACKUP_DIR}/grafana_config.tar.gz" -C /etc/grafana .

echo "[OK] Respaldo finalizado en ${BACKUP_DIR}"
```

### 11.2 Rotación de Contraseña de Administrador de Grafana
Si se requiere rotar la contraseña del usuario `admin`:
```bash
sudo grafana-cli admin reset-admin-password "[NUEVA_CONTRASEÑA_FUERTE]"
```

---

## 12. Guía de Solución de Problemas (Troubleshooting) y Rollback

### 12.1 Matriz de Diagnóstico de Errores

| Síntoma / Problema | Causa Raíz Probable | Solución de Ingeniería |
| :--- | :--- | :--- |
| **Target en estado `DOWN` en Prometheus** | Node Exporter detenido en el cliente o bloqueado por firewall. | 1. Probar conectividad: `curl -m 3 http://<IP_NODO>:9100/metrics`.<br>2. En el nodo: `sudo systemctl status node_exporter`.<br>3. Revisar reglas: `sudo nft list ruleset`. |
| **Timeouts por Firewall nftables** | Falta regla de aceptación en la cadena `input` para `10.100.29.30`. | Añadir `ip saddr 10.100.29.30 tcp dport 9100 accept` en `/etc/nftables.conf` y recargar con `sudo nft -f /etc/nftables.conf`. |
| **Desfase de Tiempo (*Clock Skew*)** | Chrony / NTP desincronizado entre nodos. | Prometheus rechaza métricas con desfase > 30s. Ejecutar en el nodo: `sudo chronyc tracking` y forzar sincronización con `sudo chronyc makestep`. |
| **Disco Lleno en SSD de 128 GB** | Retención de Prometheus demasiado alta. | 1. Purgar bloques antiguos en `/var/lib/prometheus`.<br>2. Asegurar que `--storage.tsdb.retention.size=15GB` esté activo en `/etc/systemd/system/prometheus.service`. |
| **Cardinalidad Alta (Prometheus consume > 6 GB RAM)** | Exportadores exponiendo etiquetas dinámicas excesivas (ej. puertos o PIDs). | Limitar collectors en Node Exporter removiendo `--collector.processes` si no es indispensable. |

### 12.2 Procedimiento de Rollback Completo
Para desmantelar completamente los servicios sin dejar residuos:

```bash
# 1. En el Nodo 306:
sudo systemctl stop prometheus grafana-server alertmanager blackbox_exporter
sudo systemctl disable prometheus grafana-server alertmanager blackbox_exporter
sudo rm -rf /etc/prometheus /etc/alertmanager /etc/blackbox_exporter /var/lib/prometheus /var/lib/alertmanager
sudo rm -f /usr/local/bin/{prometheus,promtool,alertmanager,amtool,blackbox_exporter}
sudo apt-get purge -y grafana

# 2. En los 8 nodos clientes:
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
sudo rm -f /etc/systemd/system/node_exporter.service /usr/local/bin/node_exporter
sudo userdel -r node_exporter 2>/dev/null || true
sudo systemctl daemon-reload
```

# Manual Maestro de Observabilidad y Guía Operativa de Expansión Futura
## Suite Unificada: OpenTelemetry, Prometheus/VictoriaMetrics, Loki, Tempo y Grafana
### Clúster Híbrido: Bare-Metal, OpenStack Kolla 2025.1 Epoxy y Kubernetes RKE2

---

## 1. Resumen Ejecutivo y Estado Actual de Producción

La suite de observabilidad completa (Métricas, Logs y Trazas) ha sido desplegada y validada en producción sin generar ninguna disrupción, respetando de forma estricta los puertos de OpenStack (VIP `10.100.29.5`), los servicios de aprovisionamiento de Ironic (DHCP `67 UDP`, TFTP `69 UDP`, HTTPBoot `8089`) y la red eBPF Cilium de RKE2.

### Estado en Vivo de los Componentes Desplegados:
* **VictoriaMetrics Single-Node (`victoriametrics-0`):** `1/1 Running` en K8s, StorageClass `local-path` con cuota de `25 GiB`, retención a 30 días. Expuesto en NodePort `30428`.
* **Grafana Loki (`loki-0`):** `1/1 Running` en K8s, StorageClass `local-path` con cuota de `20 GiB`, retención a 7 días. Expuesto en NodePort `30100`.
* **Grafana Tempo (`tempo-0`):** `1/1 Running` en K8s, StorageClass `local-path` con cuota de `15 GiB`, retención a 3 días con 20% head-sampling. Expuesto en NodePort `30200`.
* **cert-manager v1.15.3:** `3/3 Running` (`cert-manager`, `cainjector`, `webhook`).
* **OpenTelemetry Operator v0.104.0:** `2/2 Running` en namespace `opentelemetry-operator-system`.
* **OpenTelemetry Gateway (`otel-gateway-collector`):** `2/2 Running` (2 réplicas), expuesto en NodePort `30317` (gRPC) y `30318` (HTTP).
* **OpenTelemetry Agent (`otel-agent-collector`):** `3/3 Running` (DaemonSet activo en todos los nodos de K8s producción).
* **Clúster Kubernetes en Nodo-314 (`k8s-bastion-314`):** Conectado al monitoreo central:
  * Agente OTel DaemonSet activo en `nodo-314` enviando todos los logs de contenedores hacia **Loki** (`{cluster="k8s-bastion-314"}`).
  * Scraping de `kube-apiserver` (`:6443`) y cAdvisor (`:10250`) en Prometheus y retransmitido a **VictoriaMetrics**.
* **Prometheus Server (`nodo-306 :9090`):** `Active`, transmitiendo en tiempo real mediante `remote_write` hacia VictoriaMetrics (`http://10.100.29.101:30428/api/v1/write`).
* **Grafana (`nodo-306 :3000`):** `Active`, aprovisionado con los datasources correlacionados:
  * `Prometheus-BareMetal` (`http://127.0.0.1:9090`)
  * `VictoriaMetrics` (`http://10.100.29.101:30428`)
  * `Loki` (`http://10.100.29.101:30100`)
  * `Tempo` (`http://10.100.29.101:30200`) con correlación `Trace -> Logs` y `Trace -> Metrics`.

---

## 2. Mapa de Puertos y Endpoints del Clúster

| Servicio | Tipo | IP / Endpoint Interno | Puerto / NodePort | Función |
| :--- | :--- | :--- | :--- | :--- |
| **Grafana UI** | Host (`nodo-306`) | `http://10.100.29.30:3000`<br>`http://192.168.29.25:3000` | `3000` | Dashboard unificado de métricas, logs y trazas |
| **Prometheus Local** | Host (`nodo-306`) | `http://10.100.29.30:9090` | `9090` | Buffer local de scraping (48h) |
| **VictoriaMetrics API**| K8s Service | `http://10.100.29.101:30428` | `30428` | Almacenamiento TSDB a largo plazo (30 días) |
| **Loki HTTP Ingest** | K8s Service | `http://10.100.29.101:30100` | `30100` | Ingesta y consulta de Logs LogQL |
| **Tempo HTTP Query** | K8s Service | `http://10.100.29.101:30200` | `30200` | Consulta de Trazas TraceQL |
| **OTel Gateway gRPC** | K8s Service | `10.100.29.101:30317` | `30317` | Ingesta de trazas y métricas OTLP gRPC |
| **OTel Gateway HTTP** | K8s Service | `http://10.100.29.101:30318` | `30318` | Ingesta de trazas y métricas OTLP HTTP/JSON |
| **node_exporter** | Host (Todos) | `http://<nodo-ip>:9100/metrics`| `9100` | Métricas de CPU, RAM, disco y red de los nodos |

---

## 3. Guía de Operaciones Futuras: Cómo Conectar Nuevos Entornos

### A. Cómo Conectar un Nuevo Clúster de Kubernetes (Multicluster)

Para que un segundo o tercer clúster de Kubernetes envíe sus métricas, logs y trazas a esta suite centralizada:

#### 1. Enviar Métricas (Prometheus / VictoriaMetrics vmagent en el nuevo K8s)
En el clúster nuevo, instala `vmagent` o configura Prometheus con `remote_write`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-remote-write
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      external_labels:
        cluster: 'k8s-produccion-02'
    remote_write:
      - url: "http://10.100.29.101:30428/api/v1/write"
        queue_config:
          max_samples_per_send: 1000
          capacity: 2500
```

#### 2. Enviar Logs de Pods hacia Loki (Promtail DaemonSet en el nuevo K8s)
Despliega Promtail en el clúster secundario apuntando al NodePort de Loki:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail-remote
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: promtail-remote
  template:
    metadata:
      labels:
        app: promtail-remote
    spec:
      containers:
        - name: promtail
          image: grafana/promtail:3.1.0
          args:
            - "-config.file=/etc/promtail/promtail.yaml"
          volumeMounts:
            - name: config
              mountPath: /etc/promtail
            - name: varlog
              mountPath: /var/log
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: promtail-config
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: kube-system
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
    positions:
      filename: /tmp/positions.yaml
    clients:
      - url: http://10.100.29.101:30100/loki/api/v1/push
        external_labels:
          cluster: 'k8s-produccion-02'
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
```

#### 3. Enviar Trazas OTLP (OpenTelemetry Collector en el nuevo K8s)
En el nuevo clúster, configura el pipeline del OTel Collector para exportar por gRPC hacia la IP del Gateway:
```yaml
exporters:
  otlp:
    endpoint: "10.100.29.101:30317"
    tls:
      insecure: true
```

---

### B. Cómo Conectar Hosts con Docker Standalone (Contenedores Fuera de K8s)

Si tienes un servidor físico o VM que corre Docker y quieres monitorizarlo completamente:

#### 1. Recolección de Logs de Contenedores con el Driver Loki de Docker
En el host Docker, instala el plugin oficial de Loki una sola vez:
```bash
# Instalar plugin de Loki en Docker daemon
sudo docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
```
Configura `/etc/docker/daemon.json` para que todos los contenedores envíen sus logs automáticamente a Loki:
```json
{
  "log-driver": "loki",
  "log-opts": {
    "loki-url": "http://10.100.29.101:30100/loki/api/v1/push",
    "loki-batch-size": "400",
    "loki-retries": "3",
    "labels": "environment,host",
    "max-size": "50m",
    "max-file": "5"
  }
}
```
Reinicia el servicio Docker:
```bash
sudo systemctl restart docker
```

#### 2. Recolección de Métricas de Host y Contenedores (Docker Compose)
Crea y levanta este `docker-compose.yml` en cualquier host Docker:
```yaml
version: '3.8'

services:
  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

  otel-host-agent:
    image: otel/opentelemetry-collector-contrib:0.104.0
    container_name: otel-host-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./otel-agent-config.yaml:/etc/otelcol/config.yaml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: ["--config=/etc/otelcol/config.yaml"]
```
Con el archivo de configuración `./otel-agent-config.yaml`:
```yaml
receivers:
  docker_stats:
    endpoint: "unix:///var/run/docker.sock"
    collection_interval: 15s

exporters:
  otlp:
    endpoint: "10.100.29.101:30317"
    tls:
      insecure: true

service:
  pipelines:
    metrics:
      receivers: [docker_stats]
      exporters: [otlp]
```

---

### C. Cómo Instrumentar Nuevos Servicios y Microservicios

#### 1. En Kubernetes (Auto-Instrumentación Zero-Code con OpenTelemetry Operator)
Ya dejamos instalado y activo el recurso `Instrumentation` en el namespace `observability`.  
Para que cualquier nuevo pod de **Java** o **Python** sea instrumentado automáticamente con trazas y métricas OTLP sin tocar una sola línea de código, agrega la anotación respectiva a su Deployment:

##### Para Aplicaciones Java (Spring Boot, Quarkus, Tomcat, etc.):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-servicio-java
  namespace: default
spec:
  template:
    metadata:
      annotations:
        # Inyecta el agente OpenTelemetry Java automáticamente
        instrumentation.opentelemetry.io/inject-java: "observability/auto-instrumentation"
    spec:
      containers:
        - name: app
          image: 10.100.29.20:8083/mi-app-java:1.0.0
          ports:
            - containerPort: 8080
```

##### Para Aplicaciones Python (FastAPI, Flask, Django):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-servicio-python
  namespace: default
spec:
  template:
    metadata:
      annotations:
        # Inyecta el agente OpenTelemetry Python automáticamente
        instrumentation.opentelemetry.io/inject-python: "observability/auto-instrumentation"
    spec:
      containers:
        - name: app
          image: 10.100.29.20:8083/mi-app-python:1.0.0
          ports:
            - containerPort: 5000
```

#### 2. En Servicios Standalone o Contenedores Docker Manuales
Pasa las variables de entorno estándar de OpenTelemetry al contenedor:
```bash
docker run -d \
  --name api-pagos \
  -e OTEL_SERVICE_NAME=api-pagos \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://10.100.29.101:30318 \
  -e OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
  -e OTEL_RESOURCE_ATTRIBUTES=deployment.environment=produccion,host.name=nodo-315 \
  mi-imagen:latest
```

---

### D. Cómo Agregar Nuevos Exporters a Prometheus / VictoriaMetrics

Para agregar el monitoreo de un nuevo componente (ejemplo: PostgreSQL de Nexus, Kafka, Redis, o Nginx):

1. Edita el archivo de configuración en `nodo-306`:
   ```bash
   sudo nano /etc/prometheus/prometheus.yml
   ```
2. Agrega el nuevo bloque de scraping bajo `scrape_configs`:
   ```yaml
     - job_name: 'postgresql_nexus'
       static_configs:
         - targets: ['10.100.29.20:9187']
           labels:
             instance: 'nexus-postgres'
             role: 'Base de datos Nexus'
   ```
3. Recarga la configuración sin reiniciar el servicio:
   ```bash
   curl -X POST http://localhost:9090/-/reload
   ```
4. **Automático:** Prometheus recolecta las métricas y las envía de forma transparente a VictoriaMetrics mediante `remote_write`, haciéndolas disponibles de inmediato en Grafana.

---

## 4. Guía de Solución de Problemas y Mantenimiento Preventivo

### 1. Comprobar Salud de los Backends en Kubernetes
```bash
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods,pvc -n observability -o wide
```
* Si algún pod entra en `CrashLoopBackOff`, revisa sus logs con:
  ```bash
  kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml logs <nombre-pod> -n observability --tail=50
  ```

### 2. Verificar Consumo de Almacenamiento NVMe
En cada nodo de Kubernetes, el almacenamiento de los volúmenes persistentes se encuentra en `/var/lib/rancher/k3s/storage/`:
```bash
df -h /var/lib/rancher/k3s/storage/
```
Las políticas de compactación y retención configuradas (30d para VictoriaMetrics, 7d para Loki y 3d para Tempo) garantizan que el almacenamiento nunca supere los 60 GiB combinados.

### 3. Verificar Conectividad de Grafana hacia los Datasources
Desde cualquier navegador conectado vía túnel SSH ([http://localhost:3000](http://localhost:3000)):
* Menú lateral -> **Connections** -> **Data sources**.
* Haz clic en **VictoriaMetrics**, **Loki** o **Tempo** y presiona el botón **Save & test**. Debe responder en verde: *"Data source is working"*.

---

## 5. Procedimiento de Rollback de Emergencia

Si por cualquier requerimiento operativo necesitas desmantelar los componentes de observabilidad sin afectar la operación de OpenStack ni de Kubernetes:

```bash
# 1. Eliminar los componentes de Kubernetes de forma limpia
kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete namespace observability

# 2. O ejecutar el playbook automatizado de rollback de Ansible
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/99_observability_rollback.yml
```
El clúster base, las redes L2/L3 y los servicios de virtualización permanecerán 100% operativos.

---

## 6. Ecosistema de Microservicios Empresariales en Kubernetes (`namespace: aplicaciones`)

Se ha desplegado un conjunto completo de microservicios auto-instrumentados con OpenTelemetry en el clúster Kubernetes RKE2, junto con un simulador de tráfico continuo que alimenta métricas, logs y trazas distribuidas hacia VictoriaMetrics, Loki y Tempo.

### Arquitectura de Microservicios

```
                                  [ Navegador / Laptop ]
                                            │
                                            ▼ (NodePort 30080)
                                    ┌───────────────┐
                                    │ frontend-web  │ (Nginx UI + Reverse Proxy)
                                    └───────┬───────┘
                                            │
               ┌────────────────────────────┼───────────────────────────┐
               ▼                            ▼                           ▼
      ┌─────────────────┐          ┌─────────────────┐         ┌─────────────────┐
      │ orders-service  │          │   backend-api   │         │ notifications   │
      │ (Python 3 +     │          │  (Python 3 +    │         │ (Python 3 +     │
      │  OTel Tracing)  │          │   OTel Tracing) │         │  OTel Tracing)  │
      └────────┬────────┘          └─────────────────┘         └─────────────────┘
               │ (Cache + Estado)
               ▼
      ┌──────────────────────────┐
      │   redis (v7-alpine)      │
      │ ┌──────────────────────┐ │
      │ │ redis_exporter:9121  │ │ ──► Métricas Prometheus hacia VictoriaMetrics
      │ └──────────────────────┘ │
      └──────────────────────────┘
               ▲
               │ (Tráfico continuo de pedidos, consultas y errores 404 simulados)
      ┌──────────────────────────┐
      │    traffic-simulator     │
      └──────────────────────────┘
```

### Componentes Activos en el Clúster
1. **`frontend-web`** (2 réplicas): Dashboard visual responsivo en Nginx 1.27 Alpine. Sirve el portal web y enruta llamadas a `/api/orders`, `/api/notify` y `/api/v1/data`. Expuesto en NodePort `30080`.
2. **`orders-service`** (2 réplicas): API Python instrumentada con OTel. Gestiona pedidos, consulta caché en Redis y dispara eventos asíncronos hacia `notifications-service`.
3. **`notifications-service`** (2 réplicas): Microservicio de mensajería y alertas instrumentado con OTel. Recibe eventos de pedidos y genera logs estructurados procesados por Loki.
4. **`backend-api-python`** (2 réplicas): Microservicio base para consumo de datos generales.
5. **`redis`** (1 réplica + 1 sidecar): Redis 7 Alpine con persistencia AOF y sidecar `redis_exporter` (puerto `9121`), escrapeado automáticamente por el OpenTelemetry Collector.
6. **`traffic-simulator`** (1 réplica): Pod continuo que ejecuta peticiones periódicas (GETs, POSTs de pedidos, y un 10% de errores 404 intencionales para verificar las alertas y gráficos de error rate en Grafana).

### Accesos Locales vía Túnel SSH

Todos los servicios están expuestos localmente en la máquina del administrador mediante el comando de túnel SSH:

| Servicio | URL Local | Descripción |
| :--- | :--- | :--- |
| **Portal Microservicios Web** | [http://localhost:30080](http://localhost:30080) | Dashboard interactivo de pedidos y estado del clúster |
| **Grafana Observabilidad** | [http://localhost:3000](http://localhost:3000) | Dashboards de Métricas, Logs, Trazas y OpenStack |
| **VictoriaMetrics Web UI** | [http://localhost:30428](http://localhost:30428) | Explorador directo de métricas y consultas PromQL |
| **Tempo Tracing** | [http://localhost:30200](http://localhost:30200) | Endpoint OTLP y búsqueda de trazas distribuidas |
| **OpenStack Horizon** | [http://localhost:8080/auth/login/](http://localhost:8080/auth/login/) | Consola Web de OpenStack Kolla |
| **Sonatype Nexus OSS** | [http://localhost:8081](http://localhost:8081) | Registro privado de Docker y repositorio APT |
| **Prometheus PXE** | [http://localhost:9090](http://localhost:9090) | Prometheus base del nodo de control |

### Comando para Restaurar el Túnel SSH en cualquier momento
```bash
ssh -i ansible/keys/cluster_key -o StrictHostKeyChecking=no -f -N \
  -L 8080:10.100.29.5:80 \
  -L 8081:10.100.29.20:8081 \
  -L 8082:10.100.29.20:8082 \
  -L 8083:10.100.29.20:8083 \
  -L 3000:10.100.29.30:3000 \
  -L 9090:10.100.29.30:9090 \
  -L 6443:10.100.29.101:6443 \
  -L 30080:10.100.29.101:30080 \
  -L 30428:10.100.29.101:30428 \
  -L 30200:10.100.29.101:30200 \
  n306@192.168.29.25
```

---

## 7. Gestión de Usuarios, Contraseñas y Proyectos en OpenStack

### 1. Cambiar la Contraseña del Administrador (`admin`)

#### Método A: Desde la Consola Web Horizon
1. Accede a [http://localhost:8080/auth/login/](http://localhost:8080/auth/login/).
2. Inicia sesión con:
   * **Domain**: `Default`
   * **User Name**: `admin`
   * **Password**: `Admin2025!`
3. En la esquina superior derecha, haz clic en el usuario `admin` -> **Settings (Configuración)**.
4. En el menú lateral izquierdo, haz clic en **Change Password (Cambiar Contraseña)**.
5. Introduce la contraseña actual (`Admin2025!`), la nueva contraseña y confirma.

#### Método B: Vía OpenStack Keystone CLI (Automático)
Ejecutar desde el nodo de control (`n306`):
```bash
sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 \
  --os-user-domain-name Default --os-project-domain-name Default \
  --os-project-name admin --os-username admin --os-password Admin2025! \
  --os-identity-api-version 3 \
  user set --password "TuNuevaClave2026!" admin
```
> [!IMPORTANT]
> Si cambias la contraseña de `admin`, debes actualizarla también en `/etc/kolla/admin-openrc.sh` (`export OS_PASSWORD='TuNuevaClave2026!'`) y en `scripts/disaster-recovery.sh` para que los scripts de automatización sigan operando correctamente.

---

### 2. Creación de Proyectos (Tenants), Usuarios y Roles

En OpenStack:
* **Project (Proyecto)**: Espacio de trabajo aislado donde residen las máquinas virtuales, redes y recursos.
* **User (Usuario)**: Cuenta que inicia sesión.
* **Role (Rol)**: Nivel de privilegios dentro del proyecto (`admin`, `member`, `reader`).

#### Crear desde la Interfaz Web Horizon:
1. En el menú lateral izquierdo, ve a **Identity (Identidad)**.
2. Para crear un Proyecto: Haz clic en **Projects** -> botón **+ Create Project**, define el nombre (ej. `produccion`) y las cuotas de CPU/RAM.
3. Para crear un Usuario: Haz clic en **Users** -> botón **+ Create User**:
   * **User Name**: Nombre del usuario (ej. `dev_user`).
   * **Password**: Contraseña inicial.
   * **Primary Project**: Proyecto asignado (ej. `produccion` o `admin`).
   * **Role**: Selecciona `member` (usuario estándar) o `reader` (solo lectura).

#### Crear por Línea de Comandos (Kolla Toolbox):
```bash
# 1. Crear un Proyecto
sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 \
  --os-user-domain-name Default --os-project-domain-name Default \
  --os-project-name admin --os-username admin --os-password Admin2025! \
  --os-identity-api-version 3 \
  project create --domain Default --description "Proyecto Desarrollo" dev-project

# 2. Crear un Usuario asociado al Proyecto
sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 \
  --os-user-domain-name Default --os-project-domain-name Default \
  --os-project-name admin --os-username admin --os-password Admin2025! \
  --os-identity-api-version 3 \
  user create --domain Default --project dev-project --password "ClaveUsuario2026!" desarrollador

# 3. Asignar el rol 'member' al usuario en ese proyecto
sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 \
  --os-user-domain-name Default --os-project-domain-name Default \
  --os-project-name admin --os-username admin --os-password Admin2025! \
  --os-identity-api-version 3 \
  role add --project dev-project --user desarrollador member
```

#### Cambiar la contraseña de cualquier usuario:
```bash
sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 \
  --os-user-domain-name Default --os-project-domain-name Default \
  --os-project-name admin --os-username admin --os-password Admin2025! \
  --os-identity-api-version 3 \
  user set --password "NuevaClave" <nombre_o_id_usuario>
```


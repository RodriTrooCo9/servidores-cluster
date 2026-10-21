# Matriz de Puertos y Servicios de Infraestructura

Matriz completa de puertos TCP y UDP utilizados en la red privada `10.100.29.0/24`.

| Puerto | Protocolo | Servicio | Hostname / IP | Propósito |
| :---: | :---: | :--- | :--- | :--- |
| **22** | TCP | SSH Interno | Todos los nodos | Acceso administrativo interno y automatización Ansible |
| **2222** | TCP | OpenSSH Perimetral | `bastion` (`10.100.29.10`) | Entrada única desde red de oficina vía ProxyJump |
| **3128** | TCP | Squid Proxy Egress | `bastion` (`10.100.29.10`) | Salida web HTTP/HTTPS controlada para la subred privada |
| **123** | UDP | Chrony NTP | `bastion` (`10.100.29.10`) | Servidor de hora maestro para la flota |
| **5432** | TCP | PostgreSQL 16 | `nexus-repo` (`10.100.29.20`) | Backend de datos relacional para Sonatype Nexus 3 |
| **8081** | TCP | Nexus Core Web & APT | `nexus-repo` (`10.100.29.20`) | Interfaz web de Nexus y proxy de repositorios Debian 13 |
| **8082** | TCP | Nexus Docker Group | `nexus-repo` (`10.100.29.20`) | Puerto unificado de descarga de imágenes containerd / RKE2 |
| **8083** | TCP | Nexus Docker Hosted | `nexus-repo` (`10.100.29.20`) | Registro privado local para imágenes Kolla / OpenStack |
| **53** | UDP/TCP | dnsmasq DNS | `pxe-controller` (`10.100.29.30`)| Resolución DNS local para el clúster |
| **67** | UDP | dnsmasq DHCP Server | `pxe-controller` (`10.100.29.30`)| Asignación estática de IPs por MAC para arranque |
| **69** | UDP | TFTP Server | `pxe-controller` (`10.100.29.30`)| Entrega inicial de binarios `undionly.kpxe` e `ipxe.efi` |
| **8089** | TCP | Nginx HTTPBoot | `pxe-controller` (`10.100.29.30`)| Streaming HTTP de script `boot.ipxe`, kernels e ISOs |
| **6385** | TCP | OpenStack Ironic API | `pxe-controller` (`10.100.29.30`)| API REST de aprovisionamiento bare-metal |
| **5000** | TCP | OpenStack Keystone | `pxe-controller` (`10.100.29.30`)| Servicio de identidad y tokens de OpenStack |
| **9090** | TCP | Prometheus TSDB | `pxe-controller` (`10.100.29.30`)| Base de datos de métricas de series temporales |
| **9093** | TCP | Alertmanager | `pxe-controller` (`10.100.29.30`)| Enrutamiento y deduplicación de alertas operativas |
| **9115** | TCP | Blackbox Exporter | `pxe-controller` (`10.100.29.30`)| Sondeos ICMP y endpoints HTTP |
| **3000** | TCP | Grafana OSS | `pxe-controller` (`10.100.29.30`)| Paneles y cuadros de mando de telemetría |
| **9100** | TCP | Node Exporter | Todos los 8 nodos | Métricas de sistema operativo (CPU, RAM, Disco, Red) |
| **6443** | TCP | Kubernetes API Server| `k8s-cp-01..03` | Punto de acceso a la API de Kubernetes |
| **9345** | TCP | RKE2 Supervisor API | `k8s-cp-01..03` | Coordinación de unión de nodos y control plane HA |
| **2379..2380**| TCP | etcd Client / Peer | `k8s-cp-01..03` | Base de datos de estado distribuido de Kubernetes |
| **8428** | TCP | VictoriaMetrics | Clúster K8s (Servicio) | Almacenamiento a largo plazo de métricas |
| **3100** | TCP | Grafana Loki | Clúster K8s (Servicio) | Agregación centralizada de logs |
| **4317..4318**| TCP | OpenTelemetry OTLP | Clúster K8s (Servicio) | Recepción gRPC/HTTP de trazas y telemetría |

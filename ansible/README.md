# 🚀 Orquestación y Automatización con Ansible

Entorno de automatización profesional, declarativo e idempotente para los **8 nodos físicos bare-metal** del clúster Dell OptiPlex 3020M con Debian 13.

## 📁 Estructura del Entorno

```text
ansible/
├── site.yml                           # Orquestador maestro integral estructurado por fases y tags
├── collections/
│   └── requirements.yml               # Dependencias de colecciones (community.general, posix, etc.)
├── keys/                              # Directorio protegido de llaves SSH (chmod 700)
│   ├── cluster_key                    # [IGNORADO POR GIT] Llave privada ed25519 (chmod 600)
│   └── README.md
├── playbooks/                         # Playbooks organizados por fases de ejecución
│   ├── 00-preflight/                  # Ping, auditoría de puertos y resumen de hardware
│   ├── 10-base/                       # Homologación SO Debian 13 y hardening del Bastión
│   ├── 20-services/                   # Nexus 3 OSS, PXE Controller y OpenStack Ironic
│   ├── 30-platform/                   # Clúster Kubernetes HA RKE2 + Cilium eBPF
│   ├── 40-observability/              # Prometheus, Grafana, Node Exporter y rollback
│   ├── 50-validation/                 # Healthcheck integral de puertos y servicios
│   └── 90-operations/                 # Disaster Recovery y respaldos automatizados
└── roles/                             # Roles reutilizables y modulares
    ├── common/                        # Hostname, /etc/hosts, networkd, Chrony, fuentes APT
    ├── bastion/                       # OpenSSH :2222, Squid :3128, nftables con NAT
    ├── nexus/                         # PostgreSQL 16 + Sonatype Nexus 3 OSS
    ├── pxe_controller/                # DHCP dnsmasq con reservas por MAC, TFTP, Nginx :8089
    ├── ironic/                        # OpenStack Ironic Standalone en Podman
    ├── rke2_ha/                       # Kubernetes RKE2 HA (Control Planes y Workers)
    └── monitoring/                    # Node Exporter, Prometheus TSDB y Grafana
```

## ⚡ Comandos Rápidos de Uso

Se recomienda invocar los playbooks desde la raíz del proyecto usando el `Makefile` o directamente con `ansible-playbook`:

```bash
# 1. Probar conectividad con toda la flota (8 nodos en paralelo)
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/00_ping.yml

# 2. Ejecutar resumen de hardware y telemetría
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/02_system_summary.yml

# 3. Despliegue completo por fases
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml

# 4. Comprobación de salud post-despliegue
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/50-validation/01_healthcheck.yml
```

# 🚀 Orquestación y Automatización con Ansible Core

Entorno de automatización profesional, declarativo e idempotente para los **8 nodos físicos bare-metal** del clúster Dell OptiPlex 3020M con Debian 13.

Este entorno reemplaza y optimiza la suite de scripts Bash imperativos anteriores, unificando la configuración de la flota bajo un único motor de ejecución paralela con soporte nativo para OpenStack Ironic Standalone, Sonatype Nexus 3, Kubernetes RKE2 HA (Cilium eBPF) y Prometheus/Grafana.

---

## 📁 Estructura del Entorno

```text
ansible/
├── ansible.cfg                    # Configuración optimizada (forks=8, pipelining, ControlPersist)
├── .vault_pass                    # [IGNORADO POR GIT] Clave maestra de cifrado de secretos
├── keys/                          # [IGNORADO POR GIT] Directorio seguro de llaves SSH (chmod 700)
│   ├── cluster_key                # Llave privada ed25519 con permisos estrictos (chmod 600)
│   └── README.md
├── inventory/
│   ├── hosts.yml                  # Inventario estructurado en YAML de los 8 nodos físicos
│   └── group_vars/
│       └── all/
│           ├── vars.yml           # Variables maestras del clúster (IPs, subredes, puertos, tokens)
│           └── vault.yml.example  # Plantilla de secretos para cifrar con Ansible Vault
├── roles/
│   ├── common/                    # Hostname, /etc/hosts, networkd, Swap, sysctl, Chrony, APT Nexus (ex 01, 04)
│   ├── bastion/                   # OpenSSH hardening :22, Squid :3128, nftables con NAT (ex 02)
│   ├── nexus/                     # PostgreSQL 16 + Sonatype Nexus 3 OSS con tuning 4GB RAM (ex 03)
│   ├── pxe_controller/            # DHCP dnsmasq con reservas MAC dinámicas, TFTP, Nginx :8089 (ex 05)
│   ├── ironic/                    # OpenStack Ironic Standalone en Podman, ramdisk IPA y baremetal.yaml (ex 06)
│   ├── rke2_ha/                   # Kubernetes RKE2 HA (Control Planes 1-3 y Workers 1-2) con Cilium (ex 08)
│   └── monitoring/                # Prometheus TSDB, Grafana y Node Exporter en toda la flota (ex 10)
├── playbooks/
│   ├── 00_ping.yml                # Comprobación de conectividad paralela en toda la flota
│   ├── 01_system_summary.yml      # Telemetría de hardware (RAM, Disco, CPU, Kernel)
│   ├── 02_base_config.yml         # Homologación del SO (invoca rol common)
│   ├── 03_bastion.yml             # Despliegue perimetral en Nodo 314 (invoca rol bastion)
│   ├── 04_nexus.yml               # Despliegue de Nexus y PostgreSQL en Nodo 315 (invoca rol nexus)
│   ├── 05_pxe_controller.yml      # Servicios PXE, dnsmasq e iPXE en Nodo 306 (invoca rol pxe_controller)
│   ├── 06_ironic_deploy.yml       # OpenStack Ironic Standalone en Nodo 306 (invoca rol ironic)
│   ├── 07_kubernetes_ha.yml       # Clúster Kubernetes HA RKE2 + Cilium (invoca rol rke2_ha)
│   ├── 08_monitoring.yml          # Suite de Monitoreo Centralizado (invoca rol monitoring)
│   └── 09_healthcheck.yml         # Auditoría integral de puertos y servicios (Nexus, PXE, K8s, Exporters)
├── site.yml                       # Orquestador maestro integral por tags (reemplaza ejecutar-desde-laptop.sh)
└── setup_keys.sh                  # Script de blindaje y sincronización inicial de llaves
```

---

## ⚡ Comandos Rápidos de Uso

Todos los comandos se pueden ejecutar desde el directorio `ansible/`:

```bash
cd /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible
```

### 1. Probar conectividad con toda la flota (8 nodos en paralelo):
```bash
ansible-playbook playbooks/00_ping.yml
# O comando ad-hoc:
ansible baremetal -m ping
```

### 2. Obtener resumen de hardware y recursos de todos los nodos:
```bash
ansible-playbook playbooks/01_system_summary.yml
```

### 3. Ejecutar fases individuales mediante Playbooks o Tags:
```bash
# Fase 1: Configuración Base OS (todos los nodos):
ansible-playbook site.yml --tags base

# Fase 2: Bastion Host y Seguridad Perimetral:
ansible-playbook site.yml --tags bastion

# Fase 3: Sonatype Nexus 3 + PostgreSQL:
ansible-playbook site.yml --tags nexus

# Fase 5: Servidor PXE, dnsmasq e iPXE:
ansible-playbook site.yml --tags pxe

# Fase 6: OpenStack Ironic Standalone:
ansible-playbook site.yml --tags ironic

# Fase 7: Clúster Kubernetes HA (RKE2 + Cilium):
ansible-playbook site.yml --tags k8s

# Fase 8: Monitoreo (Prometheus, Grafana, Node Exporter):
ansible-playbook site.yml --tags monitoring

# Fase 9: Auditoría Integral de Salud:
ansible-playbook site.yml --tags healthcheck
```

### 4. Orquestación Completa con Validación Previa (Dry-Run):
```bash
# Simular ejecución completa sin aplicar cambios:
ansible-playbook site.yml --check --diff

# Ejecutar despliegue completo de la infraestructura:
ansible-playbook site.yml
```

---

## 🌐 Compatibilidad con `ejecutar-desde-laptop.sh`

El script maestro del proyecto [`ejecutar-desde-laptop.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ejecutar-desde-laptop.sh) ha sido completamente actualizado para actuar como interfaz CLI de alto nivel hacia Ansible Core:
```bash
# Chequeo rápido de conectividad:
./ejecutar-desde-laptop.sh --check

# Ejecución por fases:
./ejecutar-desde-laptop.sh --fase 1
./ejecutar-desde-laptop.sh --fase 8

# Despliegue de toda la flota:
./ejecutar-desde-laptop.sh --all
```

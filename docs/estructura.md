# Manual de Operación: Suite de Automatización Bash para Infraestructura Bare-Metal Edge

> **Automatización oficial para Debian 13 (Trixie) sobre 8 servidores físicos**  
> **Alineado 1:1 con la Guía Maestra [README.md principal](../README.md)**  
> **Modo de Operación**: Ejecución desatendida, idempotente, segura y con trazabilidad completa.

---

## 1. Estructura del Proyecto

```text
infra-scripts/
├── README.md                          # Guía Maestra de Arquitectura y Despliegue
├── ejecutar-desde-laptop.sh           # Orquestador DevOps Remoto desde Laptop (SSH Jump Host)
├── .gitignore                         # Exclusión de claves, certificados, respaldos e ISOs
│
├── config/                            # Parámetros, variables y catálogo de red
│   ├── env                            # Variables maestras activas del clúster (chmod 600)
│   ├── env.example                    # Plantilla de variables de entorno y puertos
│   ├── nodes.csv                      # Inventario físico de los 8 nodos con MACs normalizadas
│   └── dnsmasq.conf                   # Plantilla de referencia para reservas DHCP y PXE
│
├── docs/                              # DOCUMENTACIÓN TÉCNICA Y OPERATIVA (.md)
│   ├── env.md                         # Cheat-sheet de IPs, claves, BIOS y alias SSH
│   ├── estructura.md                  # Este manual de operación y trazabilidad
│   ├── manual_maestro_infraestructura_pxe_openstack.md # Manual técnico exhaustivo
│   ├── arranque_e_instalacion_por_red_pxe.md # Guía e investigación técnica de arranque por red PXE
│   ├── monitoreo_prometheus_grafana.md # Manual Maestro de Monitoreo (Prometheus, Grafana, Alertmanager)
│   ├── redes/                         # Arquitectura y seguridad de redes
│   │   ├── aislamiento_red_oficina.md # Topología As-Built y blindaje de la red corporativa
│   │   ├── redes.md                   # Plan maestro de direccionamiento L2/L3
│   │   └── conflictos_vlan_manual.md  # Matriz de riesgos y mitigación de VLANs
│   ├── runbooks/                      # Procedimientos operativos estándar (SOP)
│   │   ├── blindaje-red-oficina.md    # Protocolo de contención Rogue DHCP y reglas NAT
│   │   └── recuperacion-desastres.md  # Procedimientos ante caídas de nodos y etcd
│   └── openstack/                     # Decisiones de diseño y arquitectura bare-metal
│       ├── glance_ironic_bifrost_arquitectura_comparativa.md
│       ├── OpenStack Glance, Formatos de Disco e Ironic Bare-Metal.md
│       └── Diferencias entre un entorno de desarrollo y uno de producción.md
│
├── lib/                               # Biblioteca compartida
│   └── common.sh                      # Logging, comprobaciones, traps y carga de configuración
│
├── scripts/                           # SCRIPTS EJECUTABLES DE APROVISIONAMIENTO (.sh)
│   ├── 00-preflight.sh                # Fase 0: Validación de requisitos y variables
│   ├── 01-base-servidores.sh          # Fase 1: Hostname, red estática, Chrony y sudoers
│   ├── 02-bastion.sh                  # Fase 2: Bastion Host, SSH :2222, Squid y nftables
│   ├── 03-nexus.sh                    # Fase 3: Sonatype Nexus 3 OSS + PostgreSQL 17
│   ├── 04-clientes-nexus.sh           # Fase 4: Redirección APT hacia el proxy de Nexus
│   ├── 05-pxe-dhcp-tftp.sh            # Fase 5: Servidor PXE, dnsmasq amarrado y Nginx :8089
│   ├── 06-openstack-glance-bifrost.sh # Fase 6: Ironic Standalone en Podman y ramdisk IPA
│   ├── 07-cloud-init.sh               # Fase 7: Plantillas Cloud-Init, ConfigDrive y NoCloud
│   ├── 08-kubernetes.sh               # Fase 8: Clúster RKE2 HA + Cilium eBPF
│   ├── 09-verificacion.sh             # Fase 9: Validación integral de conectividad y K8s
│   ├── 10-monitoreo.sh                # Fase 10: Suite de Monitoreo (Node Exporter, Prometheus, Grafana)
│   ├── deploy-masivo.sh               # Despliegue masivo bare-metal "un solo botón"
│   └── healthcheck.sh                 # Auditoría de estado y tabla visual de métricas
│
└── rollback/                          # Scripts de reversión por fase
    ├── rollback-01-base-servidores.sh
    ├── rollback-02-bastion.sh
    ├── rollback-03-nexus.sh
    ├── rollback-04-clientes-nexus.sh
    ├── rollback-05-pxe-dhcp-tftp.sh
    ├── rollback-06-openstack-glance-bifrost.sh
    ├── rollback-07-cloud-init.sh
    ├── rollback-08-kubernetes.sh
    └── rollback-10-monitoreo.sh
```

---

## 2. Matriz de Nodos y Orden Cronológico de Ejecución

Los scripts deben ejecutarse estrictamente en el siguiente orden lógico:

| Paso | Script | Fase del README | Nodo Destino | IP | Propósito Clave |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **0** | `00-preflight.sh` | Pre-requisitos | Cualquier nodo | N/A | Valida Debian 13, kernel 6.12+, RAM (8/16 GB) y disco 128 GB. |
| **1** | `01-base-servidores.sh` | Fase 1 | **Todos (1 al 8)** | `10.100.29.x` | Fija hostnames, red estática, Chrony NTP y usuario administrativo. |
| **2** | `02-bastion.sh` | Fase 2 | **Bastion (ID 314)** | `10.100.29.10` | Asegura OpenSSH, proxy Squid :3128 y firewall `nftables`. |
| **3** | `03-nexus.sh` | Fase 3 | **Nexus (ID 315)** | `10.100.29.20` | Despliega PostgreSQL 17 y Nexus 3 OSS con tuning de 4 GB JVM. |
| **4** | `04-clientes-nexus.sh`| Fase 4 | **Clientes (3 al 8)** | `10.100.29.x` | Redirige `sources.list` y containerd al proxy local de Nexus. |
| **5** | `05-pxe-dhcp-tftp.sh` | Fase 5 | **PXE (ID 306)** | `10.100.29.30` | Arranca `dnsmasq` con reservas fijas por MAC y Nginx en :80/:8089. |
| **6** | `06-openstack-glance-bifrost.sh` | Fase 6 | **PXE (ID 306)** | `10.100.29.30` | Inicia Ironic en Podman, descarga IPA y enrola los 8 nodos en catálogo. |
| **7** | `07-cloud-init.sh` | Fase 7 | **PXE (ID 306)** | `10.100.29.30` | Prepara plantillas Packer, ConfigDrive `config-2` y NoCloud HTTP. |
| **8** | `deploy-masivo.sh` | Fase 8 | **PXE (ID 306)** | `10.100.29.30` | **"Un solo botón"**: Dispara WoL/IPMI y despliega la imagen en paralelo. |
| **9** | `08-kubernetes.sh` | Fase 9 | **K8s (269,280,320,321,279)** | `10.100.29.10x` | Inicia RKE2 Server (CPs) y RKE2 Agent (Workers) con Cilium eBPF. |
| **10**| `09-verificacion.sh` | Fase 11 | **Bastion (ID 314)** | `10.100.29.10` | Ejecuta prueba de tráfico pod-a-pod y valida los nodos Ready. |
| **--**| `ejecutar-desde-laptop.sh` | Orquestación | **Desde Laptop (Wi-Fi)**| `192.168.29.16` | Orquestador centralizado con ProxyJump vía Nodo 306 (`192.168.29.25`). |
| **--**| `healthcheck.sh` | Operaciones | **Cualquier nodo / Laptop** | N/A | Inspección continua con tabla visual en tiempo real. |

---

## 3. Preparación Inicial y Distribución de Scripts

### 3.1 Configuración de Variables Privadas
Antes de la primera ejecución, copie la plantilla de entorno y ajuste las credenciales:

```bash
cp config/env.example config/env
chmod 600 config/env
nano config/env
```

### 3.2 Despliegue y Orquestación Directa desde la Laptop (Sin cables de red)
Con la arquitectura de aislamiento implementada, la laptop permanece **100% conectada por Wi-Fi** y administra el clúster a través del Nodo 306 (`ProxyJump n306-wifi`):

```bash
# 1. Auditar conectividad y SSH de la flota completa
./ejecutar-desde-laptop.sh --check

# 2. Sincronizar scripts automáticamente a todos los nodos en línea
./ejecutar-desde-laptop.sh --sync

# 3. Ejecutar cualquier fase de forma desatendida (-y)
./ejecutar-desde-laptop.sh --fase 7
```

---

## 4. Banderas Globales y Modo Seguro

Todos los scripts soportan las siguientes banderas universales:

* **`--dry-run`**: Analiza el entorno y muestra exactamente qué comandos se ejecutarían sin modificar ningún archivo, instalar paquetes ni reiniciar servicios.
  ```bash
  sudo ./02-bastion.sh --dry-run
  ```
* **`--force`**: Omite la comprobación estricta de host/rol (útil para pruebas en entornos de laboratorio o VMs).
* **`-y`, `--yes`**: Omite las solicitudes interactivas de confirmación `[s/N]`, ideal para ejecución en pipelines desatendidos.
* **`-h`, `--help`**: Imprime la ayuda en pantalla con los parámetros disponibles.

---

## 5. Operación del "Botón Único": `deploy-masivo.sh`

El script maestro `/opt/infra-scripts/deploy-masivo.sh` orquesta el aprovisionamiento de los servidores físicos en paralelo sin requerir intervención manual:

```bash
# Desplegar los 5 nodos de Kubernetes simultáneamente por red
sudo ./deploy-masivo.sh

# Desplegar toda la flota física registrada en nodes.csv
sudo ./deploy-masivo.sh --all

# Desplegar únicamente nodos específicos por su ID de inventario
sudo ./deploy-masivo.sh --nodes 321,279

# Reinstalar limpiamente un nodo averiado (undeploy + deploy)
sudo ./deploy-masivo.sh --nodes 279 --rebuild

# Forzar método de encendido por IPMI o Redfish
sudo ./deploy-masivo.sh --nodes k8s-cp-01 --power-method ipmi
```

---

## 6. Procedimiento de Reversión (Rollback)

Si una fase presenta un error o se requiere reiniciar la configuración de un nodo:

1. Cada fase genera respaldos automáticos con marca de tiempo: `<archivo>.bak.YYYYMMDD_HHMMSS`.
2. Diríjase a la carpeta `rollback/` y ejecute el script correspondiente a la fase que desea deshacer:
   ```bash
   cd rollback/
   sudo ./rollback-02-bastion.sh
   ```
3. **Límites de Reversión**:
   * Los volcados de bloques a bajo nivel en discos NVMe (`wipefs` o particionado de Ironic) destruyen la tabla de particiones previa y no pueden ser deshechos sin una copia de seguridad externa.

---

## 7. Tabla de Trazabilidad: Guía Maestra (README.md) vs Scripts

Esta tabla garantiza la coherencia técnica entre el documento de arquitectura y el código ejecutable:

| Sección / Fase de la Guía Maestra | Script Automatizado | Archivos del Sistema Creados o Gestionados |
| :--- | :--- | :--- |
| **Sección 4**: Requisitos y Compatibilidad | `00-preflight.sh` | N/A (Auditoría de solo lectura en `/etc/os-release`, RAM, disco) |
| **Fase 1**: Preparación Base Debian 13 | `01-base-servidores.sh` | `/etc/hosts`, `/etc/systemd/network/10-lan-static.network`, `/etc/chrony/chrony.conf`, `/etc/sudoers.d/99-debian` |
| **Fase 2**: Bastion Host y Perímetro | `02-bastion.sh` | `/etc/ssh/sshd_config.d/99-hardening.conf`, `/etc/squid/squid.conf`, `/etc/nftables.conf` |
| **Fase 3**: Sonatype Nexus y PostgreSQL 16 | `03-nexus.sh` | `/opt/sonatype/nexus/bin/nexus.vmoptions`, `/opt/sonatype/sonatype-work/nexus3/etc/nexus.properties`, `/etc/systemd/system/nexus.service`, `/etc/cron.hourly/nexus-disk-guard` |
| **Fase 4**: Clientes de Nexus | `04-clientes-nexus.sh` | `/etc/apt/sources.list`, `/etc/rancher/rke2/registries.yaml`, `/etc/environment` |
| **Fase 5**: PXE, TFTP y DHCP dnsmasq | `05-pxe-dhcp-tftp.sh` | `/etc/dnsmasq.conf`, `/tftpboot/boot.ipxe`, `/etc/nginx/sites-available/httpboot` |
| **Fase 6**: OpenStack Glance e Ironic | `06-openstack-glance-bifrost.sh` | `/opt/ironic/baremetal.yml`, Contenedor Podman `ironic-conductor`, `/httpboot/ipa/` |
| **Fase 7**: Cloud-Init y Packer | `07-cloud-init.sh` | `/opt/infra/packer/packer.pkr.hcl`, `/opt/infra/scripts/generate_configdrive.sh`, `/opt/infra/configdrive/*` |
| **Fase 8**: Despliegue Masivo "Un Botón" | `deploy-masivo.sh` | Orquestación Ironic API (`:6385`), disparos WoL/IPMI y sondeo SSH |
| **Fase 9**: Clúster Kubernetes HA (RKE2) | `08-kubernetes.sh` | `/etc/rancher/rke2/config.yaml`, `/etc/modules-load.d/k8s.conf`, `/etc/sysctl.d/99-kubernetes.conf`, `/root/.kube/config` |
| **Fase 10**: Reinstalación y Ciclo de Vida | `deploy-masivo.sh --rebuild` | Ciclo `undeploy` / `deploy`, rolling updates |
| **Fase 11**: Validación Integral | `09-verificacion.sh` | Despliegue de prueba Cilium eBPF, balanceo de servicios y sondas ICMP/SSH |
| **Sección 8/9**: Auditoría y Diagnóstico | `healthcheck.sh` | Lectura de sockets, APIs REST (:8081, :8089, :6385) y `kubectl get nodes` |

---

## 8. Suposiciones, Decisiones Técnicas y Parámetros [POR DEFINIR]

### 8.1 Suposiciones y Decisiones Adoptadas
1. **Idempotencia Absoluta**: Todos los scripts comprueban la existencia de usuarios, archivos, bases de datos o servicios antes de crearlos, garantizando que una re-ejecución accidental no cause interrupción del servicio ni pérdida de datos.
2. **Desacoplamiento de Secretos**: No existen contraseñas ni tokens en texto plano dentro del código de los scripts; todas las credenciales se leen exclusivamente desde `config/env` con permisos restringidos `0600`.
3. **Aislamiento de Red L2**: Se asume que los 8 servidores físicos están interconectados a través de un switch L2 no gestionado o VLAN dedicada para el segmento `10.100.29.0/24`, donde el Bastion es el único equipo con una segunda tarjeta hacia la WAN.

### 8.2 Parámetros Marcados como [POR DEFINIR] en `config/env`
* `<IP_BASTION_WAN>`: Dirección IP pública o corporativa asignada a la interfaz externa del Bastion Host.
* `<GATEWAY_WAN>`: Puerta de enlace predeterminada de la red perimetral WAN.
* `<POSTGRES_NEXUS_PASSWORD>`: Contraseña fuerte para la base de datos de metadatos de Nexus en PostgreSQL 16.
* `<RKE2_CLUSTER_TOKEN>`: Cadena alfanumérica de seguridad compartida para registrar nodos en el clúster Kubernetes.
* `<BMC_IP_xxx>` y `<BMC_PASSWORD>`: IPs de gestión fuera de banda (iLO/iDRAC) si se utiliza control de energía por IPMI o Redfish en lugar de Wake-on-LAN.

### 8.3 Incoherencias Detectadas entre el README y la Realidad Operativa
1. **Concurrencia en la Fase de Arranque**: En el README se describe que todos los nodos deben booteaar por PXE simultáneamente; sin embargo, en placas base con tarjetas Realtek o sin soporte nativo de PXE-over-UEFI, se recomienda encender primero el Nodo 306 (`pxe-controller`), esperar a que `dnsmasq` y Nginx estén activos (validado por `05-pxe-dhcp-tftp.sh`), y posteriormente disparar el encendido de los nodos restantes con `deploy-masivo.sh`.
2. **Generación de ISOs de ConfigDrive**: El README menciona inyectar la partición `config-2` de 64 MB; para compilar este volumen en entornos Debian 13 sin herramientas privativas, `07-cloud-init.sh` automatiza la instalación de `genisoimage` o `mkisofs` para empaquetar los metadatos VFAT de forma estándar y portable.

# Manual de Operación: Suite de Automatización Bash para Infraestructura Bare-Metal Edge

> **Automatización oficial para Debian 13 (Trixie) sobre 8 servidores físicos**  
> **Alineado 1:1 con la Guía Maestra [README.md principal](../README.md)**  
> **Modo de Operación**: Ejecución desatendida, idempotente, segura y con trazabilidad completa.

---

## 1. Estructura del Proyecto

```text
infra-scripts/
├── README.md                          # Este manual de operación y tabla de trazabilidad
├── .gitignore                         # Exclusión de claves, certificados, respaldos e ISOs
├── config/
│   ├── env.example                    # Plantilla maestra de variables de entorno y puertos
│   └── nodes.csv                      # Inventario físico de los 8 nodos con MACs normalizadas
├── lib/
│   └── common.sh                      # Biblioteca común: logging, respaldos, comprobaciones y traps
├── 00-preflight.sh                    # Auditoría previa de Debian 13, kernel 6.12+, RAM y disco
├── 01-base-servidores.sh              # Hostname, /etc/hosts, systemd-networkd, Chrony y sudoers
├── 02-bastion.sh                      # Endurecimiento SSH :2222, Squid :3128 y cortafuegos nftables
├── 03-nexus.sh                        # Sonatype Nexus 3 OSS con PostgreSQL 16 y afinamiento de memoria
├── 04-clientes-nexus.sh               # Redirección de APT hacia Nexus, variables de proxy y mirrors
├── 05-pxe-dhcp-tftp.sh                # dnsmasq con reservas fijas por MAC, bootloader iPXE y Nginx :8089
├── 06-openstack-glance-bifrost.sh     # Ironic Standalone en Podman, ramdisk IPA y enrolamiento por MAC
├── 07-cloud-init.sh                   # Plantilla Packer HCL2 y generador de volumen ConfigDrive (config-2)
├── 08-kubernetes.sh                   # Clúster RKE2 (3 Control Planes HA + 2 Workers) con Cilium eBPF
├── 09-verificacion.sh                 # Validación integral de conectividad, datapath Cilium y API Server
├── deploy-masivo.sh                   # El "Botón Único": Aprovisionamiento masivo paralelo por MAC
├── healthcheck.sh                     # Auditoría de estado y tabla visual de métricas de la flota
└── rollback/                          # Scripts individuales de desmantelamiento por fase
    ├── rollback-01-base-servidores.sh
    ├── rollback-02-bastion.sh
    ├── rollback-03-nexus.sh
    ├── rollback-04-clientes-nexus.sh
    ├── rollback-05-pxe-dhcp-tftp.sh
    ├── rollback-06-openstack-glance-bifrost.sh
    ├── rollback-07-cloud-init.sh
    └── rollback-08-kubernetes.sh
```

---

## 2. Matriz de Nodos y Orden Cronológico de Ejecución

Los scripts deben ejecutarse estrictamente en el siguiente orden lógico:

| Paso | Script | Fase del README | Nodo Destino | IP | Propósito Clave |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **0** | `00-preflight.sh` | Pre-requisitos | Cualquier nodo | N/A | Valida Debian 13, kernel 6.12+, RAM (8/16 GB) y disco 128 GB. |
| **1** | `01-base-servidores.sh` | Fase 1 | **Todos (1 al 8)** | `10.0.1.x` | Fija hostnames, red estática, Chrony NTP y usuario administrativo. |
| **2** | `02-bastion.sh` | Fase 2 | **Bastion (ID 314)** | `10.0.1.10` | Asegura OpenSSH en puerto 2222, proxy Squid :3128 y firewall `nftables`. |
| **3** | `03-nexus.sh` | Fase 3 | **Nexus (ID 315)** | `10.0.1.20` | Despliega PostgreSQL 16 y Nexus 3 OSS con tuning de 4 GB JVM. |
| **4** | `04-clientes-nexus.sh`| Fase 4 | **Clientes (3 al 8)** | `10.0.1.x` | Redirige `sources.list` y containerd al proxy local de Nexus. |
| **5** | `05-pxe-dhcp-tftp.sh` | Fase 5 | **PXE (ID 306)** | `10.0.1.30` | Arranca `dnsmasq` con 8 reservas fijas por MAC y Nginx en :8089. |
| **6** | `06-openstack-glance-bifrost.sh` | Fase 6 | **PXE (ID 306)** | `10.0.1.30` | Inicia Ironic en Podman, descarga IPA y enrola los 8 nodos en catálogo. |
| **7** | `07-cloud-init.sh` | Fase 7 | **PXE (ID 306)** | `10.0.1.30` | Prepara plantillas Packer y generador de volumen `config-2`. |
| **8** | `deploy-masivo.sh` | Fase 8 | **PXE (ID 306)** | `10.0.1.30` | **"Un solo botón"**: Dispara WoL/IPMI y despliega la imagen en paralelo. |
| **9** | `08-kubernetes.sh` | Fase 9 | **K8s (269,280,320,321,279)** | `10.0.1.10x` | Inicia RKE2 Server (CPs) y RKE2 Agent (Workers) con Cilium eBPF. |
| **10**| `09-verificacion.sh` | Fase 11 | **Bastion (ID 314)** | `10.0.1.10` | Ejecuta prueba de tráfico pod-a-pod y valida los 5 nodos Ready. |
| **--**| `healthcheck.sh` | Operaciones | **Bastion (ID 314)** | `10.0.1.10` | Inspección continua con tabla visual en tiempo real. |

---

## 3. Preparación Inicial y Distribución de Scripts

### 3.1 Configuración de Variables Privadas
Antes de la primera ejecución, copie la plantilla de entorno y ajuste las credenciales:

```bash
cp config/env.example config/env
chmod 600 config/env
nano config/env
```

### 3.2 Copia de Scripts hacia los Nodos Internos vía ProxyJump
Desde su estación DevOps externa, copie la carpeta hacia el Bastion Host y propáguela a los servidores internos a través del túnel SSH del puerto 2222:

```bash
# 1. Copiar suite completa al Bastion Host
scp -P 2222 -i ~/.ssh/id_ed25519_bastion -r ../infra-scripts debian@<IP_BASTION_WAN>:/tmp/

# 2. Conectarse al Bastion
ssh -p 2222 -i ~/.ssh/id_ed25519_bastion debian@<IP_BASTION_WAN>

# 3. Propagar scripts a un nodo interno usando la llave interna (ej. al servidor Nexus)
scp -i ~/.ssh/id_ed25519_nodes -r /tmp/infra-scripts debian@10.0.1.20:/tmp/
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
3. **Aislamiento de Red L2**: Se asume que los 8 servidores físicos están interconectados a través de un switch L2 no gestionado o VLAN dedicada para el segmento `10.0.1.0/24`, donde el Bastion es el único equipo con una segunda tarjeta hacia la WAN.

### 8.2 Parámetros Marcados como [POR DEFINIR] en `config/env`
* `<IP_BASTION_WAN>`: Dirección IP pública o corporativa asignada a la interfaz externa del Bastion Host.
* `<GATEWAY_WAN>`: Puerta de enlace predeterminada de la red perimetral WAN.
* `<POSTGRES_NEXUS_PASSWORD>`: Contraseña fuerte para la base de datos de metadatos de Nexus en PostgreSQL 16.
* `<RKE2_CLUSTER_TOKEN>`: Cadena alfanumérica de seguridad compartida para registrar nodos en el clúster Kubernetes.
* `<BMC_IP_xxx>` y `<BMC_PASSWORD>`: IPs de gestión fuera de banda (iLO/iDRAC) si se utiliza control de energía por IPMI o Redfish en lugar de Wake-on-LAN.

### 8.3 Incoherencias Detectadas entre el README y la Realidad Operativa
1. **Concurrencia en la Fase de Arranque**: En el README se describe que todos los nodos deben booteaar por PXE simultáneamente; sin embargo, en placas base con tarjetas Realtek o sin soporte nativo de PXE-over-UEFI, se recomienda encender primero el Nodo 306 (`pxe-controller`), esperar a que `dnsmasq` y Nginx estén activos (validado por `05-pxe-dhcp-tftp.sh`), y posteriormente disparar el encendido de los nodos restantes con `deploy-masivo.sh`.
2. **Generación de ISOs de ConfigDrive**: El README menciona inyectar la partición `config-2` de 64 MB; para compilar este volumen en entornos Debian 13 sin herramientas privativas, `07-cloud-init.sh` automatiza la instalación de `genisoimage` o `mkisofs` para empaquetar los metadatos VFAT de forma estándar y portable.

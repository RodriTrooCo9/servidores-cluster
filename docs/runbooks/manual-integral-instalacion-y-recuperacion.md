> **Referencia histórica del laboratorio conjunto.** Este documento mezcla ambos proyectos y conserva topologías y procedimientos anteriores. No lo uses como secuencia vigente. Consulta la [guía de Kubernetes](../../GUIA_DE_INSTALACION.md) o la [guía de instalación de sistemas operativos](../../GUIA_OPENSTACK.md). Los comandos de recuperación requieren contrastarse con el estado real.

# Manual Integral de Instalación, Operación y Recuperación ante Desastres
## Clúster Bare-Metal Edge: OpenStack Ironic, Nexus 3, Kubernetes HA (RKE2 + Cilium eBPF) y Observabilidad Completa

> **Flota Física**: 8 Servidores Dell OptiPlex 3020M (Debian 13 Trixie, 128 GB SSD NVMe/SATA)  
> **Topología de Red**: Subred privada aislada `10.100.29.0/24` | Gateway PXE/Router: `10.100.29.30` | Gateway Bastión: `10.100.29.10`  
> **Punto de Enlace WiFi de Mantenimiento**: `192.168.29.25` (Nodo 306) | **VIP OpenStack**: `10.100.29.5`  
> **Nivel de Criticidad**: Tier 1 (Producción Bare-Metal Edge / Alta Disponibilidad)  
> **Autor**: Staff SRE / DevOps Core Team  
> **Última Actualización**: Octubre 2026 | **Versión del Manual**: 2.0.0 (Unificado)

---

## 📋 Índice General

- [PARTE I: INSTALACIÓN Y DESPLIEGUE DESDE CERO](#parte-i-instalación-y-despliegue-desde-cero)
  - [I.1 Requisitos Previos y Preparación del Entorno](#i1-requisitos-previos-y-preparación-del-entorno)
    - [I.1.1 Inventario Canónico de Hardware de los 8 Nodos Físicos](#i11-inventario-canónico-de-hardware-de-los-8-nodos-físicos)
    - [I.1.2 Configuración Crítica de BIOS/UEFI en los Dell OptiPlex 3020M](#i12-configuración-crítica-de-biosuefi-en-los-dell-optiplex-3020m)
    - [I.1.3 Preparación de la Estación de Trabajo del Administrador (Laptop)](#i13-preparación-de-la-estación-de-trabajo-del-administrador-laptop)
    - [I.1.4 Topología de Red, Segmentación L2/L3 y Matriz de Puertos](#i14-topología-de-red-segmentación-l2l3-y-matriz-de-puertos)
    - [I.1.5 Gestión de Secretos, Credenciales y Criptografía](#i15-gestión-de-secretos-credenciales-y-criptografía)
    - [I.1.6 Infraestructura de Accesos SSH y Modelo ProxyJump](#i16-infraestructura-de-accesos-ssh-y-modelo-proxyjump)
    - [I.1.7 Repositorio Local de Artefactos e Imágenes](#i17-repositorio-local-de-artefactos-e-imágenes)
  - [I.2 Fases de Despliegue Automatizado (Paso a Paso)](#i2-fases-de-despliegue-automatizado-paso-a-paso)
    - [Fase 00: Preflight y Auditoría de Conectividad](#fase-00-preflight-y-auditoría-de-conectividad)
    - [Fase 10: Configuración Base del Sistema Operativo Debian 13](#fase-10-configuración-base-del-sistema-operativo-debian-13)
    - [Fase 11: Bastión Perimetral, Hardening nftables y Proxy Squid](#fase-11-bastión-perimetral-hardening-nftables-y-proxy-squid)
    - [Fase 20: Repositorio Sonatype Nexus 3 OSS y PostgreSQL 16](#fase-20-repositorio-sonatype-nexus-3-oss-y-postgresql-16)
    - [Fase 21: Controlador PXE, dnsmasq DHCP/TFTP y HTTPBoot](#fase-21-controlador-pxe-dnsmasq-dhcptftp-y-httpboot)
    - [Fase 22: Despliegue de OpenStack Ironic Standalone y Glance (Kolla)](#fase-22-despliegue-de-openstack-ironic-standalone-y-glance-kolla)
    - [Fase 23: Aprovisionamiento Bare-Metal Masivo (ConfigDrive y WoL)](#fase-23-aprovisionamiento-bare-metal-masivo-configdrive-y-wol)
    - [Fase 30: Plataforma Kubernetes HA (RKE2 + Cilium eBPF)](#fase-30-plataforma-kubernetes-ha-rke2--cilium-ebpf)
    - [Fase 40: Suite Central de Observabilidad (Prometheus, VictoriaMetrics, Grafana, Loki, Tempo)](#fase-40-suite-central-de-observabilidad)
    - [Fase 45: Despliegue de Aplicaciones y Microservicios Demo](#fase-45-despliegue-de-aplicaciones-y-microservicios-demo)
    - [Fase 50: Validación Integral de Salud (Healthcheck)](#fase-50-validación-integral-de-salud-healthcheck)
    - [Fase 90: Creación del Respaldo Inicial de Recuperación](#fase-90-creación-del-respaldo-inicial-de-recuperación)
  - [I.3 Orquestación Completa con Comando Único (`site.yml` y `levantar-todo.sh`)](#i3-orquestación-completa-con-comando-único)
  - [I.4 Matriz de Aceptación y Checklist de Pase a Producción](#i4-matriz-de-aceptación-y-checklist-de-pase-a-producción)
- [PARTE II: OPERACIÓN, FALLAS Y REINICIO](#parte-ii-operación-fallas-y-reinicio)
  - [II.1 Secuencia Global de Arranque y Rearranque Justificada](#ii1-secuencia-global-de-arranque-y-rearranque-justificada)
  - [II.2 Catálogo de los 21 Escenarios Operativos de Falla](#ii2-catálogo-de-los-21-escenarios-operativos-de-falla)
- [CAPÍTULOS TRANSVERSALES](#capítulos-transversales)
  - [A. Tarjeta Rápida (Runsheet 3 a.m.): Apagón Total en 10 Pasos](#a-tarjeta-rápida-runsheet-3-am-apagón-total-en-10-pasos)
  - [B. Árbol de Decisión de Diagnóstico de Incidentes (Mermaid)](#b-árbol-de-decisión-de-diagnóstico-de-incidentes-mermaid)
  - [C. Matriz de Dependencias Cruzadas de Servicios](#c-matriz-de-dependencias-cruzadas-de-servicios)
  - [D. Tabla Canónica de Puertos, Interfaces y Unidades systemd](#d-tabla-canónica-de-puertos-interfaces-y-unidades-systemd)
  - [E. Directorio Central de Logs por Componente](#e-directorio-central-de-logs-por-componente)
  - [F. Matriz de Errores Comunes, Causas Raíz y Soluciones Inmediatas](#f-matriz-de-errores-comunes-causas-raíz-y-soluciones-inmediatas)
  - [G. Política de Respaldos, Retención y Procedimiento de Restauración](#g-política-de-respaldos-retención-y-procedimiento-de-restauración)
  - [H. Seguridad, Hardening y Rotación Criptográfica de Secretos](#h-seguridad-hardening-y-rotación-criptográfica-de-secretos)
  - [I. Procedimiento de Acceso de Emergencia (Out-of-Band / Bastión Caído)](#i-procedimiento-de-acceso-de-emergencia)
  - [J. Directorio de Contactos, Glosario y Matriz de Escalamiento](#j-directorio-de-contactos-glosario-y-matriz-de-escalamiento)

---

# PARTE I: INSTALACIÓN Y DESPLIEGUE DESDE CERO

## I.1 Requisitos Previos y Preparación del Entorno

### I.1.1 Inventario Canónico de Hardware de los 8 Nodos Físicos

La infraestructura consta de 8 computadores físicos de formato ultra-reducido **Dell OptiPlex 3020M Micro**, interconectados mediante un switch Gigabit dedicado no gestionado o gestionado con VLAN nativa aislada.

> [!IMPORTANT]
> Todos los servidores cuentan con una sola interfaz Ethernet Gigabit integrada en placa (`enp2s0` / `eno1`). Por diseño arquitectónico, **la interfaz física jamás debe asociarse directamente a puentes OVS de OpenStack Neutron** para evitar la pérdida permanente de conectividad L2 y SSH.

| ID Nodo | Hostname Físico | Dirección IP LAN | Dirección MAC (`enp2s0`) | RAM (GB) | SSD (GB) | Rol Primario en la Arquitectura | Usuario SSH |
| :---: | :--- | :--- | :--- | :---: | :---: | :--- | :--- |
| **314** | `bastion` | `10.100.29.10` | `64:00:6a:2a:60:62` | 8 | 128 | Bastión SSH, Proxy Egress Squid, Firewall nftables | `aget-ic` |
| **315** | `nexus-repo` | `10.100.29.20` | `64:00:6a:2a:5f:99` | 16 | 128 | Repositorio Sonatype Nexus 3, Registry Docker, PostgreSQL 16 | `io` |
| **306** | `pxe-controller` | `10.100.29.30` | `64:00:6a:2a:62:42` | 16 | 128 | Router LAN, PXE/dnsmasq, OpenStack Kolla, Prometheus, Grafana | `n306` |
| **269** | `k8s-cp-01` | `10.100.29.101` | `64:00:6a:2a:5f:f9` | 16 | 128 | Nodo de Cómputo Kubernetes (Worker-05 / ex CP-01) | `debian` |
| **280** | `k8s-cp-02` | `10.100.29.102` | `64:00:6a:2a:60:63` | 16 | 128 | Nodo de Cómputo Kubernetes (Worker-01) | `debian` |
| **320** | `k8s-cp-03` | `10.100.29.103` | `64:00:6a:2a:2c:75` | 16 | 128 | Nodo de Cómputo Kubernetes (Worker-02) | `debian` |
| **321** | `k8s-worker-01` | `10.100.29.111` | `64:00:6a:2a:62:a4` | 8 | 128 | Nodo de Cómputo Kubernetes (Worker-03) | `debian` |
| **279** | `k8s-worker-02` | `10.100.29.112` | `64:00:6a:2a:2f:cb` | 8 | 128 | Nodo de Cómputo Kubernetes (Worker-04) | `debian` |

*Fuente de verdad verificada en el repositorio: [`inventory/nodes.csv`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/inventory/nodes.csv) e [`inventory/lab/hosts.yml`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/inventory/lab/hosts.yml).*

---

### I.1.2 Configuración Crítica de BIOS/UEFI en los Dell OptiPlex 3020M

Para garantizar el encendido por red (Wake-on-LAN), el ciclo de auto-reparación y el arranque PXE/iPXE desatendido, configure la BIOS de cada equipo pulsando `F2` al encender:

1. **General -> Boot Sequence**:
   - `Boot List Option`: Seleccionar **UEFI**.
   - Secuencia de arranque: 1º `NIC integrada (Onboard NIC IPv4)`, 2º `SSD Interno (Debian / UEFI OS)`.
2. **System Configuration -> Integrated NIC**:
   - Habilitar: `Enabled w/PXE`.
3. **Power Management -> Wake on LAN / WLAN**:
   - Seleccionar: **`LAN Only`** o **`LAN with Boot Path Acceleration`**.
4. **Power Management -> Deep Sleep Control**:
   - Seleccionar: **`Disabled`** (crítico; si Deep Sleep está activo, la tarjeta de red apaga el chip PHY al suspenderse y el paquete mágico WoL es ignorado).
5. **Power Management -> AC Recovery**:
   - Seleccionar: **`Last Power State`** o **`Power On`** (garantiza reinicio automático tras corte de energía eléctrica).

---

### I.1.3 Preparación de la Estación de Trabajo del Administrador (Laptop)

La laptop o estación de administración ejecuta las tareas de orquestación a través del `Makefile` o Ansible.

#### Dependencias Mínimas Requeridas
* **Sistema Operativo**: Linux (Debian 12/13, Ubuntu 22.04/24.04, Fedora) o macOS.
* **Python**: `>= 3.10` con entorno virtual `venv`.
* **Ansible**: `>= 2.15` (`ansible-core`).
* **Herramientas de CLI**: `git`, `make`, `curl`, `jq`, `ssh`, `rsync`, `wakeonlan`, `openstackclient`.

#### Instalación Automatizada de la Estación de Trabajo
Ejecute el script aprovisionador que instala las herramientas necesarias y configura la resolución de nombres local:

```bash
# 1. Clonar el repositorio y situarse en la raíz
cd ~/Documents/gitlabinf/GuiaImplementacion/infra-scripts

# 2. Ejecutar la configuración asistida
make setup
# O directamente:
./scripts/client/setup-client-workstation.sh
```

El script configura automáticamente:
- El archivo de configuración SSH local `~/.ssh/config` con los perfiles `ProxyJump` hacia la red `10.100.29.0/24`.
- Las entradas canónicas en `/etc/hosts` (`bastion.lab.local`, `nexus.lab.local`, `pxe.lab.local`, etc.).
- La validación de conectividad directa hacia el nodo controlador WiFi (`192.168.29.25`).

---

### I.1.4 Topología de Red, Segmentación L2/L3 y Matriz de Puertos

#### Segmentos de Red
* **Subred Privada del Clúster (LAN)**: `10.100.29.0/24` (Broadcast: `10.100.29.255`, Máscara: `255.255.255.0`).
* **Puerta de Enlace Predeterminada**: `10.100.29.30` (Nodo 306, router de laboratorio con masquerade/NAT) y `10.100.29.10` (Bastión perimetral).
* **Servidor DNS Corporativo**: `192.168.26.120`.
* **Rango DHCP Efímero (dnsmasq)**: `10.100.29.50` - `10.100.29.99` (Lease time: 1 hora, para inspección y descubrimiento).
* **Rango DHCP de Aprovisionamiento Ironic**: `10.100.29.150` - `10.100.29.199` (Servido por dnsmasq embebido de Kolla).
* **IP Virtual de Kolla (HAProxy/Keystone)**: `10.100.29.5`.
* **Red WiFi de Mantenimiento Out-of-Band**: `192.168.29.0/24` (IP Nodo 306: `192.168.29.25`).

#### Matriz Canónica de Puertos de Servicio

| Componente | Host / IP | Puerto / Protocolo | Servicio | Función |
| :--- | :--- | :---: | :--- | :--- |
| **Bastión** | `10.100.29.10` | `22/TCP` | OpenSSH | Punto de entrada único vía ProxyJump |
| **Squid Proxy** | `10.100.29.10` | `3128/TCP` | Squid | Proxy HTTP/HTTPS Egress con lista blanca |
| **Nexus Web UI** | `10.100.29.20` | `8081/TCP` | Sonatype Nexus | Interfaz web de administración y repositorios APT |
| **Nexus Registry Pull** | `10.100.29.20` | `8082/TCP` | Docker Group | Repositorio Docker Registry de lectura y caché |
| **Nexus Registry Push** | `10.100.29.20` | `8083/TCP` | Docker Hosted | Repositorio Docker Registry privado de escritura |
| **PostgreSQL 16** | `10.100.29.20` | `5432/TCP` | PostgreSQL | Base de datos relacional dedicada para Nexus 3 |
| **TFTP Server** | `10.100.29.30` | `69/UDP` | dnsmasq | Entrega del bootloader primario iPXE |
| **HTTPBoot Server** | `10.100.29.30` | `8089/TCP` | Nginx HTTP | Servidor web para scripts iPXE, kernels e ISOs |
| **OpenStack Keystone** | `10.100.29.5` / `:30` | `5000/TCP` | Keystone API | Autenticación y catálogo de servicios OpenStack |
| **OpenStack Glance** | `10.100.29.5` / `:30` | `9292/TCP` | Glance API | Registro y almacenamiento de imágenes QCOW2 |
| **OpenStack Ironic** | `10.100.29.5` / `:30` | `6385/TCP` | Ironic API | Gestión de hardware bare-metal y ciclo de vida |
| **OpenStack Horizon** | `10.100.29.30` | `80/TCP` | Horizon Dashboard | Interfaz gráfica web de OpenStack |
| **RKE2 Kubernetes API**| `10.100.29.30` | `6443/TCP` | kube-apiserver | API REST del clúster de Kubernetes |
| **RKE2 Server Node** | `10.100.29.30` | `9345/TCP` | rke2-server | Canal de registro de agentes y unión al clúster |
| **Kubelet & cAdvisor** | Todos los K8s | `10250/TCP` | kubelet | Métricas de pods y cAdvisor (HTTPS autenticado) |
| **Prometheus Server** | `10.100.29.30` | `9090/TCP` | Prometheus | Motor central de métricas y scraping |
| **Grafana Server** | `10.100.29.30` | `3000/TCP` | Grafana | Dashboards visuales de flota y contenedores |
| **Node Exporter** | Los 8 nodos | `9100/TCP` | node_exporter | Métricas a nivel de sistema operativo y hardware |
| **VictoriaMetrics TSDB**| K8s NodePort | `30428/TCP` | VictoriaMetrics | Almacenamiento a largo plazo TSDB (30 días) |
| **Loki Logs** | K8s NodePort | `30100/TCP` | Grafana Loki | Ingesta centralizada de registros y logs de pods |
| **Tempo Traces** | K8s NodePort | `30200/TCP` | Grafana Tempo | Recolección distribuida de trazas OTel |

---

### I.1.5 Gestión de Secretos, Credenciales y Criptografía

> [!CAUTION]
> **REGLA DE SEGURIDAD**: Nunca registre contraseñas, tokens de Kubernetes ni llaves privadas en texto plano en commits de Git ni en la consola pública.

#### Ubicación Canónica de los Secretos en el Repositorio
* **Variables Maestras de Red y Clúster**: [`inventory/env`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/inventory/env) (derivado de [`inventory/env.example`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/inventory/env.example)).
  * Variables clave: `RKE2_CLUSTER_TOKEN`, `POSTGRES_NEXUS_PASSWORD`, `BMC_PASSWORD`.
* **Secretos de OpenStack Kolla**: [`openstack/secrets/passwords.yml`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/openstack/secrets/passwords.yml).
  * Generación segura: Se generan automáticamente con `.venv-kolla/bin/kolla-genpwd` o mediante `ansible-vault`.
  * Llave de cifrado Vault: Archivo local `.vault_pass` en la raíz del repositorio (excluido en `.gitignore`).
* **Credenciales de Acceso a OpenStack CLI**: [`openstack/secrets/admin-openrc.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/openstack/secrets/admin-openrc.sh) y [`openstack/secrets/clouds.yaml`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/openstack/secrets/clouds.yaml).
* **Tokens de Kubernetes para Prometheus**: Secret tipo `kubernetes.io/service-account-token` almacenado en `/etc/prometheus/tokens/k8s_token` en Nodo 306.

---

### I.1.6 Infraestructura de Accesos SSH y Modelo ProxyJump

La infraestructura aplica un modelo de **Acceso Seguro por Bastión y Doble Vía de Emergencia**:

1. **Vía Primaria (Producción Corporativa)**:
   - Conexión vía Bastión (`10.100.29.10`), usuario `aget-ic`, autenticado mediante llave ED25519 (`ansible/keys/cluster_key`).
   - Todos los nodos privados se alcanzan mediante directiva `ProxyJump bastion`.
2. **Vía Secundaria / Mantenimiento Local (Laboratorio Físico)**:
   - Conexión directa a través de la tarjeta WiFi del Nodo 306 en `192.168.29.25` (usuario `n306`).
   - Permite operar la flota si el Bastión se encuentra apagado o en mantenimiento.

#### Distribución y Sincronización de Llaves SSH
Para autorizar la estación de trabajo y los nodos entre sí:

```bash
# Ejecutar desde la raíz del repositorio
./scripts/bootstrap/setup_keys.sh
```

El script genera el par de llaves `ansible/keys/cluster_key` (si no existe) y distribuye la llave pública a los usuarios administradores (`debian`, `aget-ic`, `io`, `n306`) en los 8 nodos físicos.

---

### I.1.7 Repositorio Local de Artefactos e Imágenes

Para permitir el aprovisionamiento de nodos en una red completamente aislada de Internet:

1. **Kernel e Initramfs de Ironic Python Agent (IPA)**:
   - Descarga automatizada:
     ```bash
     ./artifacts/download_ipa.sh
     ```
   - Almacenamiento local:
     - [`artifacts/openstack/ironic-agent.kernel`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/artifacts/openstack/ironic-agent.kernel)
     - [`artifacts/openstack/ironic-agent.initramfs`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/artifacts/openstack/ironic-agent.initramfs)
2. **Imagen del Sistema Operativo Bare-Metal**:
   - `debian-baremetal.qcow2` (Debian 13 Trixie optimizado con cloud-init y paquetes para RKE2).
   - Servida mediante Nginx HTTPBoot en `http://10.100.29.30:8089/images/debian-baremetal.qcow2` y registrada en OpenStack Glance.
3. **Binarios del Bootloader iPXE**:
   - `undionly.kpxe` (para clientes BIOS tradicional).
   - `ipxe.efi` (para clientes UEFI x86_64).
   - Script de compilación custom: [`network/ipxe/compilar-ipxe-custom.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/network/ipxe/compilar-ipxe-custom.sh).

---

## I.2 Fases de Despliegue Automatizado (Paso a Paso)

```mermaid
flowchart TD
    F00["Fase 00: Preflight & Ping\n(Auditoría y Conectividad)"] --> F10["Fase 10: OS Base\n(Debian 13, sysctl, límites)"]
    F10 --> F11["Fase 11: Bastión Perimetral\n(Squid 3128, nftables, SSH)"]
    F11 --> F20["Fase 20: Nexus 3 + Postgres\n(Repositorios APT y Docker)"]
    F20 --> F21["Fase 21: PXE Controller\n(dnsmasq, TFTP, HTTPBoot 8089)"]
    F21 --> F22["Fase 22: OpenStack Ironic & Glance\n(Kolla-Ansible, MariaDB, RabbitMQ)"]
    F22 --> F23["Fase 23: Aprovisionamiento Masivo\n(Wake-on-LAN, iPXE, ConfigDrive)"]
    F23 --> F30["Fase 30: Kubernetes HA\n(RKE2 Server cp-01 + Workers + Cilium)"]
    F30 --> F40["Fase 40: Observabilidad Central\n(Prometheus, Grafana, VictoriaMetrics)"]
    F40 --> F45["Fase 45: Despliegue de Apps\n(Microservicios Demo)"]
    F45 --> F50["Fase 50: Healthcheck Final\n(17 Targets UP, 35 Contenedores)"]
    F50 --> F90["Fase 90: Respaldo Inicial DR\n(etcd, MariaDB, configs)"]
```

---

### Fase 00: Preflight y Auditoría de Conectividad

* **Objetivo**: Verificar accesibilidad SSH, conectividad física a nivel L2, mapeo de direcciones MAC y estado de recursos en toda la flota de 8 nodos.
* **Nodo(s) donde se ejecuta**: Desde la laptop o estación de administración hacia el grupo `baremetal`.
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/00_ping.yml
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/01_audit_ports.yml
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/02_system_summary.yml
  ```
  *O mediante script diagnóstico directo*:
  ```bash
  ./scripts/diagnostics/00-preflight.sh
  ```
* **Parámetros**: `-i inventory/lab/hosts.yml`.
* **Resultado esperado**: Los 8 nodos responden con estado `SUCCESS` o `pong`. La auditoría reporta arquitectura `x86_64`, versión de kernel `>= 6.12` y almacenamiento disponible en `/`.
* **Verificación**:
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m ping -o
  ```
* **Duración estimada**: 45 segundos.
* **Errores comunes**:
  - `Host key verification failed`: Ejecutar `ssh-keygen -R 10.100.29.X` o verificar que la llave `ansible/keys/cluster_key` tenga permisos `0600`.
  - `Connection refused`: El nodo objetivo está apagado. Enviar paquete mágico WoL: `wakeonlan <MAC>`.
* **Idempotencia y Reversión**: Completamente idempotente (operaciones de solo lectura). No requiere reversión.

---

### Fase 10: Configuración Base del Sistema Operativo Debian 13

* **Objetivo**: Estandarizar el sistema operativo en toda la flota: configurar repositorios APT locales, habilitar módulos del kernel (`overlay`, `br_netfilter`), activar reenvío IPv4 (`net.ipv4.ip_forward=1`), deshabilitar particiones swap y fijar límites del sistema (`limits.conf`).
* **Nodo(s) donde se ejecuta**: En los 8 nodos (`baremetal`).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml
  ```
* **Parámetros**: `become: true`.
* **Resultado esperado**: Módulos del kernel cargados en `/etc/modules-load.d/`, sysctl aplicados en `/etc/sysctl.d/99-kubernetes.conf`, swap desactivada (`swapoff -a`), paquetes base instalados (`curl`, `tar`, `jq`, `socat`, `conntrack`).
* **Verificación**:
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m shell -a "sysctl net.ipv4.ip_forward && swapon --show"
  ```
  *(Debe mostrar `net.ipv4.ip_forward = 1` y ninguna línea de swap activa).*
* **Duración estimada**: 2 a 4 minutos.
* **Errores comunes**:
  - `E: Could not get lock /var/lib/apt/lists/lock`: Esperar liberación automática de procesos `apt.systemd.daily` o reiniciar el servicio de apt diario.
* **Idempotencia y Reversión**: Idempotente. Si se requiere revertir parámetros de red, eliminar `/etc/sysctl.d/99-kubernetes.conf` y recargar `sysctl --system`.

---

### Fase 11: Bastión Perimetral, Hardening nftables y Proxy Squid

* **Objetivo**: Configurar el Nodo 314 (`bastion`) como único punto de entrada SSH, activar firewall por reglas `nftables` (aislando la red interna de tráfico corporativo no deseado) e iniciar el proxy Squid en `:3128` con lista blanca para descargas oficiales de paquetes y certificados.
* **Nodo(s) donde se ejecuta**: Nodo 314 (`bastion.lab.local` / `10.100.29.10`).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/02_bastion_hardening.yml
  ```
* **Parámetros**: Limitado a host `bastion`.
* **Resultado esperado**:
  - Servicio `squid.service` en estado `active (running)`.
  - Servicio `nftables.service` activo aplicando políticas de DROP por defecto hacia la subred privada excepto tráfico establecido y puertos permitidos (`22`, `3128`).
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key aget-ic@10.100.29.10 "sudo systemctl is-active squid nftables && curl -s -x http://localhost:3128 -I http://deb.debian.org"
  ```
  *(Retorna `active`, `active` y `HTTP/1.1 200 OK` o `301 Moved Permanently`).*
* **Duración estimada**: 2 minutos.
* **Errores comunes**:
  - `nftables.service failed`: Conflicto con reglas previas de `iptables-legacy`. El playbook unifica el backend mediante `iptables-nft`.
* **Idempotencia y Reversión**: Idempotente. En caso de bloqueo de conectividad en Bastión, conectarse por consola física o vía Nodo 306 y restaurar reglas base: `sudo nft flush ruleset`.

---

### Fase 20: Repositorio Sonatype Nexus 3 OSS y PostgreSQL 16

* **Objetivo**: Desplegar el servidor de artefactos local en el Nodo 315 para eliminar la dependencia de Internet durante las fases de arranque de imágenes y despliegues masivos. Configura PostgreSQL 16 como backend de base de datos de Nexus y aprovisiona repositorios APT Proxy, Docker Hosted (`:8083`) y Docker Group (`:8082`).
* **Nodo(s) donde se ejecuta**: Nodo 315 (`nexus-repo` / `10.100.29.20`).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/01_nexus.yml
  ```
  *Y posterior inicialización de repositorios Docker*:
  ```bash
  ./nexus/scripts/setup_nexus_kolla_registry.sh
  ```
* **Parámetros**: Memoria Heap JVM fijada en 4 GB (`-Xms4096m -Xmx4096m`), cuota de blobstore limitada a 60 GB para proteger el disco de 128 GB.
* **Resultado esperado**:
  - PostgreSQL 16 escuchando en `127.0.0.1:5432`.
  - Sonatype Nexus 3 en estado `active (running)` respondiendo en puertos `8081` (UI), `8082` (Docker Pull) y `8083` (Docker Push).
* **Verificación**:
  ```bash
  curl -sI http://10.100.29.20:8081/ | head -n 1
  curl -sI http://10.100.29.20:8082/v2/ | head -n 1
  ```
  *(Retorna `HTTP/1.1 200 OK` y `HTTP/1.1 401 Unauthorized` con cabecera `Docker-Distribution-Api-Version: registry/2.0`).*
* **Duración estimada**: 4 a 6 minutos (Nexus requiere ~90 segundos en su primer arranque JVM).
* **Errores comunes**:
  - `Connection refused en :8081`: Nexus sigue inicializando sus bundles OSGi. Inspeccionar logs con `sudo journalctl -u nexus -f` o esperar 60 segundos.
* **Idempotencia y Reversión**: Idempotente. Si se requiere reinstalar desde cero, vaciar el directorio `/opt/sonatype-work/nexus3/` y reiniciar el servicio.

---

### Fase 21: Controlador PXE, dnsmasq DHCP/TFTP y HTTPBoot

* **Objetivo**: Configurar el Nodo 306 (`pxe-controller`) como núcleo de aprovisionamiento de red: servidor DHCP con reservas estáticas por dirección MAC, servidor TFTP para bootloaders iPXE y servidor Nginx HTTPBoot en `:8089` para servir kernels, initramfs y scripts de encadenamiento dinámico.
* **Nodo(s) donde se ejecuta**: Nodo 306 (`pxe-controller` / `10.100.29.30`).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
  ```
* **Parámetros**: Configuración canónica en [`network/dnsmasq/dnsmasq.conf`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/network/dnsmasq/dnsmasq.conf).
* **Resultado esperado**:
  - `dnsmasq` activo escuchando en interfaz `enp2s0` (puertos `:67 UDP` DHCP y `:69 UDP` TFTP).
  - Directorio `/tftpboot` poblado con `undionly.kpxe` e `ipxe.efi`.
  - Nginx activo en `:8089` sirviendo `/var/www/html/ipxe/boot.ipxe`.
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo systemctl is-active dnsmasq nginx"
  curl -s http://10.100.29.30:8089/boot.ipxe | head -n 5
  ```
  *(Debe devolver `#!ipxe` y directivas de encadenamiento).*
* **Duración estimada**: 1 minuto.
* **Errores comunes**:
  - `dnsmasq: failed to bind DHCP server socket: Address already in use`: Conflicto con `systemd-resolved` o instancias previas. El playbook desactiva listeners conflictivos.
* **Idempotencia y Reversión**: Idempotente.

---

### Fase 22: Despliegue de OpenStack Ironic Standalone y Glance (Kolla)

* **Objetivo**: Desplegar los servicios de cómputo físico de OpenStack utilizando contenedores Kolla-Ansible sobre el Nodo 306: MariaDB Galera, RabbitMQ, Keystone, Glance (almacenamiento de imágenes file backend), Ironic API, Ironic Conductor y Neutron (interfaz virtual `veth-neutron`).
* **Nodo(s) donde se ejecuta**: Nodo 306 (`pxe-controller`).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml
  ```
  *O mediante el entorno virtual de Kolla en el controlador*:
  ```bash
  ssh n306@192.168.29.25
  source /home/n306/.venv-kolla/bin/activate
  kolla-ansible -i /etc/kolla/inventory/multinode deploy
  kolla-ansible -i /etc/kolla/inventory/multinode post-deploy
  ```
* **Parámetros**: Configuración canónica en [`openstack/globals.yml`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/openstack/globals.yml) (Kolla release 2025.1 Epoxy, distro base Ubuntu noble, VIP `10.100.29.5`).
* **Resultado esperado**: Contenedores Kolla en ejecución (`kolla_toolbox`, `mariadb`, `rabbitmq`, `keystone`, `glance_api`, `ironic_api`, `ironic_conductor`, `ironic_dnsmasq`, `openvswitch_vswitchd`, `openvswitch_db`, `horizon`).
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker ps --format '{{.Names}}: {{.Status}}'"
  ```
  *(Verificar que al menos 10 contenedores figuren como `Up`).*
* **Duración estimada**: 12 a 18 minutos.
* **Errores comunes**:
  - `MariaDB cluster failed to bootstrap`: Si MariaDB se detuvo abruptamente, arrancar con `safe_to_bootstrap: 1` en `grastate.dat`.
* **Idempotencia y Reversión**: Idempotente. Para reiniciar contenedores caídos: `sudo docker start $(sudo docker ps -a -q)`.

---

### Fase 23: Aprovisionamiento Bare-Metal Masivo (ConfigDrive y WoL)

* **Objetivo**: Registrar los servidores físicos en OpenStack Ironic, inyectar metadatos `cloud-init` mediante ConfigDrive (configuración de red estática, usuario `debian` y llaves SSH autorizadas) y enviar paquetes Wake-on-LAN para flashear el disco SSD de los equipos destino por red iPXE.
* **Nodo(s) donde se ejecuta**: Ejecutado desde el controlador hacia los nodos trabajadores (`k8s-cp-01`, `k8s-cp-02`, `k8s-cp-03`, `k8s-worker-01`, `k8s-worker-02`).
* **Comando exacto**:
  ```bash
  # Registrar y flashear un nodo individual por Wake-on-LAN:
  ./scripts/ops/disaster-recovery.sh --reprovision k8s-cp-02
  ```
* **Parámetros**: Inyección de user-data mediante plantilla [`cloud-init/templates/user-data.j2`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/cloud-init/templates/user-data.j2).
* **Resultado esperado**: El nodo recibe el paquete mágico WoL, enciende su hardware, descarga el kernel IPA por iPXE, flashea la imagen Debian 13 en el SSD local (`/dev/sda`), reinicia y arranca en el sistema instalado con SSH activo.
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key -o ProxyJump=n306@192.168.29.25 debian@10.100.29.102 "hostname && uname -a"
  ```
* **Duración estimada**: 3 a 5 minutos por máquina.
* **Errores comunes**:
  - `El nodo no enciende`: Revisar configuración de BIOS (Deep Sleep desactivado, WoL habilitado).

---

### Fase 30: Plataforma Kubernetes HA (RKE2 + Cilium eBPF)

* **Objetivo**: Desplegar el clúster de Kubernetes en alta disponibilidad utilizando Rancher RKE2 con CNI Cilium en modo eBPF nativo (sin `kube-proxy`), garantizando alto rendimiento y baja latencia en los servidores físicos Dell OptiPlex.
* **Arquitectura de Nodos del Clúster**:
  - **Control Plane (`cp-01`)**: Nodo 306 (`10.100.29.30`, escucha en `:6443` y `:9345`).
  - **Workers**:
    - `worker-01`: `10.100.29.102` (Nodo 280)
    - `worker-02`: `10.100.29.103` (Nodo 320)
    - `worker-03`: `10.100.29.111` (Nodo 321)
    - `worker-04`: `10.100.29.112` (Nodo 279)
    - `worker-05`: `10.100.29.101` (Nodo 269)
    - `worker-06`: `10.100.29.20` (Nodo 315)
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml
  ```
* **Parámetros**:
  - CNI: `cilium`.
  - Token de clúster: Definido en `inventory/env` (`RKE2_CLUSTER_TOKEN`).
  - Almacenamiento local: Driver CSI `local-path-provisioner` con StorageClass predeterminado `local-path`.
* **Resultado esperado**: Todos los nodos se registran en el API server de RKE2 y alcanzan estado `Ready`. Los pods de Cilium agent, Cilium operator, CoreDNS y Traefik se encuentran en estado `Running`.
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide"
  ```
  *(Debe mostrar los 7 nodos en estado `Ready` con versión `v1.36.5+rke2r1`).*
* **Duración estimada**: 5 a 8 minutos.
* **Errores comunes**:
  - `Node status NotReady`: El agente Cilium aún está compilando los programas BPF en el kernel. Esperar 45 segundos.
* **Idempotencia y Reversión**: Idempotente.

---

### Fase 40: Suite Central de Observabilidad (Prometheus, VictoriaMetrics, Grafana, Loki, Tempo)

* **Objetivo**: Desplegar la arquitectura completa de observabilidad (métricas, logs y trazas) integrando los 8 nodos físicos bare-metal y los contenedores de Kubernetes.
* **Componentes Desplegados**:
  1. **Node Exporter**: Activo como servicio nativo systemd en los 8 nodos físicos (`:9100`).
  2. **Prometheus Server**: Activo en Nodo 306 (`:9090`), raspando 17 targets en tiempo real (8 bare-metal, 7 kubelets cAdvisor en `:10250`, 1 kube-apiserver en `:6443`, 1 Prometheus local).
  3. **VictoriaMetrics TSDB**: StatefulSet en K8s expuesto en NodePort `:30428` con volumen persistente `local-path` de 25 GiB y retención a 30 días. Alimentado por `remote_write` continuo desde Prometheus.
  4. **Grafana Server**: Activo en Nodo 306 (`:3000`), aprovisionado automáticamente con 4 dashboards oficiales.
  5. **Loki**: StatefulSet en K8s expuesto en NodePort `:30100` para almacenamiento centralizado de logs.
  6. **Tempo**: StatefulSet en K8s expuesto en NodePort `:30200` para almacenamiento de trazas OTel.
* **Comando exacto**:
  ```bash
  # 1. Desplegar Node Exporter y servicios centrales en Nodo 306:
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml

  # 2. Desplegar backends de observabilidad en Kubernetes:
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f /tmp/01_backends.yaml"
  ```
* **Parámetros**: Datasources canónicos configurados con UIDs estáticos: `Prometheus-BareMetal`, `VictoriaMetrics`, `Loki` y `tempo`.
* **Resultado esperado**:
  - 17/17 targets en Prometheus en estado `UP`.
  - 4 dashboards operativos en Grafana mostrando métricas de hardware y de los 35 contenedores del clúster.
* **Verificación**:
  ```bash
  # Verificar salud de los 17 targets:
  curl -s http://192.168.29.25:9090/api/v1/targets | jq '[.data.activeTargets[] | {job: .labels.job, health: .health}] | group_by(.health) | map({health: .[0].health, count: length})'
  ```
  *(Debe devolver `[{"count": 17, "health": "up"}]`).*
* **Duración estimada**: 3 minutos.
* **Idempotencia y Reversión**: Idempotente.

---

### Fase 45: Despliegue de Aplicaciones y Microservicios Demo

* **Objetivo**: Desplegar la pila de microservicios y aplicaciones de validación en Kubernetes para certificar el enrutamiento CNI Cilium, balanceo de carga Traefik y persistencia.
* **Nodo(s) donde se ejecuta**: Clúster Kubernetes.
* **Comando exacto**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 \
    "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f /tmp/demo_apps.yaml -f /tmp/microservices_stack.yaml"
  ```
* **Resultado esperado**: Namespaces `desarrollo-apps` y `demo` con pods en ejecución y servicios accesibles vía Ingress Traefik.
* **Duración estimada**: 2 minutos.

---

### Fase 50: Validación Integral de Salud (Healthcheck)

* **Objetivo**: Ejecutar la batería completa de pruebas end-to-end (conectividad SSH, base de datos MariaDB, APIs de OpenStack, nodos K8s, pods críticos, endpoints de monitoreo).
* **Comando exacto**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/50-validation/01_healthcheck.yml
  # O mediante script local:
  ./scripts/diagnostics/healthcheck.sh
  ```
* **Resultado esperado**: 14/14 comprobaciones en verde (`HEALTHY` / `SUCCESS`).

---

### Fase 90: Creación del Respaldo Inicial de Recuperación

* **Objetivo**: Generar la primera copia de seguridad consistente de la infraestructura (dump SQL de MariaDB OpenStack, configuraciones `/etc/kolla`, credenciales y snapshot de etcd de Kubernetes) para garantizar un punto de restauración seguro tras la instalación exitosa.
* **Comando exacto**:
  ```bash
  ./scripts/ops/disaster-recovery.sh --backup-all
  ```
* **Resultado esperado**: Archivos `.sql.gz` y `etcd_snapshot_*.db` guardados localmente en `backups/dr_$(date +%Y%m%d)/`.

---

## I.3 Orquestación Completa con Comando Único

Para ejecutar la instalación completa de extremo a extremo sin intervención manual entre fases:

### 1. Ejecución Automatizada mediante Playbook Maestro
```bash
# Despliegue completo desde la estación de trabajo:
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml
```

#### Ejecución por Etiquetas (Tags) y Reanudación Intermedia
Si el despliegue se interrumpe en una fase intermedia (por ejemplo, durante la fase de servicios), puede reanudar exactamente desde esa fase utilizando `--tags` o `--start-at-task`:

```bash
# Ejecutar solo la fase de servicios centrales:
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --tags services

# Ejecutar solo la fase de plataforma Kubernetes:
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --tags platform

# Ejecutar solo la fase de observabilidad:
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --tags observability

# Reanudar la ejecución a partir de una tarea específica si falló:
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --start-at-task="Suite de Monitoreo Centralizado"
```

### 2. Ejecución mediante Script Operativo Unificado
```bash
# Secuencia global de rearranque y validación:
./scripts/ops/levantar-todo.sh
```

---

## I.4 Matriz de Aceptación y Checklist de Pase a Producción

| Capa Tecnológica | Comando de Verificación | Criterio de Éxito / Resultado Esperado |
| :--- | :--- | :--- |
| **1. Conectividad Física y OS** | `ansible baremetal -i inventory/lab/hosts.yml -m ping` | **8/8 nodos retornan `SUCCESS` (`pong`)** |
| **2. Perímetro y Proxy Egress** | `ssh aget-ic@10.100.29.10 "systemctl is-active squid nftables"` | **`active` y `active`** |
| **3. Repositorios Locales** | `curl -sI http://10.100.29.20:8081/ \| head -n 1` | **`HTTP/1.1 200 OK`** |
| **4. Registro Docker Nexus** | `curl -sI http://10.100.29.20:8082/v2/ \| head -n 1` | **`HTTP/1.1 401 Unauthorized`** (Docker Auth) |
| **5. Controlador PXE / TFTP** | `ssh n306@192.168.29.25 "systemctl is-active dnsmasq nginx"` | **`active` y `active`** |
| **6. Contenedores OpenStack** | `ssh n306@192.168.29.25 "sudo docker ps -q \| wc -l"` | **`>= 10` contenedores activos** |
| **7. Nodos de Kubernetes RKE2** | `ssh n306@192.168.29.25 "sudo kubectl get nodes --no-headers \| wc -l"`| **`7` nodos en estado `Ready`** |
| **8. CNI Cilium eBPF** | `ssh n306@192.168.29.25 "sudo kubectl get pods -n kube-system -l k8s-app=cilium --no-headers \| grep -v Running \| wc -l"` | **`0`** (todos los agentes Cilium en `Running`) |
| **9. Targets en Prometheus** | `curl -s http://192.168.29.25:9090/api/v1/targets \| jq '[.data.activeTargets[] \| select(.health==\"up\")] \| length'` | **`17` targets en estado `up`** |
| **10. Métricas de Contenedores** | `curl -s -G http://192.168.29.25:9090/api/v1/query --data-urlencode 'query=count(count by (container) (container_cpu_usage_seconds_total{container!=\"\"}))' \| jq .data.result[0].value[1]` | **`>= 30` contenedores rastreados** |
| **11. Almacenamiento Persistente**| `ssh n306@192.168.29.25 "sudo kubectl get pvc -n observability --no-headers \| grep -v Bound \| wc -l"` | **`0`** (PVCs de VictoriaMetrics, Loki, Tempo `Bound`) |
| **12. Dashboards en Grafana** | `curl -s http://admin:admin@192.168.29.25:3000/api/search \| jq 'length'` | **`>= 4` dashboards provisionados** |
| **13. Copias de Seguridad DR** | `ls -la backups/dr_*/openstack/*.sql.gz backups/dr_*/etcd/*.db` | **Archivos de backup presentes y tamaño > 0** |


---

# PARTE II: OPERACIÓN, FALLAS Y REINICIO

## II.1 Secuencia Global de Arranque y Rearranque Justificada

El encendido o rearranque de un centro de datos edge bare-metal con OpenStack y Kubernetes no es conmutativo: **el orden de activación determina la estabilidad del clúster**. Romper la secuencia genera bloqueos por dependencias circulares, fallas de quórum en bases de datos y caídas en bucle (`CrashLoopBackOff` o `ImagePullBackOff`).

### Diagrama Mermaid del Orden de Arranque Canónico

```mermaid
flowchart TD
    subgraph S0["Capa 0: Infraestructura Física y Conmutación"]
        L2["1. Switch de Red Físico y Cableado L2\n(Validación de Enlace 1 Gbps)"]
    end

    subgraph S1["Capa 1: Enrutamiento y Seguridad Perimetral"]
        PXE["2. Nodo 306 (pxe-controller)\nRouter LAN, DHCP dnsmasq, HTTPBoot"]
        BAS["3. Nodo 314 (bastion)\nFirewall nftables, Proxy Squid :3128, SSH"]
    end

    subgraph S2["Capa 2: Artefactos y Control de Cómputo Bare-Metal"]
        NEX["4. Nodo 315 (nexus-repo)\nPostgreSQL 16 + Sonatype Nexus 3 (:8081/:8082)"]
        OST["5. OpenStack Kolla en Nodo 306\nMariaDB, RabbitMQ, Keystone, Glance, Ironic"]
    end

    subgraph S3["Capa 3: Plataforma de Cómputo Distribuido"]
        KCP["6. Kubernetes Control-Plane (Nodo 306 cp-01)\nrke2-server :6443, etcd embebido"]
        KWK["7. Kubernetes Workers (Nodos 101, 102, 103, 111, 112, 20)\nrke2-agent, CNI Cilium eBPF, Traefik"]
    end

    subgraph S4["Capa 4: Observabilidad y Monitoreo"]
        OBS["8. Suite de Observabilidad\nPrometheus :9090, Grafana :3000, VictoriaMetrics :30428, Loki"]
    end

    subgraph S5["Capa 5: Cargas de Trabajo y Negocio"]
        APP["9. Aplicaciones y Microservicios\nNamespaces demo y desarrollo-apps"]
    end

    L2 --> PXE --> BAS --> NEX --> OST --> KCP --> KWK --> OBS --> APP

    classDef physical fill:#f9f,stroke:#333,stroke-width:2px;
    classDef core fill:#bbf,stroke:#333,stroke-width:2px;
    classDef k8s fill:#dfd,stroke:#333,stroke-width:2px;
```

### Justificación Técnica de la Secuencia y Modo de Falla si se Altera

1. **Switch Físico L2 -> Nodo 306 (Router / PXE / Gateway)**:
   - *Por qué primero:* El Nodo 306 provee el servidor DHCP `dnsmasq`, el enrutamiento LAN (`10.100.29.30`) y el punto de acceso WiFi de emergencia (`192.168.29.25`).
   - *Qué falla si se altera:* Si los otros servidores arrancan sin DHCP ni gateway, sus interfaces fallarán la negociación IP, entrarán en modo de enlace local APIPA (`169.254.x.x`) o bootloop de BIOS/PXE.
2. **Nodo 314 (Bastión) -> Nodo 315 (Nexus 3)**:
   - *Por qué:* Nexus 3 (`10.100.29.20`) y el clúster entero requieren que el Bastión esté activo para salidas puntuales a Internet vía Squid (`:3128`).
   - *Qué falla si se altera:* Si los nodos de cómputo inician antes de Nexus, cualquier pod con política `imagePullPolicy: Always` o nuevas instancias fallarán con `ImagePullBackOff` o `ErrImagePull`.
3. **OpenStack Kolla (MariaDB/RabbitMQ/Ironic) -> RKE2 Server**:
   - *Por qué:* OpenStack Ironic mantiene el estado de aprovisionamiento de hardware y el control de energía WoL.
   - *Qué falla si se altera:* Si se intenta recuperar un nodo dañado antes de que MariaDB e Ironic estén arriba, el controlador no podrá ejecutar la reimagen.
4. **RKE2 Control-Plane -> RKE2 Workers**:
   - *Por qué:* Los agentes `rke2-agent` en los trabajadores se registran contra el supervisor en `https://10.100.29.30:9345`.
   - *Qué falla si se altera:* Si los trabajadores inician sin el servidor activo, `kubelet` intentará conectarse en bucle y entrará en estado degradado con alta carga de CPU por reconexiones TLS fallidas.
5. **Cilium eBPF & CoreDNS -> Observabilidad -> Aplicaciones**:
   - *Por qué:* VictoriaMetrics, Loki y las aplicaciones dependen de la red de pods provista por Cilium eBPF y de la resolución de nombres de CoreDNS.
   - *Qué falla si se altera:* Los recolectores OTel y Prometheus no podrán alcanzar los servicios por DNS interno (`*.svc.cluster.local`).

---

## II.2 Catálogo de los 21 Escenarios Operativos de Falla

---

### Escenario 1: Apagón Total del Laboratorio (Blackout de los 8 Nodos)

* **Síntomas:** No hay respuesta a ping en ninguna IP de la subred `10.100.29.0/24`. Todos los LEDs de los servidores Dell OptiPlex están apagados o parpadeando en ámbar.
* **Impacto:** Pérdida total del servicio, caída de todos los contenedores y plataformas.
* **Prerrequisitos:** Acceso físico al laboratorio o conexión WiFi al Nodo 306 tras retorno de energía.
* **Diagnóstico:**
  1. Verificar estado eléctrico del switch y PDUs.
  2. Ejecutar ping a la IP de mantenimiento del controlador: `ping -c 3 192.168.29.25`.
* **Pasos Numerados de Recuperación:**
  1. **Encendido L2 y Nodo 306:**
     - Encienda el switch. Si el Nodo 306 no enciende solo, presione el botón frontal.
     - Espere 30 segundos y verifique conectividad: `ssh n306@192.168.29.25 "uptime"`.
  2. **Reactivación de Servicios Base en Nodo 306:**
     - Ejecutar en `pxe-controller`:
       ```bash
       sudo systemctl restart dnsmasq nginx
       sudo docker start $(sudo docker ps -a -q)
       ```
  3. **Despertar Nodos Core mediante Wake-on-LAN:**
     - Ejecutar en `pxe-controller`:
       ```bash
       wakeonlan 64:00:6a:2a:60:62  # Bastión (314)
       wakeonlan 64:00:6a:2a:5f:99  # Nexus (315)
       sleep 30
       ```
  4. **Despertar Nodos del Clúster Kubernetes:**
     - Ejecutar en `pxe-controller`:
       ```bash
       wakeonlan 64:00:6a:2a:5f:f9  # worker-05 (101)
       wakeonlan 64:00:6a:2a:60:63  # worker-01 (102)
       wakeonlan 64:00:6a:2a:2c:75  # worker-02 (103)
       wakeonlan 64:00:6a:2a:62:a4  # worker-03 (111)
       wakeonlan 64:00:6a:2a:2f:cb  # worker-04 (112)
       ```
  5. **Orquestación Automática de Rearranque:**
     - Desde la laptop o desde el Nodo 306, ejecute:
       ```bash
       ./scripts/ops/levantar-todo.sh
       ```
* **Verificación:**
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m ping
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
  ```
  *(Todos los nodos en estado `Ready`).*
* **Rollback / Escalamiento:** Si un nodo físico no responde a WoL, inspeccionar el botón frontal del equipo. Si la luz está apagada, verificar cable de alimentación o presionar botón de encendido manualmente.
* **Prevención:** Asegurar que `Deep Sleep Control = Disabled` y `AC Recovery = Last State / Power On` en la BIOS.
* **Tiempo Estimado y Riesgo:** 12 a 18 minutos. Nivel de Riesgo: **Alto**.

---

### Escenario 2: Reinicio Planificado y Apagado Ordenado por Mantenimiento

* **Síntomas:** Ventana de mantenimiento programada para intervención física, eléctrica o actualización de firmware de switch.
* **Impacto:** Detención controlada sin corrupción de bases de datos ni pérdida de datos en TSDB.
* **Prerrequisitos:** Llave SSH autorizada, acceso a consola administrativa.
* **Diagnóstico:** Verificar que no haya tareas activas de aprovisionamiento en Ironic (`openstack baremetal node list`).
* **Pasos Numerados:**
  1. **Drenar Cargas de Kubernetes de Manera Segura:**
     - En Nodo 306:
       ```bash
       for n in worker-01 worker-02 worker-03 worker-04 worker-05 worker-06; do
         sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml cordon $n
       done
       ```
  2. **Detener Contenedores y Servicios de Kubernetes en los Trabajadores:**
     - En cada worker: `sudo systemctl stop rke2-agent`.
  3. **Detener Control-Plane de Kubernetes:**
     - En Nodo 306: `sudo systemctl stop rke2-server`.
  4. **Detener Servicios OpenStack Kolla:**
     - En Nodo 306: `sudo docker stop $(sudo docker ps -q)`.
  5. **Detener Nexus y PostgreSQL:**
     - En Nodo 315: `sudo systemctl stop nexus postgresql`.
  6. **Apagar los Nodos en Secuencia Inversa:**
     ```bash
     ansible k8s_workers -i inventory/lab/hosts.yml -m shell -a "poweroff"
     ssh aget-ic@10.100.29.10 "sudo poweroff"
     ssh io@10.100.29.20 "sudo poweroff"
     ssh n306@192.168.29.25 "sudo poweroff"
     ```
* **Verificación:** Todos los LEDs frontales apagados; consumo eléctrico en reposo.
* **Rollback / Escalamiento:** En caso de abortar, reactivar con `./scripts/ops/levantar-todo.sh`.
* **Tiempo Estimado y Riesgo:** 8 minutos. Nivel de Riesgo: **Bajo**.

---

### Escenario 3: Caída Aislada del Bastión (Nodo 314) y Acceso de Emergencia

* **Síntomas:** Los comandos desde la laptop fallan con `ssh: connect to host 10.100.29.10 port 22: Connection refused` o `No route to host`. El monitoreo reporta alerta `BastionDown`.
* **Impacto:** Pérdida del canal ProxyJump primario. Los nodos del clúster no pueden descargar paquetes externos vía Squid. El clúster Kubernetes y los servicios internos siguen funcionando localmente.
* **Prerrequisitos:** Conexión a la red WiFi de mantenimiento del laboratorio (`192.168.29.0/24`).
* **Diagnóstico:**
  1. Conectarse directamente al Nodo 306 por WiFi:
     ```bash
     ssh -i ansible/keys/cluster_key n306@192.168.29.25 "uptime"
     ```
  2. Verificar si el Bastión responde en su IP LAN:
     ```bash
     ssh n306@192.168.29.25 "ping -c 2 10.100.29.10"
     ```
* **Pasos Numerados:**
  1. Si el host no responde a ping, enviar paquete WoL desde Nodo 306:
     ```bash
     ssh n306@192.168.29.25 "wakeonlan 64:00:6a:2a:60:62"
     sleep 25
     ```
  2. Si el sistema operativo arrancó pero SSH o Squid están caídos:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 aget-ic@10.100.29.10 "sudo systemctl restart ssh squid nftables"
     ```
  3. Si la interfaz corporativa WAN (`enp2s0`) perdió la IP:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 aget-ic@10.100.29.10 "sudo systemctl restart systemd-networkd"
     ```
* **Verificación:**
  ```bash
  ssh -i ansible/keys/cluster_key aget-ic@10.100.29.10 "systemctl is-active squid"
  ```
  *(Retorna `active`).*
* **Rollback / Escalamiento:** Si el hardware del Nodo 314 sufrió fallo irrecuperable, aplicar procedimiento de reasignación de IP `10.100.29.10` en Nodo 306 como gateway secundario.
* **Prevención:** Supervisar logs de Squid en `/var/log/squid/cache.log` para evitar saturación de memoria.
* **Tiempo Estimado y Riesgo:** 3 a 5 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 4: Caída de un Nodo Worker de Kubernetes

* **Síntomas:** En Grafana o CLI, un nodo trabajador aparece en estado `NotReady`. La alerta `K8sWorkerNotReady` se dispara en Prometheus.
* **Impacto:** Los pods alojados en ese nodo quedan en estado `Terminating` o se reprograman automáticamente en los nodos restantes según el scheduler de Kubernetes.
* **Prerrequisitos:** Acceso SSH al clúster vía Nodo 306.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
  ssh n306@192.168.29.25 "ping -c 2 <IP_NODO_CAIDO>"
  ```
* **Pasos Numerados:**
  1. **Si el nodo físico se apagó:**
     - Enviar paquete Wake-on-LAN con su dirección MAC canónica:
       ```bash
       # Ejemplo para worker-01 (Nodo 280, 10.100.29.102):
       ssh n306@192.168.29.25 "wakeonlan 64:00:6a:2a:60:63"
       ```
     - Esperar 45 segundos a que arranque el sistema operativo.
  2. **Si el nodo responde a SSH pero `rke2-agent` está caído:**
     - Conectarse al nodo afectado:
       ```bash
       ssh -o ProxyJump=n306@192.168.29.25 debian@10.100.29.102 "sudo systemctl restart rke2-agent"
       ```
     - Inspeccionar logs si no levanta:
       ```bash
       ssh -o ProxyJump=n306@192.168.29.25 debian@10.100.29.102 "sudo journalctl -u rke2-agent -n 50 --no-pager"
       ```
  3. **Si el CNI Cilium falló en el nodo:**
     ```bash
     ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=worker-01"
     ```
* **Verificación:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get node worker-01"
  ```
  *(Debe mostrar estado `Ready`).*
* **Tiempo Estimado y Riesgo:** 2 a 4 minutos. Nivel de Riesgo: **Bajo**.

---

### Escenario 5: Caída de un Nodo Control-Plane y Pérdida de Quórum etcd

* **Síntomas:** `kubectl` reporta errores de tipo `etcdserver: leader changed` o timeouts en peticiones al API Server. Un miembro de etcd no responde a comprobaciones de salud.
* **Impacto:** Si se pierde la mayoría estricta en etcd (más de (N-1)/2 nodos caídos), el clúster entra en modo de solo lectura y rechaza operaciones de escritura o creación de pods.
* **Prerrequisitos:** Acceso SSH con permisos de root al nodo superviviente.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl \
    --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
    endpoint health --cluster"
  ```
* **Pasos Numerados:**
  1. Identificar miembros caídos en etcd:
     ```bash
     ssh n306@192.168.29.25 "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl \
       --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
       --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
       --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
       member list"
     ```
  2. Si un nodo de control plane sufrió falla de disco SSD irreversible, removerlo explícitamente del quórum para restablecer la mayoría:
     ```bash
     # Remover miembro muerto usando disaster-recovery.sh:
     ./scripts/ops/disaster-recovery.sh --heal-etcd k8s-cp-02
     ```
     *O manualmente*:
     ```bash
     ssh n306@192.168.29.25 "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl \
       --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
       --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
       --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
       member remove <MEMBER_ID>"
     ```
* **Verificación:**
  ```bash
  ssh n306@192.168.29.25 "sudo ETCDCTL_API=3 /var/lib/rancher/rke2/bin/etcdctl \
    --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
    endpoint health"
  ```
  *(Endpoint reporta `is healthy: successfully committed proposal`).*
* **Tiempo Estimado y Riesgo:** 5 minutos. Nivel de Riesgo: **Alto**.

---

### Escenario 6: Caída Total de Todos los Control-Plane (Corrupción Fatal de etcd)

* **Síntomas:** Todos los comandos de `kubectl` fallan con `The connection to the server 10.100.29.30:6443 was refused`. El servicio `rke2-server` entra en ciclo de reinicios continuos.
* **Impacto:** Inoperabilidad total de la API de Kubernetes. Las cargas existentes pueden seguir ejecutándose en containerd temporalmente, pero sin orquestación ni recuperación.
* **Prerrequisitos:** Respaldo previo de snapshot etcd disponible en `backups/dr_*/etcd/`.
* **Diagnóstico:** Inspeccionar logs del servidor RKE2: `sudo journalctl -u rke2-server -e`.
* **Pasos Numerados:**
  > ⚠️ **PASO DESTRUCTIVO**: Restauración de base de datos etcd desde snapshot. Requiere confirmación explícita.
  1. Detener el servicio RKE2 en el nodo controlador (Nodo 306):
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl stop rke2-server"
     ```
  2. Restaurar el snapshot etcd más reciente:
     ```bash
     # Localizar el último snapshot:
     LATEST_SNAP=$(ls -t backups/dr_*/etcd/*.db | head -n 1)
     scp "${LATEST_SNAP}" n306@192.168.29.25:/tmp/etcd_restore.db

     ssh n306@192.168.29.25 "sudo rke2 server \
       --cluster-reset \
       --cluster-reset-restore-path=/tmp/etcd_restore.db"
     ```
  3. Reiniciar el servicio `rke2-server`:
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl start rke2-server"
     ```
  4. Reiniciar los agentes en los nodos trabajadores para forzar sincronización de TLS:
     ```bash
     ansible k8s_workers -i inventory/lab/hosts.yml -m shell -a "systemctl restart rke2-agent"
     ```
* **Verificación:** `kubectl get nodes` retorna todos los nodos `Ready` y `kubectl get pods -A` lista las aplicaciones recuperadas.
* **Tiempo Estimado y Riesgo:** 10 a 15 minutos. Nivel de Riesgo: **Crítico**.

---

### Escenario 7: Nexus Caído o PostgreSQL Corrupto (ImagePullBackOff Masivo)

* **Síntomas:** Los pods nuevos en Kubernetes quedan atascados en `ImagePullBackOff` o `ErrImagePull`. Peticiones a `http://10.100.29.20:8081` retornan `502 Bad Gateway` o `Connection refused`.
* **Impacto:** Imposibilidad de desplegar nuevos pods o reiniciar contenedores que requieran descargar imágenes desde el registro local `:8082`.
* **Prerrequisitos:** Acceso SSH al Nodo 315 (`io@10.100.29.20`).
* **Diagnóstico:**
  ```bash
  ssh -o ProxyJump=n306@192.168.29.25 io@10.100.29.20 "sudo systemctl status postgresql nexus"
  ssh -o ProxyJump=n306@192.168.29.25 io@10.100.29.20 "tail -n 50 /opt/sonatype-work/nexus3/log/nexus.log"
  ```
* **Pasos Numerados:**
  1. Si PostgreSQL está caído:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 io@10.100.29.20 "sudo systemctl restart postgresql"
     ```
  2. Si PostgreSQL arrancó, reiniciar Sonatype Nexus 3:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 io@10.100.29.20 "sudo systemctl restart nexus"
     ```
  3. Esperar 60 segundos y validar la API de registro Docker:
     ```bash
     curl -sI http://10.100.29.20:8082/v2/
     ```
  4. Si los pods siguen en `ImagePullBackOff`, forzar reintento en K8s:
     ```bash
     ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete pods -A --field-selector status.phase=Failed"
     ```
* **Verificación:** `curl -sI http://10.100.29.20:8081` retorna `HTTP/1.1 200 OK`.
* **Tiempo Estimado y Riesgo:** 4 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 8: Fallo en Cadena PXE/dnsmasq/HTTPBoot (Nodos no arrancan por red)

* **Síntomas:** Los equipos físicos se quedan en pantalla negra con mensaje `PXE-E51: No DHCP or proxyDHCP offers were received` o `TFTP timeout`.
* **Impacto:** Imposibilidad de aprovisionar o reinstalar servidores físicos bare-metal.
* **Prerrequisitos:** Acceso al Nodo 306 (`n306@192.168.29.25`).
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo systemctl status dnsmasq nginx"
  ssh n306@192.168.29.25 "sudo netstat -tulpn | grep -E ':67|:69|:8089'"
  ```
* **Pasos Numerados:**
  1. Si `dnsmasq` está detenido:
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl restart dnsmasq"
     ```
  2. Validar sintaxis de configuración:
     ```bash
     ssh n306@192.168.29.25 "dnsmasq --test"
     ```
  3. Si Nginx HTTPBoot `:8089` está caído:
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl restart nginx"
     ```
  4. Comprobar que los binarios iPXE existan en `/tftpboot`:
     ```bash
     ssh n306@192.168.29.25 "ls -la /tftpboot/undionly.kpxe /tftpboot/ipxe.efi"
     ```
* **Verificación:**
  ```bash
  curl -sI http://10.100.29.30:8089/boot.ipxe | head -n 1
  ```
  *(Retorna `HTTP/1.1 200 OK`).*
* **Tiempo Estimado y Riesgo:** 2 a 3 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 9: Servicios OpenStack Kolla Caídos tras Reinicio Inesperado

* **Síntomas:** `openstack baremetal node list` o `glance image-list` retornan `503 Service Unavailable` o `Failed to connect to 10.100.29.5:5000`. Horizon Web UI no responde en `:80`.
* **Impacto:** Pérdida de capacidades de aprovisionamiento bare-metal y control de máquinas Ironic.
* **Prerrequisitos:** Acceso root a Docker en Nodo 306.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}'"
  ```
* **Pasos Numerados:**
  1. Si MariaDB se detuvo abruptamente (fallo de cluster Galera):
     - Inspeccionar si requiere bootstrap seguro:
       ```bash
       ssh n306@192.168.29.25 "sudo grep safe_to_bootstrap /var/lib/docker/volumes/mariadb/_data/grastate.dat"
       ```
     - Si indica `safe_to_bootstrap: 0`, fijar a `1` y arrancar:
       ```bash
       ssh n306@192.168.29.25 "sudo sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /var/lib/docker/volumes/mariadb/_data/grastate.dat"
       ssh n306@192.168.29.25 "sudo docker start mariadb"
       ```
  2. Levantar RabbitMQ y Keystone:
     ```bash
     ssh n306@192.168.29.25 "sudo docker start rabbitmq keystone"
     ```
  3. Levantar el resto de contenedores Kolla en bloque:
     ```bash
     ssh n306@192.168.29.25 "sudo docker start \$(sudo docker ps -a -q)"
     ```
* **Verificación:**
  ```bash
  ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack --os-auth-url http://10.100.29.30:5000/v3 --os-project-name admin --os-username admin --os-password Admin2025! --os-identity-api-version 3 endpoint list"
  ```
  *(Lista los servicios Keystone, Glance e Ironic activos).*
* **Tiempo Estimado y Riesgo:** 5 a 8 minutos. Nivel de Riesgo: **Alto**.

---

### Escenario 10: Nodo Bare-Metal que no se Aprovisiona o Cloud-Init que Falla

* **Síntomas:** El nodo enciende por WoL, pero en Ironic entra en estado `deploy failed` o `error`. En la consola serie o pantalla se observa bloqueo en `Waiting for cloud-init`.
* **Impacto:** El nodo físico no puede unirse como trabajador al clúster de Kubernetes.
* **Prerrequisitos:** Acceso a la CLI de Ironic en Nodo 306.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack baremetal node show <NODE_NAME> -c last_error -f value"
  ```
* **Pasos Numerados:**
  1. Abortar el intento fallido y devolver el nodo a estado gestionable:
     ```bash
     ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack baremetal node abort <NODE_NAME> || true"
     ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack baremetal node manage <NODE_NAME>"
     ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack baremetal node provide <NODE_NAME>"
     ```
  2. Verificar que la dirección MAC en Ironic coincida exactamente con la tarjeta física:
     ```bash
     ssh n306@192.168.29.25 "sudo docker exec kolla_toolbox openstack baremetal port list --node <NODE_UUID>"
     ```
  3. Relanzar el aprovisionamiento automatizado:
     ```bash
     ./scripts/ops/disaster-recovery.sh --reprovision <NODE_NAME>
     ```
* **Verificación:** El nodo arranca el sistema operativo y responde por SSH con la llave autorizada.
* **Tiempo Estimado y Riesgo:** 4 a 6 minutos. Nivel de Riesgo: **Medio**.


---

### Escenario 11: Cilium / Red de Pods Rota (eBPF degradado, pods sin IP)

* **Síntomas:** Pods nuevos quedan en estado `ContainerCreating` indefinidamente. Error en eventos de Kubernetes: `Failed to create pod sandbox: rpc error: code = Unknown desc = failed to set up sandbox container: networkPlugin cni failed: [Cilium error]`. Comunicación pod-to-pod bloqueada.
* **Impacto:** Falla de conectividad transversal para microservicios y pérdida de métricas en cAdvisor.
* **Prerrequisitos:** Acceso SSH al nodo afectado o al nodo controlador.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=cilium -o wide"
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml logs -n kube-system -l k8s-app=cilium --tail=50"
  ```
* **Pasos Numerados:**
  1. Identificar el agente Cilium que reporta fallos en el nodo afectado:
     ```bash
     ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=cilium"
     ```
  2. Si el mapa BPF en el kernel está corrupto, reiniciar el daemonset de Cilium en ese nodo:
     ```bash
     ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete pod <CILIUM_POD_NAME> -n kube-system"
     ```
  3. Si la interfaz virtual `cilium_host` en el nodo perdió la ruta:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> "sudo ip link set cilium_host up && sudo systemctl restart rke2-agent"
     ```
* **Verificación:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
  ```
  *(Todos los nodos en estado `Ready`).*
* **Tiempo Estimado y Riesgo:** 3 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 12: Stack de Observabilidad Caído (Prometheus, VictoriaMetrics o Grafana)

* **Síntomas:** No cargan los dashboards en `http://192.168.29.25:3000` o reportan errores `HTTP 502 Bad Gateway` / `Status 400`. Prometheus no responde en `:9090`.
* **Impacto:** Pérdida de visibilidad del clúster, pero las aplicaciones y pods continúan operando sin interrupción.
* **Prerrequisitos:** Acceso SSH al Nodo 306.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo systemctl status prometheus grafana-server"
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n observability"
  ```
* **Pasos Numerados:**
  1. Si Prometheus Server `:9090` está detenido en el host 306:
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl restart prometheus"
     ```
  2. Si Grafana Server `:3000` está detenido en el host 306:
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl restart grafana-server"
     ```
  3. Si los pods de VictoriaMetrics (`:30428`) o Loki (`:30100`) están caídos en Kubernetes:
     ```bash
     ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml rollout restart statefulset victoriametrics loki tempo -n observability"
     ```
  4. Si Grafana muestra paneles sin datos, verificar los UIDs de los datasources:
     ```bash
     ssh n306@192.168.29.25 "curl -s http://admin:admin@localhost:3000/api/datasources | jq '.[] | {name: .name, uid: .uid}'"
     ```
     *(Asegurar que existan `Prometheus-BareMetal` y `VictoriaMetrics`).*
* **Verificación:**
  ```bash
  curl -s http://192.168.29.25:9090/-/ready
  curl -s http://192.168.29.25:3000/api/health
  ```
  *(Ambos retornan `200 OK` o `Prometheus Server is Ready`).*
* **Tiempo Estimado y Riesgo:** 2 a 3 minutos. Nivel de Riesgo: **Bajo**.

---

### Escenario 13: Saturación Crítica de Disco (Límite 128 GB SSD)

* **Síntomas:** La alerta `NodeDiskSpaceFillingUp` o `DiskPressure` se activa en Kubernetes. Procesos fallan con `No space left on device`. `df -h /` muestra uso superior al 90%.
* **Impacto:** `kubelet` inicia la expulsión agresiva de pods (`Evicted`), se rechazan escrituras en etcd y se congela el nodo.
* **Prerrequisitos:** Acceso SSH al nodo saturado.
* **Diagnóstico:**
  ```bash
  ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> "df -h / && sudo du -sh /var/lib/* /var/log/* 2>/dev/null | sort -hr | head -n 10"
  ```
* **Pasos Numerados:**
  1. Purgar imágenes de contenedores no utilizadas en containerd:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> \
       "sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock rmi --prune"
     ```
  2. Rotar y truncar logs sobredimensionados de systemd:
     ```bash
     ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> \
       "sudo journalctl --vacuum-size=200M"
     ```
  3. Si es el Nodo 315 (Nexus), purgar blobstores huérfanos o aplicar política de retención:
     ```bash
     # Limpieza de paquetes APT antiguos:
     ssh -o ProxyJump=n306@192.168.29.25 io@10.100.29.20 \
       "find /opt/sonatype-work/nexus3/blobs/ -type f -atime +30 -delete || true"
     ```
  4. Si es el Nodo 306 (Docker / Kolla):
     ```bash
     ssh n306@192.168.29.25 "sudo docker system prune -af --volumes"
     ```
* **Verificación:**
  ```bash
  ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> "df -h /"
  ```
  *(El uso de disco debe reducirse por debajo del 75%).*
* **Prevención:** Configurar tareas cron de mantenimiento diario basadas en [`cloud-init/packer/packer.pkr.hcl`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/cloud-init/packer/packer.pkr.hcl).
* **Tiempo Estimado y Riesgo:** 3 a 5 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 14: Reloj y Sincronización NTP Desfasados (Drift Temporal)

* **Síntomas:** Falla de comunicación entre nodos con errores `certificate has expired or is not yet valid` o caídas en etcd por timeout de latencia en rafts.
* **Impacto:** Bloqueo de autenticación TLS y desintegración del clúster etcd.
* **Prerrequisitos:** Conectividad UDP al puerto 123.
* **Diagnóstico:**
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m shell -a "timedatectl status | grep -E 'synchronized|Time zone'"
  ```
* **Pasos Numerados:**
  1. Verificar el servidor NTP Chrony en el Bastión (`10.100.29.10`):
     ```bash
     ssh aget-ic@10.100.29.10 "sudo systemctl restart chrony && chronyc tracking"
     ```
  2. Forzar sincronización inmediata en toda la flota:
     ```bash
     ansible baremetal -i inventory/lab/hosts.yml -m shell -a "sudo systemctl restart systemd-timesyncd || sudo chronyc makestep"
     ```
* **Verificación:**
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m shell -a "date -u"
  ```
  *(Todas las salidas deben coincidir al mismo segundo).*
* **Tiempo Estimado y Riesgo:** 2 minutos. Nivel de Riesgo: **Bajo**.

---

### Escenario 15: Certificados Internos Expirados (RKE2, Kubelet y Tokens)

* **Síntomas:** `kubectl` reporta `x509: certificate has expired or is not yet valid`. Los agentes RKE2 rechazan conectarse con el servidor.
* **Impacto:** Parálisis en el plano de control de Kubernetes.
* **Prerrequisitos:** Acceso root a los servidores físicos.
* **Diagnóstico:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/rke2 certificate check"
  ```
* **Pasos Numerados:**
  1. Rotar certificados en el servidor de RKE2 (Nodo 306):
     ```bash
     ssh n306@192.168.29.25 "sudo systemctl stop rke2-server"
     ssh n306@192.168.29.25 "sudo rke2 certificate rotate"
     ssh n306@192.168.29.25 "sudo systemctl start rke2-server"
     ```
  2. Regenerar el kubeconfig administrativo:
     ```bash
     ssh n306@192.168.29.25 "sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config"
     ```
  3. Reiniciar los agentes en los nodos de cómputo para recibir los nuevos certificados:
     ```bash
     ansible k8s_workers -i inventory/lab/hosts.yml -m shell -a "systemctl restart rke2-agent"
     ```
  4. Regenerar el token del ServiceAccount de Prometheus si fue invalidado:
     ```bash
     TOKEN=$(ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get secret prometheus-token -n kube-system -o jsonpath='{.data.token}' | base64 -d")
     ssh n306@192.168.29.25 "echo -n '$TOKEN' | sudo tee /etc/prometheus/tokens/k8s_token > /dev/null && sudo systemctl reload-or-restart prometheus"
     ```
* **Verificación:**
  ```bash
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
  ```
* **Tiempo Estimado y Riesgo:** 5 minutos. Nivel de Riesgo: **Alto**.

---

### Escenario 16: Pérdida de Conectividad de Red o Fallo en Puerto del Switch

* **Síntomas:** Un servidor físico deja de responder repentinamente por red; los LEDs del puerto RJ45 en el switch están apagados o parpadeando erráticamente.
* **Impacto:** Aislamiento del nodo físico afectado del clúster.
* **Prerrequisitos:** Acceso físico al rack o switch.
* **Diagnóstico:**
  1. Inspección visual de la interfaz del switch correspondiente.
  2. Comprobar negociación MII desde el sistema operativo si se tiene acceso Out-of-Band:
     ```bash
     sudo ethtool enp2s0
     ```
     *(Verificar `Link detected: yes` y `Speed: 1000Mb/s`).*
* **Pasos Numerados:**
  1. Cambiar el cable de red UTP Cat6 por uno certificado.
  2. Si el puerto del switch está dañado, conectar el cable a un puerto libre.
  3. Si la interfaz se encuentra administrativamente caída en Debian:
     ```bash
     sudo ip link set enp2s0 up
     sudo systemctl restart systemd-networkd
     ```
* **Verificación:** `ping -c 3 10.100.29.30` retorna 0% packet loss.
* **Tiempo Estimado y Riesgo:** 5 minutos. Nivel de Riesgo: **Bajo**.

---

### Escenario 17: Falla de un Disco SSD o Reemplazo de Hardware Físico

* **Síntomas:** Errores de I/O en logs (`I/O error, dev sda, sector ...`). La máquina entra en modo `Read-only file system` o BIOS reporta `No bootable device found`.
* **Impacto:** Pérdida permanente del nodo de cómputo físico hasta su sustitución.
* **Prerrequisitos:** Unidad SSD nueva instalada en el chasis Dell OptiPlex (o equipo de reemplazo).
* **Diagnóstico:** Comprobar estado SMART con `sudo smartctl -a /dev/sda` si responde.
* **Pasos Numerados:**
  > ⚠️ **PASO DESTRUCTIVO**: Sobrescribe por red el nuevo disco SSD mediante iPXE y Wake-on-LAN.
  1. Si se sustituyó el equipo completo con una placa base distinta (nueva dirección MAC):
     ```bash
     ./scripts/ops/disaster-recovery.sh --reprovision <NOMBRE_NODO> --new-mac <NUEVA_MAC>
     ```
  2. Si solo se cambió el SSD manteniendo el mismo chasis Dell OptiPlex:
     ```bash
     ./scripts/ops/disaster-recovery.sh --reprovision <NOMBRE_NODO>
     ```
  3. El orquestador enviará el paquete WoL, flasheará la imagen Debian 13 en el disco nuevo mediante Ironic/Glance y lo reincorporará automáticamente al clúster de Kubernetes vía Ansible.
* **Verificación:**
  ```bash
  ssh -o ProxyJump=n306@192.168.29.25 debian@<IP_NODO> "df -h / && uptime"
  ssh n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
  ```
  *(El nodo reemplazado aparece en estado `Ready`).*
* **Tiempo Estimado y Riesgo:** 6 a 8 minutos. Nivel de Riesgo: **Alto**.

---

### Escenario 18: Credenciales Comprometidas o Perdidas (Rotación de Secretos)

* **Síntomas:** Fuga de claves SSH, compromiso de credenciales administrativas o rotación periódica obligatoria de seguridad.
* **Impacto:** Ventana controlada de cambio de llaves criptográficas y tokens de APIs.
* **Prerrequisitos:** Acceso administrativo mediante llave SSH actual o por consola local.
* **Pasos Numerados:**
  1. **Rotación de Llaves SSH de la Flota:**
     - Ejecutar el runbook de rotación:
       ```bash
       # Generar nuevo par ED25519 y propagar:
       ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new -N ""
       ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml \
         -e "new_public_key='$(cat ~/.ssh/id_ed25519_new.pub)'"
       ```
  2. **Rotación de Contraseñas de OpenStack Kolla:**
     - En el entorno virtual de Kolla:
       ```bash
       source /home/n306/.venv-kolla/bin/activate
       kolla-genpwd -p /etc/kolla/passwords.yml
       kolla-ansible -i /etc/kolla/inventory/multinode reconfigure
       ```
  3. **Rotación del Token del Clúster RKE2:**
     - Actualizar `token` en `/etc/rancher/rke2/config.yaml` en Nodo 306 y reiniciar `rke2-server`.
     - Actualizar en cada worker `/etc/rancher/rke2/config.yaml` y reiniciar `rke2-agent`.
* **Verificación:**
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m ping --private-key=~/.ssh/id_ed25519_new
  ```
* **Tiempo Estimado y Riesgo:** 10 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 19: Actualización Fallida de Componentes (Rollback Operativo)

* **Síntomas:** Una actualización de versión de Kubernetes, CNI Cilium o del kernel Debian genera inestabilidad, Kernel Panics o fallos de CNI en los nodos.
* **Impacto:** Imposibilidad de programar pods o caídas de nodos de cómputo.
* **Prerrequisitos:** Puntos de restauración y playbooks de rollback disponibles.
* **Pasos Numerados:**
  1. Si falló la capa de observabilidad o agentes:
     ```bash
     ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/99_rollback.yml
     ```
  2. Si falló una actualización de versión de Kubernetes en un worker:
     - Bloquear versión del paquete en Debian:
       ```bash
       sudo apt-mark hold rke2-agent rke2-server
       ```
     - Degradar binario a la versión previa:
       ```bash
       sudo curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="v1.30.2+rke2r1" sh -
       sudo systemctl restart rke2-agent
       ```
* **Verificación:**
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m shell -a "rke2 --version"
  ```
* **Tiempo Estimado y Riesgo:** 6 minutos. Nivel de Riesgo: **Medio**.

---

### Escenario 20: Restauración Completa de la Infraestructura desde Backup

* **Síntomas:** Desastre mayor con pérdida de bases de datos de OpenStack MariaDB y base de datos etcd de Kubernetes simultáneamente.
* **Impacto:** Pérdida del estado de las cargas y registros de aprovisionamiento.
* **Prerrequisitos:** Respaldo completo disponible en `backups/dr_*/`.
* **Pasos Numerados:**
  > ⚠️ **PASO DESTRUCTIVO**: Reescritura total de bases de datos desde copias de seguridad previas.
  1. **Restaurar Base de Datos OpenStack MariaDB:**
     ```bash
     # Localizar volcado SQL:
     LATEST_SQL=$(ls -t backups/dr_*/openstack/*.sql.gz | head -n 1)
     scp "${LATEST_SQL}" n306@192.168.29.25:/tmp/mariadb_restore.sql.gz

     ssh n306@192.168.29.25 "gunzip -c /tmp/mariadb_restore.sql.gz | sudo docker exec -i mariadb mysql -u root -pAdmin2025!"
     ssh n306@192.168.29.25 "sudo docker restart mariadb keystone glance_api ironic_api"
     ```
  2. **Restaurar Base de Datos etcd de Kubernetes:**
     ```bash
     LATEST_SNAP=$(ls -t backups/dr_*/etcd/*.db | head -n 1)
     scp "${LATEST_SNAP}" n306@192.168.29.25:/tmp/etcd_restore.db

     ssh n306@192.168.29.25 "sudo systemctl stop rke2-server"
     ssh n306@192.168.29.25 "sudo rke2 server --cluster-reset --cluster-reset-restore-path=/tmp/etcd_restore.db"
     ssh n306@192.168.29.25 "sudo systemctl start rke2-server"
     ```
  3. **Reconectar Workers:**
     ```bash
     ansible k8s_workers -i inventory/lab/hosts.yml -m shell -a "systemctl restart rke2-agent"
     ```
* **Verificación:**
  ```bash
  ./scripts/diagnostics/healthcheck.sh
  ```
  *(14/14 comprobaciones en verde).*
* **Tiempo Estimado y Riesgo:** 15 a 20 minutos. Nivel de Riesgo: **Crítico**.

---

### Escenario 21: Reconstrucción Total del Laboratorio desde Cero (Desastre Mayor)

* **Síntomas:** Pérdida total de discos SSD en las 8 máquinas o sustitución completa de hardware por incidente de inundación, sobretensión o robo.
* **Impacto:** Infraestructura en estado "Cold-Metal" (sin sistemas operativos instalados).
* **Prerrequisitos:** Repositorio Git clonado en la laptop de administración, switch de laboratorio conectado.
* **Pasos Numerados:**
  > ⚠️ **PASO DESTRUCTIVO TOTAL**: Despliegue de raíz de toda la flota bare-metal.
  1. Conectar la laptop mediante cable de red o WiFi al switch del laboratorio.
  2. Instalar manualmente el sistema operativo base Debian 13 en el Nodo 306 mediante memoria USB de rescate.
  3. Ejecutar el despliegue canónico de la Fase 00 a la Fase 90:
     ```bash
     make setup
     ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml
     ```
  4. Levantar la secuencia global:
     ```bash
     ./scripts/ops/levantar-todo.sh
     ```
* **Verificación:** Ejecutar `./scripts/diagnostics/healthcheck.sh` y comprobar que Grafana grafique los 8 nodos físicos y todos los contenedores en `http://192.168.29.25:3000`.
* **Tiempo Estimado y Riesgo:** 45 a 60 minutos. Nivel de Riesgo: **Crítico**.

---

# CAPÍTULOS TRANSVERSALES

## A. Tarjeta Rápida (Runsheet 3 a.m.): Apagón Total en 10 Pasos

> [!CRITICAL]
> **OBJETIVO**: Devolver la flota de 8 nodos físicos y las cargas de Kubernetes a estado `HEALTHY` en menos de **20 minutos**. Siga estrictamente la secuencia; no invierta el orden.

| Paso | Capa Tecnológica | Acción Operativa Inmediata | Host de Ejecución | Comando Exacto | Criterio de Éxito |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | **Eléctrica/L2** | Encender switch físico de laboratorio y verificar luces de enlace. | Físico | Inspección visual de LEDs frontales | Todos los puertos activos en verde (1 Gbps) |
| **2** | **Acceso/PXE** | Encender Nodo 306 (`pxe-controller`). Enlace WiFi/LAN de gestión. | Físico / Botón | Pulsar botón frontal Dell OptiPlex | Ping responde en `192.168.29.25` y `10.100.29.30` |
| **3** | **Enrutamiento** | Levantar servicios de red en Nodo 306 (DHCP dnsmasq, TFTP, Nginx). | `# en: pxe-controller` | `sudo systemctl restart dnsmasq nginx` | `systemctl is-active dnsmasq nginx` -> `active` |
| **4** | **Bastión** | Encender Nodo 314 (`bastion`) vía WoL o botón y validar SSH. | `# en: pxe-controller` | `wakeonlan 64:00:6a:2a:60:62 && sleep 20` | `ssh -o ConnectTimeout=3 aget-ic@10.100.29.10 "uptime"` |
| **5** | **Repositorios** | Encender Nodo 315 (`nexus-repo`) y arrancar PostgreSQL + Nexus. | `# en: pxe-controller` | `wakeonlan 64:00:6a:2a:5f:99 && sleep 30` | `curl -sI http://10.100.29.20:8081 \| head -n 1` -> `HTTP/1.1 200` |
| **6** | **OpenStack** | Reactivar contenedores Kolla-Ansible en Nodo 306. | `# en: pxe-controller` | `sudo docker start $(sudo docker ps -a -q)` | `sudo docker ps --filter "status=running" \| wc -l` >= 10 |
| **7** | **K8s CP Leader** | Levantar plano de control RKE2 (`cp-01`) en Nodo 306. | `# en: pxe-controller` | `sudo systemctl restart rke2-server` | `systemctl is-active rke2-server` -> `active` |
| **8** | **K8s Workers** | Despertar nodos trabajadores por Wake-on-LAN. | `# en: pxe-controller` | `for m in 64:00:6a:2a:5f:f9 64:00:6a:2a:60:63 64:00:6a:2a:2c:75 64:00:6a:2a:62:a4 64:00:6a:2a:2f:cb; do wakeonlan $m; done` | Los 6 nodos responden a ping en `10.100.29.x` |
| **9** | **Monitoreo** | Reactivar Prometheus `:9090` y Grafana `:3000` en Nodo 306. | `# en: pxe-controller` | `sudo systemctl restart prometheus grafana-server` | `curl -s http://localhost:9090/-/ready` -> `Ready` |
| **10**| **Validación** | Ejecutar validación integral end-to-end desde laptop. | `# en: laptop` | `make health` (o `./scripts/diagnostics/healthcheck.sh`) | 14/14 comprobaciones en verde (`HEALTHY`) |

---

## B. Árbol de Decisión de Diagnóstico de Incidentes (Mermaid)

```mermaid
flowchart TD
    START["🚨 Incidente Detectado\n¿Qué síntoma presenta el sistema?"] --> Q1{"¿Responde a ping el Nodo 306\n(192.168.29.25 o 10.100.29.30)?"}
    
    Q1 -- No --> A1["Fallo Eléctrico o Switch L2\n1. Verificar PDUs y LEDs del switch\n2. Presionar botón físico en Nodo 306\n3. Ver Escenario 1"]
    Q1 -- Sí --> Q2{"¿Puedo conectar por SSH a los nodos\nvía Bastión (10.100.29.10)?"}
    
    Q2 -- No --> A2["Fallo en Bastión (Nodo 314)\n1. Conectar vía WiFi: ssh n306@192.168.29.25\n2. Comprobar nftables y squid en 314\n3. Ver Escenario 3"]
    Q2 -- Sí --> Q3{"¿Responde la API de Kubernetes\n(kubectl get nodes)?"}
    
    Q3 -- No --> A3["Fallo en RKE2 Server o etcd\n1. En 306: sudo systemctl restart rke2-server\n2. Comprobar salud etcdctl endpoint health\n3. Ver Escenarios 5 y 6"]
    Q3 -- Sí --> Q4{"¿Hay pods en CrashLoopBackOff\no ImagePullBackOff?"}
    
    Q4 -- Sí --> A4["Fallo en Nexus o CNI Cilium\n1. En 315: systemctl status nexus\n2. En 306: kubectl get pods -n kube-system\n3. Ver Escenarios 7 y 11"]
    Q4 -- No --> Q5{"¿Grafana muestra paneles vacíos\no errores de datasource?"}
    
    Q5 -- Sí --> A5["Fallo en Datasources / Prometheus\n1. Comprobar 17 targets en :9090/targets\n2. Verificar UIDs en Grafana provisioning\n3. Ver Escenario 12"]
    Q5 -- No --> OK["✅ Sistema 100% Operativo y Saludable"]
```

---

## C. Matriz de Dependencias Cruzadas de Servicios

| Servicio | Depende Directamente De | Si Falla el Servicio Padre, el Síntoma Es: | Comando de Verificación de Salud |
| :--- | :--- | :--- | :--- |
| **DHCP / PXE (`dnsmasq`)** | Interfaz `enp2s0` física activa | Nodos físicos no obtienen IP ni arrancan por red | `sudo systemctl is-active dnsmasq` |
| **Proxy Squid (`:3128`)** | Interfaz WAN `enp2s0` en Bastión | Nodos no pueden descargar paquetes Debian de Internet | `curl -x http://10.100.29.10:3128 -I http://deb.debian.org` |
| **Sonatype Nexus (`:8081`)**| PostgreSQL 16 en localhost | Nexus entra en bucle de inicialización o `502 Bad Gateway` | `sudo systemctl is-active postgresql nexus` |
| **OpenStack Ironic** | MariaDB, RabbitMQ, Keystone | Errores `503 Service Unavailable` en endpoints Ironic | `openstack baremetal node list` |
| **RKE2 Server (`cp-01`)** | Base de datos etcd local, puerto `6443` | `kubectl` retorna connection refused | `sudo systemctl is-active rke2-server` |
| **RKE2 Agent (Workers)** | Supervisor RKE2 (`10.100.29.30:9345`) | Nodos trabajadores pasan a estado `NotReady` | `sudo systemctl is-active rke2-agent` |
| **Cilium CNI (eBPF)** | Módulos del kernel `br_netfilter`, `overlay` | Pods no obtienen IP del CIDR `10.42.0.0/16` | `cilium status` o `kubectl get pods -n kube-system` |
| **Prometheus (`:9090`)** | Node Exporters (`:9100`), Kubelets (`:10250`) | Targets en estado `DOWN` o `UNKNOWN` en `/targets` | `curl -s http://localhost:9090/api/v1/targets` |
| **VictoriaMetrics (`:30428`)**| StorageClass `local-path`, Prometheus write | Grafana devuelve paneles vacíos de largo plazo | `curl -s http://10.100.29.30:30428/health` |
| **Grafana Server (`:3000`)**| Prometheus `:9090`, VictoriaMetrics `:30428` | Error `Bad Gateway` o paneles sin datos | `curl -s http://localhost:3000/api/health` |

---

## D. Tabla Canónica de Puertos, Interfaces y Unidades systemd

| Nodo / Host | Servicio del Sistema | Unidad systemd | Puerto / Protocolo | Interfaz de Escucha |
| :--- | :--- | :--- | :---: | :--- |
| **Nodo 314 (`bastion`)** | Servidor OpenSSH | `ssh.service` | `22/TCP` | `0.0.0.0` (WAN y LAN) |
| **Nodo 314 (`bastion`)** | Proxy Squid Egress | `squid.service` | `3128/TCP` | `10.100.29.10` (LAN privada) |
| **Nodo 314 (`bastion`)** | Firewall Perimetral | `nftables.service` | Filtrado L3/L4 | Tablas en kernel Linux |
| **Nodo 315 (`nexus-repo`)**| Base de Datos PostgreSQL 16 | `postgresql.service` | `5432/TCP` | `127.0.0.1` |
| **Nodo 315 (`nexus-repo`)**| Sonatype Nexus 3 OSS | `nexus.service` | `8081, 8082, 8083` | `0.0.0.0` |
| **Nodo 306 (`pxe-controller`)**| DHCP y TFTP embebido | `dnsmasq.service` | `67/UDP, 69/UDP` | `enp2s0` (`10.100.29.30`) |
| **Nodo 306 (`pxe-controller`)**| Servidor HTTPBoot Nginx | `nginx.service` | `8089/TCP` | `0.0.0.0` |
| **Nodo 306 (`pxe-controller`)**| OpenStack MariaDB | Docker: `mariadb` | `3306/TCP` | `10.100.29.5` / `10.100.29.30` |
| **Nodo 306 (`pxe-controller`)**| OpenStack Keystone | Docker: `keystone` | `5000/TCP` | `10.100.29.5` / `10.100.29.30` |
| **Nodo 306 (`pxe-controller`)**| OpenStack Glance API | Docker: `glance_api` | `9292/TCP` | `10.100.29.5` / `10.100.29.30` |
| **Nodo 306 (`pxe-controller`)**| OpenStack Ironic API | Docker: `ironic_api` | `6385/TCP` | `10.100.29.5` / `10.100.29.30` |
| **Nodo 306 (`pxe-controller`)**| OpenStack Horizon Dashboard | Docker: `horizon` | `80/TCP` | `10.100.29.30` |
| **Nodo 306 (`cp-01`)** | RKE2 Server (API & Supervisor)| `rke2-server.service` | `6443, 9345/TCP` | `0.0.0.0` |
| **Todos los K8s Workers** | RKE2 Agent (Kubelet Engine) | `rke2-agent.service` | `10250/TCP` | `0.0.0.0` |
| **Nodo 306 (`pxe-controller`)**| Prometheus Server | `prometheus.service` | `9090/TCP` | `0.0.0.0` |
| **Nodo 306 (`pxe-controller`)**| Grafana Server | `grafana-server.service`| `3000/TCP` | `0.0.0.0` |
| **Los 8 Nodos Físicos** | Node Exporter Hardware | `node_exporter.service` | `9100/TCP` | `0.0.0.0` |
| **K8s Service NodePort** | VictoriaMetrics TSDB | K8s: `victoriametrics` | `30428/TCP` | Toda la red de nodos K8s |
| **K8s Service NodePort** | Loki Ingesta de Logs | K8s: `loki` | `30100/TCP` | Toda la red de nodos K8s |
| **K8s Service NodePort** | Tempo Recolección Trazas | K8s: `tempo` | `30200/TCP` | Toda la red de nodos K8s |

---

## E. Directorio Central de Logs por Componente

| Componente del Sistema | Host Físico | Ubicación del Archivo de Log / Comando de Inspección |
| :--- | :--- | :--- |
| **Proxy Squid Egress** | `10.100.29.10` | `/var/log/squid/access.log` y `/var/log/squid/cache.log` |
| **Firewall nftables** | `10.100.29.10` | `sudo dmesg \| grep nftables` o `/var/log/messages` |
| **Sonatype Nexus 3** | `10.100.29.20` | `/opt/sonatype-work/nexus3/log/nexus.log` |
| **PostgreSQL 16** | `10.100.29.20` | `/var/log/postgresql/postgresql-16-main.log` |
| **dnsmasq (DHCP/TFTP)** | `10.100.29.30` | `sudo journalctl -u dnsmasq -f` |
| **Nginx HTTPBoot** | `10.100.29.30` | `/var/log/nginx/access.log` y `/var/log/nginx/error.log` |
| **OpenStack Kolla Docker** | `10.100.29.30` | `sudo docker logs <NOMBRE_CONTENEDOR> --tail=100` |
| **RKE2 Server (`cp-01`)** | `10.100.29.30` | `sudo journalctl -u rke2-server -f` |
| **RKE2 Agents (Workers)** | Workers K8s | `sudo journalctl -u rke2-agent -f` |
| **CNI Cilium (eBPF)** | Workers K8s | `sudo kubectl logs -n kube-system -l k8s-app=cilium -c cilium-agent` |
| **Prometheus Server** | `10.100.29.30` | `sudo journalctl -u prometheus -f` |
| **Grafana Server** | `10.100.29.30` | `/var/log/grafana/grafana.log` |
| **VictoriaMetrics TSDB** | En Pod K8s | `sudo kubectl logs -n observability statefulset/victoriametrics` |
| **Loki Logs** | En Pod K8s | `sudo kubectl logs -n observability statefulset/loki` |

---

## F. Matriz de Errores Comunes, Causas Raíz y Soluciones Inmediatas

| Síntoma de Error | Causa Raíz Detectada | Solución Operativa Inmediata |
| :--- | :--- | :--- |
| `dial tcp 127.0.0.1:6443: connect: connection refused` | Se ejecutó `kubectl` en un worker en vez del controlador, o `rke2-server` está detenido | Conectarse al Nodo 306 (`10.100.29.30`) y ejecutar `sudo systemctl restart rke2-server`. |
| `stat /etc/rancher/rke2/rke2.yaml: no such file or directory` | El archivo de kubeconfig administrativo solo existe en el nodo control-plane (`cp-01`) | Usar `--kubeconfig /etc/rancher/rke2/rke2.yaml` únicamente en el Nodo 306 o copiar a la laptop. |
| `PXE-E51: No DHCP or proxyDHCP offers were received` | `dnsmasq` detenido o cable de red desconectado | Ejecutar `sudo systemctl restart dnsmasq` en Nodo 306 y revisar LEDs del switch. |
| `ImagePullBackOff` masivo en Kubernetes | Sonatype Nexus `:8082` inaccesible o PostgreSQL caído en Nodo 315 | En Nodo 315: `sudo systemctl restart postgresql nexus` y esperar 60 segundos. |
| Paneles de Grafana con "No Data" | Discrepancia entre `job_name` en Prometheus y query en el dashboard | Alinear job en `prometheus.yml` a `baremetal-nodes` y forzar UIDs estáticos. |
| `VictoriaMetrics connection refused en :30428` | StatefulSet de VictoriaMetrics no desplegado o CNI sin NodePort | Desplegar [`01_backends.yaml`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/kubernetes/observability/backends/01_backends.yaml) con NodePort `30428` y StorageClass `local-path`. |
| `x509: certificate signed by unknown authority` en cAdvisor | Prometheus raspando sin certificado o sin token RBAC | Inyectar token en `/etc/prometheus/tokens/k8s_token` con `insecure_skip_verify: true`. |
| Nodo físico no enciende por Wake-on-LAN | `Deep Sleep Control` habilitado en la BIOS del Dell OptiPlex | Entrar a BIOS con `F2` -> Power Management -> desactivar `Deep Sleep Control`. |
| `MariaDB WSREP has not yet prepared node for application use` | Bloqueo en cluster Galera por apagón brusco | En `grastate.dat` cambiar `safe_to_bootstrap: 0` a `1` y reiniciar contenedor `mariadb`. |

---

## G. Política de Respaldos, Retención y Procedimiento de Restauración

### Componentes Incluidos en la Política de Respaldos
1. **OpenStack MariaDB**: Volcado de todas las bases de datos relacionales (`keystone`, `glance`, `ironic`). Frecuencia: Diaria.
2. **Configuraciones Kolla**: Archivo comprimido `/etc/kolla/` con `passwords.yml`, certificados y globals. Frecuencia: Tras cada cambio.
3. **Kubernetes etcd**: Snapshot binario de la base de datos de objetos y estados de K8s. Frecuencia: Diaria.
4. **Nexus Repositories**: Metadata y configuraciones de blobstores. Frecuencia: Semanal.

### Retención Canónica
* **Copias Locales en Nodo 306**: Últimos 7 días en `/var/backups/infra/`.
* **Copias en Laptop / Almacenamiento Seguro**: Últimos 30 días en `backups/dr_$(date +%Y%m%d)/`.

### Ejecución de Respaldo Automatizado
```bash
./scripts/ops/disaster-recovery.sh --backup-all
```

---

## H. Seguridad, Hardening y Rotación Criptográfica de Secretos

1. **Aislamiento de Red L2**: La subred `10.100.29.0/24` no posee enrutamiento directo desde la red de oficina. Todo tráfico externo debe atravesar obligatoriamente el Bastión con inspección de reglas `nftables`.
2. **Principio de Mínimo Privilegio**: Acceso SSH restringido exclusivamente mediante llaves ED25519; autenticación por contraseña deshabilitada (`PasswordAuthentication no`).
3. **Protección de Puertos Administrativos**: Horizon `:80`, Prometheus `:9090` y Grafana `:3000` solo escuchan en la red interna o se acceden mediante túneles SSH cifrados (`./scripts/client/tunnels.sh`).
4. **Prohibición Estricta**: No almacenar claves privadas ni volcados de `passwords.yml` sin cifrar en repositorios públicos.

---

## I. Procedimiento de Acceso de Emergencia (Out-of-Band)

Si el Bastión (`10.100.29.10`) se encuentra completamente inoperativo o la red corporativa pierde el uplink:

1. **Conexión Física al Laboratorio**: Conéctese al SSID WiFi de mantenimiento del laboratorio.
2. **Acceso al Controlador PXE**:
   ```bash
   ssh -i ansible/keys/cluster_key n306@192.168.29.25
   ```
3. **Acceso Directo a los Nodos Internos desde el Controlador**:
   ```bash
   # Salto directo sin pasar por el Bastión:
   ssh debian@10.100.29.101
   ssh debian@10.100.29.102
   ssh io@10.100.29.20
   ```
4. **Apertura de Túneles de Emergencia desde la Laptop**:
   ```bash
   # Túnel hacia Grafana por WiFi:
   ssh -L 3000:localhost:3000 n306@192.168.29.25
   ```

---

## J. Directorio de Contactos, Glosario y Matriz de Escalamiento

### Directorio de Contactos Técnicos y Escalamiento

| Nivel de Soporte | Rol Técnico | Especialidad / Componentes | Canal de Contacto |
| :--- | :--- | :--- | :--- |
| **Nivel 1 (Operaciones)** | Guardia SRE / Turno On-Call | Fallo de nodos físicos, reinicio de servicios, WoL | Canal Slack `#infra-alerts` |
| **Nivel 2 (Plataforma)** | Ingeniero DevOps Senior | Kubernetes RKE2, Cilium eBPF, OpenStack Ironic | Canal Slack `#cloud-platform` |
| **Nivel 3 (Arquitectura)**| Staff SRE / Principal Architect | Pérdida de quórum etcd, desastre mayor, restauración DR | Escalado telefónico PagerDuty Tier-1 |

### Glosario Canónico de Términos

* **IPA (Ironic Python Agent)**: Sistema operativo mínimo efímero en RAM que ejecuta la inspección de hardware y escritura de imágenes en el disco SSD físico vía iPXE.
* **ConfigDrive (config-2)**: Partición ISO 9660 / VFAT inyectada en el servidor que contiene metadatos de red y scripts de inicialización `cloud-init`.
* **eBPF (Extended Berkeley Packet Filter)**: Tecnología del kernel Linux empleada por Cilium para sustituir `kube-proxy` y enrutar paquetes a nivel de socket sin sobrecarga de iptables.
* **Kolla-Ansible**: Sistema oficial de OpenStack para desplegar servicios de infraestructura virtualizados en contenedores Docker de alta disponibilidad.
* **ProxyJump**: Mecanismo de OpenSSH que permite encadenar conexiones pasando a través de un bastión intermedio sin exponer llaves privadas en el servidor de salto.
* **WoL (Wake-on-LAN)**: Protocolo estándar por el cual una tarjeta de red en reposo enciende el computador al recibir un "paquete mágico" con su dirección MAC repetida 16 veces.

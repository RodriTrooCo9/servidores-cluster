# Control de Tareas y Estado de Infraestructura (`todo.md`)

> **Proyecto**: Plataforma Bare-Metal Edge con 8 Servidores Dell OptiPlex 3020M  
> **Sistema Operativo**: Debian GNU/Linux 13 (Trixie)  
> **Segmento de Red**: Subred Privada L2 `10.100.29.0/24` (Aislada de la Red de Oficina)  
> **Última Auditoría**: 14 de Octubre de 2026  

---

## 📌 Estado General de Fases del Proyecto

| Fase | Tarea / Módulo | Script Asociado | Documentación | Estado |
| :---: | :--- | :--- | :--- | :---: |
| **0** | Preflight y Validación de Entorno | [`scripts/00-preflight.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/00-preflight.sh) | [`docs/env.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/env.md) | ✅ COMPLETADO |
| **1** | Base de Servidores (Debian 13, NTP, Sudo) | [`scripts/01-base-servidores.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/01-base-servidores.sh) | [`docs/estructura.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/estructura.md) | ✅ COMPLETADO |
| **2** | Bastión SSH, Proxy y Hardening Perimetral | [`scripts/02-bastion.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/02-bastion.sh) | [`docs/runbooks/blindaje-red-oficina.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/runbooks/blindaje-red-oficina.md) | ✅ COMPLETADO |
| **3** | Repositorio Central Nexus 3 OSS + PostgreSQL 17 | [`scripts/03-nexus.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/03-nexus.sh) | [`credenciales.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/credenciales.md) | ✅ COMPLETADO |
| **4** | Redirección de Clientes APT a Nexus Local | [`scripts/04-clientes-nexus.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/04-clientes-nexus.sh) | [`docs/estructura.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/estructura.md) | ✅ COMPLETADO |
| **5** | **Configurar el arranque por red (entrada por red)** | [`scripts/05-pxe-dhcp-tftp.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/05-pxe-dhcp-tftp.sh) | [`docs/openstack/Configurar el arranque por red.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/Configurar%20el%20arranque%20por%20red.md) | 🎯 **AUDITADO Y APROBADO** |
| **6** | OpenStack Glance & Ironic Standalone | [`scripts/06-openstack-glance-bifrost.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/06-openstack-glance-bifrost.sh) | [`docs/openstack/OpenStack Glance, Formatos de Disco e Ironic Bare-Metal.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/OpenStack%20Glance,%20Formatos%20de%20Disco%20e%20Ironic%20Bare-Metal.md) | 🎯 **AUDITADO (8 Nodos Enrolados + Imagen Dorada)** |
| **7** | Cloud-Init NoCloud HTTP y ConfigDrive | [`scripts/07-cloud-init.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/07-cloud-init.sh) | [`docs/estructura.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/estructura.md) | 🎯 **AUDITADO (8 Endpoints HTTP 200 + ISOs)** |
| **8** | Clúster Kubernetes RKE2 HA + Cilium CNI | [`scripts/08-kubernetes.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/08-kubernetes.sh) | [`docs/estructura.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/estructura.md) | 🎯 **AUDITADO (7 Nodos Ready + Cilium eBPF)** |
| **9** | Verificación Integral de Red y Cómputo | [`scripts/09-verificacion.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/09-verificacion.sh) | [`docs/estructura.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/estructura.md) | ✅ COMPLETADO |
| **10**| Suite de Monitoreo (Prometheus, Grafana, Node Exp) | [`scripts/10-monitoreo.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/10-monitoreo.sh) | [`docs/monitoreo_prometheus_grafana.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/monitoreo_prometheus_grafana.md) | ✅ COMPLETADO |

---

## 🎯 Auditoría Detallada: Configurar el Arranque por Red (Fase 5)

> **Documento Maestro de la Auditoría**: Consulte la documentación exhaustiva en [**`docs/openstack/Configurar el arranque por red.md`**](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/Configurar%20el%20arranque%20por%20red.md).

### 1. Resumen de lo Planificado vs lo Implementado

- [x] **Investigación Teórica de la Pila PXE**:
  - Evaluación del estándar Intel WfM 2.0 y RFC 4578.
  - Mapeo de señalización de red DHCP (Opciones 53, 54, 60, 66, 67, 93), TFTP y HTTP.
- [x] **Solución al Cuello de Botella de TFTP**:
  - Se sustituyó la transferencia completa por TFTP (limitada a 2-5 MB/s) por **Chainloading**: TFTP descarga únicamente el binario ligero `ipxe.efi` (~1 MB en < 1s), y este transfiere el kernel y el ramdisk a **1 Gbps vía HTTP Nginx en el puerto `:8089`**.
- [x] **Investigación de Hardware Dell OptiPlex 3020M Micro**:
  - Identificación de controladora de red Realtek RTL8111G/RTL8168.
  - Resolución de opción oculta en BIOS A05: `Integrated NIC` debe estar en **`Enabled w/PXE`** (si está en `Enabled`, la BIOS oculta el arranque por red).
  - Configuración obligatoria: `SATA: AHCI`, `Secure Boot: Disabled`, `Deep Sleep: Disabled`, `AC Recovery: Power On`.
- [x] **Mitigación del Bucle de Reinstalación Infinito**:
  - Al no contar con BMC/IPMI dedicado para manipular la secuencia de arranque de forma remota, se estableció como estándar mantener el SSD local como boot #1 permanente y pulsar **`F12`** temporalmente seleccionando `UEFI: IP4 Realtek...` exclusivamente durante el aprovisionamiento.
- [x] **Blindaje Perimetral Anti-Rogue DHCP**:
  - **Evidencia Forense**: Se detectaron paquetes de smartphones (`karen`, `realme-C71`) y laptops en la red de pruebas.
  - **Hardening Implementado**: `dnsmasq` amarrado a la interfaz física `enp2s0` con `bind-interfaces` y cortafuegos L2:
    ```ini
    dhcp-ignore=tag:!known
    dhcp-mac=set:known,64:00:6a:2a:*:*:*
    ```
  - Cualquier solicitud DHCP de equipos ajenos a los 8 mini PCs del clúster es descartada en silencio sin emitir ofertas.
- [x] **Migración a Subred L2 Aislada `10.100.29.0/24`**:
  - Reservas estáticas de IP por dirección MAC física para los 8 servidores leídas dinámicamente de [`config/nodes.csv`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/config/nodes.csv).
  - Rango efímero `10.100.29.50 - 10.100.29.99` para enrolamiento e inspección de nuevos nodos.
- [x] **Automatización en Repositorio**:
  - Script de instalación: [`scripts/05-pxe-dhcp-tftp.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/05-pxe-dhcp-tftp.sh)
  - Script de reversión: [`rollback/rollback-05-pxe-dhcp-tftp.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/rollback/rollback-05-pxe-dhcp-tftp.sh)
  - Script de rescate automático: [`scripts/bootstrap_node.py`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/bootstrap_node.py)
  - Auditoría de puertos y sockets: [`scripts/healthcheck.sh`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/healthcheck.sh)
- [x] **Optimización de Entrada por Red con iPXE Custom (`github.com/ipxe/ipxe`)**:
  - Plan Maestro de Instalación: [`docs/openstack/plan_maestro_instalacion_ipxe.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/plan_maestro_instalacion_ipxe.md)
  - Caso Hipotético y Experimento: [`docs/openstack/arranque por red_ipxe.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/arranque%20por%20red_ipxe.md)
  - Guía Paso a Paso: [`docs/openstack/Implementar PXE.md`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/docs/openstack/Implementar%20PXE.md)

---

## 📋 Inventario de Nodos y Reservas DHCP Auditadas

| ID Nodo | Hostname | Rol en Clúster | Dirección MAC | IP Asignada (VLAN 29) | RAM / SSD | Estado Físico |
| :---: | :--- | :--- | :--- | :--- | :---: | :---: |
| **314** | `bastion` | Bastión SSH / K8s Master | `64:00:6a:2a:60:62` | `10.100.29.10` | 8 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **315** | `nexus-repo` | Nexus OSS / K8s Worker | `64:00:6a:2a:5f:99` | `10.100.29.20` | 16 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **306** | `pxe-controller` | Servidor PXE / dnsmasq / HTTP | `64:00:6a:2a:62:42` | `10.100.29.30` | 16 GB / 128 GB | 🟢 Operativo |
| **269** | `k8s-cp-01` | K8s Worker (worker-02) | `64:00:6a:2a:5f:f9` | `10.100.29.101` | 16 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **280** | `k8s-cp-02` | K8s Worker (worker-03) | `64:00:6a:2a:60:63` | `10.100.29.102` | 16 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **320** | `k8s-cp-03` | K8s Worker (worker-04) | `64:00:6a:2a:2c:75` | `10.100.29.103` | 16 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **321** | `k8s-worker-01`| K8s Worker (worker-05) | `64:00:6a:2a:62:a4` | `10.100.29.111` | 8 GB / 128 GB | 🟢 Operativo (K8s Ready) |
| **279** | `k8s-worker-02`| K8s Worker (worker-06) | `64:00:6a:2a:2f:cb` | `10.100.29.112` | 8 GB / 128 GB | 🟢 Operativo (K8s Ready) |

---

## 🔍 Checklist de Verificación Rápida para el Operador

```bash
# 1. En Nodo 306: Validar servicios de red
sudo ss -ulpn | grep -E ':(67|69)'
sudo ss -tlpn | grep ':8089'

# 2. Descargar script iPXE de prueba
curl -fsI http://10.100.29.30:8089/boot.ipxe | head -n 1
# Esperado: HTTP/1.1 200 OK

# 3. Monitorear solicitudes en tiempo real durante encendido
sudo tcpdump -i enp2s0 -nn -e "port 67 or port 68 or port 69 or port 8089"
```

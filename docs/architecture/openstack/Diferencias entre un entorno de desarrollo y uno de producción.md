# Diferencias entre un Entorno de Desarrollo y uno de Producción (OpenStack & Bare-Metal)

> **Contexto de Infraestructura**: Clúster Edge Bare-Metal con 8 Nodos Dell OptiPlex 3020M  
> **Subred Privada L2**: `10.100.29.0/24` (Aislada de la Red de Oficina)  

---

## 1. Resumen Comparativo de Arquitectura

| Dimensión Técnica | Entorno de Desarrollo / Laboratorio | Entorno de Producción Oficial (Este Despliegue) |
| :--- | :--- | :--- |
| **Topología de Servidores** | Una sola máquina virtual All-in-One con Kolla | 8 Servidores Físicos Bare-Metal distribuidos |
| **Manejo de Imágenes** | Descarga manual de ISOs desde Internet | Imágenes inmutables `.qcow2` pre-cocinadas con Packer o instalador PXE desatendido |
| **Repositorios de Paquetes**| Descargas repetitivas desde `deb.debian.org` hacia internet | Caché centralizada en Sonatype Nexus 3 local (`10.100.29.20:8081` a 1 Gbps) |
| **Control de Energía** | Apagado/Encendido manual o mock driver | Wake-on-LAN / BMC IPMI automatizado |
| **Alta Disponibilidad K8s**| 1 Control Plane solitario (SPOF) | 3 Control Planes con quórum Raft etcd distribuido |
| **Seguridad y Perímetro** | Acceso SSH directo con contraseñas por defecto | Acceso exclusivo vía Bastion Host con llaves Ed25519 y túneles jump host |
| **Aislamiento de Red** | Red plana compartida con estaciones de trabajo | Subred privada L2 `10.100.29.0/24` en switch físico aislado sin uplink a oficina |

---

## 2. Por qué OpenStack Kolla-Ansible Completo no es Viable en este Hardware

OpenStack Kolla-Ansible tradicional levanta más de 30 contenedores por nodo (Keystone, Nova, Neutron con OVS/OVN, Glance, Horizon, Heat, Placement, MariaDB Galera, RabbitMQ, Memcached, etc.).

1. **Restricción de Memoria RAM**:
   - Kolla All-in-One requiere un mínimo de **32 a 64 GB de RAM** solo para los servicios de control de OpenStack.
   - Nuestros nodos físicos cuentan con **8 GB y 16 GB de RAM**. Correr OpenStack completo provocaría fallos constantes por OOM (*Out Of Memory*).
2. **Restricción de Almacenamiento (128 GB SSD)**:
   - Los registros de OpenStack, volúmenes de MariaDB Galera y réplicas de Glance saturan discos de 128 GB en cuestión de días.
3. **Decisión Arquitectónica de Producción**:
   - Se utiliza **Ironic Standalone / PXE HTTPBoot desatendido** y **Sonatype Nexus 3 OSS**:
     - Consumo mínimo de recursos (< 3 GB RAM en Nodo 306).
     - Provisión de metal desnudo nativa sin sobrecarga de virtualización.
     - Plataforma de cómputo final basada en **Kubernetes (RKE2 + Cilium eBPF)** de alto rendimiento.

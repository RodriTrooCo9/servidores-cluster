# Índice Maestro de Documentación Técnica

Bienvenido al repositorio de documentación de la infraestructura bare-metal con OpenStack Kolla-Ansible, Kubernetes RKE2 HA y observabilidad completa.

---

## 🗺️ Mapa de Navegación

### 1. [Arquitectura y Diseño (`docs/architecture/`)](architecture/)
- [**Manual Maestro de Infraestructura**](architecture/manual_maestro_infraestructura.md): Guía fundamental de arquitectura, direccionamiento y despliegue.
- [**Flujo Detallado de Arranque PXE/iPXE**](architecture/arranque_pxe_detallado.md): Investigación y configuración paso a paso del booteo de red.
- [**Topología y Aislamiento de Red**](architecture/network/aislamiento_red_oficina.md): Seguridad L2/L3 y contención de tráfico.
- [**Evolución Histórica de Infraestructura**](architecture/evolucion_infraestructura.md): Registro histórico de cambios y trazabilidad.
- [**OpenStack Glance e Ironic Bare-Metal**](architecture/openstack/OpenStack%20Glance,%20Formatos%20de%20Disco%20e%20Ironic%20Bare-Metal.md): Conceptos clave de aprovisionamiento físico.

### 2. [Procedimientos Operativos / Runbooks (`docs/runbooks/`)](runbooks/)
- [**Manual Maestro de Recuperación y Rearranque (SRE Runbook)**](runbooks/manual-recuperacion-y-rearranque.md): Guía exhaustiva para apagones totales, caídas de nodo, pérdida de quórum etcd y fallos de servicio.
- [**Recuperación ante Desastres (Disaster Recovery)**](runbooks/disaster_recovery.md): Protocolo de contingencia y restauración de etcd y MariaDB.
- [**Blindaje de Red y Contención Rogue DHCP**](runbooks/blindaje_red_oficina.md): Reglas para aislar la red de pruebas de la oficina.
- [**Rotación y Renovación de Secretos**](runbooks/rotacion_secretos.md): Guía de actualización periódica de claves y tokens.
- [**Incorporación de Nuevo Nodo Bare-Metal**](runbooks/anadir_nodo.md): Procedimiento de alta y enrolamiento de servidores adicionales.

### 3. [Observabilidad y Telemetría (`docs/observability/`)](observability/)
- [**Guía de Monitoreo Prometheus y Grafana**](observability/prometheus_grafana.md): Configuración de paneles, agentes y métricas.
- [**Manual Maestro de Observabilidad Avanzada**](observability/manual_maestro_observabilidad.md): Arquitectura de VictoriaMetrics, Loki, Tempo y OpenTelemetry.

### 4. [Decisiones de Arquitectura / ADRs (`docs/adr/`)](adr/)
- [**ADR 0001: Migración de Scripts Bash a Ansible**](adr/0001-migracion-bash-a-ansible.md)
- [**ADR 0002: Cilium eBPF en sustitución de kube-proxy**](adr/0002-cilium-ebpf-sin-kube-proxy.md)
- [**ADR 0003: Mitigación de almacenamiento para SSD de 128 GB**](adr/0003-mitigacion-disco-128gb.md)

### 5. [Referencia Rápida (`docs/reference/`)](reference/)
- [**Matriz de Puertos y Servicios**](reference/puertos_y_servicios.md): Inventario completo de puertos TCP/UDP.
- [**Cheat-Sheet de IPs y Hardware**](reference/env_cheatsheet.md): Resumen rápido de direcciones y alias SSH.
- [**Plantilla de Credenciales**](reference/credentials.example.md): Modelo sanitizado sin secretos en texto plano.
- [**Control de Tareas y Pendientes**](reference/todo.md): Bitácora de seguimiento.

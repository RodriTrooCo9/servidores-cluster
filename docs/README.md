# Índice Maestro de Documentación Técnica

Bienvenido al repositorio de documentación de la infraestructura bare-metal con OpenStack Kolla-Ansible, Kubernetes RKE2 HA y observabilidad completa.

---

> 🚀 **¿Nuevo en el clúster? Empieza aquí:**  
> 👉 [**Guía Rápida de Uso y Operación Paso a Paso (docs/GUIA_RAPIDA_USO.md)**](GUIA_RAPIDA_USO.md): Puesta en marcha en 10 minutos (llaves, SSH, tunnels, dashboards y comandos).

---

## 🗺️ Mapa de Navegación

### 1. [Arquitectura y Diseño (`docs/architecture/`)](architecture/)
- [**Manual Maestro de Infraestructura**](architecture/manual_maestro_infraestructura.md): Guía fundamental de arquitectura, direccionamiento y despliegue.
- [**Flujo Detallado de Arranque PXE/iPXE**](architecture/arranque_pxe_detallado.md): Investigación y configuración paso a paso del booteo de red.
- [**Topología y Aislamiento de Red**](architecture/network/aislamiento_red_oficina.md): Seguridad L2/L3 y contención de tráfico.
- [**Evolución Histórica de Infraestructura**](architecture/evolucion_infraestructura.md): Registro histórico de cambios y trazabilidad.
- [**Arquitectura Comparativa Ironic, Glance y Bifrost**](architecture/openstack/glance_ironic_bifrost_arquitectura_comparativa.md): Análisis arquitectónico de aprovisionamiento físico bare-metal.
- [**Plan Maestro de Compilación e Instalación iPXE**](architecture/openstack/plan_maestro_instalacion_ipxe.md): Compilación y despliegue del binario iPXE con drivers integrados.

### 2. [Procedimientos Operativos / Runbooks (`docs/runbooks/`)](runbooks/)
- [**MANUAL INTEGRAL DEL PROYECTO (Instalación desde Cero + Operación + 21 Escenarios de Falla)**](runbooks/manual-integral-instalacion-y-recuperacion.md): **La biblia técnica del clúster.** Despliegue paso a paso (Fases 00 a 90), arquitectura de red, secuencia de arranque y los 21 escenarios SRE de contingencia.
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

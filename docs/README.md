# Documentación de los proyectos

El repositorio mantiene dos proyectos separados y herramientas compartidas.

## Infraestructura Kubernetes

- [Instalación de RKE2, aplicaciones y monitoreo](../GUIA_DE_INSTALACION.md).
- [Guía de observabilidad](../GUIA_OBSERVABILIDAD.md).
- [Añadir un nodo con sistema operativo instalado](runbooks/anadir_nodo.md).
- [Instalar Coroot en un sistema existente](observability/instalar-coroot-primero.md).

## Instalación de sistemas operativos en máquinas físicas

- [Guía principal de OpenStack e Ironic](../GUIA_OPENSTACK.md).
- [Configuraciones del proyecto](../openstack/README.md).
- [Imágenes y metadatos](../cloud-init/README.md).
- [Referencia de arranque PXE](architecture/arranque_pxe_detallado.md).
- [Comparativa de Ironic, Glance y Bifrost](architecture/openstack/glance_ironic_bifrost_arquitectura_comparativa.md).
- [Referencia de iPXE](architecture/openstack/plan_maestro_instalacion_ipxe.md).

## Herramientas y datos compartidos

- [Conexión SSH](../GUIA_RAPIDA.md).
- [Ansible por proyecto y respaldos separados](../GUIA_ANSIBLE.md).
- [Red y aislamiento](architecture/network/aislamiento_red_oficina.md).
- [Estado observado del laboratorio](reference/estado-observado-2026-10-30.md).
- [Auditoría y mejoras](reference/auditoria-proyecto-2026-10-27.md).
- [Correcciones y validación pendiente](reference/correcciones-aplicadas-2026-10-27.md).

## Referencias históricas

Estos documentos conservan la instalación conjunta anterior; no son el punto de partida para instalar un proyecto.

- [Guía conjunta original](../REFERENCIA_HISTORICA_INFRAESTRUCTURA.md).
- [Manual de arquitectura del laboratorio](architecture/manual_maestro_infraestructura.md).
- [Manual integral y escenarios de recuperación](runbooks/manual-integral-instalacion-y-recuperacion.md).
- [Recuperación del laboratorio anterior](runbooks/disaster_recovery.md).

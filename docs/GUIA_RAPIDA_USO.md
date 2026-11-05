# Elegir una guía de uso del laboratorio

Para preparar la conexión SSH, sigue la [guía rápida de acceso](../GUIA_RAPIDA.md).

| Necesidad | Procedimiento |
|---|---|
| Instalar un sistema operativo en una máquina física | [Proyecto OpenStack e Ironic](../GUIA_OPENSTACK.md) |
| Instalar RKE2, aplicaciones y monitoreo sobre un sistema operativo existente | [Proyecto de infraestructura Kubernetes](../GUIA_DE_INSTALACION.md) |
| Revisar métricas, registros y trazas | [Observabilidad](../GUIA_OBSERVABILIDAD.md) |
| Usar Ansible o respaldar un proyecto | [Ansible por proyecto](../GUIA_ANSIBLE.md) |

Los atajos `make deploy`, `make services`, `make health` y `make backup` conservan alcance conjunto. Usa los comandos específicos de la guía elegida. La comprobación de un proyecto no exige tener desplegado el otro.

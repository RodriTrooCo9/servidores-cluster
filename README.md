# Proyectos de infraestructura y aprovisionamiento

Este repositorio contiene dos proyectos con objetivos y guías de instalación separados.

| Proyecto | Resultado | Guía principal |
|---|---|---|
| Infraestructura Kubernetes | Servidores con sistema operativo existente que ejecutan RKE2, aplicaciones y observabilidad | [Instalar la plataforma](GUIA_DE_INSTALACION.md) |
| Instalación de sistemas operativos en máquinas físicas | Una máquina arranca su sistema operativo y permite acceso por SSH | [OpenStack e Ironic para instalar sistemas operativos](GUIA_OPENSTACK.md) |

Ironic prepara el sistema operativo de equipos físicos nuevos o recuperados. Glance entrega las imágenes registradas en OpenStack. Cuando esos servicios se detienen, se interrumpe el aprovisionamiento que los usa. RKE2, Nexus y la observabilidad se ejecutan sobre equipos con Debian instalado y siguen usando sus propios servicios y almacenamiento. Consulta qué operaciones dependen de cada servicio y cómo comprobarlas. [Dependencias del aprovisionamiento](GUIA_OPENSTACK.md#dependencias-del-aprovisionamiento)

Los dos proyectos comparten repositorio, inventarios, roles y algunos playbooks. En el laboratorio, `nodo-306` también aloja el plano de control de RKE2, el servidor PXE y servicios de observabilidad. Una caída del nodo completo tiene un alcance mayor que la parada de sus contenedores Kolla.

## Guías de cada proyecto

### Infraestructura Kubernetes

- [Instalación paso a paso](GUIA_DE_INSTALACION.md).
- [Observabilidad y monitoreo](GUIA_OBSERVABILIDAD.md).
- [Añadir un nodo con sistema operativo instalado](docs/runbooks/anadir_nodo.md).

### Instalación de sistemas operativos

- [Guía de OpenStack e Ironic](GUIA_OPENSTACK.md).
- [Instalación desatendida de Debian 13 por iPXE](network/ipxe/debian-netboot/README.md).
- [Configuraciones del controlador de aprovisionamiento](openstack/README.md).

### Herramientas compartidas

- [Acceso SSH al laboratorio](GUIA_RAPIDA.md).
- [Ansible por proyecto](GUIA_ANSIBLE.md).
- [Índice de documentación](docs/README.md).
- [Trabajo con ramas](GITFLOW_PLAN.md).

## Antes de ejecutar

El inventario describe un diseño distinto de la instalación actual. Confirma los roles y las IP reales antes de modificar equipos existentes. [Estado observado del laboratorio](docs/reference/estado-laboratorio.md)

`ansible/site.yml`, `make deploy`, `make services`, `make health` y `make backup` mantienen operaciones de ambos proyectos. Las guías usan playbooks concretos y etiquetas de respaldo para escoger el alcance. No ejecutes la secuencia conjunta como requisito de ninguno de los proyectos.

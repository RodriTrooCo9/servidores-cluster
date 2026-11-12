# Proyectos de infraestructura y aprovisionamiento

Este repositorio contiene dos proyectos con objetivos y guías de instalación separados.

| Proyecto | Resultado | Guía principal |
|---|---|---|
| Infraestructura Kubernetes | Servidores con sistema operativo existente que ejecutan RKE2, aplicaciones y observabilidad | [Instalar la plataforma](GUIA_DE_INSTALACION.md) |
| Instalación de sistemas operativos en máquinas físicas | Una máquina arranca su sistema operativo y permite acceso por SSH | [OpenStack e Ironic para instalar sistemas operativos](GUIA_OPENSTACK.md) |

La instalación del sistema operativo termina antes de configurar la plataforma de aplicaciones. Kolla OpenStack e Ironic standalone se conservan como alternativas de aprovisionamiento. No es necesario desplegar OpenStack para instalar la plataforma sobre máquinas que ya tienen su sistema operativo.

La separación es documental dentro de este repositorio. Los inventarios, roles y playbooks todavía comparten archivos; no se ha creado un repositorio remoto nuevo ni cambiado los servicios en funcionamiento.

## Guías de cada proyecto

### Infraestructura Kubernetes

- [Instalación paso a paso](GUIA_DE_INSTALACION.md).
- [Observabilidad y monitoreo](GUIA_OBSERVABILIDAD.md).
- [Añadir un nodo con sistema operativo instalado](docs/runbooks/anadir_nodo.md).

### Instalación de sistemas operativos

- [Guía de OpenStack e Ironic](GUIA_OPENSTACK.md).
- [Instalación desatendida de Debian 13 por iPXE](network/ipxe/debian-netboot/README.md).
- [Configuraciones del controlador de aprovisionamiento](openstack/README.md).
- [Imágenes y metadatos de primer arranque](cloud-init/README.md).

### Herramientas compartidas

- [Acceso SSH al laboratorio](GUIA_RAPIDA.md).
- [Ansible por proyecto](GUIA_ANSIBLE.md).
- [Índice de documentación](docs/README.md).
- [Trabajo con ramas](GITFLOW_PLAN.md).

## Antes de ejecutar

El inventario describe un diseño distinto del registrado en la [inspección del 30 de octubre de 2026](docs/reference/estado-observado-2026-10-30.md). Confirma los roles e IP reales antes de modificar equipos existentes.

`ansible/site.yml`, `make deploy`, `make services`, `make health` y `make backup` mantienen operaciones de ambos proyectos. Las guías usan playbooks concretos y etiquetas de respaldo para escoger el alcance. No ejecutes la secuencia conjunta como requisito de ninguno de los proyectos.

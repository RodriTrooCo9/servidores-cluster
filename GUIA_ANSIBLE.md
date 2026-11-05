# Ansible para los dos proyectos

Ansible aplica configuraciones por SSH desde la laptop de administración. Este repositorio comparte herramientas e inventarios, pero la instalación de sistemas operativos y la plataforma Kubernetes tienen procedimientos separados.

## 1 Requisitos

- Laptop Linux con Git, Python, un entorno virtual y Ansible Core. Las guías del proyecto usan Python 3.11 o superior y Ansible Core 2.17 o superior; no existe un bloqueo completo de versiones.
- Llave SSH autorizada, permisos `sudo` y red de administración disponibles.
- `inventory/lab/hosts.yml`, sus variables y la contraseña de Vault revisados.
- Colecciones de `ansible/collections/requirements.yml` instaladas.

La preparación de la laptop y Vault está explicada en los pasos 3 a 8 de la [guía de infraestructura](GUIA_DE_INSTALACION.md). La alternativa Kolla usa su propio entorno y requisitos en la [guía del sistema operativo](GUIA_OPENSTACK.md).

## 2 Elegir el proyecto

| Proyecto | Playbooks o configuración | Resultado |
|---|---|---|
| Instalar sistemas operativos | `20-services/02_pxe_controller.yml`, `20-services/03_ironic_deploy.yml`, roles `pxe_controller` e `ironic`; o configuración `openstack/` con Kolla | Arranque por red e instalación de un sistema operativo |
| Infraestructura Kubernetes | `10-base/`, `20-services/01_nexus.yml`, `30-platform/01_rke2_cluster.yml`, `40-observability/` | Plataforma sobre máquinas con sistema operativo ya disponible |

Las rutas de playbooks de la tabla están bajo `ansible/playbooks/`. El rol `common` configura un sistema operativo existente; no instala Debian en un disco vacío.

El inventario define nodos 269, 280 y 320 como control planes, pero el [registro de inspección](docs/reference/estado-observado-2026-10-30.md) describe otro estado real. Reconcilia los datos antes de aplicar cambios.

## 3 Preparar y revisar

**Dónde:** laptop, raíz del repositorio, con el entorno `.venv` ya creado. Este comando activa las herramientas de Ansible.

```bash
source .venv/bin/activate
```

Este comando instala las colecciones declaradas en el proyecto; modifica el entorno de la laptop.

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

Estos comandos comprueban sintaxis y muestran los destinatarios de la plataforma, sin desplegarla.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml --syntax-check
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml --list-hosts
```

**Resultado esperado:** sintaxis válida y solo los equipos previstos para esa tarea. Si los destinos no coinciden, corrige el inventario antes de seguir.

## 4 Ejecutar por proyecto

Para instalar el sistema operativo sigue la [guía de OpenStack e Ironic](GUIA_OPENSTACK.md). Para configurar la plataforma sigue la [guía de Kubernetes](GUIA_DE_INSTALACION.md). Ambas explican qué modifica cada comando y cómo comprobarlo.

`ansible/site.yml` mantiene imports de ambos proyectos. `--tags services` incluye Nexus, PXE e Ironic. `make deploy` y `make services` también mantienen ese alcance conjunto. No los uses para ejecutar un proyecto de forma independiente.

El modo `--check` no prueba una instalación completa y algunas tareas consultan servicios reales. Consulta primero la sintaxis y los hosts del playbook concreto; no uses el orquestador integral como simulación de un único proyecto.

El rol `ironic` se ejecuta en el grupo `pxe_controller`. Limitarlo a un equipo destino mediante `--limit` no instala el sistema en ese equipo. Además, su plantilla recorre todo `groups['baremetal']`: limitar el controlador no limita el inventario que se genera.

## 5 Respaldos separados

**Dónde:** laptop, raíz del repositorio. **Advertencia:** estos comandos crean y copian datos sensibles a `backups/`; ejecútalos por separado después de validar el inventario y proteger el destino.

Este comando respalda etcd y su token para el proyecto Kubernetes.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup_etcd
```

Este comando respalda la base de datos y configuración Kolla del proyecto de instalación de sistemas operativos; requiere Kolla existente y credenciales correctas.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup_openstack
```

`backup_openstack` no corresponde al servicio standalone. La etiqueta general `backup` ejecuta ambos bloques. Ninguna de estas órdenes demuestra por sí sola una restauración completa ni respalda todos los volúmenes e imágenes.

## 6 Errores frecuentes

| Error | Qué revisar |
|---|---|
| `UNREACHABLE` | Red, IP, usuario, llave y salto SSH del inventario |
| Vault no descifra | Contraseña original y ruta `.vault_pass`; no la sustituyas por otra |
| No aparece ningún host con `--limit` | El grupo del playbook puede ser el controlador, no la máquina que recibirá la imagen |
| La comprobación integral exige OpenStack | El healthcheck actual cubre ambos proyectos; usa las verificaciones de la guía elegida |
| Sintaxis correcta, instalación fallida | La sintaxis no verifica repositorios externos, imágenes, red ni servicios activos |

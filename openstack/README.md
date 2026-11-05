# Proyecto de instalación de sistemas operativos en máquinas físicas

Este proyecto prepara imágenes y usa Ironic para instalar un sistema operativo en un equipo físico. Su resultado es una máquina que arranca y permite acceso SSH. La [guía principal](../GUIA_OPENSTACK.md) contiene los pasos y las comprobaciones.

## Alternativas

| Alternativa | Archivos del repositorio | Cómo se administra |
|---|---|---|
| Kolla OpenStack | `globals.yml`, `inventory/multinode`, `config/` | Kolla-Ansible administra contenedores de los servicios OpenStack |
| Ironic standalone | `../ansible/roles/ironic/`, `../ansible/roles/pxe_controller/` | Playbooks Ansible del controlador y servicio Ironic en Podman |

Kolla e Ironic standalone son alternativas distintas. El rol `ironic` no instala Kolla: detecta un conductor Kolla activo y omite el servicio standalone para evitar colisiones.

## Configuración

- `globals.yml`: versión Kolla 2025.1, servicios, interfaces y VIP del diseño del laboratorio.
- `inventory/multinode`: destinos y acceso SSH de Kolla. Ajusta sus rutas absolutas a tu equipo.
- `config/ironic.conf` y `config/glance.conf`: configuraciones de servicio.
- `secrets/`: ejemplos y archivos privados ignorados por Git; no publiques credenciales reales.
- `../inventory/lab/hosts.yml`: inventario compartido. Revisa los destinatarios antes de usarlo para aprovisionamiento.

`node_custom_config` conserva una ruta antigua a `kolla/config`. Antes de una instalación nueva, configura la ruta real a `openstack/config`. Revisa también la interfaz externa `veth-neutron`, que el despliegue actual no prepara automáticamente.

## Alcance

Este proyecto termina al verificar el sistema operativo y SSH del equipo destino. La plataforma de aplicaciones tiene [otra guía](../GUIA_DE_INSTALACION.md). Compartir el nodo 306, el inventario o la red del laboratorio no convierte ambos despliegues en una única secuencia.

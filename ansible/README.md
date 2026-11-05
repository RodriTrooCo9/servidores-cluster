# Automatización compartida con Ansible

Los roles e inventarios se comparten entre dos proyectos. La [guía de Ansible](../GUIA_ANSIBLE.md) explica cómo seleccionar el alcance y preparar las herramientas.

| Proyecto | Archivos principales | Guía |
|---|---|---|
| Instalación de sistemas operativos | Roles `pxe_controller`, `ironic` y playbooks `20-services/02_pxe_controller.yml`, `20-services/03_ironic_deploy.yml` | [OpenStack e Ironic](../GUIA_OPENSTACK.md) |
| Infraestructura Kubernetes | Roles `common`, `bastion`, `nexus`, `rke2_ha`, `monitoring`, `coroot_node_agent`; playbooks de base, plataforma y observabilidad | [Instalación de la plataforma](../GUIA_DE_INSTALACION.md) |

Las rutas de playbooks de la tabla están bajo `ansible/playbooks/`. Kolla se configura mediante `../openstack/` y su propio entorno de Kolla-Ansible; el rol `ironic` corresponde a la alternativa standalone.

## Archivos compartidos

- `collections/requirements.yml`: dependencias de colecciones.
- `../inventory/lab/hosts.yml`: inventario y variables del laboratorio.
- `site.yml`: orquestador integral que conserva imports de ambos proyectos.
- `playbooks/50-validation/01_healthcheck.yml`: comprobaciones que esperan servicios de ambos proyectos.
- `playbooks/90-operations/01_disaster_recovery.yml`: respaldo seleccionado mediante `backup_etcd` o `backup_openstack`.

Ejecuta desde la raíz del repositorio los playbooks concretos que indique la guía elegida. No uses el despliegue integral, el healthcheck conjunto ni la etiqueta general `backup` como requisito de un proyecto independiente.

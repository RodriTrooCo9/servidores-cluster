# OpenStack Kolla-Ansible (Bare-Metal Ironic & Glance)

Este directorio contiene la configuración declarativa para el despliegue contenerizado de **OpenStack Ironic Standalone** y **Glance** mediante Kolla-Ansible sobre el controlador de aprovisionamiento (Nodo 306).

## Estructura
```text
openstack/
├── globals.yml                # Configuración maestra de servicios Kolla
├── inventory/
│   └── multinode              # Inventario de despliegue para kolla-ansible
├── config/
│   ├── glance.conf            # Ajustes específicos para Glance
│   └── ironic.conf            # Ajustes específicos para Ironic Bare-Metal
├── secrets/                   # [CIFRADO / IGNORADO] Credenciales y archivos openrc
│   ├── passwords.yml.example  # Plantilla de variables de claves
│   ├── admin-openrc.sh.example# Plantilla de entorno para CLI openstack
│   └── clouds.yaml.example    # Plantilla de configuración de SDK
└── README.md
```

## Flujo de Despliegue con Kolla
```bash
# 1. Validar sintaxis y prerequisitos
kolla-ansible -i openstack/inventory/multinode prechecks

# 2. Desplegar contenedores de OpenStack
kolla-ansible -i openstack/inventory/multinode deploy

# 3. Generar archivo openrc si no existe
kolla-ansible -i openstack/inventory/multinode post-deploy
```

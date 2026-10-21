# Inventario de Infraestructura y Red Bare-Metal

Este directorio constituye la **única fuente de verdad** física y lógica de la infraestructura bare-metal.

## 1. Estructura del Directorio
```text
inventory/
├── nodes.csv              # Matriz física de hardware (MACs, IPs, roles, especificaciones)
├── env.example            # Plantilla de variables de entorno para scripts shell
├── lab/                   # Entorno de Laboratorio / Staging activo (8 Dell OptiPlex 3020M)
│   ├── hosts.yml          # Inventario YAML de Ansible con metadatos por host
│   └── group_vars/        # Variables agrupadas (all/vars.yml, observability.yml, vault.yml)
└── prod/                  # Entorno de Producción (Plantilla desacoplada)
    └── hosts.yml          # Topología segregada para despliegue productivo
```

## 2. Matriz Física de Servidores (`nodes.csv`)
El archivo [`nodes.csv`](nodes.csv) define el hardware base:
- **ID 314**: `bastion` (`10.100.29.10`, MAC `64:00:6a:2a:60:62`, 8 GB RAM, 128 GB SSD).
- **ID 315**: `nexus-repo` (`10.100.29.20`, MAC `64:00:6a:2a:5f:99`, 16 GB RAM, 128 GB SSD).
- **ID 306**: `pxe-controller` (`10.100.29.30`, MAC `64:00:6a:2a:62:42`, 16 GB RAM, 128 GB SSD).
- **ID 269**: `k8s-cp-01` (`10.100.29.101`, MAC `64:00:6a:2a:5f:f9`, 16 GB RAM, 128 GB SSD) - *Líder etcd*.
- **ID 280**: `k8s-cp-02` (`10.100.29.102`, MAC `64:00:6a:2a:60:63`, 16 GB RAM, 128 GB SSD).
- **ID 320**: `k8s-cp-03` (`10.100.29.103`, MAC `64:00:6a:2a:2c:75`, 16 GB RAM, 128 GB SSD).
- **ID 321**: `k8s-worker-01` (`10.100.29.111`, MAC `64:00:6a:2a:62:a4`, 8 GB RAM, 128 GB SSD).
- **ID 279**: `k8s-worker-02` (`10.100.29.112`, MAC `64:00:6a:2a:2f:cb`, 8 GB RAM, 128 GB SSD).

## 3. Manejo de Secretos en `group_vars/all/`
Las credenciales confidenciales nunca se almacenan en texto plano:
- Archivo de variables generales: `inventory/lab/group_vars/all/vars.yml`
- Plantilla de variables cifradas: `inventory/lab/group_vars/all/vault.yml.example`
- Archivo cifrado real: `inventory/lab/group_vars/all/vault.yml` (gestionado con `ansible-vault` y `.vault_pass`).

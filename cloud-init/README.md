# Aprovisionamiento Inmutable con Cloud-Init, ConfigDrive y Packer

Este módulo gestiona la creación de imágenes de sistema operativo inmutables y la inyección Zero-Touch de metadatos para servidores físicos gestionados por OpenStack Ironic.

## Estructura
```text
cloud-init/
├── packer/
│   └── packer.pkr.hcl                 # Plantilla HCL2 para compilar imágenes Debian QCOW2
├── scripts/
│   └── generate_configdrive.sh        # Generador de ISOs VFAT config-2 y NoCloud HTTP
├── templates/                         # Plantillas declarativas Jinja2
│   ├── meta-data.j2                   # Identidad de host y claves SSH públicas
│   ├── network-config.j2              # Asignación estática de red L2/L3
│   └── user-data.j2                   # #cloud-config (usuarios, apt, kernel k8s, swapoff)
└── README.md
```

## Uso
```bash
# 1. Compilar imagen base inmutable con Packer
packer build cloud-init/packer/packer.pkr.hcl

# 2. Generar volumen ConfigDrive para un nodo específico (ej. k8s-cp-01 o ID 269)
./cloud-init/scripts/generate_configdrive.sh k8s-cp-01
```

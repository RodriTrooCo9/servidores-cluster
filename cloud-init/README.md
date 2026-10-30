# Aprovisionamiento Inmutable con Cloud-Init, ConfigDrive y Packer

Este módulo gestiona la creación de imágenes de sistema operativo inmutables y la inyección Zero-Touch de metadatos para servidores físicos gestionados por OpenStack Ironic.


## Uso
```bash
# 1. Compilar imagen base inmutable con Packer
packer build cloud-init/packer/packer.pkr.hcl

# 2. Generar volumen ConfigDrive para un nodo específico (ej. k8s-cp-01 o ID 269)
./cloud-init/scripts/generate_configdrive.sh k8s-cp-01
```

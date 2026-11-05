# Imágenes y metadatos para instalar sistemas operativos

Este directorio pertenece al [proyecto de instalación de sistemas operativos en máquinas físicas](../GUIA_OPENSTACK.md). Contiene plantillas Packer, formatos cloud-init y un generador auxiliar de ConfigDrive.

## Archivos existentes

| Archivo | Alcance actual |
|---|---|
| `packer/packer.pkr.hcl` | Plantilla anterior basada en un preseed que no está completo en el repositorio; no usarla como instalación verificada |
| `packer/debian13-coroot.pkr.hcl` | Imagen especializada con agente de observabilidad; requiere seed, llave temporal y binarios preparados |
| `scripts/generate_configdrive.sh` | Utilidad heredada que toma datos de `inventory/nodes.csv` e incluye ajustes para Kubernetes y Nexus |
| `templates/` | Referencias de metadatos y configuración de primer arranque |

La guía independiente usa una imagen del sistema operativo y metadatos revisados para el equipo destino. No exige construir una imagen con agentes de observabilidad.

El generador heredado no es un paso de la nueva guía: conserva una llave de ejemplo de respaldo y configura servicios ajenos al sistema base. No lo ejecutes sin revisar su contenido y sus destinos. Las utilidades Bash existentes se conservan como código heredado; la preparación del controlador se explica con Ansible.

La construcción de la imagen especializada permanece en la [referencia de Packer y Coroot](../docs/observability/coroot-debian13-packer.md#8-construir-una-imagen-con-packer).

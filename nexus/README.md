# Repositorios de Sonatype Nexus

El nodo 315 (`10.100.29.20`) aloja el proxy APT y el registro de contenedores del laboratorio. Usa el YAML como referencia para configurar los repositorios en Nexus y confirma el almacenamiento existente antes de asignarlo. Ansible configura el servicio. [Referencia de repositorios](repositories.yml)

## Puertos

- `8081` para la interfaz web, la API REST y el proxy APT `/repository/debian-proxy/`.
- `8082` para descargar imágenes a través de `docker-group`.
- `8083` para publicar imágenes en `docker-hosted`.

En el laboratorio también existe `docker-quay-proxy`. Antes de configurar el mirror de RKE2, verifica en Nexus los miembros de `docker-group` y el acceso a las imágenes de Docker Hub y Quay. [Guía de instalación](../GUIA_DE_INSTALACION.md)

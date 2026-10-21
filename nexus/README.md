# Repositorios y Registros Locales (Sonatype Nexus 3 as Code)

Este directorio gestiona la configuración declarativa de **Sonatype Nexus 3 OSS** sobre el Nodo 315 (`10.100.29.20`), proporcionando repositorio APT local y registro de contenedores OCI para el clúster.

## Estructura
```text
nexus/
├── repositories.yml           # Declaración de repositorios APT, Docker Hosted, Proxy y Group
├── blobstores.yml             # Cuotas y afinamiento de almacenamiento para SSD 128 GB
├── cleanup_policies.json      # Políticas de retención y purga automática de imágenes
├── scripts/
│   └── setup_nexus_kolla_registry.sh # Automatización de carga de imágenes Kolla-Ansible
└── README.md
```

## Puertos de Servicio
- **`8081`**: Interfaz Web y API REST de Nexus / Proxy APT (`/repository/debian-proxy/`).
- **`8082`**: Registro Docker Group (Lectura/Pull unificado para RKE2 y containerd).
- **`8083`**: Registro Docker Hosted (Escritura/Push para imágenes Kolla locales).

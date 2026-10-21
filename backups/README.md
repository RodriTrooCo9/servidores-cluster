# Almacenamiento Local de Respaldos (Disaster Recovery)

Este directorio está destinado exclusivamente para la recepción temporal de volcados locales y snapshots de contingencia generados por Ansible (`ansible/playbooks/90-operations/01_disaster_recovery.yml`) o el script `scripts/ops/disaster-recovery.sh`.

## Protocolo de Respaldos (DR Policy)
1. **Exclusión de Git**: Todos los archivos de respaldo (`*.tar.gz`, `*.sql.gz`, `*.bak`) están estrictamente ignorados por Git (`.gitignore`).
2. **Cifrado en Reposo**: Todo volcado que contenga bases de datos o secretos debe ser cifrado con GPG o SOPS antes de su transporte fuera del entorno.
3. **Rotación**: Los respaldos locales deben sincronizarse con un almacenamiento S3/NFS externo y rotarse con una retención máxima de 7 días para evitar saturar el disco de 128 GB.

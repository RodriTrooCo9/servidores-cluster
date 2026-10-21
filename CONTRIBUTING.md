# Guía de Contribución

¡Gracias por contribuir a la infraestructura bare-metal y clúster Kubernetes HA!

## 1. Principios de Diseño
- **Infraestructura y Observabilidad como Código**: Todo cambio debe ser reproducible, idempotente y declarativo.
- **Zero Plaintext Secrets**: Nunca se suben credenciales, claves SSH, certificados o tokens en texto plano al repositorio. Emplea siempre `ansible-vault` o `sops`.
- **Una Sola Fuente de Verdad**: La asignación física de hardware reside exclusivamente en `inventory/nodes.csv`.
- **Conformidad de Estilo**: Todos los commits deben pasar las pruebas estáticas (`make lint`).

## 2. Flujo de Trabajo (Git Flow)
1. Crea una rama descriptiva: `feature/descripcion-corta` o `fix/problema-especifico`.
2. Realiza commits atómicos siguiendo la convención de [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` Nueva funcionalidad o rol.
   - `fix:` Corrección de bugs en playbooks o scripts.
   - `refactor:` Mejoras de estructura sin alterar comportamiento.
   - `docs:` Modificaciones en manuales y runbooks.
   - `chore:` Tareas de mantenimiento o dependencias.
3. Ejecuta `make lint` y `make syntax-check` antes de solicitar revisión.
4. Abre un Merge Request / Pull Request detallando el impacto del cambio.

## 3. Manejo de Secretos con Ansible Vault
Para editar o crear archivos cifrados:
```bash
# Crear o editar archivo cifrado
ansible-vault edit inventory/lab/group_vars/all/vault.yml

# Cifrar un archivo nuevo
ansible-vault encrypt openstack/secrets/passwords.yml
```

Asegúrate de que el archivo `.vault_pass` exista localmente con permisos `0600` y nunca sea añadido a Git.

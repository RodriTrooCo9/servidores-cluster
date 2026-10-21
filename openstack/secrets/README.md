# Gestión de Secretos de OpenStack

Este directorio almacena las credenciales de autenticación y contraseñas generadas por Kolla-Ansible.

## Protocolo de Seguridad (Zero Plaintext Secrets)
- Los archivos con credenciales reales (`passwords.yml`, `admin-openrc.sh`, `clouds.yaml`) están estrictamente ignorados por Git (`.gitignore`).
- Para versionar cambios en producción, cifra los archivos con Ansible Vault o SOPS:
  ```bash
  ansible-vault encrypt openstack/secrets/passwords.yml
  ```
- Si requieres desplegar en un entorno nuevo:
  1. Copia las plantillas `*.example`:
     ```bash
     cp openstack/secrets/passwords.yml.example openstack/secrets/passwords.yml
     ```
  2. Genera contraseñas criptográficas con Kolla:
     ```bash
     kolla-genpwd -p openstack/secrets/passwords.yml
     ```

# Directorio Seguro de Llaves Criptográficas

Este directorio está estrictamente protegido por el archivo [`.gitignore`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/.gitignore).
**Ninguna llave privada (`*.key`, `id_*`, `*.pem`) almacenada aquí será subida al repositorio Git.**

---

### Reglas de Seguridad Obligatorias:

1. **Permisos del Directorio:**
   El directorio `keys/` debe tener permisos restringidos exclusivamente a tu usuario (`0700`):
   ```bash
   chmod 700 /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible/keys
   ```

2. **Permisos de las Llaves Privadas:**
   Cualquier llave SSH colocada en este directorio debe tener permisos `0600` (lectura/escritura solo por el dueño):
   ```bash
   chmod 600 /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible/keys/*
   ```

3. **Contraseña Maestra de Ansible Vault (`.vault_pass`):**
   La clave para desencriptar `vault.yml` debe residir en la raíz de `ansible/`:
   ```bash
   echo "mi_password_maestra" > /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible/.vault_pass
   chmod 600 /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible/.vault_pass
   ```

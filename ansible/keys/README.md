# Directorio Seguro de Llaves Criptográficas

Este directorio está estrictamente protegido por el archivo [`.gitignore`](../../.gitignore).
**Ninguna llave privada (`*.key`, `id_*`, `*.pem`) almacenada aquí será subida al repositorio Git.**

---

## Permisos y custodia

1. **Permisos del Directorio:**
   El directorio `keys/` debe tener permisos restringidos exclusivamente a tu usuario (`0700`):
   ```bash
   chmod 700 ansible/keys
   ```

2. **Permisos de las Llaves Privadas:**
   Cualquier llave SSH colocada en este directorio debe tener permisos `0600` (lectura/escritura solo por el dueño):
   ```bash
   chmod 600 ansible/keys/cluster_key
   ```

3. **Rotación SSH.** Autoriza la llave pública nueva en cada destino y prueba
   el acceso desde una sesión independiente antes de retirar la anterior.
4. **Ansible Vault.** Guarda la contraseña original en `.vault_pass` en la raíz
   del repositorio con permisos `0600`. Usa el procedimiento de la guía al
   preparar una instalación nueva. [Preparación de Vault](../../GUIA_DE_INSTALACION.md#etapa-a-preparar-equipos-y-laptop)

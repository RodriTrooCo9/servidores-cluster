# Runbook: Rotación y Renovación de Secretos

## Objetivo
Estandarizar el procedimiento operativo para la rotación periódica o de emergencia de contraseñas de bases de datos, tokens de RKE2, claves de Kolla y llaves SSH.

## 1. Rotación de Clave SSH del Clúster (`cluster_key`)
1. Generar nuevo par de claves ed25519 en una estación segura:
   ```bash
   ssh-keygen -t ed25519 -f cluster_key_new -C "admin-cluster-nodes-$(date +%Y%m%d)"
   ```
2. Desplegar la nueva clave pública en los 8 nodos:
   ```bash
   ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml
   ```
3. Sustituir la clave privada local y validar conexión a todos los nodos con `make preflight`.
4. Retirar la clave anterior de los archivos `authorized_keys`.

## 2. Rotación de Secretos de Kolla-Ansible (`passwords.yml`)
1. Desencriptar el archivo de secretos:
   ```bash
   ansible-vault decrypt openstack/secrets/passwords.yml
   ```
2. Modificar la contraseña objetivo (ej. `database_password` o `keystone_admin_password`).
3. Re-cifrar inmediatamente:
   ```bash
   ansible-vault encrypt openstack/secrets/passwords.yml
   ```
4. Reconfigurar los servicios de OpenStack:
   ```bash
   kolla-ansible -i openstack/inventory/multinode reconfigure
   ```

## 3. Rotación de Token de Clúster RKE2
1. En el nodo líder (`k8s-cp-01`), actualizar el token en `/etc/rancher/rke2/config.yaml`.
2. Reiniciar el servicio `rke2-server`:
   ```bash
   sudo systemctl restart rke2-server
   ```
3. Actualizar `vault_rke2_token` en `inventory/lab/group_vars/all/vault.yml`.
4. Ejecutar el playbook de plataforma para alinear los secundarios y workers:
   ```bash
   ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml
   ```

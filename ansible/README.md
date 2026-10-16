# 🚀 Orquestación y Automatización con Ansible Core

Entorno de automatización profesional e idempotente para los **8 nodos físicos bare-metal** del clúster Dell OptiPlex 3020M con Debian 13.

---

## 📁 Estructura del Entorno

```text
ansible/
├── ansible.cfg                    # Configuración optimizada (forks=8, pipelining, ControlPersist)
├── .vault_pass                    # [IGNORADO POR GIT] Clave maestra de cifrado de secretos
├── keys/                          # [IGNORADO POR GIT] Directorio seguro de llaves SSH (chmod 700)
│   ├── cluster_key                # Llave privada ed25519 con permisos estrictos (chmod 600)
│   └── README.md
├── inventory/
│   ├── hosts.yml                  # Inventario estructurado en YAML de los 8 nodos físicos
│   └── group_vars/
│       └── all/
│           ├── vars.yml           # Variables de conexión, ProxyJump y parámetros de red
│           └── vault.yml.example  # Plantilla de secretos para cifrar con Ansible Vault
├── playbooks/
│   ├── 00_ping.yml                # Comprobación de conectividad paralela en toda la flota
│   ├── 01_system_summary.yml      # Telemetría de hardware (RAM, Disco, CPU, Kernel)
│   ├── 02_base_config.yml         # Homologación del SO (Swap off, Sysctl k8s, Chrony, herramientas)
│   └── 03_healthcheck.yml         # Verificación de puertos y servicios (Nexus, PXE, Exporters)
├── site.yml                       # Playbook orquestador maestro (soporta ejecución por tags)
└── setup_keys.sh                  # Script de blindaje y sincronización inicial de llaves
```

---

## 🔐 Seguridad y Gestión de Llaves Criptográficas

1. **Aislamiento en `.gitignore`:**
   Tanto las llaves SSH en `ansible/keys/` como la contraseña `.vault_pass` y los archivos `vault_*.yml` están expresamente excluidos de Git para evitar filtraciones accidentales.

2. **Permisos Estrictos:**
   - Carpeta de llaves: `chmod 700 ansible/keys`
   - Llaves privadas: `chmod 600 ansible/keys/*`
   - Archivo de vault: `chmod 600 ansible/.vault_pass`

3. **Ansible Vault para Secretos:**
   Para cifrar contraseñas sensibles (como tokens de RKE2 o claves de Nexus):
   ```bash
   cd ansible
   # Crear archivo cifrado a partir del ejemplo:
   ansible-vault create inventory/group_vars/all/vault.yml
   
   # O editarlo posteriormente:
   ansible-vault edit inventory/group_vars/all/vault.yml
   ```

---

## ⚡ Comandos Rápidos de Uso

Todos los comandos se ejecutan desde el directorio `ansible/`:

```bash
cd /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/ansible
```

### 1. Probar conectividad con toda la flota (8 nodos en paralelo):
```bash
ansible-playbook playbooks/00_ping.yml
# O comando ad-hoc:
ansible baremetal -m ping
```

### 2. Obtener resumen de hardware y recursos de todos los nodos:
```bash
ansible-playbook playbooks/01_system_summary.yml
```

### 3. Ejecutar configuración base de sistema operativo:
```bash
ansible-playbook playbooks/02_base_config.yml
```

### 4. Ejecutar el orquestador maestro por Tags:
```bash
# Solo ping y salud:
ansible-playbook site.yml --tags ping,healthcheck

# Ejecutar únicamente en el clúster de Kubernetes:
ansible-playbook site.yml --limit k8s_cluster
```

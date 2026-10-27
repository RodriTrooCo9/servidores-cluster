# Guía de Credenciales y Accesos SSH a la Flota Bare-Metal (Plantilla de Ejemplo)

> [!WARNING]
> **Aviso de Seguridad**: Este archivo es una plantilla de referencia. Los secretos y contraseñas reales se gestionan exclusivamente mediante **Ansible Vault** en `inventory/lab/group_vars/all/vault.yml` y `openstack/secrets/passwords.yml`.

---

## 1. Conexiones Estándar (Acceso por IP y Usuario)

| ID | Hostname | Rol | IP Privada (Clúster) | Comando SSH Directo | Usuario | Contraseña | Sudo NOPASSWD |
| :---: | :---: | :---: | :---: | :--- | :---: | :---: | :---: |
| **314** | `bastion` | Bastion / Proxy | `10.100.29.10` | `ssh <ADMIN_USER>@10.100.29.10` | `n314` | `<VAULT_PASSWORD>` | ✅ Sí |
| **315** | `nexus-repo` | Sonatype Nexus OSS | `10.100.29.20` | `ssh <ADMIN_USER>@10.100.29.20` | `n315` | `<VAULT_PASSWORD>` | ✅ Sí |
| **306** | `pxe-controller` | PXE / Router / Monitoreo | `10.100.29.30` | `ssh <ADMIN_USER>@10.100.29.30` | `n306` | `<VAULT_PASSWORD>` | ✅ Sí |
| **269** | `k8s-cp-01` | Control-Plane 01 (Líder) | `10.100.29.101` | `ssh debian@10.100.29.101` | `debian` | `<VAULT_PASSWORD>` | ✅ Sí |
| **280** | `k8s-cp-02` | Control-Plane 02 | `10.100.29.102` | `ssh debian@10.100.29.102` | `debian` | `<VAULT_PASSWORD>` | ✅ Sí |
| **320** | `k8s-cp-03` | Control-Plane 03 | `10.100.29.103` | `ssh debian@10.100.29.103` | `debian` | `<VAULT_PASSWORD>` | ✅ Sí |
| **321** | `k8s-worker-01` | Worker Node 01 | `10.100.29.111` | `ssh debian@10.100.29.111` | `debian` | `<VAULT_PASSWORD>` | ✅ Sí |
| **279** | `k8s-worker-02` | Worker Node 02 | `10.100.29.112` | `ssh debian@10.100.29.112` | `debian` | `<VAULT_PASSWORD>` | ✅ Sí |

---

## 2. Atajos Rápidos por Alias SSH
Configura en tu `~/.ssh/config` local:
```ssh-config
Host nodo-314
    HostName 10.100.29.10
    User aget-ic
    ProxyJump n306-wifi

Host nodo-306
    HostName 10.100.29.30
    User n306

Host n306-wifi
    HostName 192.168.29.25
    User n306
```

---

## 3. URLs de Servicios y Dashboards
- **Grafana Observabilidad**: `http://localhost:3000` (Vía túnel SSH `make tunnels`).
- **OpenStack Horizon Web**: `http://localhost:8080` (Vía túnel SSH `make tunnels`).
- **Sonatype Nexus 3 Web**: `http://localhost:8081` (Vía túnel SSH `make tunnels`).
- **Prometheus TSDB**: `http://localhost:9090`.
- **VictoriaMetrics**: `http://localhost:8428`.

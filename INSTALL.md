# INSTALL.md

## 1. Requisitos
- Laptop con Linux (Debian 12/13 o Ubuntu 22.04/24.04), Python 3.11+, Ansible Core 2.17+, Packer 1.10+, QEMU/KVM, OpenStackClient, kubectl 1.30+.
- Llave SSH privada `ansible/keys/cluster_key` con permisos 0600 y archivo `.vault_pass` (0600).
- Conexión de red al switch privado o Wi-Fi de gestión del clúster (`192.168.29.25`).

## 2. Variables globales

```bash
export CONTROLLER_IP="192.168.29.25"
export CONTROLLER_INTERNAL_IP="10.100.29.30"
export BASTION_IP="10.100.29.10"
export NEXUS_IP="10.100.29.20"
export K8S_CP01_IP="10.100.29.101"
export K8S_CP02_IP="10.100.29.102"
export K8S_CP03_IP="10.100.29.103"
export K8S_WORKER01_IP="10.100.29.111"
export K8S_WORKER02_IP="10.100.29.112"
export SUBRED="10.100.29.0/24"
export SSH_KEY="ansible/keys/cluster_key"
export INVENTORY="inventory/lab/hosts.yml"
export ANSIBLE_CONFIG="ansible.cfg"
export KUBECONFIG="${HOME}/.kube/config"
```

## 3. Matriz del Motor Ansible

| Fase | Playbook Nativo Ansible | Rol Invocado | Target / Host | Tags |
| :---: | :--- | :--- | :--- | :--- |
| **F0** | `ansible/playbooks/00-preflight/00_ping.yml` | N/A (`ping`) | `baremetal` (8 nodos) | `preflight,ping` |
| **F2.1** | `ansible/playbooks/10-base/01_os_base.yml` | `common` | `baremetal` (8 nodos) | `base,common` |
| **F2.2** | `ansible/playbooks/10-base/02_bastion_hardening.yml` | `bastion` | `bastion` (Nodo 314) | `base,bastion` |
| **F2.3** | `ansible/playbooks/20-services/01_nexus.yml` | `nexus` | `nexus` (Nodo 315) | `services,nexus` |
| **F2.4** | `ansible/site.yml` | `common` | `baremetal:!bastion:!nexus` | `common` |
| **F3** | `ansible/playbooks/20-services/02_pxe_controller.yml` | `pxe_controller` | `pxe_controller` (306) | `services,pxe` |
| **F4** | `ansible/playbooks/20-services/03_ironic_deploy.yml` | `ironic` | `pxe_controller` (306) | `services,ironic` |
| **F6** | `ansible/playbooks/30-platform/01_rke2_cluster.yml` | `rke2_ha` | `k8s_cluster` (7 nodos) | `platform,k8s` |
| **F8** | `ansible/playbooks/40-observability/01_monitoring.yml` | `monitoring` | `baremetal` (8 nodos) | `observability` |
| **F9** | `ansible/playbooks/40-observability/02_coroot_agent.yml` | `coroot_node_agent` | `baremetal:!pxe_controller`| `coroot` |
| **F10** | `ansible/playbooks/50-validation/01_healthcheck.yml` | N/A (`assert`) | `baremetal` (8 nodos) | `validation` |
| **F11** | `ansible/playbooks/90-operations/01_disaster_recovery.yml`| N/A (`backup`) | `baremetal` (8 nodos) | `backup` |

---

## 4. Fases de Despliegue

### F1: Preparación y Compilación de Imagen Dorada (laptop)

1. Configurar entorno de trabajo y dependencias de la laptop:
```bash
chmod +x scripts/client/setup-client-workstation.sh
./scripts/client/setup-client-workstation.sh
```
✔ Verificar: `ansible --version && test -f ansible/keys/cluster_key` retorna código 0.

2. Compilar imagen dorada Debian 13 con agente Coroot preinstalado:
```bash
packer build \
  -var "image_path=https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64.qcow2" \
  -var "image_checksum=file:https://cloud.debian.org/images/cloud/trixie/daily/latest/SHA512SUMS" \
  cloud-init/packer/debian13-coroot.pkr.hcl
```
✔ Verificar: `qemu-img check output-debian13-coroot/debian13-coroot.qcow2` retorna "No errors were found".

3. Comprimir imagen qcow2 para distribución en red:
```bash
qemu-img convert -c -O qcow2 output-debian13-coroot/debian13-coroot.qcow2 output-debian13-coroot/debian13-coroot-compressed.qcow2
```
✔ Verificar: `test -f output-debian13-coroot/debian13-coroot-compressed.qcow2 && ls -lh output-debian13-coroot/debian13-coroot-compressed.qcow2` muestra archivo de ~600MB.

---

### F2: Servicios Base con Ansible: Bastión, Red y Nexus (laptop)

1. Configuración base del sistema operativo en la flota (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml
```
✔ Verificar: `ansible baremetal -i inventory/lab/hosts.yml -m ping` retorna SUCCESS en todos los nodos.

2. Endurecimiento de Bastión, SSH, Squid y Chrony NTP (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/02_bastion_hardening.yml
```
✔ Verificar: `ssh -i ansible/keys/cluster_key aget-ic@10.100.29.10 "sudo systemctl is-active ssh squid chrony"` retorna active en las 3 líneas.

3. Despliegue de Sonatype Nexus 3 OSS y PostgreSQL 16 (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/01_nexus.yml
```
✔ Verificar: `curl -fsS -o /dev/null -w "%{http_code}" http://10.100.29.20:8081/service/rest/v1/status` retorna 200.

4. Redirección de clientes APT hacia el repositorio Nexus local (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --tags "common" --limit "baremetal:!bastion:!nexus"
```
✔ Verificar: `ansible baremetal -i inventory/lab/hosts.yml -m command -a "grep -r '10.100.29.20:8081' /etc/apt/"` retorna entradas válidas en los nodos.

---

### F3: Red Bare-Metal: dnsmasq, iPXE y BIOS (nodo 306 y consola física)

1. Configurar BIOS en los nodos Dell OptiPlex 3020M (ejecutar manualmente en cada nodo físico):
```text
F2 -> System Configuration: Integrated NIC = Enabled w/PXE, SATA Operation = AHCI | Security: Secure Boot = Disabled | General: Boot Sequence = UEFI | Power: AC Recovery = Power On, Deep Sleep = Disabled
```
✔ Verificar: `sudo dmidecode -s bios-version` retorna A05.

2. Desplegar servidor PXE, DHCP dnsmasq e iPXE HTTPBoot con Ansible (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "curl -fsI http://10.100.29.30:8089/boot.ipxe"` retorna HTTP/1.1 200 OK.

3. Envío de Wake-on-LAN para arranque de nodos:
```bash
wakeonlan <MAC>
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo ss -ulpn | grep :67"` confirma dnsmasq escuchando en el puerto DHCP.

---

### F4: OpenStack Kolla-Ansible (nodo 306 y laptop)

1. Iniciar servicios contenerizados de OpenStack Kolla (ejecutar en: nodo 306):
```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker start \$(sudo docker ps -a -q)"
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker ps --filter 'name=glance_api' --format '{{.Status}}'"` contiene Up.

2. Transferir y registrar la imagen dorada en Glance:
```bash
scp -i ansible/keys/cluster_key output-debian13-coroot/debian13-coroot-compressed.qcow2 n306@192.168.29.25:/tmp/debian13-coroot.qcow2
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "source /etc/kolla/admin-openrc.sh && openstack image create debian13-coroot-lab --disk-format qcow2 --container-format bare --public --file /tmp/debian13-coroot.qcow2 && rm -f /tmp/debian13-coroot.qcow2"
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "source /etc/kolla/admin-openrc.sh && openstack image show debian13-coroot-lab -c status -f value"` retorna active.

3. Desplegar configuración de Ironic Bare-Metal con Ansible (ejecutar en: laptop):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "source /etc/kolla/admin-openrc.sh && openstack endpoint list --service ironic -c Enabled -f value"` contiene True.

---

### F5: Aprovisionamiento y Verificación de Nodos (nodo 306 y laptop)

1. Generar configuraciones Cloud-Init NoCloud y ConfigDrives (ejecutar en: nodo 306):
```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo bash /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/scripts/ops/07-cloud-init.sh -y"
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "test -d /opt/infra/configdrive"` retorna código 0.

2. ⚠️ Re-aprovisionar nodo físico bare-metal con imagen de red (destructivo: formatea el disco del nodo):
```bash
scripts/ops/disaster-recovery.sh --reprovision <NODO>
```
✔ Verificar: `ansible <NODO> -i inventory/lab/hosts.yml -m ping` retorna SUCCESS tras completar el primer boot.

3. Validar conectividad SSH global de toda la flota con Ansible:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/00_ping.yml
```
✔ Verificar: Salida `ok=8 changed=0 unreachable=0 failed=0`.

---

### F6: Clúster Kubernetes HA con RKE2 y Cilium eBPF (laptop)

1. Desplegar RKE2 HA con 3 Control Planes y Cilium CNI vía Ansible:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"` muestra 7 nodos en estado Ready.

2. Configurar kubeconfig local en la laptop:
```bash
mkdir -p ~/.kube
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo cat /etc/rancher/rke2/rke2.yaml" | sed "s/127.0.0.1/10.100.29.101/g" > ~/.kube/config
chmod 600 ~/.kube/config
```
✔ Verificar: `kubectl get nodes` lista los nodos del clúster con roles y estados.

3. Validar Cilium eBPF, cert-manager e Ingress-Nginx:
```bash
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
```
✔ Verificar: Todos los pods retornan STATUS Running.

---

### F7: Aplicaciones (laptop)

1. Desplegar microservicios en el namespace `aplicaciones`:
```bash
kubectl apply -k kubernetes/overlays/lab
```
✔ Verificar: `kubectl get pods -n aplicaciones` muestra backend-api, frontend-web, orders-service, notifications-service, redis y traffic-simulator en estado Running.

2. Validar respuesta HTTP de la aplicación en el NodePort:
```bash
curl -fsS http://192.168.29.25:30080/api/v1/data
```
✔ Verificar: Retorna `{"status": "ok", "service": "backend-api"}`.

---

### F8: Telemetría de Infraestructura y K8s (laptop)

1. Desplegar Prometheus, Grafana, Alertmanager, Blackbox y Node Exporter vía Ansible:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml
```
✔ Verificar: `curl -fsS http://10.100.29.30:9090/-/ready && curl -fsI http://10.100.29.30:3000/login` devuelven Ready y HTTP/1.1 200 OK.

2. Desplegar backends de telemetría K8s (VictoriaMetrics, Loki, Tempo):
```bash
kubectl apply -k kubernetes/observability/backends
```
✔ Verificar: `kubectl get statefulset -n observability` muestra loki, tempo y victoriametrics en 1/1 READY.

3. Desplegar OpenTelemetry Operator y Gateway Collector:
```bash
kubectl apply -k kubernetes/observability/otel
```
✔ Verificar: `kubectl get deployment -n observability otel-gateway-collector` muestra 2/2 READY.

---

### F9: Observabilidad eBPF con Coroot (nodo 306 y laptop)

1. Levantar servidor central de Coroot CE y ClickHouse (ejecutar en: nodo 306):
```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 "cd /opt/coroot && sudo docker compose -f compose.yaml up -d"
```
✔ Verificar: `curl -fsI http://192.168.29.25:19000/` retorna HTTP/1.1 200 OK.

2. Instalar y activar Coroot Node Agent v1.37.0 en los 8 nodos vía Ansible:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/02_coroot_agent.yml
```
✔ Verificar: `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "cd /opt/coroot && sudo docker compose logs --tail=10 coroot"` muestra "got 8 nodes".

---

### F10: Validación Final del Sistema (laptop)

1. Ejecutar pruebas unitarias de regresión en Python:
```bash
pytest tests/test_cli_regressions.py tests/test_backup_pipeline.py
```
✔ Verificar: Retorna "11 passed".

2. Ejecutar auditoría integral de salud de la infraestructura vía Ansible:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/50-validation/01_healthcheck.yml
```
✔ Verificar: Salida `failed=0` en los 8 nodos.

3. Comprobar endpoints de red principales:
```bash
curl -fsS http://10.100.29.20:8081/service/rest/v1/status >/dev/null && echo "Nexus :8081 OK"
curl -fsI http://10.100.29.30:8089/boot.ipxe >/dev/null && echo "HTTPBoot :8089 OK"
curl -fsS http://10.100.29.30:9090/-/ready >/dev/null && echo "Prometheus :9090 OK"
curl -fsI http://10.100.29.30:3000/login >/dev/null && echo "Grafana :3000 OK"
curl -fsI http://192.168.29.25:19000/ >/dev/null && echo "Coroot :19000 OK"
curl -fsS http://192.168.29.25:30080/api/v1/data >/dev/null && echo "App :30080 OK"
```
✔ Verificar: Las 6 líneas retornan "OK".

---

### F11: Respaldo y Recuperación ante Desastres (laptop)

1. Generar respaldo completo con Ansible (`--tags backup`):
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup
```
✔ Verificar: `ls -lh backups/openstack/ backups/etcd/` contiene archivos `.sql.gz` y `.db` con tamaño mayor a cero.

2. ⚠️ Eliminar nodo fallido en etcd para permitir auto-sanación del control plane:
```bash
scripts/ops/disaster-recovery.sh --heal-etcd <NODO_CP>
```
✔ Verificar: `kubectl get nodes` confirma el quórum de control planes restantes en estado Ready.

---

## 5. Troubleshooting Mínimo

- PXE no inicia en Dell OptiPlex $\rightarrow$ Reiniciar, presionar F12 y verificar que en BIOS esté `Integrated NIC: Enabled w/PXE`.
- dnsmasq no entrega ofertas DHCP $\rightarrow$ `ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo systemctl restart dnsmasq"`.
- Cilium no arranca por conflicto con kube-proxy $\rightarrow$ Verificar en `/etc/rancher/rke2/config.yaml` las líneas `cni: cilium` y `disable: [rke2-canal, rke2-kube-proxy]`.
- Coroot node-agent no inicia eBPF $\rightarrow$ `test -r /sys/kernel/btf/vmlinux || sudo apt-get install -y linux-headers-$(uname -r)`.
- Conflicto con puerto 9090 al arrancar Coroot $\rightarrow$ Eliminar `9090:9090` del servicio `prometheus` en `/opt/coroot/compose.yaml` (utilizar red puente interna).
- Nexus bloquea descargas de APT $\rightarrow$ `ssh -i ansible/keys/cluster_key io@10.100.29.20 "sudo systemctl restart nexus"`.
- Desfase horario entre nodos $\rightarrow$ `ansible baremetal -i inventory/lab/hosts.yml -m command -a "sudo chronyc makestep"`.
- Error al aplicar Kustomize por selectores inmutables $\rightarrow$ Asegurar `includeSelectors: false` en `kubernetes/overlays/lab/kustomization.yaml`.
- Error de permisos en llave SSH $\rightarrow$ `chmod 600 ansible/keys/cluster_key .vault_pass`.
- kubectl no conecta al clúster $\rightarrow$ Ejecutar `./scripts/client/tunnels.sh` o verificar IP `10.100.29.101:6443` en `~/.kube/config`.

---

## 6. Discrepancias

- `inventory/env` especifica RKE2 `v1.30.2+rke2r1`, mientras que los nodos del laboratorio ejecutan activamente `v1.36.5+rke2r1`.
- `inventory/env` documenta el gateway interno en `10.100.29.10` (Bastión), pero el enrutamiento y NAT de salida real lo ejecuta el Nodo 306 (`10.100.29.30`).
- `openstack/globals.yml` referencia `node_custom_config: .../kolla/config`, carpeta inexistente en la raíz; la ruta real en el repo es `openstack/config`.
- `scripts/client/tunnels.sh` redirige Grafana localmente al puerto `3001` para prevenir colisiones con instancias locales en `3000`.
- El script orquestador reside en `scripts/client/ejecutar-desde-laptop.sh` (no existe en la raíz del repositorio).
- No existe script de restauración automática para MariaDB en `disaster-recovery.sh`; el dump se genera pero su restauración requiere cliente MySQL manual.
- `inventory/prod/hosts.yml` contiene placeholders (`<PLACEHOLDER>`) y requiere adaptación antes de su aplicación en un entorno productivo real.

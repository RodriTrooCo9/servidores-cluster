# Runbook: Incorporación de Nuevo Nodo Bare-Metal

## Objetivo
Procedimiento para registrar, aprovisionar y anexar un nuevo servidor físico (Dell OptiPlex 3020M) a la infraestructura como Worker o Control Plane.

## Prerrequisitos
- Servidor conectado físicamente al switch de la subred `10.100.29.0/24`.
- Dirección MAC de la interfaz Gigabit Ethernet registrada.
- Configuración de BIOS Dell (A05): UEFI activado, Secure Boot desactivado, Wake-on-LAN habilitado.

## Procedimiento Paso a Paso

### 1. Registrar en el Inventario Físico (`inventory/nodes.csv`)
Añadir una nueva línea con la ID, MAC, Hostname, IP y especificaciones:
```csv
322,64:00:6a:2a:xx:yy,k8s-worker-03,10.100.29.113,k8s-worker,8,128,<BMC_IP>
```

### 2. Registrar en el Inventario YAML (`inventory/lab/hosts.yml`)
Bajo la sección `k8s_workers`:
```yaml
nodo-322:
  ansible_host: 10.100.29.113
  ansible_user: debian
  node_id: 322
  cluster_hostname: k8s-worker-03
  mac: "64:00:6a:2a:xx:yy"
  ram_gb: 8
  disk_gb: 128
```

### 3. Actualizar Servicios PXE y DHCP
Ejecutar el playbook del controlador PXE para registrar la reserva DHCP fija en `dnsmasq`:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
```

### 4. Aprovisionamiento Bare-Metal con Ironic
Enrolar e iniciar el despliegue de imagen:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml --limit nodo-322
```

### 5. Configuración Base y Anexión a Kubernetes
Una vez iniciado el sistema operativo:
```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml --limit nodo-322
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml --limit nodo-322
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml --limit nodo-322
```

### 6. Validación
Verificar que el nuevo nodo aparezca en estado `Ready`:
```bash
kubectl get nodes -o wide
```

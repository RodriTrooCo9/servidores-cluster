> **Referencia histórica del laboratorio conjunto.** Este documento mezcla ambos proyectos y conserva topologías y procedimientos anteriores. No lo uses como secuencia vigente. Consulta la [guía de Kubernetes](../../GUIA_DE_INSTALACION.md) o la [guía de instalación de sistemas operativos](../../GUIA_OPENSTACK.md). Los comandos de recuperación requieren contrastarse con el estado real.

# Runbook: Procedimientos de Recuperación ante Desastres (Disaster Recovery)

> **Entorno**: Clúster de Infraestructura On-Premise Dell OptiPlex 3020M  
> **Subred**: `10.100.29.0/24` (Aislada L2)  
> **Herramienta de Orquestación**: `./ejecutar-desde-laptop.sh`  

---

## 1. Escenario A: Caída o Reinicio Inesperado del Nodo 306 (Gateway/PXE)

El Nodo 306 actúa como Default Gateway (`10.100.29.30`) y servidor de arranque PXE/Cloud-Init. Si se reinicia o pierde energía:

### Síntomas
- Los nodos internos (`10.100.29.10`, `10.100.29.20`, etc.) no tienen salida a internet.
- Los nuevos nodos que arrancan por PXE no obtienen IP ni descargan imágenes.

### Procedimiento de Recuperación
1. **Comprobar acceso Wi-Fi al Nodo 306 desde la laptop**:
   ```bash
   ping -c 3 192.168.29.25
   ssh n306-wifi
   ```
2. **Restablecer el reenvío de paquetes y NAT Masquerade**:
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   sudo iptables -t nat -C POSTROUTING -o wlp3s0 -j MASQUERADE 2>/dev/null || \
     sudo iptables -t nat -A POSTROUTING -o wlp3s0 -j MASQUERADE
   ```
3. **Reiniciar servicios de arranque y verificar estado**:
   ```bash
   sudo systemctl restart dnsmasq
   sudo systemctl restart nginx
   sudo systemctl status dnsmasq nginx --no-pager
   ```
4. **Validar salida a internet desde un nodo del clúster**:
   ```bash
   ssh -J n306 debian@10.100.29.10 "ping -c 2 8.8.8.8"
   ```

---

## 2. Escenario B: Falla de Control Plane Kubernetes (RKE2 / etcd en Nodo 314)

El Nodo 314 aloja el API Server de Kubernetes y la base de datos distribuida `etcd`.

### Síntomas
- `kubectl` falla con `Unable to connect to the server: dial tcp 127.0.0.1:6443: connect: connection refused`.
- Los pods de Cilium o cargas de trabajo se encuentran en estado `Terminating` o no programables.

### Procedimiento de Recuperación
1. **Acceder al Nodo 314**:
   ```bash
   ssh -J n306 debian@10.100.29.10
   ```
2. **Revisar estado y logs del servicio RKE2 Server**:
   ```bash
   sudo systemctl status rke2-server --no-pager
   sudo journalctl -u rke2-server -n 100 --no-pager
   ```
3. **Verificar que el alias de IP secundario `192.168.21.107` esté presente** (si etcd se inicializó con esa IP previa):
   ```bash
   ip addr show dev enp2s0
   # Si no está presente, agregarla temporalmente para mantener quorum etcd:
   sudo ip addr add 192.168.21.107/24 dev enp2s0
   ```
4. **Reiniciar RKE2 Server**:
   ```bash
   sudo systemctl restart rke2-server
   ```
5. **Verificar salud de etcd y nodos**:
   ```bash
   sudo /var/lib/rancher/rke2/bin/kubectl \
     --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide
   ```

### Restauración de Snapshot etcd
Si la base de datos de etcd está corrupta:
```bash
# Listar snapshots disponibles
ls -lh /var/lib/rancher/rke2/server/db/snapshots/

# Detener el servicio
sudo systemctl stop rke2-server

# Restaurar desde el snapshot más reciente
sudo rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/<SNAPSHOT_NOMBRE>

# Iniciar nuevamente el servicio
sudo systemctl start rke2-server
```

---

## 3. Escenario C: Falla o Corrupción de Sonatype Nexus / PostgreSQL (Nodo 315)

El Nodo 315 aloja el registry de contenedores y la caché local de APT.

### Síntomas
- `apt-get update` en los nodos falla con error de conexión al puerto 8081.
- Contenedores no pueden hacer pull de imágenes locales (`10.100.29.20:8082` / `:8083`).

### Procedimiento de Recuperación
1. **Acceder al Nodo 315**:
   ```bash
   ssh -J n306 debian@10.100.29.20
   ```
2. **Verificar base de datos PostgreSQL 17**:
   ```bash
   sudo systemctl status postgresql --no-pager
   sudo -u postgres psql -c "SELECT datname FROM pg_database WHERE datname='nexus';"
   ```
3. **Verificar servicio Nexus y espacio en disco**:
   ```bash
   df -h /opt/sonatype-work
   sudo systemctl status nexus --no-pager
   sudo tail -n 50 /opt/sonatype-work/nexus3/log/nexus.log
   ```
4. **Si el blobstore se quedó sin espacio**:
   ```bash
   # Purgar tareas y cachés temporales si el disco está al 100%
   sudo systemctl stop nexus
   sudo find /opt/sonatype-work/nexus3/tmp/ -type f -delete
   sudo systemctl start nexus
   ```

---

## 4. Escenario D: Reprovisión Completa de un Nodo Físico Dañado

Si un nodo de trabajo (por ejemplo `k8s-worker-01`, Nodo 315 o un nuevo nodo) sufre daño en el sistema operativo o se reemplaza su SSD:

1. **Asegurar configuración en BIOS (F2)**:
   - `Onboard NIC`: **Enabled w/PXE**
   - `Boot List Option`: **UEFI**
   - `Secure Boot`: **Disabled**
   - `SATA Operation`: **AHCI**
2. **Encender y presionar F12**:
   - Seleccionar **UEFI Network Boot (IPv4)**.
3. **El instalador desatendido / Cloud-Init reconstruirá el sistema operativo automáticamente**:
   - El nodo obtendrá su IP estática según su MAC en `config/nodes.csv`.
   - Se aplicará el hostname, particionamiento y llaves SSH.
4. **Unir nuevamente al clúster de Kubernetes desde la laptop**:
   ```bash
   ./ejecutar-desde-laptop.sh --nodo 315 --fase 8
   ```

---

## 5. Contactos y Escalamiento

- **Administrador de Infraestructura**: Equipo DevSecOps / Cloud Engineering.
- **Red de Oficina**: Administrador de Redes Corporativas (solo si se requiere soporte Wi-Fi `192.168.29.0/24` en AP central).

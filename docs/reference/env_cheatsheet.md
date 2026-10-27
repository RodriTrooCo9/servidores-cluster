# 📌 GUÍA RÁPIDA DE ENTORNO, CREDENCIALES Y TOPOLOGÍA (env.md)
> **Infraestructura Bare-Metal Edge Aislada (10.100.29.0/24)**  
> **Última Actualización**: Octubre 2026 | **Estado**: 100% Operativo y Aislado

---

## 1. Parámetros Maestros de Red

| Parámetro | Valor Oficial | Descripción |
| :--- | :--- | :--- |
| **Subred Privada del Clúster** | `10.100.29.0/24` | Red física conmutada en switch independiente (aislado de la oficina). |
| **Máscara de Red** | `255.255.255.0` | Prefijo `/24` estándar. |
| **Gateway del Clúster / NAT** | `10.100.29.30` | Nodo 306 (enruta el tráfico saliente a internet vía Wi-Fi con Masquerade). |
| **DNS Corporativo** | `192.168.26.120` | Servidor DNS institucional / reenvío dnsmasq. |
| **Rango DHCP Dinámico PXE** | `10.100.29.50 - 10.100.29.99` | Rango efímero para descubrimiento inicial y arranque de instaladores. |
| **IP Wi-Fi Nodo 306 (Jump Host)**| `192.168.29.25` | IP en la Wi-Fi de oficina donde la laptop se conecta para saltar al clúster. |
| **IP Wi-Fi Laptop Admin** | `192.168.29.16` | Estación de trabajo devops (conectada **únicamente por Wi-Fi**). |

---

## 2. Inventario de Flota Bare-Metal (8 Nodos)

| ID | MAC Address | Hostname | IP Asignada | RAM | Disco | Rol en Clúster | Estado Actual |
| :---: | :--- | :--- | :--- | :---: | :---: | :--- | :---: |
| **314** | `64:00:6a:2a:60:62` | `bastion` | `10.100.29.10` | 8 GB | 128 GB | K8s Master Leader / Bastion / nftables | 🟢 **ONLINE / READY** |
| **315** | `64:00:6a:2a:5f:99` | `nexus-repo` | `10.100.29.20` | 16 GB| 128 GB | Sonatype Nexus 3 / Postgres 17 / K8s Worker | 🟢 **ONLINE / READY** |
| **306** | `64:00:6a:2a:62:42` | `pxe-controller` | `10.100.29.30` | 16 GB| 128 GB | PXE, TFTP, HTTPBoot, NAT Gateway, Jump Host | 🟢 **ONLINE (Wi-Fi+Eth)**|
| **269** | `64:00:6a:2a:5f:f9` | `k8s-cp-01` | `10.100.29.101` | 16 GB| 128 GB | K8s Control Plane 01 | 🟡 Pendiente Boot F12 |
| **280** | `64:00:6a:2a:60:63` | `k8s-cp-02` | `10.100.29.102` | 16 GB| 128 GB | K8s Control Plane 02 | 🟡 Pendiente Boot F12 |
| **320** | `64:00:6a:2a:2c:75` | `k8s-cp-03` | `10.100.29.103` | 16 GB| 128 GB | K8s Control Plane 03 | 🟡 Pendiente Boot F12 |
| **321** | `64:00:6a:2a:62:a4` | `k8s-worker-01` | `10.100.29.111` | 8 GB | 128 GB | K8s Worker Node 01 | 🟡 Pendiente Boot F12 |
| **279** | `64:00:6a:2a:2f:cb` | `k8s-worker-02` | `10.100.29.112` | 8 GB | 128 GB | K8s Worker Node 02 | 🟡 Pendiente Boot F12 |

---

## 3. Matriz de Conectividad SSH y Credenciales

### A. Conexión Directa desde la Laptop (Sin saltos manuales)
Tu laptop salta de forma 100% transparente a través del Nodo 306 gracias a `~/.ssh/config`:
```bash
ssh bastion           # Entra a Nodo 314 (10.100.29.10) como aget-ic
ssh nexus-repo        # Entra a Nodo 315 (10.100.29.20) como io
ssh n306-wifi         # Entra a Nodo 306 (192.168.29.25) como n306
ssh cp-01             # Entra a Nodo 269 (10.100.29.101) como debian
ssh cp-02             # Entra a Nodo 280 (10.100.29.102) como debian
ssh cp-03             # Entra a Nodo 320 (10.100.29.103) como debian
ssh worker-01         # Entra a Nodo 321 (10.100.29.111) como debian
ssh worker-02         # Entra a Nodo 279 (10.100.29.112) como debian
```

### B. Conexión desde la terminal interna del Nodo 306
Una vez dentro del Nodo 306, puedes usar los alias de comando rápido sin clave:
```bash
ssh bastion    # o ssh 314   (Usuario aget-ic)
ssh nexus-repo # o ssh 315   (Usuario io)
ssh cp-01      # o ssh 269   (Usuario debian)
ssh cp-02      # o ssh 280   (Usuario debian)
ssh cp-03      # o ssh 320   (Usuario debian)
ssh worker-01  # o ssh 321   (Usuario debian)
ssh worker-02  # o ssh 279   (Usuario debian)
```

### C. Tabla de Usuarios y Contraseñas de Respaldo
| Nodo | Usuario | Contraseña | Privilegios Sudo |
| :--- | :--- | :--- | :--- |
| **306** (`pxe-controller`) | `n306` | `306` | `NOPASSWD:ALL` |
| **314** (`bastion`) | `aget-ic` | `ag70v7` | `NOPASSWD:ALL` (en `/etc/sudoers.d/99-aget-ic`) |
| **315** (`nexus-repo`) | `io` | `59766` | `NOPASSWD:ALL` |
| **Nodos K8s (269, 280, 320, 321, 279)** | `debian` | `321` | `NOPASSWD:ALL` (inyectado por preseed / cloud-init) |
| **Root en todos los nodos instalados** | `root` | `321` | Acceso directo / consola |

---

## 4. Servicios Activos y Accesos Directos desde la Laptop

### A. Clúster Kubernetes HA (RKE2 + Cilium eBPF)
El API Server está tunelizado localmente al puerto `6443`. Puedes usar `kubectl` directo en tu terminal:
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### B. Sonatype Nexus 3 OSS (Repositorio y Registro Docker)
El puerto `8081` está tunelizado a tu máquina local:
* **URL Web**: `http://localhost:8081`
* **Usuario**: `admin`
* **Contraseña**: `70c7d98a-6561-40c3-b72f-9893b8eedd7d`
* **Repositorios Activos**:
  * `debian-proxy`: Caché APT local en `http://10.100.29.20:8081/repository/debian-proxy/`
  * `docker-hub-proxy`: Caché de Docker Hub
  * `docker-hosted`: Registro Docker privado de escritura (`:8083`)
  * `docker-group`: Registro Docker unificado de lectura (`:8082`)

### C. PostgreSQL 17 (Base de Datos de Nexus)
* **Host**: `10.100.29.20:5432`
* **Base de datos**: `nexus`
* **Usuario**: `nexus`
* **Contraseña**: `NexusPgSecret2026_lab!`

### D. Cloud-Init, ConfigDrive y NoCloud (Nodo 306)
* **Plantilla Packer**: `/opt/infra/packer/packer.pkr.hcl`
* **Script Generador Dinámico**: `/opt/infra/scripts/generate_configdrive.sh`
* **ISOs ConfigDrive compiladas**: `/opt/infra/configdrive/*.iso`
* **Endpoints HTTP NoCloud**: `http://10.100.29.30/cloud-init/<hostname>/user-data`

---

## 5. Configuración de BIOS / UEFI (Dell OptiPlex 3020M Micro)

Para enrolar los nodos restantes por arranque en red:
1. **Encender** y pulsar **`F2`** para entrar al Setup.
2. Modificar los 5 parámetros críticos:
   * **`System Configuration` ➔ `Integrated NIC`**: `Enabled w/PXE`.
   * **`Security` ➔ `Secure Boot`**: `Disabled`.
   * **`System Configuration` ➔ `SATA Operation`**: `AHCI`.
   * **`General` ➔ `Boot Sequence`**: `UEFI`.
   * **`Power Management` ➔ `AC Recovery`**: `Power On`.
3. Guardar cambios (**Apply** y **Exit**).
4. Al reiniciar, presionar **`F12`** y seleccionar:
   * **`UEFI: IP4 Realtek PCIe GBE Family Controller(IPv4)`**.

---

## 6. Comandos del Orquestador Remoto (`ejecutar-desde-laptop.sh`)

Todo el clúster se administra desde la laptop con un solo comando:
```bash
./ejecutar-desde-laptop.sh --check      # Auditar estado de red y SSH de todos los nodos
./ejecutar-desde-laptop.sh --sync       # Sincronizar scripts a todos los nodos online
./ejecutar-desde-laptop.sh --fase 1     # Aplicar configuración base del SO
./ejecutar-desde-laptop.sh --fase 2     # Bastion Gateway y Firewall
./ejecutar-desde-laptop.sh --fase 3     # Desplegar Nexus 3 y PostgreSQL
./ejecutar-desde-laptop.sh --fase 4     # Apuntar clientes APT/Docker a Nexus
./ejecutar-desde-laptop.sh --fase 5     # Servidor PXE/TFTP/Nginx en Nodo 306
./ejecutar-desde-laptop.sh --fase 6     # OpenStack Glance / Bifrost
./ejecutar-desde-laptop.sh --fase 7     # Generar Cloud-Init y ConfigDrives
./ejecutar-desde-laptop.sh --fase 8     # Desplegar / actualizar Kubernetes RKE2
./ejecutar-desde-laptop.sh --health     # Auditoría integral de salud
```


* saber la version de la bios `sudo dmidecode -s bios-version` 
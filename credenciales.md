# Guía Maestra de Credenciales y Accesos SSH a la Flota Bare-Metal

Este documento contiene la información oficial y homologada de accesos SSH, credenciales y métodos de conexión para los **8 nodos físicos** del clúster de infraestructura.

---

## 1. Conexiones Estándar (Acceso Directo por IP y Contraseña)

Todos los nodos han sido homologados con el estándar de usuario `n{ID}`, contraseña `{ID}` y privilegios completos de `sudo`:

| ID | Hostname | Rol | IP Privada (Clúster) | Comando SSH Directo | Usuario | Contraseña | Sudo NOPASSWD |
| :---: | :---: | :---: | :---: | :--- | :---: | :---: | :---: |
| **314** | `bastion` | Bastion / RKE2 Leader | `10.100.29.10` | `ssh n314@10.100.29.10` | `n314` | `314` | ✅ Sí |
| **315** | `nexus-repo` | Sonatype Nexus OSS | `10.100.29.20` | `ssh n315@10.100.29.20` | `n315` | `315` | ✅ Sí |
| **306** | `pxe-controller` | PXE / Router / Monitoreo | `10.100.29.30` | `ssh n306@10.100.29.30` | `n306` | `306` | ✅ Sí |
| **269** | `k8s-cp-01` | Control-Plane 01 (Líder) | `10.100.29.101` | `ssh n269@10.100.29.101` | `n269` | `269` | ✅ Sí |
| **280** | `k8s-cp-02` | Control-Plane 02 | `10.100.29.102` | `ssh n280@10.100.29.102` | `n280` | `280` | ✅ Sí |
| **320** | `k8s-cp-03` | Control-Plane 03 | `10.100.29.103` | `ssh n320@10.100.29.103` | `n320` | `320` | ✅ Sí |
| **321** | `k8s-worker-01` | Worker Node 01 | `10.100.29.111` | `ssh n321@10.100.29.111` | `n321` | `321` | ✅ Sí |
| **279** | `k8s-worker-02` | Worker Node 02 | `10.100.29.112` | `ssh n279@10.100.29.112` | `n279` | `279` | ✅ Sí |

> [!TIP]
> En cualquiera de los nodos, una vez dentro puedes elevar privilegios ejecutando simplemente `sudo -i` o `sudo su` (no solicitará clave).

---

## 2. Atajos Rápidos por Alias SSH (Laptop Principal)

Desde la laptop principal configurada con `~/.ssh/config` y llave pública ed25519 inyectada, el acceso es inmediato sin ingresar contraseñas:

```bash
ssh nodo-314   # Bastion (10.100.29.10)
ssh nodo-315   # Nexus Repo (10.100.29.20)
ssh nodo-306   # PXE Controller / Router DHCP (10.100.29.30)
ssh nodo-269   # Control Plane 01 (10.100.29.101)
ssh nodo-280   # Control Plane 02 (10.100.29.102)
ssh nodo-320   # Control Plane 03 (10.100.29.103)
ssh nodo-321   # Worker 01 (10.100.29.111)
ssh nodo-279   # Worker 02 (10.100.29.112)
```

---

## 3. Conexión desde una Laptop Externa (Guía Paso a Paso)

Los 8 nodos físicos están interconectados a través de un switch gigabit en la red privada `10.100.29.0/24`.

El **Nodo 306 (`pxe-controller`)** actúa como el puente de red (gateway/router) entre la red WiFi de la oficina (`192.168.29.25`) y el switch privado (`10.100.29.30`).

Cualquier laptop externa puede conectarse usando cualquiera de los siguientes tres métodos:

---

### Método A: Vía WiFi mediante Salto SSH (`-J`) (Recomendado / Sin cables)

Conecta la laptop externa a la red WiFi de la oficina (`192.168.29.x` o `192.168.28.x`):

#### Opción 1: En un solo comando usando Jump Host (`-J`)
```bash
# Ejemplo para conectar al nodo 269:
ssh -J n306@192.168.29.25 n269@10.100.29.101

# Ejemplo para conectar al nodo 320:
ssh -J n306@192.168.29.25 n320@10.100.29.103
```
*El comando te solicitará primero la clave del Nodo 306 (`306`), y luego la del nodo destino.*

#### Opción 2: En dos pasos
1. Iniciar sesión en el nodo router/puente:
   ```bash
   ssh n306@192.168.29.25
   # Contraseña: 306
   ```
2. Desde dentro del Nodo 306, ingresar a cualquier nodo directamente:
   ```bash
   ssh n269@10.100.29.101   # clave: 269
   ssh n280@10.100.29.102   # clave: 280
   ssh n320@10.100.29.103   # clave: 320
   ssh n321@10.100.29.111   # clave: 321
   ssh n279@10.100.29.112   # clave: 279
   ssh n314@10.100.29.10    # clave: 314
   ssh n315@10.100.29.20    # clave: 315
   ```

---

### Método B: Vía WiFi agregando Ruta Estática (Acceso Directo Transparente)

El Nodo 306 ya tiene habilitado el enrutamiento de paquetes en el kernel (`net.ipv4.ip_forward = 1`). Por lo tanto, puedes indicarle al sistema operativo de la laptop externa que enrute el tráfico hacia `10.100.29.0/24` a través de la IP WiFi del nodo 306 (`192.168.29.25`).

#### En Linux:
Ejecutar en la terminal de la laptop externa:
```bash
sudo ip route add 10.100.29.0/24 via 192.168.29.25
```

#### En Windows:
Abrir **CMD** o **PowerShell como Administrador** y ejecutar:
```cmd
route add 10.100.29.0 mask 255.255.255.0 192.168.29.25
```

#### En macOS:
```bash
sudo route -n add -net 10.100.29.0/24 192.168.29.25
```

✅ **Resultado:** La laptop externa podrá hacer ping y conectarse a cualquier nodo como si estuviera en la misma red local:
```bash
ssh n269@10.100.29.101
ssh n320@10.100.29.103
```

---

### Método C: Conexión Física por Cable de Red al Switch

Si conectas físicamente la laptop externa con un cable Ethernet a un puerto libre del switch de los 8 nodos:

1. Configurar manualmente la tarjeta de red Ethernet de la laptop externa:
   - **Dirección IP:** `10.100.29.250` (o cualquier IP libre entre `.200` y `.254`)
   - **Máscara de subred:** `255.255.255.0` (`/24`)
   - **Puerta de enlace (Gateway):** `10.100.29.30`
   - **Servidor DNS:** `10.100.29.30` o `8.8.8.8`
2. Conexión directa a velocidad gigabit:
   ```bash
   ssh n269@10.100.29.101
   ssh n321@10.100.29.111
   ```

---

## 4. Servicios Centrales y Puertos de Monitoreo

Todos los servicios web y paneles de administración están disponibles en las siguientes rutas:

| Servicio | Nodo | IP / Puerto | URL |
| :--- | :---: | :---: | :--- |
| **Grafana Dashboards** | `pxe-controller` | `10.100.29.30:3000` | [http://10.100.29.30:3000](http://10.100.29.30:3000) |
| **Prometheus TSDB** | `pxe-controller` | `10.100.29.30:9090` | [http://10.100.29.30:9090](http://10.100.29.30:9090) |
| **Alertmanager** | `pxe-controller` | `10.100.29.30:9093` | [http://10.100.29.30:9093](http://10.100.29.30:9093) |
| **Blackbox Exporter** | `pxe-controller` | `10.100.29.30:9115` | [http://10.100.29.30:9115](http://10.100.29.30:9115) |
| **Sonatype Nexus OSS** | `nexus-repo` | `10.100.29.20:8081` | [http://10.100.29.20:8081](http://10.100.29.20:8081) |
| **HTTP Bootloader** | `pxe-controller` | `10.100.29.30:8089` | [http://10.100.29.30:8089](http://10.100.29.30:8089) |
| **OpenStack Ironic** | `pxe-controller` | `10.100.29.30:6385` | [http://10.100.29.30:6385](http://10.100.29.30:6385) |
| **Node Exporter (Métricas)** | *Todos los nodos* | `10.100.29.X:9100` | `http://10.100.29.X:9100/metrics` |

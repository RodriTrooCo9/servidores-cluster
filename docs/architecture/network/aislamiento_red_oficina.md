# Guía de Implementación: Aislamiento de Red y Clúster en Switch de Oficina
## Segmento Privado Dedicado: 10.100.29.0/24 | DNS: 192.168.26.120 | Acceso Exclusivo a Nodos

---

## 1. Resumen Ejecutivo y Diagnóstico Forense

Para operar de forma simultánea los servidores de oficina (PCs, telefonía, Wi-Fi) y el clúster de aprovisionamiento de servidores bare-metal (PXE, TFTP, HTTPBoot, Ironic, Kubernetes, Nexus), es un imperativo de ingeniería **aislar el tráfico en Capa 2 (Data Link) y Capa 3 (Network)**. 

El fallo experimentado previamente (colisión de IP entre el Nodo 306 y un smartphone `da:de:94:69:de:80` en `192.168.21.30`) demostró que compartir el mismo dominio de broadcast físico entre servidores y dispositivos dinámicos de oficina produce:
1. **Flapping de tablas ARP**: Dos tarjetas respondiendo a la misma IP.
2. **Riesgo de Rogue DHCP**: Servidores PXE respondiendo a clientes de oficina o viceversa.
3. **Imposibilidad de aprovisionamiento desatendido**: Peticiones PXE descartadas o interceptadas por el router de oficina.

Con la segmentación propuesta en la red `10.100.29.0/24`, se garantiza:
* **Cero interferencias con la oficina**: El switch conmuta el tráfico en una VLAN totalmente estanca.
* **Acceso restringido**: Únicamente los 8 nodos del clúster responden a las peticiones; los equipos de oficina quedan invisibles e inaccesibles desde este segmento.
* **Resolución centralizada de nombres**: Consultas DNS dirigidas al servidor corporativo `192.168.26.120`.

---

## 2. Validación Técnica: El Análisis del Gateway (10.101.29.1 vs 10.100.29.1)

### ¿Por qué requiere especial atención técnica?
La subred indicada es `10.100.29.0/24` y el gateway proporcionado es `10.101.29.1`.
Matemáticamente, en una máscara de 24 bits (`255.255.255.0`):
* **Identificador de red**: `10.100.29.0`
* **Rango de hosts utilizables**: `10.100.29.1` hasta `10.100.29.254`
* **Dirección de broadcast**: `10.100.29.255`

La dirección IP `10.101.29.1` **pertenece a una red distinta** (el segundo octeto es `101`, no `100`).

```
Subred Local:     00001010 . 01100100 (100) . 00011101 (29) . 00000000
Gateway Provisto: 00001010 . 01100101 (101) . 00011101 (29) . 00000001
                             ^^^^^^^^ (Difieren en el segundo octeto)
```

En IPv4 estándar, cuando un host con IP `10.100.29.X/24` intenta enviar un paquete a internet o al DNS `192.168.26.120` a través de un gateway fuera de su subred, el kernel de Linux ejecuta el algoritmo de enrutamiento y arroja el error:
```bash
RTNETLINK answers: Network is unreachable
```

### Opciones de Solución de Ingeniería:
1. **Caso 1: Error de dedo frecuente (Gateway Real: `10.100.29.1`)**
   * El gateway es la interfaz virtual del switch (SVI) o el router en la misma subred: `10.100.29.1`.
   * Esta es la arquitectura estándar de redes empresariales.

2. **Caso 2: Enrutamiento On-Link explícito**
   * Si la infraestructura de la empresa tiene configurado el router en `10.101.29.1` escuchando en el mismo cable físico, Linux permite alcanzarlo forzando una ruta directa de Capa 2:
     ```bash
     ip route add 10.101.29.1/32 dev <interfaz> scope link
     ip route add default via 10.101.29.1 dev <interfaz>
     ```

3. **Caso 3: Máscara Supernet (/15)**
   * Si la red en realidad tiene máscara `255.254.0.0` (`/15`), entonces `10.100.0.0/15` abarca desde `10.100.0.1` hasta `10.101.255.254`, permitiendo que `10.100.29.X` y `10.101.29.1` convivan en la misma red local.

---

## 3. Plan de Direccionamiento IP y Asignación de Roles

| ID Nodo | Hostname | Rol | Dirección MAC | IP Propuesta (VLAN 29) | Propósito Principal |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **GW** | `switch-svi` / `router` | Gateway L3 | - | `10.100.29.1` (o `10.101.29.1`) | Salida a DNS corporativo |
| **314** | `bastion` | Bastión / K8s Master | `64:00:6a:2a:60:62` | `10.100.29.10` | Acceso SSH seguro / Control Plane |
| **315** | `nexus-repo` | Nexus OSS / K8s Worker | `64:00:6a:2a:5f:99` | `10.100.29.20` | Repositorios APT/Docker/OCI |
| **306** | `pxe-controller` | PXE/TFTP/Ironic | `64:00:6a:2a:62:42` | `10.100.29.30` | Controlador Baremetal & Dnsmasq |
| **269** | `k8s-cp-01` | K8s CP 01 (Leader) | `64:00:6a:2a:5f:f9` | `10.100.29.101` | Etcd & API Server 1 |
| **280** | `k8s-cp-02` | K8s CP 02 | `64:00:6a:2a:60:63` | `10.100.29.102` | Etcd & API Server 2 |
| **320** | `k8s-cp-03` | K8s CP 03 | `64:00:6a:2a:2c:75` | `10.100.29.103` | Etcd & API Server 3 |
| **321** | `k8s-worker-01`| K8s Worker 01 | `64:00:6a:2a:62:a4` | `10.100.29.111` | Cargas de cómputo |
| **279** | `k8s-worker-02`| K8s Worker 02 | `64:00:6a:2a:2f:cb` | `10.100.29.112` | Cargas de cómputo |
| **Admin**| `workstation` | Estación Administrador | - | `10.100.29.250` | Punto de conexión de gestión |

* **Pool Dinámico de Inspección PXE**: `10.100.29.50` a `10.100.29.99` (para descubrimiento y enrolamiento con OpenStack Ironic Inspector).
* **DNS Corporativo**: `192.168.26.120`.

---

## 4. Configuración del Switch de Oficina

### 4.1 Principio de Aislamiento: VLAN de Acceso + DHCP Snooping + PortFast
Para que el switch de la oficina no sufra interrupciones y la red de oficina quede 100% protegida:
1. **Crear VLAN dedicada (ej. VLAN 29)**: Las tramas no pueden saltar entre VLANs sin pasar por un router.
2. **Puertos en Modo Access**: Los puertos donde se conectan los 8 nodos y el nodo 306 deben estar en modo acceso con VLAN 29.
3. **PortFast**: Evita que los puertos tarden 30 segundos en habilitarse durante el arranque PXE.
4. **BPDU Guard**: Desconecta inmediatamente cualquier puerto si alguien conecta accidentalmente otro switch.
5. **DHCP Snooping**: Marca como "trusted" únicamente el puerto del Nodo 306 para la VLAN 29, e impide que cualquier paquete DHCP del clúster viaje a la VLAN de oficina.

### 4.2 Sintaxis para Switch Cisco (Catalyst / CBS / SG-Series)
```cisco
! 1. Ingresar al modo privilegiado y configuración global
enable
configure terminal

! 2. Crear la VLAN del Clúster
vlan 29
 name CLUSTER_BAREMETAL_ISOLATED
 exit

! 3. Configurar los puertos físicos de los nodos (ejemplo: puertos GigabitEthernet 1/0/1 al 1/0/9)
interface range GigabitEthernet 1/0/1 - 9
 description CONEXION_NODOS_CLUSTER_BAREMETAL
 switchport mode access
 switchport access vlan 29
 spanning-tree portfast
 spanning-tree bpduguard enable
 exit

! 4. Proteger contra Rogue DHCP (DHCP Snooping)
ip dhcp snooping
ip dhcp snooping vlan 29
no ip dhcp snooping information option

! 5. Marcar como CONFIABLE ÚNICAMENTE el puerto del Nodo 306 (ejemplo: Gi 1/0/3)
interface GigabitEthernet 1/0/3
 description NODO_306_PXE_CONTROLLER_DHCP
 ip dhcp snooping trust
 exit

! 6. (Opcional - Switch L3) Configurar la IP del Gateway en el Switch si actúa como SVI:
interface Vlan 29
 description GATEWAY_CLUSTER_VLAN
 ip address 10.100.29.1 255.255.255.0
 no shutdown
 exit

! 7. Guardar cambios
write memory
```

### 4.3 Sintaxis para Switch MikroTik (RouterOS v7)
```routeros
# 1. Crear la VLAN en la interfaz bridge
/interface vlan add name=vlan29_cluster vlan-id=29 interface=bridge

# 2. Asignar los puertos del clúster a la VLAN 29 (ejemplo ether2 a ether10)
/interface bridge port
set [find interface=ether2] pvid=29 edge=yes bpdu-guard=yes
set [find interface=ether3] pvid=29 edge=yes bpdu-guard=yes
set [find interface=ether4] pvid=29 edge=yes bpdu-guard=yes

# 3. Asignar IP al Gateway en MikroTik si actúa como router:
/ip address add address=10.100.29.1/24 interface=vlan29_cluster

# 4. Aislar tráfico en firewall para que la VLAN 29 no pueda hablar con la red de oficina:
/ip firewall filter
add chain=forward src-address=10.100.29.0/24 dst-address=192.168.21.0/24 action=drop comment="Bloquear cluster -> oficina"
add chain=forward src-address=192.168.21.0/24 dst-address=10.100.29.0/24 action=drop comment="Bloquear oficina -> cluster"
add chain=forward src-address=10.100.29.0/24 dst-address=192.168.26.120 action=accept comment="Permitir consulta DNS"
```

### 4.4 Sintaxis para Switch HP / Aruba (AOS-S)
```cli
configure terminal
vlan 29
   name "CLUSTER_ISOLATED"
   untagged 1-9
   exit

spanning-tree 1-9 admin-edge-port
dhcp-snooping
dhcp-snooping vlan 29
dhcp-snooping trust 3
write memory
```

---

## 5. Control de Acceso: "Llamar desde ahí SOLO a los nodos y no a otros equipos"

Para cumplir la regla estricta de que el tráfico desde este segmento **únicamente llame a los nodos** y no pueda escanear ni colisionar con equipos de la oficina:

### 5.1 Lista de Control de Acceso (ACL) en el Switch / Router Perimetral
```cisco
! Definir ACL de aislamiento
ip access-list extended ACL_CLUSTER_STRICT_ISOLATION

 ! 1. Permitir comunicación interna entre los nodos del clúster
 permit ip 10.100.29.0 0.0.0.255 10.100.29.0 0.0.0.255

 ! 2. Permitir consultas DNS al servidor corporativo 192.168.26.120
 permit udp 10.100.29.0 0.0.0.255 host 192.168.26.120 eq 53
 permit tcp 10.100.29.0 0.0.0.255 host 192.168.26.120 eq 53

 ! 3. DENEGAR terminantemente cualquier acceso al resto de las redes de oficina
 deny ip 10.100.29.0 0.0.0.255 192.168.0.0 0.0.255.255
 deny ip 192.168.0.0 0.0.255.255 10.100.29.0 0.0.0.255

 ! 4. Permitir salida a Internet general si se requiere descargar paquetes
 permit ip 10.100.29.0 0.0.0.255 any

! Aplicar la ACL en la entrada de la interfaz VLAN del clúster
interface Vlan 29
 ip access-group ACL_CLUSTER_STRICT_ISOLATION in
 exit
```

### 5.2 Blindaje con Firewall Linux (`nftables` / `iptables`) en el Nodo 306
En el Nodo 306 (PXE Controller), aplicamos una política de filtrado para que su interfaz física cableada `enp2s0` solo atienda a las direcciones MAC de los nodos:
```bash
# Regla iptables en Nodo 306 para descartar tráfico de equipos no registrados
sudo iptables -A INPUT -i enp2s0 -s 10.100.29.0/24 -m mac --mac-source 64:00:6a:2a:60:62 -j ACCEPT
sudo iptables -A INPUT -i enp2s0 -s 10.100.29.0/24 -m mac --mac-source 64:00:6a:2a:5f:99 -j ACCEPT
# (Aceptar resto de MACs del nodes.csv)...
# Descartar cualquier otra MAC de intrusos
sudo iptables -A INPUT -i enp2s0 -s 10.100.29.0/24 -j DROP
```

---

## 6. Configuración en los Servidores Linux

### 6.1 Configurar la Interfaz Física en el Nodo 306 (`enp2s0`)
Configuramos la IP estática `10.100.29.30/24` en el archivo `/etc/network/interfaces` o mediante `ip`:
```bash
sudo ip addr flush dev enp2s0
sudo ip addr add 10.100.29.30/24 dev enp2s0
sudo ip link set enp2s0 up
```

Si el gateway es `10.100.29.1`:
```bash
sudo ip route add 10.100.29.0/24 dev enp2s0 proto kernel scope link src 10.100.29.30
```

Si el gateway es `10.101.29.1` (on-link):
```bash
sudo ip route add 10.101.29.1/32 dev enp2s0 scope link
```

### 6.2 Actualización de `/etc/dnsmasq.conf` en el Nodo 306
Ajustamos `dnsmasq` para servir el nuevo direccionamiento, entregar el DNS `192.168.26.120`, y amarrar estrictamente las MACs:
```ini
interface=enp2s0
bind-interfaces

# Gateway y DNS Corporativo
dhcp-option=3,10.100.29.1
dhcp-option=6,192.168.26.120

# Rango dinámico efímero para inspección PXE / Baremetal
dhcp-range=10.100.29.50,10.100.29.99,255.255.255.0,1h

# Reservas estáticas por MAC (nodes.csv)
dhcp-host=64:00:6a:2a:60:62,10.100.29.10,bastion,24h
dhcp-host=64:00:6a:2a:5f:99,10.100.29.20,nexus-repo,24h
dhcp-host=64:00:6a:2a:62:42,10.100.29.30,pxe-controller,24h
dhcp-host=64:00:6a:2a:5f:f9,10.100.29.101,k8s-cp-01,24h
dhcp-host=64:00:6a:2a:60:63,10.100.29.102,k8s-cp-02,24h
dhcp-host=64:00:6a:2a:2c:75,10.100.29.103,k8s-cp-03,24h
dhcp-host=64:00:6a:2a:62:a4,10.100.29.111,k8s-worker-01,24h
dhcp-host=64:00:6a:2a:2f:cb,10.100.29.112,k8s-worker-02,24h

# Servidor TFTP Integrado
enable-tftp
tftp-root=/tftpboot

# Encadenamiento iPXE e Ironic HTTPBoot
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:ipxe,http://10.100.29.30:8089/boot.ipxe
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:!ipxe,tag:bios,undionly.kpxe
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-boot=tag:!ipxe,tag:efi-x86_64,ipxe.efi

log-dhcp
dhcp-ignore=tag:!known
```

---

## 7. Protocolo de Pruebas y Validación Forense

### Prueba 1: Verificar que NO hay fuga de DHCP hacia la red de oficina
En cualquier máquina de la oficina o en la interfaz Wi-Fi:
```bash
sudo tcpdump -i any -n "port 67 or port 68"
```
* **Resultado esperado**: Se observan únicamente las peticiones y respuestas del DHCP del router de oficina (`192.168.21.1` o `192.168.28.1`). **Cero** paquetes provenientes de `10.100.29.30`.

### Prueba 2: Verificar conectividad exclusiva hacia los nodos
Desde tu máquina en el segmento `10.100.29.X`:
```bash
# 1. Ping hacia los nodos del clúster (DEBE responder)
ping -c 2 10.100.29.10
ping -c 2 10.100.29.20
ping -c 2 10.100.29.30

# 2. Ping hacia equipos de la oficina (DEBE ser bloqueado / timeout)
ping -c 2 10.100.29.X   # IP de usuario no registrado -> Bloqueado
ping -c 2 192.168.21.38 # IP de oficina -> Destination Host Unreachable / Filtered

# 3. Consulta DNS al servidor corporativo (DEBE responder)
dig @192.168.26.120 google.com +short
```

### Prueba 3: Detección de colisiones ARP
En el Nodo 306:
```bash
sudo arping -I enp2s0 -c 3 10.100.29.30
```
* **Resultado esperado**: `0 replies received`. Si responde alguna MAC adicional, indica que otra máquina tiene esa misma IP configurada estáticamente.

---

## 8. Arquitectura Definitiva en Producción (Topología As-Built)

La solución final adoptada e implementada en el laboratorio garantiza **cero impacto y aislamiento absoluto** mediante la siguiente topología física y lógica:

```
 [ Tu Laptop Admin ] (192.168.29.16)
       │ (100% Conectada por Wi-Fi wlp4s0)
       ▼
 ┌────────────────────────────────────────────────────────┐
 │                      WIFI OFICINA                      │
 └─────────────────────────┬──────────────────────────────┘
                           │
                           ▼ (Wi-Fi wlp3s0: 192.168.29.25)
                  ┌─────────────────┐
                  │    Nodo 306     │ (Jump Host / NAT Router / PXE)
                  │(pxe-controller) │
                  └────────┬────────┘
                           │ (Ethernet enp2s0: 10.100.29.30)
 ══════════════════════════╪════════════════════════════════════════════════
                           ▼
            ┌─────────────────────────────┐
            │   SWITCH AISLADO PRIVADO    │ ◄── [DESCONECTADO DE LA PARED]
            │      (10.100.29.0/24)       │     (Cero colisiones L2 / DHCP)
            └──────┬───────────────┬──────┘
                   │               │
                   ▼               ▼
            ┌─────────────┐ ┌──────────────┐ ┌─────────────────────────┐
            │  Nodo 314   │ │   Nodo 315   │ │ Nodos K8s (269, 280,    │
            │  (bastion)  │ │ (nexus-repo) │ │ 320, 321, 279)          │
            │10.100.29.10 │ │10.100.29.20  │ │10.100.29.101..112       │
            └─────────────┘ └──────────────┘ └─────────────────────────┘
```

### Características de la Topología Operativa:
1. **Switch Dedicado sin Enlace a la Pared**: El switch del clúster físico no posee ningún cable Ethernet conectado a las tomas de red de la empresa. Las tramas L2 (ARP, DHCP, STP) están físicamente confinadas.
2. **Laptop sin Cables**: El ingeniero opera de forma remota a través de la Wi-Fi corporativa.
3. **Nodo 306 como Pasarela Dual**:
   * **wlp3s0 (Wi-Fi)**: Recibe peticiones SSH y realiza NAT Masquerade saliente para dar internet al clúster (`iptables -t nat -A POSTROUTING -o wlp3s0 -j MASQUERADE`).
   * **enp2s0 (Ethernet)**: Asigna IPs fijas y dinámicas en `10.100.29.0/24`, despacha TFTP/HTTPBoot y orquesta los metadatos de Cloud-Init.
4. **Túneles Locales Disponibles**:
   * `kubectl` en Laptop ➔ `https://127.0.0.1:6443` (túnel SSH hacia `10.100.29.10:6443`).
   * Sonatype Nexus Web UI ➔ `http://localhost:8081` (túnel SSH hacia `10.100.29.20:8081`).


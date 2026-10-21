# Runbook: Blindaje y Aislamiento de la Red Corporativa de Oficina

> **Clasificación**: Operaciones de Infraestructura / Seguridad de Red  
> **Subred Privada del Clúster**: `10.100.29.0/24`  
> **Subred Corporativa / Oficina**: `192.168.29.0/24` (o `10.101.29.0/24`)  
> **Nodo Dual-Homed (Gateway/PXE)**: Nodo 306 (`192.168.29.25` Wi-Fi / `10.100.29.30` Ethernet)  

---

## 1. Objetivo y Principio Rector de Seguridad

El objetivo primordial de este runbook es **garantizar el aislamiento L2 absoluto del clúster de servidores respecto a la red corporativa de oficina**.  
Bajo ninguna circunstancia los servicios internos del clúster (servidor DHCP `dnsmasq`, servidor TFTP, Nginx HTTPBoot, Cloud-Init, etcd, RKE2, Cilium) deben interferir, colisionar o ser accesibles sin autorización desde las estaciones de trabajo de los empleados de la oficina.

---

## 2. Reglas Físicas Inquebrantables

1. **Switch Privado 100% Desconectado del Switch de Oficina**:
   - El switch de 8/16 puertos donde se conectan los Dell OptiPlex 3020M **NO tiene ni debe tener ningún cable de subida (uplink)** hacia la pared, rosetas RJ45 o switches de oficina.
2. **Laptop de Administración Únicamente por Wi-Fi**:
   - La laptop del operador se conecta a la red de la oficina mediante Wi-Fi (`192.168.29.16`).
   - **NUNCA conectar cable de red Ethernet** entre la laptop y el switch privado. Toda gestión se realiza mediante SSH y túneles TCP pasando por el Nodo 306 (`ProxyJump n306-wifi`).

---

## 3. Prevención de Colisión DHCP (Rogue DHCP Server)

El riesgo más crítico es que el servidor DHCP del clúster responda a clientes de la oficina, asignándoles IPs incorrectas y cortándoles el acceso a internet.

### Configuración en Nodo 306 (`/etc/dnsmasq.conf`)
Verificar que `dnsmasq` escuche **únicamente** en la interfaz Ethernet privada:

```ini
# AMARRE OBLIGATORIO DE INTERFAZ FÍSICA
interface=enp2s0
bind-interfaces
except-interface=lo
except-interface=wlp3s0
```

### Verificación de Aislamiento DHCP
Desde el Nodo 306, validar que `dnsmasq` no emite broadcasts en la interfaz Wi-Fi:

```bash
# 1. Comprobar sintaxis de dnsmasq
sudo dnsmasq --test

# 2. Comprobar sockets en escucha (debe estar solo en 10.100.29.30:67)
sudo ss -ulnp | grep 67

# 3. Monitorear paquetes DHCP en Wi-Fi (NO DEBEN APARECER OFERTAS DEL NODO 306)
sudo tcpdump -i wlp3s0 -n "port 67 or port 68" -c 10
```

---

## 4. Enrutamiento y Salida a Internet Controlada (NAT Masquerade)

Los nodos del clúster necesitan descargar paquetes de Debian y binarios de RKE2. La salida se canaliza mediante masquerading en el Nodo 306 hacia su interfaz Wi-Fi.

### Reglas Activas de iptables
```bash
# Habilitar reenvío de paquetes en el kernel
sudo sysctl -w net.ipv4.ip_forward=1

# Regla de Masquerade exclusiva hacia la interfaz Wi-Fi de salida
sudo iptables -t nat -A POSTROUTING -o wlp3s0 -j MASQUERADE

# Forwarding solo para tráfico establecido o originado en el clúster
sudo iptables -A FORWARD -i enp2s0 -o wlp3s0 -j ACCEPT
sudo iptables -A FORWARD -i wlp3s0 -o enp2s0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlp3s0 -o enp2s0 -j DROP
```

### Persistencia de Reglas
```bash
sudo netfilter-persistent save
# O guardar manualmente en /etc/iptables/rules.v4
```

---

## 5. Acceso Remoto Seguro: Túneles SSH desde la Laptop

Para administrar la infraestructura sin tocar físicamente los servidores:

```bash
# 1. Acceso a consola de cualquier nodo interno
ssh -J n306 debian@10.100.29.10     # Bastion
ssh -J n306 debian@10.100.29.20     # Nexus / Worker

# 2. Túnel para Sonatype Nexus UI (puerto 8081)
ssh -L 8081:10.100.29.20:8081 -N -f n306-wifi
# Abrir en navegador: http://localhost:8081

# 3. Túnel para Kubernetes API Server (puerto 6443)
ssh -L 6443:10.100.29.10:6443 -N -f n306-wifi
# Usar kubectl local: kubectl --kubeconfig=rke2.yaml get nodes
```

---

## 6. Procedimiento ante Incidente o Alerta de Red

Si el equipo de redes corporativas reporta anomalías o sospecha de colisión IP:

1. **Desconectar interfaz cableada del Nodo 306**:
   ```bash
   sudo ip link set enp2s0 down
   ```
2. **Detener inmediatamente el daemon DHCP**:
   ```bash
   sudo systemctl stop dnsmasq
   ```
3. **Verificar tablas de rutas**:
   ```bash
   ip route show
   # La ruta por defecto de oficina DEBE apuntar al AP de oficina (192.168.29.1 vía wlp3s0)
   ```
4. **Validar que ningún tráfico de la subred 10.100.29.0/24 escape sin NAT**.

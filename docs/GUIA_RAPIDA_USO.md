# 🚀 Guía Rápida de Uso y Operación del Clúster (Paso a Paso)

> **Destinatarios**: Nuevos desarrolladores, DevOps y operadores SRE.  
> **Flota**: 8 Servidores Bare-Metal Dell OptiPlex 3020M (Debian 13 Trixie, Red `10.100.29.0/24`).  
> **Tiempo Estimado de Puesta en Marcha**: 10 minutos.  

---

## 📋 Tabla de Contenidos

1. [Paso 1: Requisitos y Preparación de tu Laptop](#paso-1-requisitos-y-preparación-de-tu-laptop)
2. [Paso 2: Instalación de Llaves y Configuración Automática](#paso-2-instalación-de-llaves-y-configuración-automática)
3. [Paso 3: Verificación de Conectividad con la Flota](#paso-3-verificación-de-conectividad-con-la-flota)
4. [Paso 4: Abrir y Usar los Dashboards Web (Grafana, Horizon, Nexus)](#paso-4-abrir-y-usar-los-dashboards-web-grafana-horizon-nexus)
5. [Paso 5: Gestión de Kubernetes con `kubectl` Local](#paso-5-gestión-de-kubernetes-con-kubectl-local)
6. [Paso 6: Automatización de Infraestructura con `make` y Ansible](#paso-6-automatización-de-infraestructura-con-make-y-ansible)
7. [Paso 7: Resolución Rápida de Problemas Frecuentes](#paso-7-resolución-rápida-de-problemas-frecuentes)

---

## Paso 1: Requisitos y Preparación de tu Laptop

Antes de empezar, asegúrate de cumplir con lo siguiente en tu máquina (Linux, WSL2 en Windows o macOS):

1. **Estar conectado a la red Wi-Fi del laboratorio / oficina** (subred `192.168.28.0/23` o `192.168.29.0/24`).
2. **Tener instaladas las herramientas esenciales**:
   ```bash
   # En Debian / Ubuntu:
   sudo apt update && sudo apt install -y git ssh curl python3 make
   ```
3. **Clonar el repositorio**:
   ```bash
   git clone <URL_DEL_REPOSITORIO>/infra-scripts.git
   cd infra-scripts
   ```

---

## Paso 2: Instalación de Llaves y Configuración Automática

Solicita al administrador del clúster los dos archivos de seguridad y cópialos a tu carpeta del proyecto:

1. **Llave Privada SSH**: Debe quedar en `ansible/keys/cluster_key` (o en `~/.ssh/cluster_key`).
2. **Clave de Ansible Vault**: Debe quedar en `.vault_pass` en la raíz del repositorio.

### Aplicar permisos estrictos (Obligatorio para OpenSSH):
```bash
chmod 600 ansible/keys/cluster_key
chmod 600 .vault_pass
```

### Ejecutar el autoconfigurador de cliente:
El repositorio cuenta con un script que configura tus accesos directos SSH, ProxyJump y dependencias con un solo comando:
```bash
./scripts/client/setup-client-workstation.sh
```

*(Esto crea automáticamente en tu `~/.ssh/config` los atajos para saltar al clúster a través del Nodo 306).*

---

## Paso 3: Verificación de Conectividad con la Flota

Comprueba que puedes comunicarte con los servidores físicos:

```bash
# 1. Probar que responde el controlador Wi-Fi (Nodo 306):
ping -c 2 192.168.29.25

# 2. Entrar por SSH directo a cualquier servidor usando sus alias:
ssh controller      # Entra al Nodo 306 (pxe-controller)
ssh bastion         # Entra al Nodo 314 (bastión y proxy)
ssh nexus-repo      # Entra al Nodo 315 (servidor de paquetes)
ssh cp-01           # Entra al Nodo 269 (líder de Kubernetes)

# 3. Ejecutar diagnóstico de salud con semáforo a color:
make health
```

---

## Paso 4: Abrir y Usar los Dashboards Web (Grafana, Horizon, Nexus)

Dado que los servidores están en una red privada aislada (`10.100.29.0/24`), abrimos un puente de túneles SSH hacia tu `localhost`:

### 1. En una terminal independiente, levanta los túneles:
```bash
make tunnels
```
*(Deja esta terminal abierta; mantendrá los puertos enlazados a tu máquina).*

### 2. Abre en tu navegador cualquiera de las consolas web:

| Servicio | URL en tu Navegador | Usuario por Defecto | Propósito Operativo |
| :--- | :--- | :---: | :--- |
| **Grafana** | [http://localhost:3001](http://localhost:3001) | `admin` / *(según vault)* | Métricas de CPU, RAM, red, pods y dashboards. |
| **OpenStack Horizon** | [http://localhost:8080](http://localhost:8080) | `admin` | Consola web de aprovisionamiento bare-metal. |
| **Sonatype Nexus 3** | [http://localhost:8081](http://localhost:8081) | `admin` | Registro de imágenes Docker y paquetes Debian. |
| **Prometheus TSDB** | [http://localhost:9090](http://localhost:9090) | *(Sin clave)* | Explorador de métricas PromQL y estado de targets. |

---

## Paso 5: Gestión de Kubernetes con `kubectl` Local

Puedes administrar el clúster RKE2 directamente desde tu propia laptop sin tener que entrar por SSH a los nodos:

### 1. Descargar y ajustar el `kubeconfig` en tu máquina:
```bash
mkdir -p ~/.kube
scp -i ansible/keys/cluster_key debian@cp-01:/etc/rancher/rke2/rke2.yaml ~/.kube/config
# Apuntar la IP hacia el túnel local:
sed -i 's/127.0.0.1:6443/localhost:6443/g' ~/.kube/config
chmod 600 ~/.kube/config
```

### 2. Con `make tunnels` activo, ejecuta comandos de Kubernetes:
```bash
# Ver los nodos del clúster:
kubectl get nodes -o wide

# Ver todos los pods y microservicios:
kubectl get pods -A

# Ver solo los microservicios de la aplicación:
kubectl get pods -n aplicaciones

# Ver el estado de la red eBPF Cilium:
kubectl get ds -n kube-system cilium
```

---

## Paso 6: Automatización de Infraestructura con `make` y Ansible

No necesitas recordar comandos largos de Ansible. Toda la orquestación está mapeada en el [`Makefile`](file:///home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts/Makefile) de la raíz:

```bash
# Ver menú de ayuda con todos los comandos disponibles:
make help

# 1. Auditoría de red y hardware antes de cualquier despliegue:
make preflight

# 2. Configurar el sistema operativo base Debian 13 en todos los nodos:
make base

# 3. Desplegar Nexus 3, PXE Controller y OpenStack Ironic:
make services

# 4. Desplegar o actualizar el clúster Kubernetes (RKE2 + Cilium):
make platform

# 5. Desplegar toda la infraestructura completa de 0 a 100:
make deploy

# 6. Ejecutar pruebas de sintaxis y calidad de código:
make lint
make syntax-check

# 7. Generar respaldo de seguridad (DR) de etcd y bases de datos:
make backup
```

---

## Paso 7: Resolución Rápida de Problemas Frecuentes

### Problema A: `Connection closed by UNKNOWN port 65535` al correr Ansible o SSH
- **Causa**: El Nodo 306 (`192.168.29.25`) está apagado o no conectó al Wi-Fi.
- **Solución**: Presionar el botón de encendido del chasis físico del Nodo 306. Esperar 45 segundos hasta que responda `ping 192.168.29.25`.

### Problema B: `curl: (7) Failed to connect to localhost port 3001: Connection refused`
- **Causa**: No está corriendo `make tunnels`.
- **Solución**: Abre una ventana de terminal y ejecuta `make tunnels`. Déjala corriendo mientras trabajas.

### Problema C: Kubernetes arroja `connection refused on 127.0.0.1:6443`
- **Causa**: El nodo líder `k8s-cp-01` (`10.100.29.101`) está iniciando o apagado.
- **Solución**: Verifica con `ping 10.100.29.101`. Si está encendido, espera 60 segundos a que etcd establezca quórum.

### Manual Completo de Recuperación ante Desastres:
Para emergencias mayores (apagones totales, pérdida de quórum etcd, discos llenos o caída de Nexus), consulta el manual oficial:  
👉 [**Manual Integral de Instalación y Recuperación (docs/runbooks/manual-integral-instalacion-y-recuperacion.md)**](runbooks/manual-integral-instalacion-y-recuperacion.md).

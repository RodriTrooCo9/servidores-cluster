# Instalar Coroot con Debian 13, Packer y Cloud-Init

Guía de laboratorio para este proyecto. Fecha de revisión: 2026-10-27.
Los comandos se proporcionan para ejecutarlos siguiendo el orden indicado;
no se han instalado servicios ni construido imágenes al escribir este documento.
Se comprobaron sintaxis Bash, Python, YAML y sintaxis HCL con Packer; esto no
sustituye una instalación o compilación de prueba.

## 1. Topología y decisiones

Se propone un servidor Debian 13 independiente con Coroot Community Edition,
Prometheus y ClickHouse mediante Docker Compose. Así puede seguir mostrando datos
cuando RKE2 tenga problemas. El Prometheus del nodo 306 permanece separado.

| Equipo | Instalación |
|---|---|
| Nueva VM Debian 13 de observabilidad | Stack central Compose; incluye un agente para esa VM |
| Bastión 314, Nexus 315 y controlador 306 | Agente systemd |
| Control planes y workers RKE2 | Para este piloto, también agente systemd por host |
| Nuevos nodos construidos con Packer | Binario preinstalado; configuración y arranque en Cloud-Init |

Esta guía utiliza **un agente systemd por host** para simplificar el piloto
mixto. No instalar además un DaemonSet Coroot en esos mismos nodos. La recolección
del host y sus contenedores no equivale a configurar toda la integración de API
Kubernetes; para la integración nativa completa, consultar la alternativa de la
sección 11.

Coroot requiere ClickHouse y un backend de métricas compatible; el stack oficial
incluye Prometheus con receptor Remote Write. No sustituir ClickHouse por Loki o
Tempo. Referencia: [arquitectura](https://docs.coroot.com/installation/architecture/).

Ejemplo de direccionamiento de esta guía:

```text
VM Coroot:             10.100.29.40       PROPUESTA, debe asignarse y comprobarse libre
Gateway de la VM:      10.100.29.30       según inventario lab
Collector y UI:        http://10.100.29.40:19000
Métricas agente host:  http://127.0.0.1:19080/metrics
UI en laptop:          http://127.0.0.1:19000 mediante SSH
```

No reutilizar `.40` sin reservarla. Debe ser alcanzable desde los ocho nodos.
Si la VM se crea dentro de OpenStack, comprobar security groups, rutas y acceso
desde bare-metal; una IP de una red tenant no es automáticamente accesible desde
la LAN. También se puede usar una VM KVM conectada a la LAN.

Para comenzar, reservar como presupuesto de prueba **4 vCPU, 8 GiB RAM y 60 GiB
de disco** en la VM; es una estimación para este proyecto, no un mínimo oficial.
Medir ingesta y almacenamiento antes de extender la retención. Evitar añadir el
stack completo al nodo 306, que ya concentra OpenStack, PXE y monitoreo.

## 2. Comprobaciones previas

En cada máquina Debian que llevará agente:

```bash
cat /etc/os-release
uname -r
test -r /sys/kernel/btf/vmlinux && echo 'BTF disponible'
stat -fc %T /sys/fs/cgroup
grep CONFIG_BPF_EVENTS /boot/config-"$(uname -r)"
sudo systemctl --failed
```

Se espera Debian 13, soporte eBPF y `CONFIG_BPF_EVENTS=y`. BTF se usa para el
perfilado CO-RE. Debian moderno está contemplado por Coroot, pero se debe probar
el kernel efectivo de la imagen. No desactivar Cilium ni cambiar sus ajustes
para instalar Coroot; comprobar convivencia y consumo durante el piloto.
Fuentes: [requisitos](https://docs.coroot.com/installation/requirements/) y
[agente](https://github.com/coroot/coroot-node-agent).

En la nueva VM verificar IP, disco y puertos:

```bash
ip -br address
ip route
df -h /
free -h
sudo ss -lntup
```

## 3. Instalar Docker en la VM Coroot

Ejecutar **solo en la VM nueva dedicada**. No reemplazar Docker ni containerd en
los nodos Kolla o RKE2. Usar una shell Bash con un usuario que tenga sudo.

```bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y ca-certificates curl python3 python3-yaml
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
arch=$(dpkg --print-architecture)
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable\n' "$arch" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

Docker publica soporte para Debian 13 en su
[guía oficial](https://docs.docker.com/engine/install/debian/). En una VM que ya
tenga paquetes de otro origen, revisar esa guía antes de mezclar instalaciones.

## 4. Descargar y preparar el stack central

En la VM, mantener la misma shell y ejecutar:

```bash
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /opt/coroot
cd /opt/coroot
unset LICENSE_KEY

# Resolver una revisión concreta y registrarla para poder reproducirla.
curl -fsSL https://api.github.com/repos/coroot/coroot/commits/main -o upstream.json
COROOT_COMMIT=$(python3 -c 'import json; print(json.load(open("upstream.json"))["sha"])')
printf '%s\n' "$COROOT_COMMIT" > upstream.commit
curl -fsSL "https://raw.githubusercontent.com/coroot/coroot/${COROOT_COMMIT}/deploy/docker-compose.yaml" \
  -o compose.upstream.yaml
```

Antes de continuar, revisar `compose.upstream.yaml`. Se parte del
[Compose oficial](https://github.com/coroot/coroot/blob/main/deploy/docker-compose.yaml),
que incluye servidor, agentes y backends. La revisión descargada puede evolucionar.

Preparar una copia con el puerto del proyecto y sin publicar los backends:

```bash
export COROOT_IP=10.100.29.40
python3 - <<'PY'
import os
from pathlib import Path
import yaml

config = yaml.safe_load(Path('compose.upstream.yaml').read_text())
services = config['services']
assert {'coroot', 'node-agent', 'cluster-agent', 'prometheus', 'clickhouse'} <= services.keys()
services['coroot']['image'] = 'ghcr.io/coroot/coroot:latest'
services['coroot']['ports'] = [os.environ['COROOT_IP'] + ':19000:8080']
services['coroot'].pop('environment', None)  # Community Edition, sin licencia EE
services['prometheus'].pop('ports', None)
services['clickhouse'].pop('ports', None)
# Contención inicial de métricas; ClickHouse tiene su propia retención por proyecto.
services['prometheus']['command'] += [
    '--storage.tsdb.retention.time=3d', '--storage.tsdb.retention.size=5GB']
Path('compose.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
PY

sudo docker compose -f compose.yaml config --quiet
sudo docker compose -f compose.yaml pull
```

Fijar por digest las imágenes efectivamente descargadas, antes del primer arranque:

```bash
sudo docker compose -f compose.yaml config --format json > compose.resolved.json
python3 - <<'PY'
import json, subprocess
from pathlib import Path
import yaml

config = yaml.safe_load(Path('compose.yaml').read_text())
resolved = json.loads(Path('compose.resolved.json').read_text())
for name, service in resolved['services'].items():
    info = json.loads(subprocess.check_output(
        ['sudo', 'docker', 'image', 'inspect', service['image']], text=True))[0]
    digests = info.get('RepoDigests', [])
    if not digests:
        raise SystemExit('No hay digest para ' + name)
    config['services'][name]['image'] = digests[0]
    config['services'][name]['pull_policy'] = 'if_not_present'
Path('compose.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
PY
sha256sum compose.yaml > compose.yaml.sha256
sudo docker compose -f compose.yaml config --quiet
sudo docker compose -f compose.yaml up -d
sudo docker compose -f compose.yaml ps
sudo docker compose -f compose.yaml logs --tail=100 coroot clickhouse prometheus
curl -fsS -o /dev/null http://10.100.29.40:19000/
```

Un error en `pull`, `config` o logs debe resolverse antes de instalar agentes.
Los volúmenes Compose guardan datos entre reinicios. No usar `down -v` para parar
el stack, porque borra sus volúmenes.

## 5. Abrir la UI y configurar el proyecto

Desde la laptop, si la VM es accesible a través del controlador:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:19000:10.100.29.40:19000 n306@192.168.29.25
```

Abrir `http://127.0.0.1:19000`. El puerto local 19000 evita competir con el túnel
8080 de Horizon definido en `scripts/client/tunnels.sh`.

Revisar el proyecto inicial y, cuando corresponda, generar una API key de ingesta
en sus ajustes. Las opciones visibles dependen de la versión fijada. Comprobar
los backends y configurar retención corta para logs, trazas y perfiles mediante
los ajustes disponibles; vigilar el crecimiento de ClickHouse.

La publicación en `10.100.29.40:19000` es para laboratorio aislado. Permitir tráfico
solo desde las redes administradas; revisar reglas efectivas de Docker y del
hipervisor, porque publicar un puerto Docker no equivale a restringirlo con el
firewall de la aplicación. Para redes compartidas o producción, terminar TLS en
un proxy y configurar autenticación antes de enviar una API key. No exponer
19000 directamente a Internet.

## 6. Instalar el agente en un nodo existente

Empezar por **un worker**. No instalar el agente systemd en la VM Coroot, porque
su stack Compose ya incluye uno. En el worker:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsS -o /dev/null http://10.100.29.40:19000/

# Elegir una versión concreta desde Releases y conservar el valor registrado.
read -r -p 'Versión del agente, incluyendo prefijo v: ' AGENT_VERSION
[[ "$AGENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
curl -fsSL https://raw.githubusercontent.com/coroot/coroot-node-agent/main/install.sh \
  -o /tmp/coroot-agent-install.sh
less /tmp/coroot-agent-install.sh
sha256sum /tmp/coroot-agent-install.sh
sudo env COLLECTOR_ENDPOINT=http://10.100.29.40:19000 \
  SCRAPE_INTERVAL=15s LISTEN=127.0.0.1:19080 \
  sh /tmp/coroot-agent-install.sh --version "$AGENT_VERSION"

sudo systemctl is-enabled coroot-node-agent
sudo systemctl is-active coroot-node-agent
sudo journalctl -u coroot-node-agent -n 100 --no-pager
curl -fsS http://127.0.0.1:19080/metrics | head -n 20
```

`head` puede causar una salida anticipada de curl; para una comprobación estricta,
guardar primero `/metrics` en un archivo y después leerlo.

El instalador oficial crea `/etc/systemd/system/coroot-node-agent.service.env`.
Si el proyecto requiere API key, editar ese archivo con `sudoedit`, añadir
`API_KEY=...`, conservar permisos `0600` y reiniciar el agente. No pegar la clave
en scripts versionados ni en la imagen Packer. El agente escucha por defecto en
80; aquí se cambia a loopback:19080 para evitar conflictos.
Fuentes: [instalador](https://github.com/coroot/coroot-node-agent/blob/main/install.sh),
[parámetros](https://docs.coroot.com/configuration/coroot-node-agent/).

Para repetir instalaciones, guardar una copia revisada del instalador y del
binario versionado en el repositorio de artefactos Nexus, junto con su checksum.
El instalador de `main` no queda fijado por elegir una versión de binario.

## 7. Verificar que ya funciona

En la UI deben aparecer el worker y sus servicios después de varios ciclos de
recolección. Generar tráfico contra la aplicación existente:

```bash
# Desde un equipo con acceso a la LAN:
curl -fsS http://10.100.29.111:30080/
curl -fsS http://10.100.29.111:30080/api/orders
```

El puerto 30080 depende de que el Service NodePort del proyecto esté desplegado.
Comprobar que el nodo elegido sea accesible y no esté bloqueado por firewall.

Aceptar el piloto cuando se observe:

- Host identificado correctamente y consumo de CPU/memoria actualizado.
- Servicios y conexiones del worker presentes en el mapa.
- Datos de aplicaciones con tráfico; ausencia de errores continuos de exportación.
- Logs/perfiles cuando las funciones correspondientes estén disponibles y habilitadas.
- Consumo de recursos y disco dentro del presupuesto del laboratorio.
- Recuperación de la ingesta tras reiniciar únicamente el agente.

Luego repetir la sección 6 en los otros siete nodos, uno por uno. El agente puede
observar procesos agrupados en servicios systemd y contenedores; las métricas
internas avanzadas de PostgreSQL/MySQL requieren configurar credenciales de
lectura adicionales en Coroot. No usar la cuenta administrativa de OpenStack
como sustituto de esas credenciales.

## 8. Construir una imagen con Packer

Esta sección es para **nuevas máquinas**. No hace falta reconstruir ni reinstalar
los ocho nodos para comenzar con la sección 6. La plantilla actual
`cloud-init/packer/packer.pkr.hcl` usa una ISO testing y un preseed incompleto;
el siguiente ejemplo se guarda en otro directorio para no sobrescribirla.

Usar una imagen Debian 13 **generic amd64**, con kernel estándar, para los Dell
bare-metal. La variante `genericcloud` utiliza un kernel con menos controladores.
Descargar desde la [infraestructura Debian](https://cloud.debian.org/images/cloud/trixie/)
y consultar sus [tipos de imágenes](https://wiki.debian.org/Cloud).

En una estación Linux de construcción con KVM, Packer y su plugin QEMU:

```bash
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-utils xorriso openssh-client curl
test -r /dev/kvm && test -w /dev/kvm
packer version
mkdir -p /tmp/coroot-image-build/seed
cd /tmp/coroot-image-build
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
sha512sum --ignore-missing --check SHA512SUMS
# Conservar imagen y manifiesto juntos. El checksum comprueba integridad;
# para verificar procedencia, validar también la firma Debian del manifiesto.
test -s debian-13-generic-amd64.qcow2
ssh-keygen -t ed25519 -N '' -f build_key
```

Crear seed exclusivo de construcción. Esta llave no es la llave de producción:

```bash
cat > seed/meta-data <<'EOF'
instance-id: packer-coroot-build
local-hostname: packer-coroot-build
EOF
cat > seed/user-data <<EOF
#cloud-config
users:
  - name: packer
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat build_key.pub)
write_files:
  - path: /etc/sudoers.d/90-packer
    permissions: '0440'
    content: |
      packer ALL=(ALL) NOPASSWD:ALL
EOF
```

Descargar el binario versionado del agente para incorporarlo como artefacto:

```bash
read -r -p 'Versión del agente, incluyendo v: ' AGENT_VERSION
[[ "$AGENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
curl -fsSL "https://github.com/coroot/coroot-node-agent/releases/download/${AGENT_VERSION}/coroot-node-agent-amd64" \
  -o coroot-node-agent
chmod 0755 coroot-node-agent
sha256sum coroot-node-agent > coroot-node-agent.sha256
```

Registrar ese checksum sirve para repetir el artefacto aprobado; no reemplaza
una firma o checksum publicado por el proveedor. Para builds posteriores,
verificar el checksum registrado antes de usar la copia almacenada en Nexus.

Crear `coroot-node-agent.service`:

```ini
[Unit]
Description=Coroot node agent (imagen del proyecto)
Wants=network-online.target
After=network-online.target
ConditionPathExists=/etc/coroot-node-agent/agent.env

[Service]
EnvironmentFile=/etc/coroot-node-agent/agent.env
ExecStart=/usr/local/bin/coroot-node-agent
Restart=always
RestartSec=5
Delegate=yes
LimitNOFILE=1048576
TasksMax=infinity

[Install]
WantedBy=multi-user.target
```

Esta unidad es propia del proyecto y usa rutas diferentes al instalador de la
sección 6. Elegir un método por host y no ejecutar ambos instaladores encima.

Crear `debian13-coroot.pkr.hcl`:

```hcl
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "image_path" { type = string }
variable "image_checksum" { type = string }

source "qemu" "debian13" {
  iso_url              = var.image_path
  iso_checksum         = var.image_checksum
  disk_image           = true
  output_directory     = "output-debian13-coroot"
  vm_name              = "debian13-coroot.qcow2"
  format               = "qcow2"
  disk_size            = "20G"
  accelerator          = "kvm"
  headless             = true
  memory               = 2048
  cpus                 = 2
  disk_interface       = "virtio"
  net_device           = "virtio-net"
  cd_files             = ["seed/user-data", "seed/meta-data"]
  cd_label             = "cidata"
  ssh_username         = "packer"
  ssh_private_key_file = "build_key"
  ssh_timeout          = "15m"
  shutdown_command     = "sudo sh -c 'rm -f /home/packer/.ssh/authorized_keys /etc/sudoers.d/90-packer; usermod -s /usr/sbin/nologin packer; cloud-init clean --logs --machine-id --seed; shutdown -P now'"
}

build {
  sources = ["source.qemu.debian13"]
  provisioner "shell" {
    inline = ["sudo cloud-init status --wait"]
  }
  provisioner "file" {
    source      = "coroot-node-agent"
    destination = "/tmp/coroot-node-agent"
  }
  provisioner "file" {
    source      = "coroot-node-agent.service"
    destination = "/tmp/coroot-node-agent.service"
  }
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl",
      "sudo install -m 0755 /tmp/coroot-node-agent /usr/local/bin/coroot-node-agent",
      "sudo install -m 0644 /tmp/coroot-node-agent.service /etc/systemd/system/coroot-node-agent.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable coroot-node-agent",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /var/lib/dbus/machine-id"
    ]
  }
}
```

El servicio queda habilitado pero no arranca hasta que exista su configuración.
No se incorpora endpoint, API key ni identidad de un nodo real a la imagen.
El usuario temporal queda sin llave, sin sudo y con shell deshabilitada al apagar.
El seed `cidata` de construcción no debe adjuntarse a los nodos desplegados.
Referencia del builder: [Packer QEMU](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu).

```bash
packer init debian13-coroot.pkr.hcl
packer fmt debian13-coroot.pkr.hcl
checksum="sha512:$(sha512sum debian-13-generic-amd64.qcow2 | awk '{print $1}')"
packer validate -var "image_path=$PWD/debian-13-generic-amd64.qcow2" \
  -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
packer build -var "image_path=$PWD/debian-13-generic-amd64.qcow2" \
  -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
qemu-img check output-debian13-coroot/debian13-coroot.qcow2
sha256sum output-debian13-coroot/debian13-coroot.qcow2
```

Fijar la versión concreta del plugin QEMU utilizada cuando se apruebe el build.
Este ejemplo requiere probarse con el firmware, disco y NIC de los equipos
destino; el arranque en QEMU no certifica compatibilidad bare-metal.

## 9. Primer arranque con Cloud-Init

Combinar este fragmento con el user-data que ya configura usuario, llave y red.
No crear dos claves `write_files` o `runcmd`: agregar sus elementos a las listas
existentes de `cloud-init/templates/user-data.j2` o del generador realmente usado.

```yaml
#cloud-config
write_files:
  - path: /etc/coroot-node-agent/agent.env
    owner: root:root
    permissions: '0600'
    content: |
      COLLECTOR_ENDPOINT=http://10.100.29.40:19000
      SCRAPE_INTERVAL=15s
      LISTEN=127.0.0.1:19080
runcmd:
  - [systemctl, daemon-reload]
  - [systemctl, enable, --now, coroot-node-agent]
```

Si se habilita API key, inyectarla desde Vault en el despliegue; proteger también
el user-data/config-drive y eliminar las copias temporales. No servir un user-data
con secretos desde `/httpboot` sin controles de acceso. Preferir inyectar la API
key posteriormente por Ansible mediante SSH y `no_log: true`.

El proyecto tiene varios caminos de generación: plantilla Jinja, generador Bash
y script de recuperación. Cambiar la plantilla no actualiza automáticamente los
otros caminos. Aplicar el fragmento en el que se vaya a ejecutar y revisar el
user-data resultante antes de aprovisionar.

Probar una instancia nueva y verificar:

```bash
sudo cloud-init status --wait
sudo systemctl is-active coroot-node-agent
sudo journalctl -u coroot-node-agent -n 100 --no-pager
cat /etc/machine-id
hostnamectl
```

Dos clones deben tener identidad y claves SSH de host diferentes. No publicar
la imagen como aprobada si conserva la identidad o acceso del build.

## 10. Publicar en Glance y usar con Ironic

Desde una estación con cliente OpenStack y su OpenRC cargado:

```bash
openstack token issue -c expires -f value
openstack image create debian13-coroot-lab \
  --disk-format qcow2 --container-format bare --private \
  --file output-debian13-coroot/debian13-coroot.qcow2
openstack image show debian13-coroot-lab -c id -c status -c size
```

El cliente debe poder leer esa ruta local. Si se ejecuta dentro de `kolla_toolbox`,
primero copiar la imagen al contenedor o montar su directorio de forma explícita.

Usar la imagen en el procedimiento de aprovisionamiento probado del laboratorio,
seleccionando el nodo destino de forma explícita. No ejecutar automáticamente
`scripts/ops/disaster-recovery.sh --reprovision` como paso de esta guía: su selección
Nova/Ironic y transporte del user-data siguen pendientes de validación según el
[informe de correcciones](../reference/correcciones-aplicadas-2026-10-27.md).

## 11. Alternativa: integración nativa Kubernetes

Si se prefiere el stack completo dentro de RKE2, usar el operador oficial y sus
agentes, con volúmenes persistentes y versiones fijadas. **Es una alternativa al
servidor externo del piloto**, no un paso adicional obligatorio. No instalar
ambos stacks por accidente ni duplicar agentes en los nodos.

La [instalación Kubernetes oficial](https://docs.coroot.com/installation/kubernetes/)
documenta los charts. Consultar valores y recursos de la versión elegida antes
de instalar, porque los valores de almacenamiento y topología dependen del CR.

```bash
kubectl config current-context
kubectl get nodes
kubectl get storageclass
helm repo add coroot https://coroot.github.io/helm-charts
helm repo update coroot
helm search repo coroot --versions
```

Seleccionar versiones, revisar sus valores y preparar un archivo de valores para
el almacenamiento/capacidad disponible. No copiar sin dimensionar la topología
de varios shards y réplicas del ejemplo oficial a los SSD de 128 GB del proyecto.
La elección de un servidor externo también evita depender de `local-path` para
guardar los datos de Coroot.

## 12. Diagnóstico y mantenimiento

| Síntoma | Revisar |
|---|---|
| UI inaccesible | VM tiene `.40`, binding 19000, túnel, rutas y puertos publicados |
| Agente no arranca | Kernel/eBPF, ruta del binario y permisos del archivo env |
| Choque con puerto 80 | Confirmar `LISTEN=127.0.0.1:19080` en el método de instalación usado |
| Host no aparece | Conectividad al collector, API key/proyecto y journal del agente |
| No hay conexiones | Generar tráfico real; revisar errores eBPF, cgroups y runtime |
| No hay datos internos de DB | Configurar integración y credenciales de solo lectura |
| Disco crece | Retención por señal, volumen ClickHouse, tasa de logs y duplicación con OTel |
| Reinicios/OOM | `docker stats`, `free -h`, logs y presupuesto de la VM |

En la VM:

```bash
cd /opt/coroot
sudo docker compose -f compose.yaml ps
sudo docker compose -f compose.yaml logs --tail=200 coroot node-agent cluster-agent
sudo docker stats --no-stream
sudo docker system df
df -h /
```

Antes de actualizar, registrar configuración y digests, respaldar volúmenes con
un procedimiento consistente para las bases de datos y probar restauración.
Cambiar el digest explícitamente y ensayar en desarrollo. Volver a un digest
anterior puede requerir restaurar datos si hubo migraciones de esquema.

Para detener el piloto conservando datos:

```bash
# VM Coroot:
cd /opt/coroot
sudo docker compose -f compose.yaml stop
# Cada host donde se instaló el agente systemd:
sudo systemctl disable --now coroot-node-agent
```

## 13. Criterio de puesta en funcionamiento

- [ ] VM dedicada accesible por la LAN, sin colisión de IP/puertos.
- [ ] Compose resuelto, imágenes fijadas y contenedores sanos.
- [ ] UI accesible mediante túnel y proyecto configurado.
- [ ] Primer worker visible, tráfico detectado y consumo medido.
- [ ] Ocho nodos visibles sin agentes duplicados.
- [ ] Retención y crecimiento de disco revisados.
- [ ] Reinicio controlado de agente y VM mantiene configuración y datos.
- [ ] Imagen Packer probada en una instancia nueva, si se usa ese camino.
- [ ] Clones con identidades diferentes, sin secretos ni llave del build.
- [ ] Backups y restauración comprobados antes de considerar producción.

## Fuentes

- [Coroot Community Edition](https://docs.coroot.com/)
- [Arquitectura](https://docs.coroot.com/installation/architecture/)
- [Requisitos de Coroot](https://docs.coroot.com/installation/requirements/)
- [Parámetros del agente](https://docs.coroot.com/configuration/coroot-node-agent/)
- [Instalador del agente](https://github.com/coroot/coroot-node-agent/blob/main/install.sh)
- [Compose oficial](https://github.com/coroot/coroot/blob/main/deploy/docker-compose.yaml)
- [Docker para Debian](https://docs.docker.com/engine/install/debian/)
- [Packer QEMU](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [Imágenes Debian](https://wiki.debian.org/Cloud)

# Etapa 1: instalar y poner en funcionamiento Coroot

Primero se instala Coroot sobre una VM Debian 13 existente y se conecta un
worker del proyecto. Después de validar datos y consumo se incorporan los demás
nodos. Packer, reconstrucción de imágenes, Cloud-Init y reprovisión quedan fuera
de esta etapa.

**Punto de partida:** disponer de una VM Debian 13 con sudo, salida a Internet y
acceso desde la LAN del clúster. Si todavía no existe, crearla antes de comenzar.
La dirección `10.100.29.40` de los ejemplos es una propuesta, no una IP ya
aprovisionada. Sustituirla en todos los comandos si se elige otra.

**Dónde ejecutar cada paso:** secciones 3–4 en la VM Coroot; sección 5 en la
laptop; sección 6 en un worker; sección 7 desde la UI y un equipo con acceso a la
LAN. Los ejemplos se revisaron estáticamente; no se ha instalado Coroot en los
servidores durante la preparación de esta guía.

## 1. Topología y decisiones

Se propone un servidor Debian 13 independiente con Coroot Community Edition,
Prometheus y ClickHouse mediante Docker Compose. Así puede seguir mostrando datos
cuando RKE2 tenga problemas. El Prometheus del nodo 306 permanece separado.

| Equipo | Instalación |
|---|---|
| Nueva VM Debian 13 de observabilidad | Stack central Compose; incluye un agente para esa VM |
| Bastión 314, Nexus 315 y controlador 306 | Agente systemd |
| Control planes y workers RKE2 | Para este piloto, también agente systemd por host |

Esta guía utiliza **un agente systemd por host** para simplificar el piloto
mixto. No instalar además un DaemonSet Coroot en esos mismos nodos. La recolección
del host y sus contenedores no equivale a configurar toda la integración de API
Kubernetes. La integración nativa mediante operador queda para una etapa posterior.

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

Solo después de aprobar el piloto, repetir la sección 6 en los otros siete nodos, uno por uno. El agente puede
observar procesos agrupados en servicios systemd y contenedores; las métricas
internas avanzadas de PostgreSQL/MySQL requieren configurar credenciales de
lectura adicionales en Coroot. No usar la cuenta administrativa de OpenStack
como sustituto de esas credenciales.

## 8. Diagnóstico y mantenimiento

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

## 9. Confirmar que la primera etapa terminó

- [ ] Coroot, Prometheus y ClickHouse funcionan en la VM dedicada.
- [ ] La UI abre desde la laptop mediante el túnel SSH.
- [ ] El primer worker aparece y envía telemetría sin errores continuos.
- [ ] Se detecta tráfico de las aplicaciones y se revisa el consumo de recursos.
- [ ] Se comprueba persistencia después de un reinicio controlado del stack.
- [ ] Se incorporan los demás nodos únicamente tras aprobar el piloto.

La [guía ampliada](coroot-debian13-packer.md) contiene la siguiente etapa:
preinstalar el agente en imágenes Packer y configurarlo mediante Cloud-Init.
No hace falta completar esa etapa para usar Coroot en los nodos existentes.

## Fuentes

- [Arquitectura Coroot](https://docs.coroot.com/installation/architecture/)
- [Requisitos](https://docs.coroot.com/installation/requirements/)
- [Configuración del agente](https://docs.coroot.com/configuration/coroot-node-agent/)
- [Compose oficial](https://github.com/coroot/coroot/blob/main/deploy/docker-compose.yaml)
- [Docker sobre Debian](https://docs.docker.com/engine/install/debian/)

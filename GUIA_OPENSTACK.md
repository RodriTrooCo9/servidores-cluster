# Instalación de sistemas operativos en máquinas físicas con OpenStack e Ironic

Actualización del 16 de noviembre de 2026.

## 1 Qué vamos a instalar

Este proyecto instala un sistema operativo en una máquina física y comprueba que arranque y permita acceso SSH. OpenStack con Ironic o Ironic standalone administran la instalación por red como alternativas. El procedimiento termina con el sistema operativo disponible; la plataforma de aplicaciones se instala con otra guía.

El repositorio contiene configuración Kolla y roles Ansible para PXE e Ironic. Sigue pendiente validar la instalación por red desde cero hasta el acceso SSH en un equipo físico de prueba. [Estado observado del laboratorio](docs/reference/estado-laboratorio.md)

Para instalar Debian 13 por red con Debian Installer y preseed, usa la [opción independiente de Debian netboot](network/ipxe/debian-netboot/README.md). La [revisión de `pruebaIPXE`](docs/runbooks/integracion-ipxe-debian13.md) conserva la evidencia del entorno original.

### Dependencias del aprovisionamiento

| Operación | Dependencia y efecto de una parada |
|---|---|
| Consultar, registrar o descargar imágenes desde OpenStack | Requiere Glance. Una parada deja el catálogo inaccesible aunque los archivos sigan en su volumen. La ruta por URL directa obtiene la imagen de HTTPBoot. |
| Instalar o reinstalar un equipo mediante Ironic | Requiere la API y el conductor de Ironic. DHCP, TFTP y HTTPBoot pueden seguir entregando el bootloader, el kernel, el initramfs y la imagen. Si IPA arranca y la API de Ironic está caída, el agente no puede registrarse ni completar el despliegue. |
| Aplicar cloud-init en el primer arranque | Requiere que el equipo arranque una imagen con cloud-init y reciba su ConfigDrive o encuentre un origen NoCloud válido. HTTPBoot puede seguir sirviendo NoCloud mientras Ironic está detenido. Esa respuesta HTTP solo verifica que el archivo está publicado. |
| Recuperar un nodo de RKE2 que perdió su sistema operativo | La ruta automatizada con Ironic requiere recuperar primero el SO y SSH. Un nodo con Debian instalado por USB o Debian netboot puede reincorporarse con Ansible cuando cumpla los requisitos de la plataforma. |
| Mantener RKE2, Nexus, aplicaciones y monitoreo existentes | Usan el SO ya instalado, el plano de control de Kubernetes y sus propios servicios. Una parada de Glance o Ironic bloquea el aprovisionamiento y puede retrasar la reposición de capacidad. Una caída de todo `nodo-306` también afecta los servicios de Kubernetes, PXE y monitoreo que ejecuta ese host. |

La opción Debian Installer con preseed usa su propio DHCP, TFTP y HTTP. Su procedimiento requiere un controlador y una red de aprovisionamiento aislados. [Debian netboot](network/ipxe/debian-netboot/README.md)

## 2 Requisitos previos

- Una PC Linux de administración con Git, cliente SSH, Python y `python3-venv`, conectada a la VLAN y Wi-Fi de administración. Para usar las API necesita una ruta real a la red de aprovisionamiento.
- Un controlador con sistema operativo, SSH y privilegios administrativos. En el diseño del laboratorio es `nodo-306`, con Wi-Fi `192.168.29.25` y LAN `10.100.29.30`.
- Una máquina destino de prueba, sin datos que conservar, con MAC, IP, disco y modo de arranque confirmados.
- Una red de aprovisionamiento aislada. El DHCP de pruebas no debe responder en la red de oficina.
- Una imagen del sistema operativo compatible con el equipo. Para la ruta por red, debe incluir cloud-init y un arranque de disco completo compatible con el firmware.
- Un par de llaves SSH propio. Solo la llave pública se incorpora a la máquina destino.
- Una copia independiente de los datos y configuraciones del controlador existente antes de modificar sus servicios.

| Alternativa | Componentes | Dato que debes validar |
|---|---|---|
| Kolla OpenStack | Servicios en contenedores, Ironic y Glance | `openstack/globals.yml` declara 2025.1 e imágenes Ubuntu Noble; valida el sistema del controlador y las interfaces |
| Ironic standalone | PXE local, API y conductor en Podman | El rol usa una imagen Metal3 `latest` y requiere revisión antes de una instalación nueva |

El sistema del controlador y el sistema que instalarás en los destinos son decisiones distintas. Para Kolla 2025.1, comprueba el sistema del controlador en la [matriz oficial](https://docs.openstack.org/kolla-ansible/2025.1/user/support-matrix.html); Debian 13 no figura como host soportado allí. Los destinos pueden recibir Debian 13 si la imagen y sus controladores se validaron para esas máquinas.

## 3 Instalación paso a paso

### Etapa A Preparar el acceso y los datos

**Paso 1. Abrir el repositorio y comprobar el controlador**

- **Dónde:** terminal de la PC de administración, raíz de `infra-scripts`.
- **Para qué:** revisar archivos y acceso sin cambiar la infraestructura.

Si todavía no tienes el proyecto o la llave de acceso, completa la [guía de conexión](GUIA_RAPIDA.md).

Estos comandos comprueban los archivos necesarios y el acceso al controlador.

```bash
test -f openstack/globals.yml && test -f inventory/lab/hosts.yml
ssh -i ansible/keys/cluster_key n306@192.168.29.25 'hostname; cat /etc/os-release; ip -br address'
```

**Resultado esperado:** aparece el controlador correcto, su sistema operativo y las interfaces de las redes previstas. Si cambiaste direcciones o llaves, ajusta el comando antes de ejecutarlo.

**Si aparece un error:** confirma IP, usuario y llave. Resuelve el acceso antes de instalar servicios.

**Paso 2. Registrar la máquina destino y elegir el método**

- **Dónde:** editor de la PC y consola de la máquina destino.
- **Para qué:** identificar exactamente dónde se instalará el sistema operativo.

Anota hostname, MAC, IP, usuario de administración, disco y modo UEFI o BIOS. Comprueba el aislamiento de la VLAN y el método real de encendido. Wake-on-LAN no equivale a un BMC con control completo de energía.

Para instalar un único equipo sin un servicio de aprovisionamiento validado, usa la ruta USB del paso 3. Para instalar por red, elige Kolla o standalone y continúa desde el paso 4. No actives ambas alternativas sobre los mismos equipos o puertos.

### Etapa B Instalar directamente con USB

**Paso 3. Instalar el sistema base en la máquina física**

- **Dónde:** consola física de la máquina destino, no en el controlador.
- **Para qué:** disponer de un sistema operativo aunque el arranque por red todavía no esté preparado.

**Advertencia:** el particionado puede borrar el disco. Comprueba el equipo y el disco antes de aceptar.

Descarga el instalador desde [Debian](https://www.debian.org/distrib/), verifica la imagen y prepara una USB según sus instrucciones. Instala Debian, crea el usuario administrativo y selecciona el servidor SSH. Configura la IP, puerta de enlace y DNS confirmados para ese equipo.

En el primer arranque, estos comandos comprueban el sistema y el acceso de red.

```bash
cat /etc/os-release
ip -br address
ip route
systemctl is-active ssh
```

**Resultado esperado:** Debian arranca desde el disco, la IP es correcta y SSH responde `active`. Continúa con la prueba final; no necesitas desplegar OpenStack para esta ruta.

### Etapa C Preparar la alternativa de aprovisionamiento por red

**Paso 4. Revisar si ya existe un servicio de aprovisionamiento**

- **Dónde:** PC de administración.
- **Para qué:** distinguir un controlador existente de una instalación nueva.

Este comando consulta Docker en el controlador sin iniciar ni detener contenedores.

```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 'sudo docker ps -a --format "{{.Names}} {{.Status}}"'
```

**Resultado esperado:** una lista que permita identificar Ironic y los servicios Kolla si existen. Si Docker no está instalado, revisa también el servicio standalone; ese error no demuestra que el controlador esté vacío.

Este comando consulta la unidad standalone sin modificarla.

```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 'systemctl is-active ironic-conductor'
```

Si ya tienes la alternativa elegida funcionando, conserva su configuración y continúa en el paso 6. No regeneres contraseñas de una nube existente.

**Paso 5A. Preparar Kolla OpenStack si el controlador es nuevo**

- **Dónde:** PC de administración para Kolla-Ansible; controlador como destino.
- **Para qué:** instalar los servicios de aprovisionamiento de la alternativa Kolla.

Sigue la preparación de herramientas y archivos de la [guía oficial de Kolla 2025.1](https://docs.openstack.org/kolla-ansible/2025.1/user/quickstart.html), usando un entorno virtual separado. El repositorio no contiene un instalador completo de Kolla.

Antes de desplegar, revisa estos archivos y requisitos:

| Archivo o requisito | Acción necesaria |
|---|---|
| `openstack/inventory/multinode` | Ajusta usuario, IP y ruta de llave a la PC actual |
| `/etc/kolla/globals.yml` | Prepara la configuración de la nueva instalación usando `openstack/globals.yml` como referencia |
| `node_custom_config` | Sustituye la ruta antigua `kolla/config` por la ruta real a `openstack/config` |
| `/etc/kolla/passwords.yml` | Genera credenciales solo para una nube nueva, protégelas y conserva una copia segura |
| Interfaz externa | Valida `veth-neutron`: el repositorio no crea ni conecta automáticamente ese par |
| Red | Confirma gestión, provisión, VIP libre y ausencia de DHCP competidor |
| Registro de imágenes | Comprueba que el registro configurado permite descargar las imágenes Kolla |

No asignes la interfaz de administración directamente al puente externo: podrías perder SSH. Si alguno de estos requisitos está pendiente, no ejecutes el despliegue.

**Advertencia:** estas órdenes instalan dependencias y pueden modificar Docker, red y servicios del controlador.

Con el entorno Kolla activo y la configuración validada, estas órdenes preparan y despliegan los servicios.

```bash
kolla-ansible -i openstack/inventory/multinode bootstrap-servers
kolla-ansible -i openstack/inventory/multinode prechecks
kolla-ansible -i openstack/inventory/multinode deploy
kolla-ansible -i openstack/inventory/multinode post-deploy
```

**Resultado esperado:** los prechecks y el despliegue terminan correctamente. Conserva de forma privada los archivos de autenticación generados.

**Si aparece un error:** resuelve el primer fallo de `prechecks`; no uses el arranque masivo de contenedores como sustituto de una instalación.

**Paso 5B. Preparar Ironic standalone si eliges esa alternativa**

- **Dónde:** PC de administración, raíz del proyecto, con Ansible, Vault y las colecciones configuradas.
- **Para qué:** preparar PXE e Ironic sin desplegar una nube Kolla.

La [guía de Ansible](GUIA_ANSIBLE.md) explica la preparación de las herramientas compartidas.

**Antes de ejecutar:** el rol `ironic` usa una imagen `latest`, ignora algunos errores y genera nodos desde todo `groups['baremetal']`. Revisa imagen, autenticación, dependencias y plantilla para que el registro incluya únicamente los destinos de prueba. `--limit` sobre el controlador no reduce esa lista generada. Esta rama todavía requiere una prueba completa desde cero.

**Advertencia:** los playbooks modifican DHCP, Nginx, TFTP y el servicio Ironic. Ejecútalos únicamente en la red aislada y sin un servicio Kolla competidor.

Una vez resueltos esos puntos, estas órdenes preparan el controlador standalone.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml
```

Esta consulta comprueba las unidades y el recurso de arranque del controlador.

```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 'systemctl is-active dnsmasq nginx ironic-conductor; curl -fsSI http://10.100.29.30:8089/boot.ipxe'
```

**Resultado esperado:** servicios activos y respuesta HTTP correcta. Esto no demuestra que una máquina pueda instalarse: completa la prueba de un destino dedicado.

### Etapa D Instalar el sistema operativo por red

**Paso 6. Conectar el cliente a la API elegida**

- **Dónde:** PC de administración con acceso a la red de API y un entorno virtual del cliente.
- **Para qué:** consultar Ironic sin ejecutar el despliegue integral del laboratorio.

Este bloque crea un entorno propio e instala los clientes; modifica únicamente la PC.

```bash
python3 -m venv .venv-provision
source .venv-provision/bin/activate
python -m pip install -c https://releases.openstack.org/constraints/upper/2025.1 python-openstackclient python-ironicclient
```

Para Kolla, usa sus credenciales existentes. El siguiente bloque supone que `post-deploy` generó `/etc/kolla/clouds.yaml` en esta PC; sustituye `CAMBIAR_NOMBRE_NUBE` por la entrada real de ese archivo, sin publicar su contenido.

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=CAMBIAR_NOMBRE_NUBE
openstack token issue -f value -c expires
baremetal node list
```

Para standalone usa otra terminal limpia. Si la API fue configurada sin autenticación, este bloque selecciona su endpoint de la red aislada; adapta la autenticación si utilizas otra estrategia.

```bash
export OS_AUTH_TYPE=none
export OS_ENDPOINT=http://10.100.29.30:6385/
baremetal node list
```

El formato de variables corresponde a la [configuración oficial del cliente standalone](https://docs.openstack.org/ironic/2025.1/install/standalone/configure.html#using-cli).

**Resultado esperado:** Ironic devuelve su lista de nodos. Una lista vacía significa que debes completar el registro, no que ya se instaló el sistema operativo.

**Paso 7. Verificar el registro del destino**

- **Dónde:** misma terminal del cliente, con una sola alternativa seleccionada.
- **Para qué:** confirmar que la orden de instalación irá a la máquina correcta.

La plantilla existente `ansible/roles/ironic/templates/baremetal.yaml.j2` sirve como referencia de inventario, pero no certifica el driver de cada equipo. Si falta el registro, sigue el [enrolamiento oficial](https://docs.openstack.org/ironic/2025.1/install/standalone/enrollment.html) con un driver realmente disponible y su configuración de energía y arranque. No inventes datos IPMI para equipos que no tienen BMC.

Este bloque selecciona el UUID real y comprueba el nodo y su MAC; sustituye el marcador antes de ejecutarlo.

```bash
NODE_UUID='CAMBIAR_UUID_DEL_DESTINO'
baremetal node show "$NODE_UUID" -c name -c provision_state -c last_error
baremetal port list --node "$NODE_UUID"
```

**Resultado esperado:** nombre y MAC del equipo de prueba, sin error pendiente y con estado `available` antes del despliegue. Si no está disponible, completa y valida su registro con el administrador; no fuerces el estado para saltar un fallo.

**Paso 8. Preparar imagen y datos de primer arranque**

- **Dónde:** PC de administración y servidor que ya entregue las imágenes por HTTP.
- **Para qué:** elegir qué sistema y qué configuración recibirá el destino.

Usa una imagen de disco completo, con cloud-init, validada en una máquina de prueba con el mismo modo de arranque. Verifica su firma o checksum con el proveedor antes de usarla. Confirma que Ironic, el agente IPA y el destino pueden alcanzar la URL. El controlador necesita además kernel y ramdisk IPA compatibles y accesibles según su configuración.

En el editor crea `configdrive-so.json` con este formato y sustituye **todos** los valores `CAMBIAR_...`. Solo se coloca una llave pública.

```json
{
  "meta_data": {
    "hostname": "CAMBIAR_HOSTNAME",
    "public_keys": {"admin": "CAMBIAR_LLAVE_PUBLICA_SSH"}
  },
  "network_data": {
    "links": [{"id": "lan", "type": "phy", "ethernet_mac_address": "CAMBIAR_MAC"}],
    "networks": [{"id": "provision", "type": "ipv4", "link": "lan", "ip_address": "CAMBIAR_IP", "netmask": "CAMBIAR_MASCARA", "gateway": "CAMBIAR_GATEWAY"}],
    "services": [{"type": "dns", "address": "CAMBIAR_DNS"}]
  }
}
```

Este ejemplo usa los campos de metadatos del proyecto y el formato ConfigDrive de Ironic. La imagen elegida debe interpretar esos datos y crear su usuario de acceso; en las imágenes Debian utilizadas por el proyecto se espera `debian`. Compruébalo en la VM de prueba. El generador Bash heredado incorpora ajustes de otros servicios y no se usa en esta secuencia.

Estas órdenes protegen el archivo y comprueban su sintaxis; no instalan el sistema.

```bash
chmod 600 configdrive-so.json
python3 -m json.tool configdrive-so.json > /dev/null
```

**Resultado esperado:** JSON válido, sin marcadores pendientes y con IP, MAC y llave pública correctos.

**Paso 9. Validar y desplegar un único destino**

- **Dónde:** misma terminal del cliente.
- **Para qué:** instalar la imagen elegida en el disco de la máquina de prueba.

Este bloque modifica los parámetros de imagen del nodo en Ironic. Sustituye la URL y el SHA256 por los valores reales de esa misma imagen de disco completo.

```bash
IMAGE_URL='CAMBIAR_URL_HTTP_DE_LA_IMAGEN'
IMAGE_SHA256='CAMBIAR_SHA256_VERIFICADO'
baremetal node set "$NODE_UUID" --instance-info image_source="$IMAGE_URL" --instance-info image_os_hash_algo=sha256 --instance-info image_os_hash_value="$IMAGE_SHA256"
baremetal node validate "$NODE_UUID"
```

**Resultado esperado:** las interfaces necesarias para arranque, red, energía y despliegue se validan. Estos comandos siguen el [procedimiento oficial de despliegue Ironic](https://docs.openstack.org/ironic/2025.1/user/deploy.html); no se ha ejecutado esta prueba física durante la corrección documental. Corrige cualquier interfaz requerida que falle antes de continuar.

**Advertencia de borrado:** la siguiente orden puede sobrescribir el disco del UUID seleccionado y reiniciar su máquina. Confirma nombre, MAC, disco y ausencia de datos necesarios. No la ejecutes sobre el controlador ni sobre servidores en servicio.

Esta orden solicita la instalación de un solo nodo y entrega el JSON revisado como ConfigDrive.

```bash
baremetal node deploy "$NODE_UUID" --config-drive "$(cat configdrive-so.json)"
```

Esta consulta muestra el avance y el último error sin reenviar la instalación.

```bash
baremetal node show "$NODE_UUID" -c name -c provision_state -c last_error
```

**Resultado esperado:** termina en `active`, sin `last_error`. Comprueba también la consola y el arranque desde disco: el estado de la API no sustituye la verificación del sistema operativo.

## 4 Prueba final

**Dónde:** PC con el acceso SSH al controlador ya configurado. Si instalaste por USB, todavía debes autorizar tu llave en el destino. La siguiente orden modifica `authorized_keys` de ese usuario y pide su contraseña; cambia los marcadores por tu llave pública, usuario e IP reales.

```bash
ssh-copy-id -i CAMBIAR_LLAVE_PUBLICA_SSH -o ProxyJump=n306@192.168.29.25 CAMBIAR_USUARIO@CAMBIAR_IP
```

Para la ruta por imagen, usa la llave privada correspondiente a la pública de ConfigDrive. Cambia también usuario e IP; este comando consulta la máquina destino mediante el salto del controlador.

```bash
ssh -i CAMBIAR_LLAVE_PRIVADA_SSH -J n306@192.168.29.25 CAMBIAR_USUARIO@CAMBIAR_IP 'hostname; cat /etc/os-release; ip -br address; systemctl is-active ssh'
```

**Resultado esperado:** hostname correcto, sistema operativo elegido, IP prevista y SSH `active`. Desde la consola confirma que el equipo arranca desde su disco local. Si la imagen incluye cloud-init, ejecuta allí `cloud-init status --wait` y revisa su resultado antes de dar la instalación por terminada.

Aquí termina este proyecto. Si después necesitas una plataforma de aplicaciones, sigue su [guía independiente](GUIA_DE_INSTALACION.md).

## 5 Errores frecuentes

| Error | Causa probable | Solución |
|---|---|---|
| No responde SSH al controlador | Red, usuario o llave incorrectos | Comprueba primero la guía de conexión |
| Dos servidores DHCP responden | Alternativas activas sobre la misma red | Conserva un único servicio de aprovisionamiento por red y destino |
| `boot.ipxe` responde y el agente IPA no avanza | HTTPBoot entrega los archivos, pero falta la API indicada en `ipa-api-url` o el conductor | Desde la red de aprovisionamiento comprueba la URL de Ironic y verifica que la API vea un conductor activo |
| Kolla Ironic falla al abrir DHCP, TFTP o HTTPBoot | El controlador local u otra instancia ya usa UDP 67/69 o TCP 8089 | Revisa los procesos e interfaces que escuchan. Define qué servicio atenderá el arranque en ese segmento antes de activarlo |
| `prechecks` falla | Host, interfaces o configuración no compatibles | Resuelve el fallo antes de desplegar Kolla |
| Ironic no muestra el destino | Registro pendiente o cliente conectado a otra API | Revisa endpoint, alternativa y enrolamiento |
| Ironic devuelve una lista vacía con una cuenta de proyecto | La política puede mostrar solo los nodos accesibles al proyecto | Para auditar todo el inventario Kolla, consulta la API con una credencial de alcance de sistema y un rol autorizado |
| `validate` devuelve un fallo requerido | Driver, arranque, imagen o energía incompletos | Corrige los parámetros concretos del equipo |
| La imagen no descarga | URL inaccesible o checksum de otro archivo | Comprueba acceso desde el aprovisionamiento y el hash exacto |
| `active` pero no arranca el disco | Imagen incompatible con el firmware o disco | Inspecciona la consola y valida la imagen en el mismo modo de arranque |
| Arranca pero no permite SSH | Usuario, metadatos, IP o llave pública incorrectos | Revisa cloud-init por consola y corrige la configuración |

## 6 Comandos útiles

**Dónde:** terminal del cliente con la autenticación de la alternativa correcta. Esta consulta muestra los nodos registrados.

```bash
baremetal node list
```

Esta consulta muestra los drivers que realmente ofrece el servicio.

```bash
baremetal driver list
```

**Dónde:** PC de administración, raíz del repositorio. Esta consulta muestra los contenedores Kolla existentes sin reiniciarlos.

```bash
ssh -i ansible/keys/cluster_key n306@192.168.29.25 \
  'sudo docker ps -a --format "{{.Names}} {{.Status}}"; sudo ss -ltnup'
```

Para comprobar una recuperación de Kolla, consulta `openstack image list` con una credencial de proyecto que tenga acceso al catálogo. En otra sesión, usa una credencial de alcance de sistema autorizada para consultar `baremetal node list` y `baremetal conductor list`. Verifica HTTPBoot y el acceso a Ironic desde la red donde inicia IPA. La prueba completa termina con el arranque desde disco y acceso SSH a un equipo de prueba.

Antes de reactivar el conductor en un controlador compartido con RKE2, revisa los estados de aprovisionamiento y las operaciones pendientes de sus nodos. La configuración del repositorio establece `force_power_state_during_sync = false` para que la sincronización adopte el estado de energía observado en el equipo.

**Dónde:** laptop con Ansible y Vault configurados. **Advertencia:** la siguiente orden crea y copia datos sensibles del Kolla existente; revisa credenciales y almacenamiento antes de usarla.

Este comando ejecuta solo el bloque de respaldo OpenStack, sin respaldar la plataforma de aplicaciones.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup_openstack
```

Ese respaldo requiere Kolla y no corresponde al servicio standalone. Completa la copia de imágenes, volúmenes y configuración real, y prueba una restauración aislada antes de considerarlo recuperable.

## 7 Archivos que sustentan la guía

- [Configuración del proyecto](openstack/README.md), [globals](openstack/globals.yml) e [inventario Kolla](openstack/inventory/multinode).
- [Rol Ironic](ansible/roles/ironic/tasks/main.yml) y [plantilla de inventario baremetal](ansible/roles/ironic/templates/baremetal.yaml.j2).
- [Rol PXE](ansible/roles/pxe_controller/tasks/main.yml) e [inventario de laboratorio](inventory/lab/hosts.yml).

Las direcciones del laboratorio son ejemplos del repositorio, no valores universales. La compatibilidad y los comandos externos se contrastaron con la documentación oficial enlazada; los despliegues y la escritura de discos necesitan su prueba en el entorno de destino.

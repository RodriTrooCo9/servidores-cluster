# Guía de instalación paso a paso

Fecha de preparación: 30 de octubre de 2026.

## 1. ¿Qué vamos a instalar?

Instalaremos una plataforma de servidores físicos con acceso SSH, Nexus, Kubernetes RKE2 y herramientas de monitoreo. El proyecto también permite preparar imágenes Debian y gestionar el arranque de equipos mediante PXE e Ironic, con Kolla OpenStack como alternativa. Al terminar las etapas que hayas elegido y validado, podrás abrir la aplicación de ejemplo y consultar el estado de sus servicios.

> **Para equipos nuevos:** esta guía no debe ejecutarse como reinstalación del clúster que ya funciona. Durante la inspección, el nodo 306 era el único control plane real, pero el inventario del repositorio asignaba ese trabajo a los nodos 269, 280 y 320. Ejecutar los playbooks con un inventario incorrecto puede cambiar servicios, red y datos.

**Límite importante:** el repositorio todavía tiene tramos de instalación incompletos o incompatibles entre sí. Los pasos marcados **ALTO** indican lo que debes resolver antes de continuar con esa etapa. No se ha probado una instalación completa desde cero; las comprobaciones de la infraestructura existente no sustituyen esa prueba.

**Cómo leer los comandos:** los nombres `CAMBIAR_...` son valores que debes sustituir. Los comandos de los playbooks proceden del proyecto; los comandos de preparación y comprobación son instrucciones de esta guía basadas en esos archivos. No ejecutes todos los bloques de una vez.

## 2. Requisitos previos

- Una laptop Linux con acceso a la red de administración y un usuario con `sudo`.
- Servidores nuevos o vacíos, consola física, disco de instalación y una llave USB de Debian. Instalar el sistema operativo puede borrar sus discos.
- Red de aprovisionamiento aislada de la oficina. El DHCP de pruebas no debe responder en la red de oficina.
- IP, MAC, interfaz Ethernet, puerta de enlace y DNS confirmados para cada equipo.
- Acceso a Internet para descargar paquetes, imágenes y herramientas, o copias internas verificadas.
- Una llave SSH propia y un lugar seguro para conservar las contraseñas de Vault y de OpenStack.
- Espacio independiente para respaldos y un entorno aislado para probar la recuperación.

### Sistemas y versiones

**Suposición de esta guía:** laptop Debian/Ubuntu y servidores Debian 13, salvo la decisión de compatibilidad de Kolla explicada en el paso 12.

| Herramienta | Qué pide o contiene el proyecto | Cómo se usa aquí |
|---|---|---|
| Python | Las guías piden 3.11 o superior | Entorno virtual en la laptop; no se cambia el Python del sistema. |
| Ansible Core | Las guías piden 2.17 o superior | Instalar y registrar la versión obtenida; no hay un bloqueo completo de versiones. |
| Colecciones Ansible | `ansible/collections/requirements.yml` | Instalar ese archivo, no una ruta antigua mencionada por algunos scripts. |
| RKE2 | `vars.yml` fija `v1.30.2+rke2r1`; el clúster observado tenía otra versión | Elegir y validar una versión antes de instalar; no copiar automáticamente la versión del clúster existente. |
| kubectl | Debe ser compatible con la versión de Kubernetes elegida | Usar primero el cliente que instala RKE2 en el control plane. |
| Kolla/OpenStack | `openstack/globals.yml` declara `2025.1` | Rama opcional con requisitos propios y compatibilidad pendiente. |
| Packer y QEMU/KVM | Las guías piden Packer 1.10 o superior | Solo necesarios para fabricar imágenes; no hacen falta para instalar Debian manualmente. |
| Nexus | El rol descarga `latest-unix.tar.gz` | Falta fijar una versión y validar su Java y sus opciones de arranque. |
| PostgreSQL | El rol instala el paquete `postgresql` de APT | No garantiza PostgreSQL 16. La instancia observada de Nexus usaba archivos H2. |

**No mezcles estas dos topologías:**

| Equipo | IP de ejemplo del inventario | Trabajo previsto para una instalación nueva |
|---|---|---|
| nodo-314 | `10.100.29.10` | Bastión y proxy |
| nodo-315 | `10.100.29.20` | Nexus |
| nodo-306 | `10.100.29.30`, Wi-Fi `192.168.29.25` | Provisión, OpenStack si se elige y monitoreo |
| nodo-269 | `10.100.29.101` | Primer control plane RKE2 |
| nodo-280 | `10.100.29.102` | Segundo control plane RKE2 |
| nodo-320 | `10.100.29.103` | Tercer control plane RKE2 |
| nodo-321 | `10.100.29.111` | Worker RKE2 |
| nodo-279 | `10.100.29.112` | Worker RKE2 |

Un **control plane** administra Kubernetes; un **worker** ejecuta las aplicaciones. Esta tabla describe el diseño del inventario, no el estado actual del laboratorio. Para ese estado consulta [el registro de inspección](docs/reference/estado-observado-2026-10-30.md).

## 3. Instalación paso a paso

### Etapa A. Preparar equipos y laptop

**Paso 1. Instalar Debian en los equipos nuevos**

- **Dónde:** consola física de cada servidor nuevo.
- **Para qué:** tener un sistema básico al que Ansible pueda conectarse.

**Advertencia:** el particionado del instalador puede borrar el disco. Comprueba el equipo y el disco antes de aceptar.

Descarga la imagen desde [Debian](https://www.debian.org/distrib/), verifica su integridad y prepara la USB según las instrucciones de Debian. Instala el sistema base, el servidor SSH y las herramientas habituales. Para esta primera instalación, instalar Debian manualmente evita depender de un PXE que todavía no existe.

Crea el usuario indicado en `inventory/lab/hosts.yml`: `aget-ic`, `io`, `n306` o `debian`, según el nodo. Si usas otros nombres, cámbialos también en el inventario. Durante el instalador configura la red con las direcciones que hayas confirmado.

**Comprobar:** estos comandos muestran el sistema, la red y la memoria del equipo.

```bash
cat /etc/os-release
ip -br address
ip route
free -h
```

**Resultado esperado:** el sistema elegido y las direcciones correctas, sin IP duplicadas.

**Si aparece un error:** una instalación manual de Debian no crea por sí sola el enrutamiento del nodo 306. Si los demás equipos no tienen Internet, resuelve primero la puerta de enlace y el aislamiento; no cambies rutas al azar.

**Paso 2. Preparar SSH, Python y sudo en cada servidor**

- **Dónde:** consola de cada servidor nuevo, con una cuenta que ya tenga `sudo`.
- **Para qué:** permitir que Ansible ejecute tareas remotas.

**Advertencia:** estos comandos instalan paquetes y activan SSH.

```bash
sudo apt-get update
sudo apt-get install -y python3 sudo openssh-server ca-certificates curl
sudo systemctl enable --now ssh
```

El inventario supone `sudo` sin contraseña. Si todavía no está configurado, usa temporalmente `--ask-become-pass` al ejecutar Ansible. Los comandos posteriores con `sudo` dentro de SSH requieren configurar ese acceso administrativo primero. No desactives el acceso por contraseña hasta comprobar el acceso por llave.

**Advertencia:** una regla `NOPASSWD:ALL` permite administrar todo el equipo; úsala únicamente para la cuenta de gestión elegida. Este comando abre el editor seguro de reglas sudo.

```bash
sudo visudo
```

Añade una regla con el usuario real de ese nodo, sustituyendo `CAMBIAR_USUARIO` antes de guardar.

```text
CAMBIAR_USUARIO ALL=(ALL) NOPASSWD:ALL
```

**Comprobar:** estos comandos verifican SSH y los permisos administrativos.

```bash
systemctl is-active ssh
python3 --version
sudo -v
sudo -n true && echo "Sudo no interactivo disponible"
```

**Resultado esperado:** `active`, una versión de Python y `Sudo no interactivo disponible`.

**Si aparece un error:** si tu usuario no tiene `sudo`, entra con la cuenta administrativa creada durante la instalación y concédele el acceso mediante el procedimiento de Debian.

**Paso 3. Abrir el proyecto en la laptop**

- **Dónde:** terminal Bash de la laptop.
- **Para qué:** ejecutar los comandos desde la raíz correcta del repositorio.

Este comando abre la copia que existe en este equipo; cambia la ruta si trabajas en otra laptop.

```bash
cd /home/rodrigo/Documents/gitlabinf/GuiaImplementacion/infra-scripts
export REPO_DIR="$PWD"
export ANSIBLE_CONFIG="$REPO_DIR/ansible.cfg"
```

Si todavía no tienes una copia, clona la URL real de tu repositorio en una carpeta nueva y entra en ella antes de definir esas variables. La guía no incluye una URL Git porque no se ha verificado una dirección pública utilizable.

**Comprobar:** este comando comprueba los archivos principales.

```bash
test -f ansible/site.yml && test -f inventory/lab/hosts.yml && echo "Proyecto encontrado"
```

**Resultado esperado:** `Proyecto encontrado`.

**Paso 4. Instalar las herramientas de administración**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** tener Ansible y sus dependencias sin mezclarlos con Python del sistema.

**Advertencia:** APT instala paquetes en la laptop; el entorno `.venv` se crea dentro del proyecto.

```bash
sudo apt-get update
sudo apt-get install -y git openssh-client python3 python3-venv python3-pip openssl curl
python3 -m venv .venv
source .venv/bin/activate
python -m pip install "ansible-core>=2.17" ansible-lint yamllint python-openstackclient python-ironicclient
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

**Comprobar:** estos comandos muestran las herramientas y colecciones instaladas.

```bash
ansible --version
ansible-galaxy collection list
openstack --version
```

**Resultado esperado:** Ansible usa `.venv` y aparecen las colecciones del archivo de requisitos.

**Si aparece un error:** activa `.venv` en cada terminal nueva. Si una versión de Python no admite una dependencia, usa una combinación compatible; no fuerces paquetes con `--break-system-packages`.

**Paso 5. Configurar el inventario y comprobar la red**

- **Dónde:** editor de la laptop y consolas de los servidores.
- **Para qué:** decirle a Ansible qué equipo es cada nodo.

**Advertencia:** guardar cambios en estos archivos cambia los destinos de los playbooks.

Edita estas rutas con tu editor:

| Archivo | Qué debes confirmar o cambiar |
|---|---|
| `inventory/lab/hosts.yml` | IP, usuario, MAC, hostname y pertenencia a grupos. |
| `inventory/nodes.csv` | Los mismos equipos, direcciones y nombres para ConfigDrive. |
| `inventory/lab/group_vars/all/vars.yml` | Llave SSH, salto SSH, subred, DNS, gateway, interfaces, IP líder y versión RKE2. |
| `openstack/inventory/multinode` | Solo si eliges Kolla: acceso al controlador y ruta de la llave. |

El DNS `192.168.26.120` y las interfaces `enp2s0` son valores del proyecto: cámbialos si no corresponden a tu red. El nodo 306 necesita una salida de administración y una red de provisión correctamente aisladas.

**ALTO — red:** no hay un único procedimiento automatizado y validado que reconstruya el switch, la VLAN, el Wi-Fi y el NAT del nodo 306. Confirma esa configuración antes de continuar. Consulta [redes](docs/architecture/network/redes.md) y [aislamiento](docs/architecture/network/aislamiento_red_oficina.md), que contienen alternativas y deben adaptarse a tu equipo.

**Comprobar:** este comando revisa que el YAML del inventario pueda leerse sin conectarse a servidores.

```bash
python3 -c 'import yaml; d=yaml.safe_load(open("inventory/lab/hosts.yml")); assert isinstance(d, dict) and "all" in d; print("Inventario YAML legible")'
```

**Resultado esperado:** `Inventario YAML legible`. Comprueba los grupos en el editor; para el diseño de la tabla inicial hay tres control planes y dos workers. La vista de grupos con Ansible se hace después de configurar Vault.

**Paso 6. Configurar llaves SSH**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** entrar sin enviar contraseñas en los comandos.

**Advertencia:** genera una llave solo si todavía no tienes una. No reemplaces una llave existente; comprueba las huellas de los servidores antes de aceptarlas.

Este comando crea una llave nueva con contraseña de protección elegida por ti.

```bash
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519"
```

Estos comandos distribuyen únicamente la llave pública, primero al salto y después a un nodo interno.

```bash
ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" n306@192.168.29.25
ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" -o ProxyJump=n306@192.168.29.25 debian@10.100.29.101
```

Repite el segundo comando con la IP y el usuario de cada nodo. Las IP anteriores solo son válidas si conservaste el direccionamiento del inventario.

**Comprobar:** este comando prueba el acceso al primer nodo interno.

```bash
ssh -J n306@192.168.29.25 debian@10.100.29.101 'hostname; python3 --version'
```

**Resultado esperado:** aparece el nombre del equipo correcto y una versión de Python.

**Si aparece un error:** revisa usuario, IP, llave pública autorizada y permisos de `~/.ssh`. Si SSH informa permisos incorrectos en un archivo de `/etc/ssh/ssh_config.d/`, corrige ese archivo local antes de atribuirlo a la red.

**Paso 7. Crear secretos nuevos con Ansible Vault**

- **Dónde:** laptop, raíz del proyecto, solo para una instalación nueva.
- **Para qué:** guardar contraseñas y el token del clúster cifrados.

**Advertencia:** no generes una contraseña Vault nueva para archivos cifrados que ya existan. Necesitas la contraseña original para abrirlos.

Este comando crea una contraseña privada de Vault solo cuando no existe el archivo.

```bash
umask 077
if [ ! -e .vault_pass ]; then
  openssl rand -base64 32 > .vault_pass
fi
chmod 600 .vault_pass
```

Este comando abre un editor para crear el archivo cifrado de la instalación nueva.

```bash
ansible-vault create inventory/lab/group_vars/all/vault.yml
```

Introduce en el editor estos nombres con valores nuevos y distintos. Los textos `CAMBIAR_...` son instrucciones, no contraseñas utilizables.

```yaml
vault_rke2_token: "CAMBIAR_POR_UN_TOKEN_LARGO_ALEATORIO"
vault_postgres_password: "CAMBIAR_POR_UNA_CONTRASENA_NUEVA"
```

**Comprobar:** este comando verifica el descifrado sin mostrar los valores.

```bash
ansible-vault view inventory/lab/group_vars/all/vault.yml > /dev/null && echo "Vault legible"
```

**Resultado esperado:** `Vault legible`.

**Si aparece un error:** recupera la clave correcta. No sobrescribas `.vault_pass` ni cambies contraseñas de una base existente para hacer coincidir una plantilla. Conserva una copia segura de Vault fuera del proyecto.

**Paso 8. Probar el acceso y la sintaxis**

- **Dónde:** laptop, raíz del proyecto, con `.venv` activado.
- **Para qué:** detectar problemas antes de cambiar servidores.

Estos comandos prueban la conexión y leen el playbook principal.

```bash
ansible-inventory -i inventory/lab/hosts.yml --graph
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/00-preflight/00_ping.yml
ansible-playbook -i inventory/lab/hosts.yml ansible/site.yml --syntax-check
```

**Comprobar:** estas pruebas ejecutan regresiones locales sin desplegar servicios.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

**Resultado esperado:** ningún host inaccesible, sintaxis aceptada y las pruebas terminan en `OK`. En la revisión pasaron 11 pruebas; el número puede cambiar con nuevas versiones del proyecto.

**Si aparece un error:** añade `--ask-become-pass` si falta sudo sin contraseña. No uses `make deploy` para intentar resolver errores de acceso.

### Etapa B. Sistema base y repositorios

**Paso 9. Preparar primero los nodos de infraestructura**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** preparar bastión, Nexus y controlador antes de cambiar los clientes APT.

**Advertencia:** el rol cambia hostname, `/etc/hosts`, red, swap y parámetros del sistema. Puede cortar SSH al reiniciar la red; ten acceso a la consola física. No lo ejecutes sobre una máquina en uso sin revisar sus cambios.

Este comando aplica la base únicamente al grupo de infraestructura.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml --limit infra_core
```

**Comprobar:** este comando vuelve a probar los tres nodos.

```bash
ansible infra_core -i inventory/lab/hosts.yml -m ping
```

**Resultado esperado:** los tres nodos responden correctamente.

**Si aparece un error:** comprueba que `systemd-networkd` es el gestor de red elegido. La plantilla no configura la salida Wi-Fi ni el NAT del nodo 306; conserva un único gestor responsable de cada interfaz.

**Paso 10. Endurecer el bastión**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** instalar Squid y aplicar la configuración SSH y del cortafuegos.

**Advertencia:** este rol cambia SSH y sustituye `/etc/nftables.conf`; la plantilla contiene `flush ruleset`. Comprueba el acceso por llave y las interfaces antes de usarlo.

Este comando aplica el rol de bastión a los nodos de ese grupo.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/02_bastion_hardening.yml
```

**Comprobar:** este comando consulta sus servicios.

```bash
ansible bastion -i inventory/lab/hosts.yml -m command -a 'systemctl is-active ssh squid nftables chrony'
```

**Resultado esperado:** los cuatro servicios aparecen `active`. Esto no comprueba el NAT ni demuestra aislamiento de VLAN.

**Paso 11. Instalar y preparar Nexus antes de los clientes**

- **Dónde:** laptop para Ansible; navegador con acceso al nodo 315 para la configuración inicial.
- **Para qué:** disponer de los repositorios que usarán APT y los contenedores.

**ALTO — versión de Nexus:** el rol descarga una versión `latest` y sustituye sus opciones JVM por una plantilla propia. No se ha validado la combinación de una descarga nueva, Java y esa plantilla. Fija primero una versión de Nexus y sus requisitos con la [documentación del fabricante](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html); no instales una versión nueva copiando opciones de otra.

**ALTO — base de datos:** el rol intenta configurar PostgreSQL, pero en la instalación observada los datos activos estaban en H2. Elige el motor para la instalación nueva y verifica que Nexus realmente lo use. Crear una base PostgreSQL vacía no conecta automáticamente Nexus con ella.

**Advertencia:** después de resolver esos puntos, el siguiente comando instala paquetes, crea usuarios y bases y configura Nexus.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/01_nexus.yml
```

Para acceder desde la laptop, este túnel mantiene el puerto de Nexus disponible en localhost; déjalo abierto.

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8081:10.100.29.20:8081 n306@192.168.29.25
```

Abre `http://127.0.0.1:8081`. Completa el asistente, cambia la credencial administrativa inicial y configura repositorios usando `nexus/repositories.yml` y `nexus/blobstores.yml` como referencia. Esos YAML son declaraciones: el rol no los aplica automáticamente.

Necesitas un proxy Debian accesible como `debian-proxy` y un registro de lectura en `8082`. El mirror de RKE2 configura tanto `docker.io` como `quay.io` en ese puerto: confirma que los repositorios atiendan ambos orígenes antes de desplegar.

**ALTO — APT:** la plantilla del proyecto apunta `trixie` y `trixie-updates` al mismo proxy. El YAML de Nexus solo declara `trixie`. Valida ambas distribuciones y conserva una fuente de actualizaciones de seguridad; no des por hecho que `trixie-updates` esté resuelto.

**Comprobar:** estos comandos revisan Nexus y la distribución Debian inicial desde la segunda terminal de la laptop.

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/service/rest/v1/status
curl -fsSI http://127.0.0.1:8081/repository/debian-proxy/dists/trixie/Release
curl -fsSI http://127.0.0.1:8081/repository/debian-proxy/dists/trixie-updates/Release
```

**Resultado esperado:** Nexus responde HTTP 200 y las distribuciones necesarias pueden descargarse. Si alguna falla, detén aquí el cambio de APT.

**Si aparece un error:** consulta `journalctl -u nexus` en el nodo 315. Revisa Java, la plantilla JVM y la configuración del repositorio. No uses el script del registro Kolla con una contraseña predeterminada: además atiende un caso distinto del grupo de registros requerido por RKE2.

**Paso 12. Preparar los nodos Kubernetes y comprobar APT**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** aplicar la base a los nodos Kubernetes cuando Nexus ya está listo.

**Advertencia:** este comando cambia la red y sustituye `/etc/apt/sources.list` en esos nodos. Continúa solo si el paso anterior pasó y las fuentes de seguridad quedaron resueltas.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml --limit k8s_cluster
```

**Comprobar:** este comando actualiza el índice de paquetes en los clientes.

```bash
ansible k8s_cluster -i inventory/lab/hosts.yml -b -m command -a 'apt-get update'
```

**Resultado esperado:** ningún error de repositorio, DNS, firma o conexión. Revisa también los archivos `.sources` existentes bajo `/etc/apt/sources.list.d/`: cambiar `sources.list` no los elimina.

### Etapa C. Elegir la provisión: Kolla o Ironic standalone

**Paso 13. Elegir una sola alternativa activa por red y equipo**

- **Dónde:** planificación y editor de la laptop.
- **Para qué:** evitar que dos servicios administren el mismo DHCP, API y hardware.

| Alternativa | Qué instala | Qué no debes ejecutar en paralelo sobre los mismos recursos |
|---|---|---|
| Kolla OpenStack | Ironic, Glance, Keystone y servicios OpenStack en contenedores | Los servicios locales PXE/Ironic standalone que compitan por puertos y red. |
| Ironic standalone | El rol del proyecto intenta instalar Ironic con Podman y PXE local | El despliegue Kolla que gestione esos mismos nodos. |

Puedes conservar ambas configuraciones como alternativas. No apuntes ambas a los mismos equipos físicos a la vez.

**Comprobar:** este comando consulta los contenedores existentes en el nodo 306.

```bash
ssh n306@192.168.29.25 'sudo docker ps --format "{{.Names}} {{.Status}}"'
```

**Resultado esperado:** en un equipo nuevo no hay una instalación anterior que puedas confundir con la que vas a crear. Si ves Kolla activo, no continúes como si el equipo estuviera vacío.

**Paso 14A. Preparar Kolla OpenStack desde cero — alternativa A**

- **Dónde:** laptop para Kolla-Ansible y nodo 306 como destino.
- **Para qué:** instalar OpenStack, no solo arrancar contenedores existentes.

**ALTO — compatibilidad:** la matriz oficial de Kolla 2025.1 incluye Debian 12 y Ubuntu 24.04, pero no Debian 13. La configuración del proyecto usa imágenes Ubuntu Noble. Para una instalación nueva, decide y valida una combinación soportada antes de usar esta rama. Que el laboratorio actual funcione sobre Debian 13 no demuestra una instalación nueva soportada. Consulta la [matriz de Kolla 2025.1](https://docs.openstack.org/kolla-ansible/2025.1/user/support-matrix.html).

**ALTO — red:** Kolla necesita una red de gestión y una red externa adecuadas. El proyecto declara `veth-neutron`, pero el playbook no crea ni conecta ese par de interfaces. Falta validar su configuración de red; no sustituyas esa interfaz por la NIC de administración porque podrías perder el acceso.

Una vez resueltos esos requisitos, prepara un entorno separado siguiendo la [guía oficial de Kolla 2025.1](https://docs.openstack.org/kolla-ansible/2025.1/user/quickstart.html). Estos comandos instalan herramientas en un entorno nuevo de la laptop.

```bash
sudo apt-get install -y git python3-dev python3-venv libffi-dev gcc libssl-dev libdbus-glib-1-dev
python3 -m venv .venv-kolla
source .venv-kolla/bin/activate
python -m pip install 'git+https://opendev.org/openstack/kolla-ansible@stable/2025.1'
kolla-ansible install-deps
```

En la laptop de despliegue nueva prepara `/etc/kolla/globals.yml` y `/etc/kolla/passwords.yml` con la plantilla de la versión instalada. Este bloque crea el directorio únicamente si no existe; si aparece `ALTO`, revisa lo que hay antes de continuar.

```bash
if [ -e /etc/kolla ]; then
  printf '%s\n' 'ALTO: /etc/kolla ya existe; no se sustituye su configuración.'
else
  sudo install -d -m 0700 -o "$USER" /etc/kolla
  cp "$VIRTUAL_ENV/share/kolla-ansible/etc_examples/kolla/globals.yml" /etc/kolla/globals.yml
  cp "$VIRTUAL_ENV/share/kolla-ansible/etc_examples/kolla/passwords.yml" /etc/kolla/passwords.yml
  chmod 600 /etc/kolla/globals.yml /etc/kolla/passwords.yml
fi
```

Usa `openstack/globals.yml` como referencia al editar la nueva configuración, corrigiendo `node_custom_config` para apuntar a tu `openstack/config`. Los archivos `passwords.yml.example` y los archivos cifrados de una instalación anterior no son un juego de credenciales listo para una nube nueva.

En una instalación totalmente nueva, este comando genera las contraseñas de Kolla a partir de su plantilla; protege después el archivo y conserva una copia segura.

```bash
kolla-genpwd
chmod 600 /etc/kolla/passwords.yml
```

No uses `kolla-genpwd` para sustituir las contraseñas de una nube en funcionamiento. Ajusta el inventario Kolla del proyecto: contiene rutas absolutas de otra laptop.

**Advertencia:** estos comandos pueden instalar o reiniciar Docker y modificar red y servicios del destino. Ejecútalos solo con la compatibilidad, los archivos de configuración y las interfaces validados.

```bash
kolla-ansible -i openstack/inventory/multinode bootstrap-servers
kolla-ansible -i openstack/inventory/multinode prechecks
kolla-ansible -i openstack/inventory/multinode deploy
kolla-ansible -i openstack/inventory/multinode post-deploy
```

**Comprobar:** estos comandos revisan contenedores y autenticación. El `admin-openrc.sh` debe estar en la laptop de despliegue donde `post-deploy` lo generó.

```bash
ssh n306@192.168.29.25 'sudo docker ps --format "{{.Names}} {{.Status}}"'
source /etc/kolla/admin-openrc.sh
openstack token issue -f value -c expires
openstack endpoint list --service ironic -c Enabled -f value
```

**Resultado esperado:** servicios en ejecución, una fecha de caducidad para la autenticación y endpoints Ironic habilitados. La orden de token anterior no imprime el token.

**Si aparece un error:** detente en `prechecks`; no lo saltes. No uses `docker start` sobre todos los contenedores como sustituto de una instalación nueva.

**Paso 14B. Preparar PXE e Ironic standalone — alternativa B**

- **Dónde:** laptop, raíz del proyecto, con el entorno `.venv` de Ansible activado.
- **Para qué:** preparar la alternativa sin Kolla.

**Advertencia:** DHCP puede interferir con otros equipos. Usa únicamente la VLAN aislada. Los playbooks modifican dnsmasq, Nginx y TFTP.

Este comando configura los servicios PXE locales.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
```

**ALTO — Ironic standalone:** el rol usa una imagen Metal3 `latest`, ignora algunos errores y genera un inventario que incluye toda la flota, también los equipos de infraestructura. Antes de ejecutarlo, fija una imagen comprobada, valida su API y limita el enrolamiento a equipos nuevos dedicados. No hay evidencia suficiente para prometer que el rol actual completo funcione desde cero.

Después de resolver esos puntos, este es el playbook del proyecto que instala la alternativa standalone.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml
```

**Comprobar:** este comando consulta los servicios y la cadena de arranque en el nodo 306.

```bash
ssh n306@192.168.29.25 'systemctl is-active dnsmasq nginx ironic-conductor; curl -fsSI http://10.100.29.30:8089/boot.ipxe'
```

**Resultado esperado:** servicios activos y HTTP 200. Comprueba además la respuesta de la API Ironic y el enrolamiento de un equipo de prueba; el puerto abierto no basta.

**Si aparece un error:** si Kolla está activo, la prueba de los servicios locales no corresponde. No reinicies dnsmasq local para corregir un contenedor Kolla.

### Etapa D. Instalar Kubernetes y la aplicación

**Paso 15. Confirmar versión y roles de RKE2 antes de instalar**

- **Dónde:** laptop, editor y terminal en la raíz.
- **Para qué:** evitar instalar una versión antigua o cambiar por accidente el trabajo de un nodo.

Edita `rke2_version`, `k8s_leader_ip` y los grupos del inventario solo después de elegir una versión publicada y compatible. El valor actual del archivo no se ha validado como recomendación para una instalación nueva. Consulta la [instalación RKE2](https://docs.rke2.io/install/quickstart) y las [opciones de red](https://docs.rke2.io/networking/basic_network_options).

Este comando vuelve al entorno de Ansible del proyecto si antes utilizaste el entorno separado de Kolla.

```bash
source .venv/bin/activate
```

El diseño de tres control planes ayuda a tolerar fallos de etcd, pero la configuración del proyecto apunta varios clientes a la IP del primer nodo. No promete disponibilidad completa del acceso a la API sin diseñar y probar un endpoint estable.

**Comprobar:** este comando revela si algún nodo ya tiene un servicio RKE2 activo.

```bash
ansible k8s_cluster -i inventory/lab/hosts.yml -m shell -a 'systemctl is-active rke2-server rke2-agent; true'
```

**Resultado esperado:** en servidores realmente nuevos no hay agentes ni servidores RKE2 activos. Si aparecen servicios activos, revisa el inventario antes de continuar.

**Paso 16. Desplegar RKE2**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** crear los control planes y unir los workers.

**Advertencia:** este comando escribe la configuración de RKE2, instala binarios y arranca o reinicia servicios. Continúa solo tras los pasos de Nexus, APT, secretos, versión y topología.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml
```

**Comprobar:** este comando usa el kubectl de RKE2 en el primer control plane previsto por el inventario.

```bash
ssh -J n306@192.168.29.25 debian@10.100.29.101 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'
```

**Resultado esperado:** los cinco nodos Kubernetes del diseño nuevo aparecen `Ready`, con tres control planes y dos workers. En el laboratorio actual se observaron siete nodos y otra topología; no es el resultado de este diseño.

**Si aparece un error:** revisa `journalctl -u rke2-server` o `journalctl -u rke2-agent` en el nodo que falla. Una protección del playbook se detiene si detecta el rol contrario activo; resuelve el inventario, no quites la protección.

**Paso 17. Preparar kubectl en la laptop**

- **Dónde:** laptop y primer control plane.
- **Para qué:** administrar el clúster sin entrar por SSH en cada orden.

Instala un kubectl compatible mediante la [guía oficial para Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/). No elijas la última versión sin compararla con la versión RKE2 instalada.

**Advertencia:** el kubeconfig permite administrar el clúster. No lo publiques ni lo muestres en la terminal. Este bloque copia el archivo a una ruta nueva y conserva su dirección de acceso local; si aparece `ALTO`, no reutilices a ciegas el archivo anterior.

```bash
umask 077
mkdir -p "$HOME/.kube"
if [ -e "$HOME/.kube/infra-nueva.yaml" ] || [ -e "$HOME/.kube/infra-nueva.yaml.part" ]; then
  printf '%s\n' 'ALTO: existe un kubeconfig o una copia parcial; revisa antes de continuar.'
else
  if ssh -J n306@192.168.29.25 debian@10.100.29.101 'sudo cat /etc/rancher/rke2/rke2.yaml' > "$HOME/.kube/infra-nueva.yaml.part"; then
    if test -s "$HOME/.kube/infra-nueva.yaml.part"; then
      mv "$HOME/.kube/infra-nueva.yaml.part" "$HOME/.kube/infra-nueva.yaml"
      chmod 600 "$HOME/.kube/infra-nueva.yaml"
    fi
  fi
fi
```

En una terminal nueva de la laptop, este túnel hace llegar la dirección local del kubeconfig al API del control plane; déjala abierta.

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:6443:10.100.29.101:6443 n306@192.168.29.25
```

En la terminal donde usarás kubectl, este comando selecciona el archivo nuevo.

```bash
export KUBECONFIG="$HOME/.kube/infra-nueva.yaml"
```

Este túnel corresponde a la dirección `https://127.0.0.1:6443` del kubeconfig RKE2. Si cambiaste ese endpoint o el puerto local, adapta el archivo y comprueba también el nombre del certificado; no desactives su validación para ocultar un error.

**Comprobar:** estos comandos comprueban conectividad y red de pods.

```bash
kubectl get nodes
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Resultado esperado:** nodos `Ready` y pods Cilium listos.

**Paso 18. Preparar el almacenamiento y OpenTelemetry Operator**

- **Dónde:** laptop, raíz del proyecto, con el kubeconfig correcto.
- **Para qué:** instalar los requisitos que no incluye el overlay de aplicaciones.

**ALTO — requisitos externos:** el repositorio solicita la StorageClass `local-path` y recursos OpenTelemetry, pero no instala esos componentes con una receta completa y fijada. Debes preparar un provisionador de almacenamiento y una versión compatible del [OpenTelemetry Operator](https://opentelemetry.io/docs/platforms/kubernetes/operator/), incluidos sus certificados o cert-manager cuando lo requiera el método elegido. No basta con aplicar los manifiestos `otel/` del proyecto.

La documentación histórica menciona versiones, pero no se comprobó su combinación para una instalación nueva. No se incluye aquí una URL `latest` que cambie lo que se instala sin control.

**Comprobar:** este script existente revisa almacenamiento, CRD y operador.

```bash
bash scripts/diagnostics/kubernetes-prerequisites.sh
```

**Resultado esperado:** CRD establecidos, `storageclass.storage.k8s.io/local-path` y operador disponible. Los CRD son las definiciones que permiten a Kubernetes entender tipos nuevos como `OpenTelemetryCollector`.

**Si aparece un error:** instala o corrige el requisito concreto antes de aplicar el overlay. Crear un PVC no instala una StorageClass.

**Paso 19. Instalar los backends de métricas, logs y trazas**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** crear VictoriaMetrics, Loki y Tempo con sus volúmenes.

**Advertencia:** estos comandos crean recursos y solicitan 25 GiB, 20 GiB y 15 GiB de almacenamiento. `local-path` guarda datos en un nodo; no implica replicación ni garantiza una cuota física del disco.

```bash
kubectl apply -k kubernetes/observability/backends
```

**Comprobar:** estos comandos revisan aplicaciones y volúmenes.

```bash
kubectl get statefulset,pods,pvc -n observability
```

**Resultado esperado:** los tres StatefulSets llegan a `1/1` y sus PVC a `Bound`.

**Si aparece un error:** si un PVC está `Pending`, revisa el provisionador y el disco. Si un pod falla, usa `kubectl describe pod NOMBRE -n observability`, sustituyendo `NOMBRE` por el mostrado.

**Paso 20. Configurar secretos de telemetría y desplegar el collector**

- **Dónde:** editor y terminal de la laptop.
- **Para qué:** enviar telemetría a los backends y al servidor Coroot que hayas elegido.

**ALTO — secretos:** se encontraron valores de API incrustados en `kubernetes/observability/otel/02_otel_operator_and_collectors.yaml` y `kubernetes/observability/coroot/03_coroot_cluster_agent.yaml`. No se reproducen aquí. Sustitúyelos por credenciales nuevas gestionadas con secretos y configura sus referencias antes de aplicar los archivos. Si eran credenciales reales, deben rotarse.

Confirma también el endpoint de Coroot. Si todavía no has instalado Coroot, prepara primero el paso 23 o adapta las rutas de exportación; no envíes datos a un endpoint supuesto.

**Advertencia:** este comando crea el collector y los recursos de instrumentación una vez resueltos los puntos anteriores.

```bash
kubectl apply -k kubernetes/observability/otel
```

**Comprobar:** estos comandos consultan el recurso y su deployment generado.

```bash
kubectl get opentelemetrycollector -n observability
kubectl get deployment -n observability otel-gateway-collector
```

**Resultado esperado:** el deployment llega a dos réplicas disponibles. Verifica ingesta real; que el pod arranque no demuestra que los exportadores estén enviando datos.

**Paso 21. Instalar las aplicaciones de ejemplo**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** desplegar backend, frontend, pedidos, notificaciones y Redis.

**Advertencia:** el comando crea recursos en `aplicaciones` y el frontend usa NodePort `30080`. Confirma que ningún otro Service use ese puerto.

```bash
kubectl apply -k kubernetes/apps/microservices
```

Se usa la carpeta de aplicaciones para no aplicar a ciegas todos los módulos del overlay. El overlay `kubernetes/overlays/lab` también incluye los backends, OpenTelemetry y Coroot.

**Comprobar:** estos comandos muestran los pods y esperan al frontend.

```bash
kubectl get pods -n aplicaciones -o wide
kubectl rollout status deployment/frontend-web -n aplicaciones --timeout=180s
```

**Resultado esperado:** pods listos y despliegue del frontend completado. El backend de ejemplo de este repositorio es un servidor HTTP Python sencillo, no una API de negocio completa.

**Si aparece un error:** ante `ImagePullBackOff`, revisa los eventos del pod. Un HTTP 401 significa que falta autorización del registro; no se soluciona reiniciando todos los nodos.

### Etapa E. Monitoreo del sistema y Coroot

**Paso 22. Instalar Prometheus, Grafana y Node Exporter**

- **Dónde:** laptop; preparación de Grafana en el nodo 306.
- **Para qué:** ver el estado de los equipos físicos.

El rol solicita `grafana`, pero no añade su repositorio APT. En una consola SSH del nodo 306 nuevo, este bloque prepara el repositorio estable según la [instalación oficial de Grafana para Debian](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/).

**Advertencia:** instala herramientas y escribe archivos APT en el nodo 306. Si ya existe una configuración de Grafana, revísala antes de sustituir estos archivos.

```bash
sudo apt-get install -y apt-transport-https wget gnupg
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt-get update
apt-cache policy grafana
```

Revisa la versión candidata antes de seguir. El rol instala la versión disponible en APT, no una versión fijada por el proyecto. Vuelve a la terminal de la laptop para ejecutar el playbook siguiente.

**Advertencia:** el playbook instala paquetes y configura servicios en la flota.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml
```

**Comprobar:** estos comandos consultan los endpoints locales del nodo 306.

```bash
ssh n306@192.168.29.25 'curl -fsS http://127.0.0.1:9090/-/ready; curl -fsS http://127.0.0.1:3000/api/health'
ansible baremetal -i inventory/lab/hosts.yml -m command -a 'systemctl is-active prometheus-node-exporter'
```

**Resultado esperado:** Prometheus listo, Grafana con su base operativa y exporters activos.

En Grafana todavía tienes que configurar fuentes, dashboards y acceso. Los archivos de `kubernetes/observability/grafana/` no se instalan automáticamente en el Grafana del host y contienen nombres de servicios que debes adaptar a rutas alcanzables desde él. Confirma también la configuración y el arranque de Alertmanager antes de considerar que tienes alertas.

**Paso 23. Añadir Coroot — opcional**

- **Dónde:** VM de observabilidad y laptop; agentes en los nodos.
- **Para qué:** observar procesos y contenedores mediante eBPF.

La documentación detallada propone una VM Debian 13 separada. La IP `10.100.29.40` es una propuesta que debes reservar, no una máquina creada por el proyecto. Como presupuesto de prueba la guía estima 4 vCPU, 8 GiB RAM y 60 GiB de disco; no son mínimos oficiales.

Sigue en orden [Instalar Coroot primero](docs/observability/instalar-coroot-primero.md): prepara Docker en esa VM, el Compose, los backends y una credencial nueva. No reemplaces Docker ni containerd de un nodo Kolla o RKE2 para hacer esa instalación. El archivo Compose no está incluido como un servicio listo para desplegar desde la raíz de este repositorio.

**Comprobar:** en la VM, estos comandos revisan el Compose que hayas creado siguiendo esa guía.

```bash
cd /opt/coroot
sudo docker compose -f compose.yaml ps
```

**Resultado esperado:** servicios del stack en ejecución. Después comprueba la UI desde la laptop con el túnel descrito en esa guía.

Si eliges el rol Ansible de agentes, ajusta primero `coroot_collector_endpoint` en `ansible/roles/coroot_node_agent/defaults/main.yml` o mediante variables del inventario. El endpoint predeterminado apunta al nodo 306 y no a la VM propuesta.

**Advertencia:** este comando instala agentes en `baremetal:!pxe_controller`, no en los ocho nodos. No lo mezcles con otro instalador o un DaemonSet de agentes en los mismos hosts.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/02_coroot_agent.yml
```

**Comprobar:** este comando consulta el servicio solo en los nodos incluidos por el playbook.

```bash
ansible 'baremetal:!pxe_controller' -i inventory/lab/hosts.yml -m command -a 'systemctl is-active coroot-node-agent'
```

**Resultado esperado:** `active` y nodos visibles en Coroot. El agente del nodo 306 requiere una decisión aparte; este playbook lo excluye.

El agente de clúster es otra pieza opcional. Tras preparar sus credenciales y endpoint, este comando lo instala en `observability`.

```bash
kubectl apply -k kubernetes/observability/coroot
```

**Comprobar:** este comando espera su despliegue.

```bash
kubectl rollout status deployment/coroot-cluster-agent -n observability --timeout=180s
```

**Resultado esperado:** una réplica disponible. El namespace correcto es `observability`, no `coroot`.

### Etapa F. Imágenes y provisión automática — opcional

**Paso 24. Construir una imagen Debian con Packer**

- **Dónde:** estación Linux de construcción con KVM, espacio y memoria disponibles.
- **Para qué:** preparar una imagen reutilizable para equipos nuevos.

No es necesario reconstruir los nodos que instalaste manualmente. La plantilla `cloud-init/packer/packer.pkr.hcl` usa un preseed incompleto dentro del repositorio; para esta ruta usa `debian13-coroot.pkr.hcl` y el procedimiento completo de [Packer y Coroot](docs/observability/coroot-debian13-packer.md#8-construir-una-imagen-con-packer).

Debes preparar todos estos insumos en el directorio de construcción: imagen Debian 13 `generic amd64`, checksum verificado, `seed/user-data`, `seed/meta-data`, llave temporal `build_key`, binario versionado `coroot-node-agent` y unidad `coroot-node-agent.service`. Esa guía contiene la creación del seed y de la unidad; no copies llaves de producción a la imagen. Instala Packer mediante el [procedimiento oficial de HashiCorp](https://developer.hashicorp.com/packer/install), comprobando su versión.

Este comando instala QEMU y las herramientas de imagen necesarias en la estación de construcción Debian/Ubuntu.

```bash
sudo apt-get install -y qemu-system-x86 qemu-utils xorriso genisoimage
```

**Comprobar:** estos comandos muestran las herramientas y el acceso a KVM.

```bash
packer version
qemu-system-x86_64 --version
test -r /dev/kvm && test -w /dev/kvm && echo "KVM disponible"
```

**Resultado esperado:** versiones instaladas y `KVM disponible`. En la sesión usada para revisar el proyecto no había `/dev/kvm`; por eso no se construyó una imagen aquí.

Estos comandos se ejecutan en el directorio que ya contiene los insumos y una copia de `debian13-coroot.pkr.hcl`; crean una VM y un archivo de salida nuevo.

```bash
packer init debian13-coroot.pkr.hcl
checksum="sha512:$(sha512sum debian-13-generic-amd64.qcow2 | awk '{print $1}')"
packer validate -var "image_path=$PWD/debian-13-generic-amd64.qcow2" -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
packer build -var "image_path=$PWD/debian-13-generic-amd64.qcow2" -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
```

**Comprobar:** estos comandos verifican el archivo de salida y registran su checksum.

```bash
qemu-img check output-debian13-coroot/debian13-coroot.qcow2
sha256sum output-debian13-coroot/debian13-coroot.qcow2
```

**Resultado esperado:** la imagen no presenta errores estructurales. También debes arrancarla en una VM de prueba; `qemu-img check` no demuestra que arranque ni que cloud-init funcione.

**Paso 25. Preparar ConfigDrive y probar un solo nodo de provisión**

- **Dónde:** equipo de provisión con una copia del proyecto, `genisoimage` y una llave pública real.
- **Para qué:** entregar nombre, red y acceso SSH al nuevo equipo.

ConfigDrive es un pequeño disco de configuración que cloud-init lee durante el primer arranque. Revisa `inventory/nodes.csv` y comprueba que exista tu llave pública; el generador contiene un valor de ejemplo que no debes usar como acceso real.

**Advertencia:** este script crea archivos en `/tmp/configdrive/` y, si existe `/httpboot`, escribe datos bajo `/httpboot/cloud-init/`. No aplica ni formatea por sí solo una imagen en un disco físico.

```bash
test -s "$HOME/.ssh/id_ed25519.pub"
bash cloud-init/scripts/generate_configdrive.sh 321
```

**Comprobar:** este comando comprueba la imagen de configuración del nodo de ejemplo.

```bash
test -s /tmp/configdrive/k8s-worker-01-configdrive.iso && echo "ConfigDrive creado"
```

**Resultado esperado:** `ConfigDrive creado`. Cambia `321` y el nombre del archivo si elegiste otro nodo.

**ALTO — escritura del disco:** antes de desplegar una imagen con Ironic debes tener un equipo dedicado y vacío, la imagen registrada, el ramdisk IPA, el driver correcto, el ConfigDrive, el estado del nodo Ironic y su método de encendido comprobados. El repositorio no ofrece una secuencia única validada para ambas alternativas. Consulta los planes de [OpenStack e iPXE](docs/architecture/openstack/plan_maestro_instalacion_ipxe.md) y prueba primero en una VM o un equipo descartable. No uses `--reprovision` sobre toda la flota: puede sobrescribir discos y servicios existentes.

### Etapa G. Respaldar antes de dar por terminada la instalación

**Paso 26. Preparar un respaldo recuperable**

- **Dónde:** laptop y almacenamiento independiente del clúster.
- **Para qué:** poder recuperar datos cuando falle un nodo.

Protege juntos estos elementos: snapshot etcd y token RKE2; base real y blobs de Nexus; MariaDB, configuración Kolla e imágenes Glance; y datos y configuración de observabilidad. Un volcado PostgreSQL vacío no respalda una instancia Nexus que usa H2.

**ALTO — playbook de respaldo:** confirma que el grupo `k8s_control_plane` y su líder son reales, y que `/etc/kolla/passwords.yml` existe y contiene credenciales válidas en el controlador de OpenStack. Si no, el playbook se detendrá. El respaldo MariaDB actual del repositorio no garantiza por sí solo consistencia con Glance ni con tablas no transaccionales.

**Advertencia:** este comando crea snapshots y volcados y copia datos y credenciales sensibles a `backups/`. Ejecútalo solo después de revisar esas condiciones y proteger el destino.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/90-operations/01_disaster_recovery.yml --tags backup
```

**Comprobar:** este comando muestra nombres y tamaños sin revelar el contenido.

```bash
find backups -type f ! -name README.md ! -name .gitkeep -printf '%p %s bytes\n'
```

**Resultado esperado:** archivos no vacíos, checksums verificados y copias fuera del nodo original. Completa una restauración aislada antes de considerar probado el respaldo.

## 4. Prueba final

No existe un único comando que inicie todo este proyecto: systemd, Kolla y Kubernetes administran componentes diferentes.

**Paso 27. Abrir la aplicación mediante un túnel local**

- **Dónde:** primera terminal de la laptop.
- **Para qué:** acceder al frontend sin publicar puertos adicionales en la red de oficina.

Este comando mantiene abierto un túnel a la aplicación; conserva la terminal abierta.

```bash
kubectl port-forward -n aplicaciones service/frontend-web 8088:80 --address 127.0.0.1
```

**Comprobar:** estos comandos se ejecutan en otra terminal de la laptop.

```bash
curl -fsS http://127.0.0.1:8088/
curl -fsS http://127.0.0.1:8088/api/v1/data
```

**Resultado esperado:** el primer comando devuelve HTML y el segundo un JSON con `status: ok` y `service: backend-api`. Abre `http://127.0.0.1:8088` en el navegador. La API de ejemplo no demuestra que Ironic pueda instalar equipos físicos.

**Paso 28. Abrir Prometheus y Grafana**

- **Dónde:** otra terminal de la laptop.
- **Para qué:** consultar el monitoreo del nodo 306.

Este comando crea dos túneles locales y mantiene la terminal ocupada.

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:3001:127.0.0.1:3000 \
  -L 127.0.0.1:9090:127.0.0.1:9090 \
  n306@192.168.29.25
```

**Comprobar:** estos comandos prueban las conexiones desde una tercera terminal.

```bash
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:3001/api/health
```

**Resultado esperado:** Prometheus listo y Grafana operativo. Abre `http://127.0.0.1:9090/targets` y `http://127.0.0.1:3001`; comprueba targets, fuentes y datos recientes, usando tus credenciales nuevas.

**Paso 29. Revisar el conjunto**

- **Dónde:** laptop, raíz del proyecto.
- **Para qué:** comprobar nodos, aplicaciones y almacenamiento.

Estos comandos consultan el estado general sin desplegar cambios.

```bash
kubectl get nodes
kubectl get pods -n aplicaciones
kubectl get pods,pvc -n observability
```

Si instalaste Kolla y todos los servicios esperados por el healthcheck, este comando revisa sus puertos además del resto de la infraestructura.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/50-validation/01_healthcheck.yml
```

**Resultado esperado:** nodos `Ready`, contenedores listos, PVC `Bound` y verificaciones sin fallos. El healthcheck presupone endpoints Kolla en `10.100.29.5` y no corresponde sin cambios a una instalación solo standalone.

**Criterio para terminar:** aplicación accesible, red y repositorios comprobados, datos llegando al monitoreo, alternativa de provisión validada en un equipo descartable y restauración de respaldo probada. Si queda un paso **ALTO** sin resolver, esa parte de la plataforma todavía no está instalada y verificada.

## 5. Errores frecuentes

| Error | Causa probable | Solución |
|---|---|---|
| `externally-managed-environment` en pip | Se intentó instalar sobre Python del sistema | Activa `.venv` e instala dentro de él. |
| `Permission denied (publickey)` | Usuario, llave o `authorized_keys` incorrectos | Prueba SSH por nodo y corrige la llave pública; no copies la privada al servidor. |
| `Bad owner or permissions` de SSH | Archivo local de configuración con permisos inseguros | Corrige propietario y permisos del archivo indicado. |
| Vault no descifra | `.vault_pass` no corresponde al archivo | Recupera su contraseña original; no generes otra encima. |
| Se pierde SSH después de la base | La interfaz, MAC o gestor de red no coincide | Revisa por consola la plantilla de red y el gestor activo antes de reintentar. |
| APT da 404 | Nexus no tiene la distribución o el repositorio esperado | Verifica `trixie`, `trixie-updates` y las fuentes de seguridad antes de cambiar los clientes. |
| Nexus no arranca | Java u opciones JVM incompatibles con la versión descargada | Revisa `journalctl -u nexus`, fija la versión y usa opciones compatibles. |
| PostgreSQL tiene una base vacía | Nexus está usando H2 u otro almacén | Comprueba el motor real; respalda los datos activos, no solo el nombre de una base. |
| `prechecks` de Kolla falla | Sistema, interfaces o configuración no compatibles | Resuelve el mensaje según la versión Kolla elegida; no saltes el precheck. |
| Dos DHCP o puertos ocupados | Kolla y standalone compiten por recursos | Define una sola alternativa activa para esa red y esos equipos. |
| Se rechaza un rol RKE2 | Inventario y servicio activo no coinciden | Reconcilia la topología; no desactives la protección para convertir nodos en uso. |
| `kubectl` no conecta | Kubeconfig, IP líder, ruta o túnel incorrectos | Verifica el destino y prueba primero el kubectl del control plane por SSH. |
| `snap-confine` al usar kubectl | Problema local de Snap/AppArmor | Corrige la instalación del cliente o usa otro método oficial; no cambies el clúster. |
| `no matches for kind OpenTelemetryCollector` | Falta el CRD o el operador | Completa los requisitos del paso 18. |
| PVC `Pending` | Falta provisionador, capacidad o nodo elegible | Revisa StorageClass, eventos del PVC y disco. |
| Pod `ImagePullBackOff` con HTTP 401 | Credenciales sin acceso al registro | Valida su vigencia y permisos; usa un mecanismo seguro de `imagePullSecrets`. |
| Collector reinicia | Configuración incompatible, secreto o endpoint erróneo | Revisa los eventos y logs protegiendo valores sensibles; valida cada exportador. |
| Grafana no muestra datos | Fuente no alcanzable desde el host o sin ingesta | Ajusta URLs reales y comprueba targets e ingesta. |
| Packer no llega a SSH | Seed, llave o imagen incorrectos | Completa los insumos del paso 24; no uses el preseed incompleto. |
| ConfigDrive no se genera | Falta `genisoimage`/`mkisofs` o el ID no existe | Instala la herramienta en el equipo generador y corrige `nodes.csv`. |
| El backup termina pero no recupera el servicio | Faltan blobs, token, base real o una copia coherente | Valida una restauración completa en aislamiento y conserva todos sus componentes juntos. |

## 6. Comandos útiles

**Dónde:** laptop, raíz del proyecto, con `.venv` y el kubeconfig correcto. Para comandos de un host, ejecuta la orden en ese host con SSH o consola.

- **Revisar equipos:** este comando consulta los nodos Kubernetes.

  ```bash
  kubectl get nodes -o wide
  ```

- **Revisar un pod:** cambia `NOMBRE` por el nombre del pod y consulta sus eventos.

  ```bash
  kubectl describe pod NOMBRE -n aplicaciones
  ```

- **Revisar logs de la aplicación:** este comando consulta el frontend.

  ```bash
  kubectl logs -n aplicaciones deployment/frontend-web --tail=50
  ```

- **Reiniciar el frontend:** este comando reemplaza sus pods y puede cortar conexiones.

  ```bash
  kubectl rollout restart deployment/frontend-web -n aplicaciones
  ```

- **Detener solo el frontend:** este comando interrumpe su servicio, pero no borra PVC ni elimina los demás módulos.

  ```bash
  kubectl scale deployment/frontend-web -n aplicaciones --replicas=0
  ```

- **Volver a iniciar el frontend:** este comando restaura sus dos réplicas declaradas en el proyecto.

  ```bash
  kubectl scale deployment/frontend-web -n aplicaciones --replicas=2
  ```

- **Revisar un servicio del host:** en el nodo correspondiente, este comando consulta Nexus sin reiniciarlo.

  ```bash
  sudo systemctl status nexus --no-pager
  ```

- **Detener, iniciar o reiniciar Nexus:** ejecuta solo la orden necesaria en el nodo 315. Detener o reiniciar corta temporalmente las descargas y subidas del repositorio.

  ```bash
  sudo systemctl stop nexus
  ```

  Esta orden inicia el servicio de nuevo.

  ```bash
  sudo systemctl start nexus
  ```

  Esta orden detiene e inicia el servicio.

  ```bash
  sudo systemctl restart nexus
  ```

- **Revisar RKE2:** en un control plane, este comando consulta el servicio; en un worker sustituye `rke2-server` por `rke2-agent`.

  ```bash
  sudo systemctl status rke2-server --no-pager
  ```

- **Revisar Kolla:** en su controlador, este comando muestra estado sin exponer configuración interna.

  ```bash
  sudo docker ps --format '{{.Names}} {{.Status}}'
  ```

- **Revisar Coroot Compose:** en la VM donde se instaló, este comando muestra los servicios.

  ```bash
  cd /opt/coroot
  sudo docker compose -f compose.yaml ps
  ```

- **Cerrar un túnel:** presiona `Ctrl+C` en la terminal que lo mantiene abierto. Eso cierra el acceso local, no detiene el servicio remoto.

No hay una orden segura de «detener todo». No uses `docker stop` sobre todos los contenedores, `kubectl delete namespace`, `compose down -v`, `--heal-etcd` o `--reprovision` como comandos normales de parada: pueden interrumpir la nube o perder datos.

### Archivos que sustentan esta guía

Las rutas principales son [el inventario](inventory/lab/hosts.yml), [las variables](inventory/lab/group_vars/all/vars.yml), [el orquestador](ansible/site.yml), [los roles](ansible/roles), [Kolla](openstack/globals.yml), [los manifiestos](kubernetes/base/kustomization.yaml), [los requisitos Kubernetes](scripts/diagnostics/kubernetes-prerequisites.sh), [Packer](cloud-init/packer/debian13-coroot.pkr.hcl), [las pruebas](tests) y [el estado observado](docs/reference/estado-observado-2026-10-30.md). Las fuentes oficiales enlazadas se consultaron para aclarar compatibilidad y requisitos externos; no convierten los tramos pendientes del repositorio en una instalación probada.

# Instalar Debian 13 por iPXE y preseed

Esta opción usa las MAC y los usuarios de `inventory/lab/hosts.yml`. Debian Installer instala el sistema en el disco elegido. Después, `00_ping.yml` comprueba el acceso por SSH y Python. Usa un controlador dedicado conectado a la red de aprovisionamiento, con IPv4 ya configurada, salida al mirror Debian desde el destino y sin otro servidor DHCP en ese segmento.

El playbook es `ansible/playbooks/20-services/04_debian_netboot.yml`. Instala `dnsmasq-base` y usa las unidades `debian-netboot-dhcp` y `debian-netboot-http`, con configuración en `/etc/debian-netboot` y artefactos en `/opt/debian-netboot/releases`. Para el HTTP de arranque reserva TCP 8088 por defecto. DHCP y TFTP usan UDP 67 y 69. El instalador debe poder alcanzar el mirror y DNS. Configura el enrutamiento en la red del piloto.

## 1. Preparar el kernel, el initrd y los binarios iPXE

En la raíz de `infra-scripts`, usa los archivos de la prueba y el checkout de iPXE como entradas. La compilación se hace en una copia temporal del commit fijado. Requiere `git`, `make`, GCC, binutils, `liblzma-dev`, `tar`, `gzip` y utilidades GNU.

```bash
bash network/ipxe/debian-netboot/prepare-artifacts.sh \
  /home/rodrigo/Desktop/pruebaIPXE/entorno/debian13 \
  /home/rodrigo/Desktop/pruebaIPXE/ipxe
```

Se generan `debian13/linux`, `debian13/initrd.gz`, `tftp/undionly.kpxe`, `tftp/snponly.efi` y `SHA256SUMS` en `artifacts/debian-netboot/`. La carpeta está excluida de Git. El script verifica el par original contra las huellas de la prueba. Para otro par Debian amd64, pasa el directorio de salida como tercer argumento y un manifiesto SHA-256 de `linux` e `initrd.gz` de una misma publicación verificada como cuarto. [Manual de Debian](https://www.debian.org/releases/trixie/amd64/apb)

## 2. Elegir controlador, MAC y disco

Para añadir un controlador dedicado, puedes usar un segundo archivo de inventario. Por ejemplo, guarda este bloque como `controlador-netboot.yml` y ajusta la dirección y la cuenta de administración. Si ya tienes un controlador dedicado en el inventario, usa su nombre y omite el segundo `-i`.

```yaml
all:
  hosts:
    controlador-piloto:
      ansible_host: 192.168.29.40
      ansible_user: admin
      ansible_ssh_common_args: ''
```

Guarda estas variables como `netboot.yml`. El ejemplo selecciona el perfil de `nodo-279` y toma de `baremetal` su MAC `64:00:6a:2a:2f:cb` y el usuario `debian`. Úsalo solo si ese equipo está destinado al piloto y su disco se puede borrar. El último registro del laboratorio describe al 279 como worker activo. [Estado observado](../../../docs/reference/estado-observado-2026-10-30.md)

```yaml
debian_netboot_controller: controlador-piloto
debian_netboot_interface: enp2s0
debian_netboot_address: 192.168.73.2/24
debian_netboot_gateway: 192.168.73.1
debian_netboot_dns: 1.1.1.1
debian_netboot_public_key_file: /home/rodrigo/.ssh/id_ed25519.pub
debian_netboot_targets:
  nodo-279:
    address: 192.168.73.79
    disk: /dev/sda
```

`address` es opcional. Si se omite, se usa `ansible_host` del equipo en el inventario. Incluye una entrada por cada equipo que deba recibir DHCP de este controlador. Confirma el nombre del disco completo desde el instalador o una consola con el mismo modo de arranque. El preseed vuelve a particionar ese disco. El `snponly.efi` compilado se usa con Secure Boot desactivado. Si el equipo usa Secure Boot, requiere un binario iPXE firmado y admitido por su firmware.

## 3. Publicar y autorizar un intento

Ejecuta desde la raíz del repositorio, con la configuración habitual de Ansible y Vault disponible:

```bash
ansible-playbook -i inventory/lab/hosts.yml -i controlador-netboot.yml \
  ansible/playbooks/20-services/04_debian_netboot.yml -e @netboot.yml --check
```

Ejecuta el mismo comando sin `--check` para publicar y arrancar los servicios. En el destino del ejemplo, la configuración anterior ofrece arranque local. Cuando el equipo, la MAC y el disco estén confirmados, añade `attempt: piloto-01` bajo el destino y vuelve a ejecutar el playbook. Elige arranque por red una vez con F12. Desde ese punto, la instalación continúa automáticamente.

El permiso se consume cuando iPXE recibe el script de instalación para la MAC e IP reservadas. Si se interrumpe la descarga o la instalación, el próximo arranque por red vuelve al disco. Para reintentar, confirma el estado del destino y usa un identificador nuevo. Para revocar una autorización, quita `attempt` y reaplica el playbook. Espera a que un instalador activo termine de descargar sus archivos antes de actualizar los perfiles o el conjunto de artefactos.

## 4. Confirmar el primer arranque

Comprueba en la consola que el destino arranca desde disco. Entra por SSH con la llave correspondiente y valida la IP, el usuario, Python y `sudo -n true`. Si usaste una IP temporal del piloto, ajusta la conexión de Ansible a esa IP y a su ruta real antes del ping.

```bash
ansible-playbook -i inventory/lab/hosts.yml \
  ansible/playbooks/00-preflight/00_ping.yml --limit NOMBRE_DEL_DESTINO
```

Para revisar los servicios o retirar esta opción del controlador:

```bash
sudo journalctl -u debian-netboot-dhcp -u debian-netboot-http
sudo systemctl disable --now debian-netboot-dhcp.service debian-netboot-http.service
```

El detalle de la prueba original y el diagnóstico por etapa están en el [runbook de integración](../../../docs/runbooks/integracion-ipxe-debian13.md).

## Validación de la implementación

En una red virtual aislada se comprobó que el rol renderiza las reservas a partir del inventario y entrega los dos binarios por TFTP. Una VM BIOS con la MAC del nodo 279 obtuvo su IP reservada, descargó kernel e initrd y solicitó el preseed con HTTP 200. Los tests también comprobaron que un intento concurrente se entrega una sola vez y sigue consumido después de reiniciar el servicio. OVMF no presentó una opción de arranque de red en la prueba UEFI. Quedan por verificar en el Dell el arranque UEFI y la instalación completa hasta el disco y SSH.

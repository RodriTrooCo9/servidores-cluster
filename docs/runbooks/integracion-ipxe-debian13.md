# Integración de la instalación desatendida de Debian 13 por iPXE

Revisión del 11 de noviembre de 2026. Origen `/home/rodrigo/Desktop/pruebaIPXE/entorno`, rama `develop`, etiqueta `v0.1.1`, commit `23cb2f1cce8c01ecd85a8345f9f196bf6b8d21b8`. El árbol vecino de iPXE estaba en `582852868c6a68db138cd5c99719b8395ce24686`. El objetivo del piloto es que un equipo arranque Debian 13 desde su disco y responda por SSH y Ansible.

La [guía de Debian netboot](../../network/ipxe/debian-netboot/README.md) documenta la opción implementada y el playbook que la activa. Este runbook conserva la comparación con la prueba original.

## Flujo de la prueba

```text
Dell → DHCP → TFTP → iPXE → HTTP → kernel + initrd → Debian Installer
  → preseed → paquetes Debian → particiones + GRUB → disco local → SSH → Ansible
                                    └→ avisos de progreso al monitor Python
```

| Paso | Componente | Comportamiento observado en los archivos |
|---|---|---|
| 1 | `dnsmasq.conf` | Escucha en `eno1` con DHCP autoritativo y DNS local desactivado (`port=0`). Reserva `192.168.1.1` para la MAC `64:00:6a:2a:2f:cb` del nodo 279. Entrega puerta de enlace `192.168.1.2`, DNS públicos y servidor TFTP. El rango dinámico `.100`–`.200` también puede dar concesiones a equipos desconocidos. |
| 2 | TFTP y firmware | `tftpd-hpa` sirve desde `/srv/tftp`. La arquitectura DHCP 0 selecciona `undionly.kpxe` (BIOS) y las arquitecturas 7 y 9 seleccionan `snponly.efi` (UEFI x86-64). `ipxe.efi` está disponible como artefacto, aunque la regla UEFI selecciona `snponly.efi`. |
| 3 | `embed.ipxe` | Abre `net0`, espera hasta 15 s por el enlace, intenta DHCP dos veces y encadena `http://192.168.1.2:80/ipxe/boot.ipxe`. Los clientes que ya se identifican como iPXE también reciben ese script por DHCP. |
| 4 | `boot.ipxe` | Compara la MAC exacta del nodo 279. Para ese nodo, el menú espera cinco segundos y elige `debian13_auto`. También ofrece diagnóstico, consola iPXE y arranque local. Para otras MAC intenta arrancar el disco. |
| 5 | Nginx y `debian13/` | Sirve `linux`, `initrd.gz`, `preseed.cfg` y el script Dell desde `/var/www/html/ipxe`. Los parámetros del kernel establecen el modo automático, la IP estática, puerta de enlace, DNS, hostname y URL del preseed. La IP tiene que funcionar antes de descargar el preseed. [Manual de preconfiguración de Debian](https://www.debian.org/releases/trixie/amd64/apbs02.en.html) |
| 6 | `preseed.cfg` | Fija idioma y teclado español, zona `America/La_Paz`, mirror `deb.debian.org` y suite `trixie`. Acepta el particionado `regular` con receta `atomic`, selecciona sistema estándar y SSH, configura GRUB con la opción EFI de ruta removible y ordena reiniciar. Los paquetes de Debian se descargan del mirror mediante la salida del controlador. |
| 7 | `desplegar.py` | Registra los avisos de `/heartbeat` en TCP 8089. El aviso `completed` escribe `DONE` en el CSV durante el `late_command`, antes de arrancar Debian desde disco. El panel es opcional para el flujo estático porque sus avisos toleran fallos. |

La ruta de instalación reconstruida usa Debian Installer y preseed. El instalador crea el sistema en el equipo usando paquetes Debian. La ruta del proyecto grande que carga IPA y despliega una imagen QCOW2 con Ironic es una opción distinta. [Encadenamiento con iPXE](https://ipxe.org/howto/chainloading) · [Preconfiguración con Debian Installer](https://www.debian.org/releases/trixie/amd64/apb)

## Evidencia recogida

| Comprobación | Resultado |
|---|---|
| Archivos publicados en la laptop | Los archivos `boot.ipxe`, `preseed.cfg`, `dell_bios_config.sh`, `linux` e `initrd.gz` de Nginx coinciden byte a byte con los de `entorno`. Las descargas HTTP de `boot.ipxe`, `linux` e `initrd.gz` coincidieron por SHA-256 en loopback. `HEAD` del preseed devolvió HTTP 200. Los tres binarios de `/srv/tftp` coinciden con `entorno/tftpboot/`; las descargas TFTP de `undionly.kpxe` y `snponly.efi` también coincidieron en loopback. |
| Servicios de la laptop | `nginx` y `tftpd-hpa` estaban activos. `dnsmasq` estaba en `failed`; su journal registró `unknown interface eno1`. En el momento de la revisión `eno1` existía con una IP link-local y sin `192.168.1.2/24`. El puerto TCP 8089 del monitor carecía de un listener. La prueba completa queda pendiente en la red física. |
| Sintaxis | Pasaron `dnsmasq --test`, `debconf-set-selections --checkonly` para ambas versiones del preseed, `bash -n`, ShellCheck a nivel error y el análisis de sintaxis Python. Estas comprobaciones validan el formato. |
| Artefactos Debian | El kernel y los módulos del initrd tienen ABI `6.12.107+deb13-amd64`. `gzip -t` pasó. En QEMU, con arranque directo y sin tarjeta de red ni disco, la pareja llegó a la detección de red de Debian Installer. Quedan por validar el encadenamiento iPXE, la instalación de paquetes y el reinicio en el Dell. |
| Binarios iPXE | `ipxe.efi` y `snponly.efi` son aplicaciones EFI x86-64 y contienen literalmente la URL de la laptop. `undionly.kpxe` se comparó con el archivo publicado en TFTP. Queda por comprobar el arranque BIOS y UEFI en el hardware elegido. |
| Monitor | Probé el manejador HTTP en loopback, con un CSV temporal y sin enviar Wake-on-LAN. Para `INSTALL` entregó un script de instalación. `completed` escribió `DONE` y el siguiente acceso al endpoint dinámico devolvió arranque local. Una MAC desconocida también recibió arranque local. |
| Evidencia histórica | `node.csv` contiene el nodo 279 en `DONE`. Ese estado registra un aviso del instalador; la aceptación de una nueva instalación exige comprobar arranque desde disco y acceso al sistema instalado. |

### Huellas de los artefactos locales

Guárdalas para reproducir esta prueba. La procedencia oficial del kernel y del initrd debe verificarse con el manifiesto de la publicación Debian que se elija antes de distribuirlos. Para cada build iPXE guarda también el commit, el script embebido y la URL objetivo.

```text
2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08  debian13/linux
57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2  debian13/initrd.gz
8f7ea7e32207da313146d0fd113e7553d4f83fda551eb3a46f9bcf216621cee2  tftpboot/undionly.kpxe
d34dc1e65036aba656082e3b362ee672df71d46adc44fa8966acf069b1544285  tftpboot/snponly.efi
e80bd68d752554cacdb4697c3659942a904b8ad3ea35a44a8f0214add8c963fc  tftpboot/ipxe.efi
```

## Qué trasladar de cada archivo

| Origen | Aplicación en `infra-scripts` |
|---|---|
| `compilar_ipxe.sh`, `embed.ipxe`, árbol `ipxe/` | Reutilizar `network/ipxe/compilar-ipxe-custom.sh`. Añadir el destino `bin-x86_64-efi/snponly.efi`, parametrizar el URL completo y conservar la espera de enlace y el reintento DHCP para probarlos en el Dell. Usar el commit fuente fijado y publicar los hashes. Los EFI de la laptop apuntan al servidor de la prueba. [Compilador actual](../../network/ipxe/compilar-ipxe-custom.sh) |
| `dnsmasq.conf` | Renderizar DHCP y TFTP desde un inventario de aprovisionamiento con la interfaz y las MAC exactas del piloto. El rol grande usa TFTP integrado en dnsmasq, por lo que puede cubrir ambos puertos en un controlador dedicado. [Plantilla actual](../../ansible/roles/pxe_controller/templates/dnsmasq.conf.j2) |
| `boot.ipxe`, `debian13/` | Crear una plantilla iPXE y un árbol HTTP propios para Debian netboot. Usar el kernel y el initrd de la misma publicación y servirlos localmente. La plantilla actual `boot.ipxe.j2` apunta a `ipa.kernel` e `ipa.initramfs`. [Arranque de IPA actual](../../ansible/roles/pxe_controller/templates/boot.ipxe.j2) |
| `preseed.cfg.example` | Portar las decisiones de idioma, red, mirror, paquetes y GRUB a una plantilla por equipo. Añadir el disco autorizado, el usuario del inventario, la llave pública, Python 3 y el acceso administrativo que requieren los playbooks. [Guía de acceso y prerrequisitos](../../GUIA_DE_INSTALACION.md#etapa-a-preparar-equipos-y-laptop) |
| `preseed.cfg`, `pressed.cfg` | El primero contiene credenciales locales en claro. El segundo está vacío. Generar un preseed nuevo para cada destino. |
| `sync_servicios.sh` | Traducir publicación, permisos, validación y reinicio de servicios a tareas idempotentes. El script de prueba sobrescribe `/etc/dnsmasq.conf`, configura NAT para cualquier origen con salida por `wlp4s0` y usa rutas propias de la laptop. Reutilizar el firewall del entorno para permitir solamente el tráfico de la subred de aprovisionamiento. |
| `node.csv` | Derivar identidad, MAC, IP y usuario del inventario del proyecto. Mantener el permiso temporal de instalación y el progreso como estado operativo fuera de Git. El CSV de prueba usa una sola fila y el monitor asume `INSTALL` si falta la columna de estado. |
| `desplegar.py`, `wakeonlan.py` | Conservar el valor del panel y del encendido remoto como complementos. Primero probar con un arranque PXE puntual desde F12. Si se integra el monitor, limitar su escucha y dejar el encendido como acción explícita por nodo. El script original envía Wake-on-LAN a todos los `INSTALL` al iniciar. |
| `dell_bios_config.sh` | Documentar SATA/AHCI, Deep Sleep, Wake-on-LAN y Fastboot como comprobaciones del firmware Dell. Mantener los cambios de BIOS fuera del preseed del piloto. El script ignora fallos de escritura, selecciona una MAC para reportar y no comprueba que el hardware sea el destino autorizado. El initrd revisado trae `sh`, `wget` y `modprobe`; no contiene `bash`, `curl`, `cctk` ni el módulo `dell-wmi-sysman`. El `wget … \| bash` del preseed carece de evidencia de haber ejecutado los cambios. |
| `generar_despliegue_masivo.sh`, `archivo_historico/` | Referencia para reservas, enrolamiento de Ironic y preparación de la laptop. La instalación desatendida publicada usa los archivos estáticos. Los scripts históricos cambian firewall, reinician servicios y, en un caso, reinician el nodo por SSH. |

## Cambios necesarios para un piloto repetible

### 1. Elegir controlador, red y equipo

| Parámetro | Prueba original | Diseño actual del laboratorio |
|---|---|---|
| Controlador de aprovisionamiento | Laptop `192.168.1.2/24`, `eno1` | Nodo 306 `10.100.29.30/24`, `enp2s0` en variables de inventario. Wi-Fi de administración `192.168.29.25`. |
| Destino original | Nodo 279 `192.168.1.1`, MAC `64:00:6a:2a:2f:cb` | Misma MAC y nodo, `10.100.29.112`, usuario `debian`. La última inspección lo registró como worker de RKE2. |
| Gateway, DNS y dominio | `192.168.1.2`, `1.1.1.1`/`8.8.8.8`, `rodri.local` | `10.100.29.30`, `192.168.26.120`, `lab.local` en el diseño. Confirmar que el instalador alcance DNS y el mirror desde el destino. |
| HTTP y telemetría | Nginx TCP 80 bajo `/ipxe/`, Python TCP 8089 | Nginx del rol actual usa TCP 8089. Dar al monitor otro puerto si ambos viven en el mismo controlador. |

Para la primera prueba del proyecto grande, usar un controlador y un equipo con disco prescindible en una red aislada. El 306 alojaba el control plane de RKE2 y servicios Kolla en la última inspección. Kolla declara DHCP en `enp2s0`. Un segundo rango DHCP en la misma VLAN no evita que ambos servidores respondan. Verificar quién gestiona DHCP UDP 67, TFTP UDP 69 y HTTP antes de asignar esa interfaz o publicar archivos en el 306. [Inventario YAML](../../inventory/lab/hosts.yml) · [Configuración de Kolla](../../openstack/globals.yml) · [Estado observado del laboratorio](../reference/estado-observado-2026-10-30.md)

### 2. Integrar un playbook de aprovisionamiento Debian netboot

Añadir un playbook explícito bajo `ansible/playbooks/20-services/`, dirigido al controlador del piloto. Reutilizar las piezas de TFTP y HTTP del rol `pxe_controller` donde corresponda. La secuencia de tareas del playbook será:

1. Validar los datos del controlador y del destino. Resolver IP, interfaz, puerto, máscara, gateway, DNS, MAC, disco, usuario y llave pública desde variables. Confirmar que el controlador tiene su IP configurada, que las MAC/IP son únicas y que los puertos pertenecen a los servicios previstos. El destino elegido debe ser un equipo distinto del controlador.
2. Preparar el par kernel/initrd y los binarios iPXE con sus checksums. Conservar `undionly.kpxe` para BIOS y `snponly.efi` para UEFI como en la prueba. Si se conserva el script embebido, reconstruirlo para el URL elegido. [Tipos de binario iPXE](https://ipxe.org/appnote/buildtargets)
3. Renderizar DHCP con reservas de MAC exactas, `port=0` si solo presta DHCP/TFTP, selección BIOS/UEFI y salto HTTP para clientes iPXE. Aplicar los artefactos primero, validar la configuración con `dnsmasq --test` y `nginx -t`, y después habilitar los servicios. La plantilla del proyecto grande actualmente marca como `known` también a cualquier MAC del prefijo Dell y recorre todo `baremetal`. Limitar el playbook al controlador solo limita dónde corre Ansible, por lo que el subconjunto de destinos debe ir en la propia configuración de aprovisionamiento.
4. Publicar por HTTP el menú iPXE, el kernel y el initrd. Usar los mismos datos por nodo para generar los parámetros de red que Debian Installer necesita antes de descargar su preseed. Probar el par kernel/initrd tal como se referencia en el script iPXE. La prueba estática usa `initrd=initrd.magic`, mientras el endpoint dinámico usa `initrd=initrd.gz`; conservar un solo método en el piloto y validar ambos modos de firmware si se van a soportar. [Manejo del initrd en iPXE](https://ipxe.org/cmd/imgfetch)
5. Generar el preseed por destino. Configurar `partman-auto/disk` de forma explícita y verificar por consola que el disco seleccionado es el autorizado. El comentario original dice `/dev/sda`, pero el archivo carece de esa directiva. Conservar la receta `atomic` para el primer ensayo, comprobar GRUB en el modo de firmware elegido y mover los comentarios de paquetes a líneas propias. Instalar `openssh-server`, `python3` y `sudo`. Añadir la llave pública al usuario correspondiente durante `late_command` y comprobar el acceso administrativo después del primer arranque. [Opciones del preseed de Debian](https://www.debian.org/releases/trixie/amd64/apbs04.en.html)
6. Revisar el acceso SSH antes del primer piloto. Deshabilitar el login directo de root y no incluir contraseñas en claro en la raíz HTTP. Si se usa un hash de contraseña, generarlo por destino y tratar el preseed como material sensible. Mantener la llave privada en la estación de administración. El archivo de prueba define un usuario distinto de `debian` en al menos una variante y carece de una instalación de llave pública. Probar la cuenta y su método de acceso antes de automatizar más destinos.

El rol `pxe_controller` actual comprueba `ironic_dnsmasq` de Kolla, pero continúa instalando paquetes y escribiendo `boot.ipxe`, `dnsmasq.conf` y el sitio Nginx. Por eso, para el piloto, ejecutar el nuevo flujo solo en el controlador dedicado. Si luego se integra en el 306, validar convivencia y propiedad de rutas/puertos antes de tocar el rol que publica IPA. [Tareas del controlador PXE](../../ansible/roles/pxe_controller/tasks/main.yml)

### 3. Evitar una segunda instalación

- En el piloto, dejar disco primero en el orden de arranque y elegir PXE una vez con F12. Hacer que el menú vuelva al disco si se cancela, falla una descarga o la MAC carece de una instalación habilitada. Validar la salida a firmware en UEFI y el arranque de disco en BIOS.
- Para un flujo desatendido a escala, habilitar explícitamente cada MAC. Servir el instalador mediante un único camino que consulte y consuma esa habilitación, con estado persistente y escritura atómica. Un nuevo intento tras fallo se habilita desde el controlador. El retorno de iPXE por defecto debe ser el disco o el firmware.
- En la prueba, `DONE` solo decide el comportamiento de `/boot_script`. El firmware embebido y el DHCP apuntan al `boot.ipxe` estático, que ignora ese estado y vuelve a elegir la instalación después de cinco segundos para la MAC 279. Además, el endpoint dinámico original descarga kernel/initrd de Internet y usa gateway `192.168.1.254`, mientras la ruta publicada carga archivos locales y usa `.2`.
- Tratar `/heartbeat` como telemetría. El original acepta `completed` sin autenticación y lo interpreta como final aunque todavía falte reiniciar. Registrar la transición a sistema operativo listo después de comprobar SSH y el disco de arranque. El aviso `partman/early_command` marca el comienzo del particionado; los porcentajes del monitor son estimaciones.

### 4. Ejecutar y aceptar el piloto

1. **Controlador.** Confirmar IP y servicios. Revisar DHCP, TFTP y HTTP desde el segmento del piloto. `HEAD` en loopback valida publicación; descargar los archivos desde el segmento y comparar los hashes valida también la ruta y el contenido.

   ```bash
   ip -br address
   sudo ss -luntp
   sudo dnsmasq --test
   sudo nginx -t
   ```

2. **Consola del destino.** Seleccionar arranque PXE puntual y comprobar en secuencia que recibe su IP, descarga el binario adecuado, abre el menú, carga kernel/initrd, obtiene el preseed y descarga paquetes. Confirmar el disco y observar que el instalador termina sin intervención. La salida de Internet se puede probar antes desde otro equipo de esa misma subred.
3. **Primer arranque.** Observar por consola que el equipo inicia desde su disco. Entrar por SSH con el usuario y la llave del inventario. Comprobar `hostname`, `cat /etc/os-release`, `ip -br address`, `findmnt /`, `systemctl is-active ssh`, `python3 --version` y `sudo -n true` si el despliegue usará sudo sin contraseña. En UEFI comprobar también que el firmware vuelve a iniciar el disco tras un segundo reinicio.
4. **Ansible.** Una vez incorporado el piloto al inventario correcto y configurado el acceso SSH, comprobar únicamente el nuevo equipo. El grupo `baremetal` debe incluirlo. Este es el punto de entrega a la guía de Kubernetes.

   ```bash
   ansible-inventory -i inventory/lab/hosts.yml --graph
   ansible-playbook -i inventory/lab/hosts.yml \
     ansible/playbooks/00-preflight/00_ping.yml --limit NOMBRE_DEL_PILOTO
   ```

5. **Prueba de regresión del arranque.** Una vez deshabilitado el destino, forzar otro arranque por red y verificar que vuelve al disco o al firmware. Comprobar que otra MAC no recibe instrucciones para instalar. Si falla alguna etapa, deshabilitar el destino y retirar DHCP del segmento de prueba hasta corregirla. Guardar la consola del instalador y los logs del controlador para identificar el último paso completado.

### Diagnóstico por etapa

| Síntoma | Qué comprobar |
|---|---|
| El firmware no recibe IP | Cable y enlace, interfaz de aprovisionamiento, VLAN, reserva MAC y `journalctl -u dnsmasq`. Confirmar que haya un solo servidor DHCP en el segmento. |
| Hay IP pero el binario no descarga o se repite el PXE | Arquitectura anunciada, nombre del binario, servicio TFTP y detección de la clase `iPXE` que cambia el destino a HTTP. |
| iPXE abre consola tras el encadenamiento | URL grabada en el binario, puerto y ruta de Nginx. Confirmar que el binario reconstruido apunte al controlador del piloto. |
| Debian Installer no encuentra el preseed | IP, gateway, hostname y URL pasados al kernel. Revisar la interfaz detectada por Debian y el acceso HTTP desde esa subred. El initrd revisado contiene `r8169`; verificar el controlador y el firmware que requiera el equipo concreto. |
| Aparecen preguntas durante el particionado o APT | Revisar el nombre real del disco, el modo BIOS/UEFI, los logs de Debian Installer y la resolución de DNS y acceso al mirror. |
| El instalador termina y el equipo vuelve a PXE | Orden de arranque, ruta EFI, GRUB y permiso de instalación del destino. Comprobar el disco local por consola antes de declarar el nodo listo. |

## Credenciales encontradas en el entorno de prueba

Nginx devolvió HTTP 200 sin autenticación para `/ipxe/preseed.cfg` desde loopback, con TCP 80 escuchando en todas las interfaces. El archivo publicado coincide con el preseed local, que contiene contraseñas en claro. El mismo archivo está versionado en el commit local histórico `316890d` de `master`, aunque `develop` lo ignora. Retirar el archivo publicado, rotar cualquier contraseña reutilizada y revisar si esa rama se compartió. La revisión omitió los valores de las credenciales y no probó acceso desde otra máquina.

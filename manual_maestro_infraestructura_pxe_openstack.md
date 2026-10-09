# Manual Maestro de Infraestructura, Automatización y Despliegue Bare-Metal
## Guía de Ingeniería: DHCP/PXE, iPXE, OpenStack Glance, Ironic, Nexus y Monitoreo

---

## 1. Resumen Ejecutivo

Este manual establece la arquitectura integral para transformar un parque de servidores bare-metal heterogéneos en una nube privada automatizada y medible. Mediante la orquestación de **dnsmasq**, **iPXE** y **Nginx**, se implementa un pipeline de aprovisionamiento de red *zero-touch* blindado contra la red de oficina. Se analiza el rol de **OpenStack Glance** clarificando la distinción crítica entre arranque por ISO virtualizada e imágenes doradas desplegadas en metal mediante **Ironic/Bifrost**, integrando **Packer**, **Nexus Sonatype** y telemetría en tiempo real con **Prometheus** y **Grafana**.

---

## 2. Glosario Técnico Breve

1. **PXE (Preboot Execution Environment)**: Estándar de la industria (WfM 1999) integrado en la ROM de la tarjeta de red (NIC) que permite a una computadora obtener IP y descargar un binario ejecutable de arranque antes de inicializar cualquier sistema operativo local.
2. **TFTP (Trivial File Transfer Protocol)**: Protocolo de transferencia de archivos extremadamente simple sobre UDP (puerto 69), sin autenticación ni control de flujo avanzado. Su único propósito en PXE es entregar el bootloader inicial de pocos kilobytes.
3. **DHCP (Dynamic Host Configuration Protocol)**: Protocolo cliente-servidor (UDP 67/68) que entrega IP, máscara, gateway, DNS y, en despliegues PXE, las **Opciones 66** (servidor TFTP/Next-Server) y **67** (nombre del archivo de arranque o Bootfile-Name).
4. **UEFI (Unified Extensible Firmware Interface)**: Especificación moderna que sustituye a la BIOS heredada (Legacy). Proporciona tablas de particionado GPT (>2 TB), ejecución modular en 64 bits y soporte de red nativo seguro.
5. **iPXE**: Bootloader de red de código abierto de alto rendimiento. Extiende las capacidades del PXE tradicional permitiendo descargar kernels y sistemas operativos a través de **HTTP/HTTPS**, iSCSI y DNS a velocidad de cable gigabit.
6. **Glance**: Servicio de registro y catálogo de imágenes de disco de OpenStack. Almacena metadatos y gestiona el backend de almacenamiento (Ceph, archivos locales, Swift, S3) para máquinas virtuales e instancias bare-metal.
7. **ISO**: Archivo de imagen de disco óptico estandarizado (ISO 9660 / UDF). Diseñado originalmente para CD/DVD de instalación guiada interactiva.
8. **QCOW2 (QEMU Copy-On-Write v2)**: Formato de imagen de disco virtual con asignación dinámica de espacio, soporte de instantáneas (*snapshots*) y compresión zlib. Formato predilecto en OpenStack.
9. **Preseed / Autoinstall**: Mecanismos de Debian/Ubuntu para responder de forma anticipada a todas las preguntas del instalador (`partman`, idioma, usuarios, red), logrando instalaciones desatendidas sin interacción humana.
10. **Cloud-Init**: Estándar multiplataforma de inicialización de instancias en el primer arranque (*early boot*). Configura llaves SSH, contraseñas, nombres de host, interfaces de red y ejecuta scripts provistos vía *user-data*.

---

## 3. Desarrollo Técnico Detallado

---

### TAREA 1: Documentación de lo Aprendido y Estructura del Conocimiento

#### 1.1 Filosofía de Documentación: Por qué la infraestructura indocumentada es deuda técnica
En ingeniería de infraestructura, "un servicio que no está documentado no existe; y si falla, es un desastre no planificado". La documentación técnica debe ser ejecutable, auditable y versionada junto con el código (enfoque *Documentation as Code*).

#### 1.2 Plantilla Reutilizable `.md`
```markdown
# [Nombre de la Herramienta o Servicio]

## 1. Descripción y Utilidad
- **¿Qué es?**: Definición técnica concisa.
- **¿Para qué sirve en este laboratorio?**: Problema real concreto que resuelve dentro de la arquitectura.
- **Analogía cotidiana**: Concepto simplificado para rápida comprensión.

## 2. Instalación y Requisitos
- **Requisitos de hardware/red**: CPU, RAM, puertos de red necesarios.
- **Comandos de instalación paso a paso**:
  \`\`\`bash
  # Comandos de instalación comentados
  \`\`\`
- **Salida esperada**: Registro de confirmación de éxito.

## 3. Uso y Configuración Operativa
- **Archivos de configuración clave**: Rutas absolutas.
- **Comandos de gestión del servicio**:
  \`\`\`bash
  sudo systemctl start/status/restart [servicio]
  \`\`\`
- **Ejemplo práctico probado**: Caso de uso real verificado en el laboratorio.

## 4. Alternativas Tecnológicas
| Herramienta | Ventajas | Desventajas | Cuándo usarla sobre la actual |
| :--- | :--- | :--- | :--- |
| Alternativa A | ... | ... | ... |
| Alternativa B | ... | ... | ... |

## 5. Roles de Usuario y Matriz de Permisos
- **Administrador**: Capacidades completas.
- **Operador / DevOps**: Despliegue y lectura de telemetría.
- **Auditor / Lector**: Monitoreo y logs sin privilegios de escritura.

## 6. Problemas Encontrados y Soluciones Forenses
| Síntoma de Error | Causa Raíz | Comando de Detección | Procedimiento de Corrección |
| :--- | :--- | :--- | :--- |
| ... | ... | ... | ... |

## 7. Referencias Oficiales y Documentación
- [Documentación Oficial de la Herramienta](https://...)
- [Repositorio o RFC de Referencia](https://...)
```

#### 1.3 Estructura de Directorios Recomendada en Git
```text
infra-scripts/
├── docs/
│   ├── tools/
│   │   ├── 01-dnsmasq.md
│   │   ├── 02-pxe-tftp.md
│   │   ├── 03-nginx.md
│   │   ├── 04-nexus.md
│   │   ├── 05-packer.md
│   │   ├── 06-cloud-init.md
│   │   ├── 07-glance.md
│   │   ├── 08-ironic-bifrost.md
│   │   ├── 09-prometheus.md
│   │   ├── 10-node-exporter.md
│   │   └── 11-grafana.md
│   ├── runbooks/
│   │   ├── recuperacion-desastres.md
│   │   └── blindaje-red-oficina.md
│   └── templates/
│       └── template-herramienta.md
├── config/
│   ├── env
│   └── nodes.csv
└── scripts/
```

---

### TAREA 2: Arranque e Instalación por Red (Network Boot & PXE)

#### 2.1 Anatomía del Arranque por Red: Paso a Paso
El ciclo de arranque de red opera como una carrera de relevos entre cuatro protocolos:

```text
+----------+          +------------+          +-------------+          +------------+
| Mini PC  |          | Servidor   |          | Servidor    |          | Servidor   |
| (Cliente)|          | DHCP       |          | TFTP        |          | Nginx HTTP |
+----+-----+          +-----+------+          +------+------+          +-----+------+
     |                      |                        |                       |
     | 1. DHCPDISCOVER      |                        |                       |
     |--------------------->|                        |                       |
     |                      |                        |                       |
     | 2. DHCPOFFER         |                        |                       |
     |    (IP + Opt 66/67)  |                        |                       |
     |<---------------------|                        |                       |
     |                      |                        |                       |
     | 3. DHCPREQUEST       |                        |                       |
     |--------------------->|                        |                       |
     | 4. DHCPACK           |                        |                       |
     |<---------------------|                        |                       |
     |                                               |                       |
     | 5. RRQ: /tftpboot/ipxe.efi                    |                       |
     |---------------------------------------------->|                       |
     | 6. TFTP DATA: Bloques binario ipxe.efi        |                       |
     |<----------------------------------------------|                       |
     |                                                                       |
     | 7. HTTP GET: /boot.ipxe                                               |
     |---------------------------------------------------------------------->|
     | 8. HTTP 200 OK: Script iPXE con parámetros de Kernel                  |
     |<----------------------------------------------------------------------|
     |                                                                       |
     | 9. HTTP GET: /debian/linux e initrd.gz (100 MB/s)                     |
     |---------------------------------------------------------------------->|
     | 10. HTTP 200 OK: Carga Kernel e Initrd en Memoria RAM                 |
     |<----------------------------------------------------------------------|
     |                                                                       |
     | 11. Ejecución del Kernel Linux -> Descarga preseed.cfg e ISO Offline |
     +-----------------------------------------------------------------------+
```

1. **Fase DHCP (Identificación y Guía)**: La NIC envía un broadcast `DHCPDISCOVER`. El servidor responde con `DHCPOFFER` entregando la IP del nodo, la máscara, el gateway y dos datos críticos:
   - **Opción 66 (*Next-Server*)**: Dirección IP del servidor TFTP (`10.100.29.30`).
   - **Opción 67 (*Bootfile-Name*)**: Archivo ejecutable de arranque correspondiente a la arquitectura de la miniPC (`ipxe.efi` para UEFI x86_64).
2. **Fase TFTP (Bootloader de Bajo Nivel)**: La ROM del cliente descarga por TFTP (UDP 69) el ejecutable `ipxe.efi`. TFTP transfiere bloques pequeños (512 o 1428 bytes), suficiente para cargar los ~1 MB de iPXE en RAM.
3. **Fase HTTP (Aceleración de Transferencia)**: iPXE toma el control de la tarjeta de red, solicita una nueva confirmación DHCP y descarga por HTTP (puerto 80/8089 de Nginx) el kernel (`linux`) y el sistema de archivos inicial (`initrd.gz`). **Ventaja**: HTTP utiliza TCP con ventanas deslizantes, transfiriendo a 1 Gbps (110 MB/s) en vez de los lentos 2-5 MB/s de TFTP.
4. **Fase Instalación Desatendida**: El kernel arranca en RAM, toma el control del hardware, inicializa los discos y descarga `preseed.cfg`. Este archivo responde automáticamente al particionamiento, formateo, instalación de paquetes y usuario, finalizando con un reinicio automático en disco local.

#### 2.2 Diferencias Críticas: BIOS Legacy vs UEFI vs HTTP Boot
| Característica | BIOS Legacy PXE | UEFI PXE Boot | UEFI HTTP Boot Nativo |
| :--- | :--- | :--- | :--- |
| **DHCP Client Arch (Opción 93)** | `00:00` (Architecture 0) | `00:07` o `00:09` (EFI x86_64) | `00:10` (HTTP Client x86_64) |
| **Bootloader Requerido** | `undionly.kpxe` / `pxelinux.0` | `ipxe.efi` / `grubnetx64.efi` | Archivo EFI servido directamente por HTTP |
| **Límite de Disco** | MBR (Máximo 2 TB) | GPT (> 2 TB nativo) | GPT (> 2 TB nativo) |
| **Seguridad** | Sin firmas | Soporta Secure Boot | Soporta Secure Boot y TLS |
| **Diagnóstico en Cliente** | Pantalla negra con texto blanco | Logo del fabricante + resolución nativa | Descarga directa por URL en firmware |

*¿Cómo saber qué usan tus mini PCs?*: Ejecuta en cualquier nodo encendido:
```bash
[ -d /sys/firmware/efi ] && echo "MODO UEFI" || echo "MODO BIOS LEGACY"
```

#### 2.3 Configuración Completa y Comentada de `dnsmasq.conf`
```ini
# ==============================================================================
# CONFIGURACIÓN MAESTRA DE DNSMASQ: DHCP + TFTP + ENCADENAMIENTO iPXE
# Archivo: /etc/dnsmasq.conf en Nodo 306
# ==============================================================================

# 1. AMARRE DE INTERFAZ FÍSICA Y AISLAMIENTO
interface=enp2s0
bind-interfaces

# 2. PUERTA DE ENLACE Y SERVIDOR DNS CORPORATIVO
dhcp-option=3,10.100.29.1
dhcp-option=6,192.168.26.120

# 3. RANGO DINÁMICO EFÍMERO (Para descubrimiento Baremetal o Ironic Inspector)
dhcp-range=10.100.29.50,10.100.29.99,255.255.255.0,1h

# 4. RESERVAS ESTÁTICAS DE IP POR DIRECCIÓN MAC (Desde config/nodes.csv)
dhcp-host=64:00:6a:2a:60:62,10.100.29.10,bastion,infinite
dhcp-host=64:00:6a:2a:5f:99,10.100.29.20,nexus-repo,infinite
dhcp-host=64:00:6a:2a:62:42,10.100.29.30,pxe-controller,infinite
dhcp-host=64:00:6a:2a:5f:f9,10.100.29.101,k8s-cp-01,infinite
dhcp-host=64:00:6a:2a:60:63,10.100.29.102,k8s-cp-02,infinite
dhcp-host=64:00:6a:2a:2c:75,10.100.29.103,k8s-cp-03,infinite
dhcp-host=64:00:6a:2a:62:a4,10.100.29.111,k8s-worker-01,infinite
dhcp-host=64:00:6a:2a:2f:cb,10.100.29.112,k8s-worker-02,infinite

# 5. SERVIDOR TFTP EMBEBIDO
enable-tftp
tftp-root=/tftpboot

# 6. ENCADENAMIENTO DE BOOTLOADER INTELIGENTE (BIOS vs UEFI vs iPXE)
# Detectar si el cliente ya ejecuta el firmware enriquecido iPXE
dhcp-userclass=set:ipxe,iPXE

# Si el cliente ya es iPXE, descargar el script de arranque vía Nginx HTTP (:8089)
dhcp-boot=tag:ipxe,http://10.100.29.30:8089/boot.ipxe

# Si NO es iPXE todavía, entregar binario de primer arranque según arquitectura:
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:!ipxe,tag:bios,undionly.kpxe

dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-boot=tag:!ipxe,tag:efi-x86_64,ipxe.efi

# 7. BLINDAJE FORENSE CONTRA EQUIPOS DE OFICINA
log-dhcp
dhcp-ignore=tag:!known
```

#### 2.4 Servidor Web HTTP con Nginx (`/etc/nginx/sites-available/default`)
```nginx
server {
    listen 80 default_server;
    listen 8089;
    server_name _;

    root /httpboot;
    autoindex on;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

#### 2.5 Instalación Desatendida con Preseed ([preseed.cfg](file:///httpboot/debian/preseed.cfg))
Ubicado en `/httpboot/debian/preseed.cfg`, suprime cualquier intervención interactiva:
```ini
#### Localizacion e Idioma
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select es

#### Red automatizada
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string unassigned-node
d-i netcfg/get_domain string lab.local
d-i hw-detect/load_media boolean false

#### Repositorio 100% Offline (Montado desde la ISO en Nodo 306)
d-i mirror/country string manual
d-i mirror/http/hostname string 10.100.29.30:8089
d-i mirror/http/directory string /iso
d-i mirror/http/proxy string
d-i mirror/suite string trixie

#### Particionado Automatico no interactivo (Disco 128 GB)
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

#### Cuentas de Usuario y Credenciales de Laboratorio
d-i passwd/root-login boolean true
d-i passwd/root-password password 321
d-i passwd/root-password-again password 321
d-i passwd/user-fullname string Debian Admin
d-i passwd/username string debian
d-i passwd/user-password password 321
d-i passwd/user-password-again password 321
d-i passwd/user-default-groups string sudo

#### Paquetes Base y SSH
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string openssh-server sudo curl htop
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default

#### Inyeccion de Llave SSH y Sudoers
d-i preseed/late_command string \
    in-target sh -c "echo 'debian ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-debian && chmod 0440 /etc/sudoers.d/99-debian"; \
    in-target sh -c "mkdir -p /etc/ssh/sshd_config.d && echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/permit-root.conf"

#### Reinicio Automatico sin Pausa
d-i finish-install/reboot_in_progress note
```

#### 2.6 Automatización con Wake-on-LAN (WoL)
Una miniPC apagada pero conectada a la corriente mantiene su chip de red en espera (*standby*). Cuando recibe un **Magic Packet** (un paquete UDP por el puerto 9 compuesto por `FF:FF:FF:FF:FF:FF` seguido de la MAC del nodo repetida 16 veces consecutivas), la tarjeta despierta la placa madre.

*Comando para despertar al nodo 321*:
```bash
wakeonlan 64:00:6a:2a:62:a4
# O usando etherwake indicando interfaz:
sudo etherwake -i {--tdr--} 64:00:6a:2a:62:a4  <--- tarjeta de red (tdr)
```

---

### TAREA 3: OpenStack Glance, Formatos de Disco e Ironic Bare-Metal

#### 3.1 Qué es Glance y dónde encaja en la Arquitectura OpenStack
OpenStack no es un programa único, sino un ecosistema modular de microservicios:
* **Keystone**: Servicio de identidad, autenticación (tokens) y catálogo de endpoints.
* **Glance**: Servicio de registro y distribución de imágenes de disco.
* **Nova**: Planificador (*scheduler*) y controlador del ciclo de vida de **Máquinas Virtuales** (hipervisores KVM/QEMU).
* **Ironic**: Hipervisor de **Metal Desnudo (*Bare-Metal*)**. En lugar de crear una VM, Ironic toma un servidor físico real, lo enciende por IPMI/WoL, escribe la imagen de disco directamente sobre el NVMe/SSD físico mediante un ramdisk auxiliar (**IPA - Ironic Python Agent**) y lo entrega como una instancia nativa.
* **Cinder**: Almacenamiento de bloques persistente (volúmenes tipo SAN/Ceph).

```text
               +----------------------------------+
               |        Keystone (Tokens)         |
               +----------------+-----------------+
                                |
             +------------------+------------------+
             |                                     |
+------------v-----------+              +----------v-------------+
|   Nova (Cómputo VM)    |              |  Ironic (Bare-Metal)   |
|   Lanza instancias KVM |              |  Aprovisiona Físicos   |
+------------+-----------+              +----------+-------------+
             |                                     |
             +------------------+------------------+
                                |
                   +------------v------------+
                   |  Glance (Catálogo de    |
                   |  Imágenes Doradas)      |
                   +-------------------------+
```

#### 3.2 Formatos de Disco y Contenedor
* **Formatos de Disco (`--disk-format`)**:
  * `raw`: Sector por sector sin compresión. Es el formato de más rápida escritura para **Ironic** (se vuelca con `dd` directamente al disco físico).
  * `qcow2`: Formato dinámico con compresión. Ideal para almacenamiento y plantillas base construidas con Packer.
  * `iso`: Imagen de CD/DVD óptico.
* **Formatos de Contenedor (`--container-format`)**:
  * `bare`: Indica que la imagen de disco no está empaquetada dentro de ningún contenedor virtual adicional (es el estándar absoluto para Linux en OpenStack).

#### 3.3 Aclaración Técnica Fundamental: ¿Qué se puede hacer REALMENTE con una ISO en Glance?

> [!CAUTION]
> **Error Conceptual Común**: "Subir una ISO de Debian/Ubuntu a Glance para que Ironic la instale por PXE en los miniPCs".
> **Realidad de Ingeniería**: **Ironic NO instala sistemas operativos ejecutando instaladores interactivos desde una ISO.**

Diferenciemos los cuatro escenarios posibles:

| Escenario | ¿Cómo funciona? | ¿Usa Glance? | ¿Aplica a bare-metal? |
| :--- | :--- | :--- | :--- |
| **A. VM con CD-ROM virtual (Nova)** | Nova monta la ISO como lectora de CD virtual en KVM. Un humano debe abrir la consola VNC y hacer clic en "Siguiente". | **SÍ** | **NO** (Es una VM). |
| **B. Imagen Dorada (Packer + Ironic)** | Packer compila un Debian preinstalado con cloud-init en formato `.qcow2` o `.raw`. Ironic arranca un kernel temporal en RAM (**IPA**), vuelca la imagen directamente a los bloques del disco físico y reinicia. | **SÍ** | **SÍ** (Es el estándar de producción en OpenStack). |
| **C. Despliegue PXE Clásico con Instalador** | dnsmasq entrega kernel + initrd; el instalador de Debian corre en memoria y formatea el disco usando `preseed.cfg`. | **NO** (Usa Nginx/TFTP, no Glance). | **SÍ** (Es lo que configuramos en la Tarea 2). |
| **D. Arranque Live ISO en Bare-Metal** | Se carga una ISO completa en RAM con iPXE (`memdisk` o `sanboot`). Consume gigabytes de RAM y no persiste datos tras reiniciar. | **NO** | **NO** recomendado. |

**Conclusión para tu Laboratorio**:
1. Para **instalar los miniPCs desde la ISO de Debian 13**: Usa el flujo de la **Tarea 2** (dnsmasq + Nginx HTTP + Preseed). No requiere Glance.
2. Para **usar OpenStack Glance e Ironic**: Usa **Packer** para crear una imagen dorada (`debian-cloud.qcow2`), súbela a Glance y deja que Ironic la escriba directo a los discos de los miniPCs en 60 segundos.

#### 3.4 Comando de Carga en Glance y Validación
```bash
# 1. Cargar credenciales administrativas de OpenStack
source /root/openrc admin admin

# 2. Subir imagen dorada a Glance
openstack image create "debian-13-baremetal-cloud" \
  --file /opt/images/debian-13-cloud.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  --public \
  --property cpu_arch=x86_64 \
  --property hypervisor_type=ironic

# 3. Validar estado (debe mostrar status: active)
openstack image show "debian-13-baremetal-cloud" -f table
```

#### 3.5 Matriz de Roles y Visibilidad en Glance
* **Roles en Keystone**:
  * `admin`: Puede crear imágenes públicas (`--public`), modificar cuotas y borrar imágenes de cualquier proyecto.
  * `member`: Puede crear imágenes privadas (`--private`) dentro de su propio proyecto/tenant.
  * `reader`: Acceso de solo lectura para listar y descargar imágenes autorizadas.
* **Visibilidad**:
  * `public`: Visible y utilizable por cualquier usuario de cualquier proyecto.
  * `private`: Visible únicamente dentro del proyecto que la subió.
  * `shared`: Compartida explícitamente con proyectos específicos mediante invitación.
  * `community`: Pública para lectura, pero sin soporte oficial del administrador.

---

## 4. Diagramas de Flujo de Arquitectura

### Flujo A: Aprovisionamiento Bare-Metal Desatendido (PXE + Preseed)
```text
+-------------------+
| Mini PC Apagada   |
+---------+---------+
          |  [1. Magic Packet por puerto UDP 9]
+---------v---------+
| Wake-on-LAN (WoL) |
+---------+---------+
          |  [2. Encendido físico y arranque de ROM de red]
+---------v---------+
|  PXE DHCP Discover|
+---------+---------+
          |  [3. Dnsmasq entrega IP privada + ipxe.efi (Opción 67)]
+---------v---------+
|    iPXE en RAM    |
+---------+---------+
          |  [4. Descarga boot.ipxe por HTTP :8089 (Nginx)]
+---------v---------+
| Kernel + Initrd   |
+---------+---------+
          |  [5. Descarga preseed.cfg e ISO offline de Debian 13]
+---------v---------+
| Instalador Debian |
+---------+---------+
          |  [6. Particionado atómico de 128 GB + Sudoers + SSH]
+---------v---------+
| Sistema Instalado | ---> Reinicio automático en disco local NVMe/SSD
+-------------------+
```

### Flujo B: Pipeline de Producción (Packer -> Glance -> Ironic)
```text
+---------------------+
| ISO Debian 13       |
| + Nexus APT Proxy   |
+----------+----------+
           |  [1. Packer compila máquina con cloud-init]
+----------v----------+
| Imagen QCOW2 Dorada |
+----------+----------+
           |  [2. openstack image create en Nodo 306]
+----------v----------+
|   Glance Catálogo   |
+----------+----------+
           |  [3. Ironic/Bifrost lanza aprovisionamiento]
+----------v----------+
| IPA Ramdisk en Nodo |  [4. Escribe imagen bit a bit en el disco local]
+----------+----------+
           |  [5. Cloud-init personaliza hostname, IPs y llaves]
+----------v----------+
| Nodo Bare-Metal OK  | ---> Listo para unirse al clúster Kubernetes RKE2
+---------------------+
```

---

## 5. Tabla de Diagnóstico Forense de Errores

| Código o Síntoma de Error | Causa Raíz Probable | Cómo Detectarlo en Terminal | Procedimiento de Corrección |
| :--- | :--- | :--- | :--- |
| **PXE-E53: No boot filename received** | El servidor DHCP respondió pero omitió la Opción 67 (`bootfile-name`), o la MAC fue rechazada por `dhcp-ignore`. | `sudo tcpdump -i enp2s0 -n -e port 67` (se ve OFFER sin opción 67). | Asegurar `dhcp-boot` en `dnsmasq.conf` y registrar la MAC en `dhcp-host`. |
| **PXE-E32: TFTP open timeout** | La miniPC no alcanza el puerto UDP 69 del servidor, o `enable-tftp` está apagado en dnsmasq. | `journalctl -u dnsmasq \| grep tftp` no muestra líneas de lectura. | Habilitar `enable-tftp` en `/etc/dnsmasq.conf`, verificar firewall `ufw allow 69/udp` y revisar enlace del cable. |
| **Kernel Panic: VFS Unable to mount root fs** | Parámetros de kernel corruptos en `boot.ipxe`, o el archivo `initrd.gz` se descargó truncado por HTTP. | Consola física de la miniPC muestra pantalla roja/negra con *Kernel panic*. | Comprobar integridad de `initrd.gz` con `gzip -t` y verificar que la línea `initrd` esté después de `kernel` en iPXE. |
| **Preseed se detiene pidiendo teclado o red** | Falta alguna directiva obligatoria en `preseed.cfg`, o la prioridad no es `critical`. | La pantalla azul del instalador de Debian espera intervención humana. | Asegurar `priority=critical` en los argumentos del kernel y definir `d-i console-setup/ask_detect boolean false`. |
| **Glance 401 Unauthorized** | El token de Keystone expiró o las variables de entorno de autenticación (`OS_*`) no están cargadas. | `openstack image list` devuelve `The request you have made requires authentication`. | Volver a cargar el archivo de variables: `source openrc admin admin`. |
| **Glance Image Status: `killed` / `queued`** | Fallo en la subida del archivo por agotamiento de espacio en disco en `/var/lib/glance/images`. | `openstack image show <id>` muestra estado `killed`. | Comprobar espacio libre con `df -h /var/lib/glance` y volver a subir con `--file`. |

---

## 6. Checklist de Validación Paso a Paso

- [ ] **Paso 1: Interfaz Cableada en Nodo 306 Activa**
  - *Listo cuando*: `cat /sys/class/net/enp2s0/carrier` devuelve `1` y `dmesg` muestra `Link is Up - 1000Mbps/Full`.
  - *Validación*: `ping -c 2 10.100.29.30` desde tu estación `10.100.29.250`.
- [ ] **Paso 2: Dnsmasq en Ejecución con Blindaje**
  - *Listo cuando*: `systemctl is-active dnsmasq` devuelve `active` y `/usr/sbin/dnsmasq --test` devuelve `syntax check OK`.
  - *Validación*: Peticiones de equipos de oficina aparecen como `ignorado` en `journalctl -u dnsmasq -f`.
- [ ] **Paso 3: Servidor Web Nginx Operativo**
  - *Listo cuando*: `curl -s -I http://10.100.29.30:8089/boot.ipxe` responde `HTTP/1.1 200 OK`.
  - *Validación*: Los archivos `linux`, `initrd.gz` y `preseed.cfg` devuelven código 200 por HTTP.
- [ ] **Paso 4: Repositorio ISO Montado**
  - *Listo cuando*: `mount | grep iso` muestra `/dev/loop0` montado en `/httpboot/iso`.
  - *Validación*: `curl -s -I http://10.100.29.30:8089/iso/README.txt` devuelve `HTTP/1.1 200 OK`.
- [ ] **Paso 5: Primer Nodo Instalado Desatendido**
  - *Listo cuando*: La miniPC seleccionada se reinicia sola tras completar la barra de instalación.
  - *Validación*: Conexión exitosa por SSH: `ssh debian@10.100.29.111` con clave `321`.

---

## 7. Documentación Técnica de las 10 Herramientas del Laboratorio

A continuación se presentan los 10 archivos `.md` de referencia listos para copiar a la carpeta `docs/tools/`:

---

### Documento 1: `docs/tools/01-dnsmasq.md`
```markdown
# Dnsmasq

## 1. Descripción y Utilidad
- **¿Qué es?**: Servidor ligero de red que combina DHCP, reenviador DNS y servidor TFTP en un solo binario de bajo consumo.
- **¿Para qué sirve en este laboratorio?**: Entrega IPs privadas fijas por MAC a las 8 mini PCs, bloquea dispositivos de oficina y sirve el bootloader iPXE.
- **Analogía**: El recepcionista del edificio que solo le entrega llaves a las personas de la lista y no deja pasar a extraños.

## 2. Instalación y Requisitos
- **Requisitos**: Tarjeta de red física, puertos UDP 67 (DHCP) y UDP 69 (TFTP).
- **Instalación**:
  \`\`\`bash
  sudo apt-get update && sudo apt-get install -y dnsmasq
  \`\`\`

## 3. Uso y Configuración
- **Archivo principal**: `/etc/dnsmasq.conf`
- **Gestión**:
  \`\`\`bash
  sudo dnsmasq --test
  sudo systemctl restart dnsmasq
  sudo journalctl -u dnsmasq -f
  \`\`\`

## 4. Alternativas
- ISC DHCP / Kea: Más potente para ISPs, pero carece de TFTP integrado y consume más memoria.

## 5. Roles
- **Root/Admin**: Modifica `/etc/dnsmasq.conf` y reinicia el servicio.

## 6. Problemas y Soluciones
- *Error*: `failed to bind DHCP server socket: Address already in use`.
- *Solución*: Desactivar `systemd-resolved` o colocar `bind-interfaces` en la configuración.

## 7. Referencias
- [Página Oficial Dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html)
```

---

### Documento 2: `docs/tools/02-pxe-tftp.md`
```markdown
# PXE / TFTP (iPXE)

## 1. Descripción y Utilidad
- **¿Qué es?**: Entorno de ejecución previo al arranque que descarga sistemas operativos sobre la red.
- **¿Para qué sirve en este laboratorio?**: Permite arrancar y formatear mini PCs sin memorias USB ni teclados conectados.
- **Analogía**: Cargar un sistema operativo desde una nube local directamente a la memoria RAM.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y ipxe
  sudo cp /usr/lib/ipxe/ipxe.efi /tftpboot/ipxe.efi
  \`\`\`

## 3. Uso y Configuración
- **Directorio raíz**: `/tftpboot/`
- **Script maestro**: `/tftpboot/boot.ipxe`

## 4. Alternativas
- GRUB2 Netboot: Bueno para menús complejos, pero iPXE es más ligero y soporta HTTP nativo.

## 5. Roles
- **Admin**: Actualiza binarios `.efi` y scripts de arranque.

## 6. Problemas y Soluciones
- *Error*: `TFTP open timeout`.
- *Solución*: Revisar que el puerto 69/UDP no esté bloqueado en el firewall.

## 7. Referencias
- [iPXE Documentation](https://ipxe.org/)
```

---

### Documento 3: `docs/tools/03-nginx.md`
```markdown
# Nginx (Servidor HTTP de Arranque)

## 1. Descripción y Utilidad
- **¿Qué es?**: Servidor web HTTP reverso de alto rendimiento orientado a eventos.
- **¿Para qué sirve en este laboratorio?**: Sirve el Kernel Linux, Initrd, preseed y la ISO de Debian 13 a 1 Gbps.
- **Analogía**: Una autopista de 10 carriles para descargar imágenes pesadas rápidamente.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y nginx
  \`\`\`

## 3. Uso y Configuración
- **Directorio raíz de red**: `/httpboot`
- **Puertos**: 80 y 8089

## 4. Alternativas
- Apache HTTPD: Más pesado en memoria para servir archivos estáticos.

## 5. Roles
- **Admin**: Configuración de `sites-available/default`.

## 6. Problemas y Soluciones
- *Error*: `403 Forbidden`.
- *Solución*: Habilitar `autoindex on;` y dar permisos `chmod -R 755 /httpboot`.

## 7. Referencias
- [Nginx Documentation](https://nginx.org/en/docs/)
```

---

### Documento 4: `docs/tools/04-glance.md`
```markdown
# OpenStack Glance

## 1. Descripción y Utilidad
- **¿Qué es?**: Catálogo y registro central de imágenes de disco en OpenStack.
- **¿Para qué sirve en este laboratorio?**: Provee las imágenes doradas que OpenStack Ironic vuelca a los discos físicos.
- **Analogía**: La biblioteca central de moldes de discos duros de la nube.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y glance python3-glanceclient
  \`\`\`

## 3. Uso y Configuración
- **Subir imagen**:
  \`\`\`bash
  openstack image create "debian-cloud" --file debian.qcow2 --disk-format qcow2 --container-format bare --public
  \`\`\`

## 4. Alternativas
- Servidor HTTP simple: Carece de metadatos de arquitectura y control de acceso multitenant.

## 5. Roles
- **Admin**: Publica imágenes globales.
- **Member**: Sube imágenes privadas de su proyecto.

## 6. Problemas y Soluciones
- *Error*: Imagen en estado `killed`.
- *Solución*: Revisar espacio en `/var/lib/glance/images`.

## 7. Referencias
- [OpenStack Glance Docs](https://docs.openstack.org/glance/latest/)
```

---

### Documento 5: `docs/tools/05-packer.md`
```markdown
# HashiCorp Packer

## 1. Descripción y Utilidad
- **¿Qué es?**: Herramienta de automatización que compila imágenes de disco idénticas a partir de una única plantilla de código.
- **¿Para qué sirve en este laboratorio?**: Convierte la ISO de Debian en una imagen QCOW2 lista con cloud-init preconfigurado.
- **Analogía**: La máquina que hornea panes listos para comer a partir de la receta.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y packer
  \`\`\`

## 3. Uso y Configuración
- **Ejecución**:
  \`\`\`bash
  packer build debian.pkr.hcl
  \`\`\`

## 4. Alternativas
- Diskimage-builder (DIB): Alternativa nativa de OpenStack para construir imágenes qcow2.

## 5. Roles
- **DevOps**: Desarrolla y versiona plantillas HCL.

## 6. Problemas y Soluciones
- *Error*: Timeout esperando conexión SSH en la compilación.
- *Solución*: Verificar la configuración de red y las credenciales temporales.

## 7. Referencias
- [Packer Official Documentation](https://developer.hashicorp.com/packer/docs)
```

---

### Documento 6: `docs/tools/06-cloud-init.md`
```markdown
# Cloud-Init

## 1. Descripción y Utilidad
- **¿Qué es?**: Paquete multiplataforma estándar de inicialización de instancias en el primer arranque.
- **¿Para qué sirve en este laboratorio?**: Personaliza cada mini PC inyectando su IP fija, hostname y llaves SSH.
- **Analogía**: El asistente de bienvenida que personaliza el sistema la primera vez que se enciende.

## 2. Instalación y Requisitos
- **Instalación en imagen**:
  \`\`\`bash
  sudo apt-get install -y cloud-init
  \`\`\`

## 3. Uso y Configuración
- **Archivos de configuración**: `/etc/cloud/cloud.cfg` y `/var/lib/cloud/seed/`

## 4. Alternativas
- Ignition: Usado principalmente en Flatcar y CoreOS.

## 5. Roles
- **Admin**: Define el archivo de directivas `user-data`.

## 6. Problemas y Soluciones
- *Error*: Llaves SSH no se copian al usuario.
- *Solución*: Revisar logs en `/var/log/cloud-init-output.log`.

## 7. Referencias
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
```

---

### Documento 7: `docs/tools/07-nexus.md`
```markdown
# Sonatype Nexus 3 OSS

## 1. Descripción y Utilidad
- **¿Qué es?**: Gestor universal de repositorios de artefactos y paquetes de software.
- **¿Para qué sirve en este laboratorio?**: Cachea paquetes de Debian (APT) e imágenes Docker/OCI en el Nodo 315, ahorrando internet.
- **Analogía**: Un almacén local de suministros para no tener que viajar al supermercado cada vez.

## 2. Instalación y Requisitos
- **Requisitos**: Java 17 LTS, PostgreSQL 17, 4 GB Heap RAM.
- **Puerto**: 8081 (Web/APT), 8082 (Docker Group), 8083 (Docker Hosted).

## 3. Uso y Configuración
- **Servicio**:
  \`\`\`bash
  sudo systemctl status nexus
  curl -I http://10.100.29.20:8081
  \`\`\`

## 4. Alternativas
- JFrog Artifactory, Harbor (solo contenedores).

## 5. Roles
- **Admin**: Gestión de cuotas y repositorios.
- **DevOps**: Lectura y publicación de imágenes.

## 6. Problemas y Soluciones
- *Error*: Nexus no arranca por falta de memoria.
- *Solución*: Ajustar `-Xms4096m -Xmx4096m` en `nexus.vmoptions`.

## 7. Referencias
- [Sonatype Nexus Official Docs](https://help.sonatype.com/repomanager3)
```

---

### Documento 8: `docs/tools/08-prometheus.md`
```markdown
# Prometheus

## 1. Descripción y Utilidad
- **¿Qué es?**: Sistema de monitoreo y base de datos de series temporales basada en métricas pull.
- **¿Para qué sirve en este laboratorio?**: Recolecta el uso de CPU, RAM, disco y red de todos los 8 nodos físicos.
- **Analogía**: El monitor cardíaco del centro de datos.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y prometheus
  \`\`\`
- **Puerto**: 9090.

## 3. Uso y Configuración
- **Archivo principal**: `/etc/prometheus/prometheus.yml`

## 4. Alternativas
- InfluxDB, VictoriaMetrics, Zabbix.

## 5. Roles
- **Admin**: Define scraping targets y alertas.

## 6. Problemas y Soluciones
- *Error*: Targets en estado `DOWN`.
- *Solución*: Revisar conectividad hacia el puerto 9100 del nodo destino.

## 7. Referencias
- [Prometheus Documentation](https://prometheus.io/docs/)
```

---

### Documento 9: `docs/tools/09-node-exporter.md`
```markdown
# Prometheus Node Exporter

## 1. Descripción y Utilidad
- **¿Qué es?**: Agente ligero para sistemas Unix que expone métricas de hardware y del kernel.
- **¿Para qué sirve en este laboratorio?**: Se instala en cada mini PC para exportar telemetría en el puerto 9100.
- **Analogía**: Los sensores de telemetría de un auto de carreras.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y prometheus-node-exporter
  \`\`\`

## 3. Uso y Configuración
- **Puerto**: 9100 (`/metrics`)
- **Validación**:
  \`\`\`bash
  curl -s http://localhost:9100/metrics | head -n 10
  \`\`\`

## 4. Alternativas
- Telegraf: Más pesado pero soporta múltiples backends.

## 5. Roles
- **Servicio Daemon**: Corre bajo usuario sin privilegios `node-exp`.

## 6. Problemas y Soluciones
- *Error*: Conexión rechazada en puerto 9100.
- *Solución*: `sudo systemctl restart prometheus-node-exporter`.

## 7. Referencias
- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
```

---

### Documento 10: `docs/tools/10-grafana.md`
```markdown
# Grafana

## 1. Descripción y Utilidad
- **¿Qué es?**: Plataforma de analítica y visualización interactiva de métricas.
- **¿Para qué sirve en este laboratorio?**: Muestra tableros gráficos de temperatura, RAM, disco y red de los 8 servidores.
- **Analogía**: El tablero de control de la cabina de un avión.

## 2. Instalación y Requisitos
- **Instalación**:
  \`\`\`bash
  sudo apt-get install -y grafana
  sudo systemctl enable --now grafana-server
  \`\`\`
- **Puerto**: 3000.

## 3. Uso y Configuración
- **Dashboard recomendado**: Node Exporter Full (ID: 1860).

## 4. Alternativas
- Kibana (orientado a logs), Netdata.

## 5. Roles
- **Admin**: Conexión de datasources.
- **Viewer**: Visualización de tableros sin permisos de edición.

## 6. Problemas y Soluciones
- *Error*: `Datasource connection failed`.
- *Solución*: Verificar la URL de Prometheus (`http://10.100.29.30:9090`).

## 7. Referencias
- [Grafana Documentation](https://grafana.com/docs/)
```

---

## 8. Plan de Acción y Hoja de Ruta

```text
[HOY]               ---> [ESTA SEMANA]           ---> [A FUTURO]
1. Enlace físico N306     1. Despliegue masivo         1. Pipeline Packer
2. Boot desatendido 321      resto de miniPCs             + Nexus APT
3. Verificación SSH       2. Ironic Conductor          2. OpenStack HA
   y tabla ARP limpia        Standby + Glance             3. Telemetría Prometheus
```

1. **Hoy**:
   - Verificar enlace del cable físico del Nodo 306 (`carrier = 1`).
   - Encender el Nodo 321 por PXE IPv4 y validar la instalación 100% desatendida de Debian 13.
   - Confirmar acceso SSH en `10.100.29.111` con clave `321`.
2. **Esta Semana**:
   - Encender en cascada los nodos restantes (269, 280, 320, 279) para completar la flota de 8 nodos.
   - Sincronizar el repositorio Nexus APT (`10.100.29.20:8081`) como mirror oficial para que los nodos instalen paquetes a velocidad de red local.
   - Instalar Node Exporter en los 8 nodos y verificar el scraping desde Prometheus en el Nodo 306.
3. **A Futuro**:
   - Implementar pipeline con Packer para compilar imágenes QCOW2 doradas con cloud-init.
   - Desplegar OpenStack Ironic Standalone para aprovisionar servidores físicos mediante reescritura de imagen directa en lugar de instalador.
   - Aislar físicamente el clúster en una VLAN dedicada de Capa 2 en el switch de la oficina.

---

## 9. Conclusión Simple

El arranque por red desatendido permite aprovisionar hardware físico a escala sin tocar ninguna máquina con monitor ni teclado. La red `10.100.29.0/24` y el blindaje de dnsmasq aíslan completamente el clúster de las computadoras de la oficina. OpenStack Glance e Ironic representan el siguiente nivel de madurez: sustituir instaladores por imágenes doradas compiladas con Packer. Todo el ciclo de vida se supervisa en tiempo real con Nexus, Prometheus y Grafana.

---

## 10. Preguntas de Confirmación

Para afinar la siguiente etapa técnica, por favor responde a estas 3 preguntas:
1. **¿Prefieres que las miniPCs queden configuradas con Debian 13 como base para Kubernetes (RKE2), o planeas desplegar Ubuntu Server en algunos nodos?**
2. **¿Tienes acceso al BIOS de las miniPCs para fijar `UEFI PXE IPv4` como primera opción permanente de arranque (evitando tener que pulsar F12 cada vez)?**
3. **¿Deseas que activemos el proxy de Nexus (`10.100.29.20:8081`) en el archivo `preseed.cfg` para que la instalación descargue paquetes directamente desde la memoria caché local?**

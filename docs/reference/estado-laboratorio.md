# Estado observado del laboratorio

Servicios y topología comprobados el 16 de noviembre de 2026, hora de Bolivia.
Las copias de respaldo conservan la fecha de su propia verificación.
Antes de operar, contrasta estos datos con el inventario y el entorno efectivo.

## RKE2 y discrepancia con el inventario

La API de Kubernetes informó siete nodos `Ready`, con RKE2 v1.36.5+rke2r1:

| Nodo físico | IP | Nombre en Kubernetes | Rol observado |
|---|---|---|---|
| 306 | 10.100.29.30 | cp-01 | control-plane, etcd |
| 280 | 10.100.29.102 | worker-01 | worker |
| 320 | 10.100.29.103 | worker-02 | worker |
| 321 | 10.100.29.111 | worker-03 | worker |
| 279 | 10.100.29.112 | worker-04 | worker |
| 269 | 10.100.29.101 | worker-05 | worker |
| 315 | 10.100.29.20 | worker-06 | worker y Nexus |

El inventario de laboratorio todavía define los nodos 269, 280 y 320 como
control planes y usa otra versión de RKE2. No ejecutar los playbooks de
despliegue ni recuperación de RKE2 sobre esa infraestructura sin reconciliar
primero el inventario y los procedimientos. El playbook de plataforma detecta
algunas inversiones de roles, pero no protege fases anteriores del despliegue.

Cilium está activo con `kube-proxy-replacement=false` y kube-proxy sigue
ejecutándose en los siete nodos. La API de Kubernetes responde en
`10.100.29.30:6443`. El destino `10.100.29.101:6443` que usa `make tunnels`
corresponde a un worker y rechaza la conexión.

## OpenStack y arranque

En el nodo 306, la API y el conductor de Ironic están detenidos y
deshabilitados en systemd. Ironic standalone también está deshabilitado.
Glance está detenido y su unidad sigue habilitada para el próximo arranque.
Keystone y MariaDB están activos. Horizon está detenido.

Nginx sirve `boot.ipxe`, la imagen Debian QCOW2 y los metadatos NoCloud en
`8089`. El script inicia IPA y lo dirige a Ironic en `6385`. La publicación
de archivos sigue funcionando. La instalación por ese flujo requiere
reactivar Ironic y comprobar el primer arranque. El `user-data` también
respondió por HTTP sin autenticación desde la red Wi-Fi de administración.

El playbook de respaldo requiere `/etc/kolla/passwords.yml`, que sigue
ausente en el nodo 306.

## Respaldos de OpenStack

El 16 de noviembre se creó una copia en frío de `/etc/kolla` y los volúmenes
MariaDB, RabbitMQ, Glance e Ironic en
`/var/backups/kolla-recovery-20261116.3Qpswv` del nodo 306. Se comprobó la
lectura de los archivos y se generaron checksums. Quedan pendientes la copia
a almacenamiento independiente y una restauración de prueba.

El 30 de octubre se copió `/etc/kolla` y el volumen local de Glance a
`backups/openstack/nodo-306/20261030_102000/kolla-glance.tar.gz` con permisos
privados. Se verificaron su checksum y lectura. Los servicios estaban activos
durante la copia, por lo que no se garantiza una imagen coherente de Glance si
hubo escrituras concurrentes. El archivo contiene configuración sensible y no
está cifrado. No incluye un volcado de MariaDB ni se ha probado su restauración.
La cuenta disponible en el contenedor solo tenía permisos de monitoreo; el
archivo local de contraseñas está cifrado y la clave Vault disponible no lo
descifró. Identificar una credencial administrativa válida antes de continuar.

## Imagen y respaldos del 30 de octubre

En el nodo 306 se observaron una plantilla Packer en `/opt/infra/packer/`, un
preseed en `/httpboot/debian/` y una imagen QCOW2 en `/httpboot/images/`. El
checksum de la imagen coincidió con el archivo de checksum presente. La
plantilla y el preseed no se probaron en una construcción completa.

Se creó un snapshot de etcd y se copió al equipo de administración, junto con
el token de restauración, en `backups/etcd/nodo-306/20261030_095015/`. Los
hashes de transferencia coincidieron y los permisos locales se restringieron.
La copia contiene información sensible, no está cifrada y no se ha probado su
restauración. No constituye un respaldo integral de OpenStack, Nexus o los PVC.

En el nodo 315, la base PostgreSQL `nexus` no tenía tablas de aplicación ni
conexiones activas durante la inspección. Se exportó una copia privada a
`backups/nexus/nodo-315/20261030_095918/` y se comprobó su formato y checksum,
pero esta copia no protege los datos activos de Nexus. Se encontró un archivo
de base H2 en `/opt/sonatype/sonatype-work/nexus3/db/nexus.mv.db` y unos 3,3 GiB
de blobs en el mismo directorio de datos. Tras detener Nexus con autorización,
se copió el directorio de datos completo en `nexus-data.tar.gz`, en ese mismo
directorio privado de respaldos. Se comprobó el checksum, la lectura del archivo
y la presencia de la base H2, los blobs y el ID del nodo. Nexus se reinició y
su API volvió a responder HTTP 200. No se ha probado una restauración; el
directorio de instalación de Nexus no se incluyó en esta copia. No sustituir
este respaldo de datos por el volcado PostgreSQL casi vacío.

## Respaldo de VictoriaMetrics

El 30 de octubre se usó `vmbackup` v1.101.0, verificando el checksum
publicado, para crear un respaldo sin detener VictoriaMetrics. La copia
quedó en el nodo 269 bajo
`/tmp/infra-vmbackup-20261030_103154/data`, protegida con permisos 0700. Su
tamaño es aproximadamente 1,5 GiB. Una restauración con `vmrestore` terminó en
un directorio aislado y se comprobaron los directorios de datos e índices; la
prueba temporal se eliminó. No se arrancó VictoriaMetrics con la copia.

La copia se dejó en `/tmp` del equipo que alojaba los datos y su presencia
actual queda sin comprobar. Falta una copia en almacenamiento independiente
y una prueba de consultas en la instancia restaurada.

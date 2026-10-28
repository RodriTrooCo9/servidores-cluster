# Correcciones aplicadas y validación pendiente — 2026-10-27

Este documento complementa la [auditoría original](auditoria-proyecto-2026-10-27.md).
Registra cambios reales en el repositorio, siguiendo el orden solicitado:
simulación y respaldos; credenciales y permisos; composición Kubernetes y rutas;
convergencia y pruebas. No constituye un acta de despliegue en los servidores.

## 1. Simulación y recuperación/backups

### Aplicado

- El orquestador de laptop valida todos los argumentos antes de ejecutar acciones. `--fase 8 --dry-run` y `--dry-run --fase 8` transmiten `--check --diff` a Ansible.
- `--all --dry-run` evita la confirmación interactiva y conserva las opciones de simulación. Ansible check mode puede realizar lecturas remotas; no equivale a una prueba completamente desconectada.
- Los argumentos inválidos o incompletos se rechazan antes de iniciar fases. Se eliminó la opción `--legacy`, que no implementaba ninguna ejecución alternativa.
- Recuperación acepta una sola acción por invocación y valida `--new-mac` antes de comenzar. La nueva MAC se interpreta con independencia de su posición.
- Los backups del script DR delegan en el mismo playbook que usa `make backup`. Se eliminó el flujo duplicado que apuntaba al controlador `.30` para respaldar etcd.
- El snapshot se genera en el control plane marcado como líder en el inventario. Se exige encontrar un archivo no vacío y se copia al equipo ejecutor con comprobación de checksum, junto con el token RKE2 necesario para restaurarlo.
- El respaldo MariaDB usa Bash remoto con `set -euo pipefail`, archivo temporal privado, validación gzip y comprobación de contenido descomprimido no vacío. Solo publica el archivo definitivo si todo termina bien.
- La contraseña de MariaDB se lee del YAML remoto sin imprimirla y se transmite al proceso mediante entorno, sin incluirla en el argumento `-p` del cliente.
- Los respaldos de MariaDB y configuración Kolla se descargan al equipo ejecutor. Un error del playbook impide anunciar respaldo exitoso.

### Archivos principales

- `scripts/client/ejecutar-desde-laptop.sh`
- `scripts/ops/disaster-recovery.sh`
- `ansible/playbooks/90-operations/01_disaster_recovery.yml`

### Pendiente

La integridad gzip y el checksum de transferencia no prueban restaurabilidad.
Falta restaurar un snapshot y un dump en laboratorio, comprobar el token asociado,
definir retención y copiar respaldos fuera del equipo ejecutor. Los datos quedan
bajo `backups/etcd/<host>/` y `backups/openstack/<host>/`, protegidos por directorios
locales privados. Los respaldos contienen secretos y requieren custodia.

La reprovisión Nova/Ironic conserva problemas de selección del nodo y acceso al
user-data dentro de `kolla_toolbox`. El parseo está corregido, pero **la reprovisión
automática no está validada para uso real**. No se ejecutó sobre ningún equipo.

## 2. Credenciales y permisos

### Aplicado

- Las variables de laboratorio PostgreSQL y RKE2 referencian `vault_postgres_password` y `vault_rke2_token`, en lugar de valores fijos en texto plano.
- Los roles Nexus y RKE2 validan que reciban sus credenciales antes de instalar o configurar componentes.
- Se actualizó la plantilla Vault con la variable PostgreSQL y la ruta correcta del inventario lab.
- DR dejó de incorporar una contraseña administrativa OpenStack fija. Las acciones que consultan OpenStack requieren `OS_PASSWORD`, cargable desde el OpenRC del operador. Los backups no necesitan esa variable.
- Las plantillas de control planes generan el kubeconfig original con `0600`.
- El archivo JVM de Nexus, que contiene la contraseña JDBC, se escribe con `0600` y su tarea oculta datos sensibles en la salida de Ansible.
- Bootstrap coloca la llave en `ansible/keys/cluster_key` y usa `.vault_pass` en la raíz. Los orquestadores afectados fijan `ANSIBLE_CONFIG` y ejecutan Ansible desde la raíz cuando corresponde.

### Migración necesaria antes de desplegar

Crear o editar el Vault real con los valores vigentes:

```bash
ansible-vault edit inventory/lab/group_vars/all/vault.yml
```

Si el archivo todavía no existe, usar `ansible-vault create` con esa misma ruta.
Conservar el token actual RKE2 y la contraseña actual PostgreSQL al migrarlos:
este cambio no implementa una rotación de credenciales existentes. No copiar
los placeholders del ejemplo a una instalación en servicio. La contraseña de
Vault debe estar disponible localmente según `ansible.cfg`.

No se rotaron claves, no se verificó autenticación real y no se modificaron
credenciales remotas. Retirar valores del código tampoco los elimina del
historial Git; la rotación debe hacerse mediante un procedimiento operativo.

## 3. Composición Kubernetes y rutas

### Aplicado

- La base compone directorios con sus propios `kustomization.yaml`; ya no carga archivos externos a su raíz mediante referencias directas prohibidas.
- Ambos overlays usan `resources` y `labels` en lugar de los campos obsoletos `bases` y `commonLabels`.
- Se añadió un backend HTTP mínimo con Deployment y Service `backend-api:8000`, utilizado por Nginx y el simulador. Expone `/health` y `/api/v1/data`; es una aplicación de demostración, sin persistencia de negocio.
- El collector OTel en modo DaemonSet monta `/var/log/pods` del host en modo de solo lectura para que `filelog` pueda acceder a los archivos configurados.
- Se añadió `scripts/diagnostics/kubernetes-prerequisites.sh`: comprueba CRDs establecidas, StorageClass `local-path` y al menos un Deployment disponible del operador OpenTelemetry. Solo realiza lecturas en el contexto Kubernetes actual.
- El arranque global apunta a `50-validation/01_healthcheck.yml`.
- La fase 7 y `--health` usan las rutas existentes bajo `scripts/ops/` y `scripts/diagnostics/`. La fase 7 sigue destinada a ejecutarse en el controlador PXE; no se añadió transporte remoto desde la laptop.
- El generador ConfigDrive falla si faltan `mkisofs`/`genisoimage` o si no aparece una ISO no vacía.
- `make deploy` serializa sus dependencias incluso cuando Make recibe `-j`.

### Comprobaciones reproducibles

```bash
kubectl kustomize kubernetes/overlays/lab
kubectl kustomize kubernetes/overlays/prod
```

Para comprobar prerrequisitos externos, tras seleccionar explícitamente el
contexto del laboratorio:

```bash
kubectl config current-context
bash scripts/diagnostics/kubernetes-prerequisites.sh
```

Este último script se preparó pero no se ejecutó contra el clúster durante estos
cambios. No instala el operador, CRDs ni el provisionador de almacenamiento.
La existencia de una StorageClass no prueba que pueda aprovisionar volúmenes;
falta verificar un PVC real y los webhooks del operador.

El inventario prod permanece como plantilla. Renderizar su overlay no certifica
que los hosts tengan variables, credenciales ni direccionamiento adecuados.
No se inventaron valores de producción.

## 4. Convergencia de servicios y firewall

### Aplicado

- RKE2 notifica reinicio cuando cambian su configuración principal o los mirrors de registros.
- El playbook de plataforma procesa primero control planes y después workers, de uno en uno, deteniéndose ante errores. El play de reincorporación también usa lotes unitarios.
- Antes de avanzar, el rol espera el puerto API del control plane actual. Esto comprueba disponibilidad TCP, no salud completa de etcd ni estado `Ready` de todos los nodos.
- El rol monitoring ya no ignora errores de instalación o arranque. Un repositorio Grafana faltante provocará un error explícito; su configuración APT sigue pendiente.
- El healthcheck Ansible ya no ignora errores de puertos requeridos. Puede devolver error cuando un servicio no esté disponible.
- El script de firewall usa una tabla propia, valida sintaxis antes de aplicarla, restringe explícitamente los puertos de observabilidad a la subred interna y evita ejecuciones simultáneas mediante `flock`.
- El firewall requiere confirmación en 60 segundos. Ante cancelación, EOF, señal manejada o falta de confirmación, restaura únicamente su tabla anterior; no vacía reglas de otros servicios. Conserva un respaldo privado para diagnóstico y no modifica persistencia.

### Límites

No se ejecutaron reinicios, instalaciones, contenedores ni cambios de firewall.
El rollback del firewall necesita una prueba real en laboratorio; el manejador
no puede recuperarse de `SIGKILL`, apagado ni caída completa del proceso anfitrión.
El healthcheck Bash conserva comprobaciones menos estrictas que el playbook
Ansible y necesita revisión adicional antes de usarse como criterio de aceptación.

Packer sigue pendiente: falta proporcionar y servir un preseed válido, verificar
la imagen de entrada y completar una compilación. Tampoco se corrigieron todos
los overrides antiguos `kolla/` de la configuración OpenStack.

## 5. Evidencia local

| Validación | Resultado | Alcance |
|---|---|---|
| `python3 -m unittest discover -s tests -v` | 11 pruebas correctas | Orden de argumentos, simulación, errores previos a ejecución, propagación de errores de backup y pipeline real con Docker simulado |
| Sintaxis Ansible de `ansible/site.yml` | Correcta | Parseo local, sin ejecutar roles |
| `make lint` con temporales Ansible en `/tmp` | Correcto, con advertencias YAML preexistentes | Ansible-lint y ShellCheck configurados por el proyecto |
| Kustomize lab y prod | Ambos renderizan correctamente | Composición local, sin aplicar recursos |
| ShellCheck del nuevo diagnóstico y firewall | Correcto con exclusiones del proyecto | Análisis estático, sin ejecución del firewall |
| `git diff --check` | Correcto | Espacios y conflictos de formato del diff |

Las pruebas de backup simulan tres casos: fallo con SQL parcial, éxito con salida
vacía y dump válido. Los dos primeros no publican un respaldo definitivo.
Se añadió un job de regresión CLI/pipeline a la etapa `dry-run` de GitLab CI.

## 6. Trabajo que requiere laboratorio

| Orden | Comprobación | Criterio de aceptación |
|---|---|---|
| 1 | Migración de secretos y preflight | Vault carga sin mostrar valores; SSH y sudo funcionan con las identidades esperadas |
| 2 | Backups reales y restauración aislada | Snapshot, token, dump y configuración se recuperan fuera del nodo origen y restauran correctamente |
| 3 | Estado de red y quórum | Endpoints esperados accesibles, miembros etcd coherentes y nodos Kubernetes `Ready` |
| 4 | Prerrequisitos Kubernetes | CRDs/webhooks operativos, operador disponible y PVC de prueba aprovisionado |
| 5 | Instalación y segunda ejecución | Servicios sanos y convergencia sin reinicios innecesarios; sin pérdida de quórum |
| 6 | Observabilidad | Logs, métricas y trazas consultables; retención y consumo de disco dentro de límites |
| 7 | Firewall | Acceso interno permitido, acceso externo a puertos protegidos rechazado y rollback comprobado |
| 8 | Packer e imágenes remotas | Preseed servido, imagen verificada y compilación completa con Cloud-Init funcional |
| 9 | Producción | Variables propias completas y validación independiente; no usar placeholders del inventario |

El repositorio tiene correcciones verificadas localmente, pero la validación
integral del laboratorio y la remediación completa de la auditoría continúan
pendientes en los puntos indicados. Ningún resultado local acredita el estado
actual de los servidores.

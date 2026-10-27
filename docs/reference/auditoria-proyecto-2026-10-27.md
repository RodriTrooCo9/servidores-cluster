# Auditoría del proyecto — 2026-10-27

Revisión estática de automatización Bash/Python, roles y playbooks Ansible,
inventarios, plantillas, manifiestos Kubernetes, configuración OpenStack/Nexus,
CI y referencias documentales. No se ejecutaron despliegues, SSH ni operaciones
sobre la infraestructura. Los cambios de documentación que ya estaban en el
árbol de trabajo se conservaron.

P1: corregir antes de usar el flujo afectado. P2: corregir para asegurar
operación y resultados confiables. Los hallazgos derivados del código no
equivalen a una comprobación del estado actual de los servidores.

## Hallazgos

| # | Prioridad | Ubicación | Problema e impacto | Corrección recomendada |
|---|---|---|---|---|
| 1 | P1 | `scripts/client/ejecutar-desde-laptop.sh:143–168` | Las acciones se ejecutan durante el parseo. `--fase 8 --dry-run` y el ejemplo documentado `--all --dry-run` llegan a Ansible sin `--check --diff`. Reproducido con un ejecutable Ansible simulado. | Parsear y validar todos los argumentos antes de ejecutar acciones; representar argumentos como array. |
| 2 | P1 | `scripts/ops/disaster-recovery.sh:178–195` | El backup de etcd usa el controlador `.30`, mientras el inventario define el líder en `.101`. Además ignora errores del snapshot y de SCP y anuncia éxito. El fallback RKE2 guarda en otra ruta que tampoco se copia. | Resolver el líder desde inventario, comprobar el snapshot generado y exigir una copia local válida antes de informar éxito. |
| 3 | P1 | `ansible/playbooks/90-operations/01_disaster_recovery.yml:115–118`; `scripts/ops/disaster-recovery.sh:160–162` | Los pipelines remotos `mysqldump | gzip` no habilitan `pipefail`: si falla el dump y gzip termina bien, se conserva un archivo vacío como respaldo exitoso. El `pipefail` del script local no se transmite por SSH. | Usar Bash remoto con `pipefail`, salida temporal y verificación del respaldo. |
| 4 | P1 | `kubernetes/base/kustomization.yaml:6` | Los recursos apuntan a archivos fuera de la raíz de la base. `kubectl kustomize kubernetes/overlays/lab` falla por restricciones de carga. | Crear kustomizations en los directorios de recursos y componerlos, o reorganizar la base para contener los archivos. |
| 5 | P1 | `kubernetes/apps/microservices/microservices_stack.yaml:352`; `kubernetes/base/kustomization.yaml` | Nginx referencia `backend-api:8000`, pero esa Service y su Deployment están en `apps/demo/demo_apps.yaml`, ausente de la base. Un despliegue limpio de la composición deja esa dependencia sin crear y puede impedir iniciar Nginx al resolver el upstream. | Incluir el backend en la composición o eliminar la dependencia. |
| 6 | P1 | `ansible/roles/rke2_ha/templates/rke2-leader-config.yaml.j2:1`; `rke2-cp-config.yaml.j2:3` | Se solicita kubeconfig con permisos `0644`: el archivo original con credenciales administrativas queda legible para otros usuarios locales aunque las copias tengan `0600`. | Generar el kubeconfig original con `0600`. |
| 7 | P1 | `inventory/lab/group_vars/all/vars.yml`; `scripts/ops/disaster-recovery.sh:41` | Hay contraseña PostgreSQL, token RKE2 y contraseña OpenStack incorporados al código en texto plano. El script usa un valor fijo en vez de cargar las credenciales configuradas. | Externalizar a Vault/variables protegidas y rotar los valores si se usan realmente. |
| 8 | P1 | `scripts/client/ejecutar-desde-laptop.sh:67,74`; `scripts/bootstrap/setup_keys.sh:38` | Los scripts cambian a subdirectorios antes de llamar Ansible. El `ansible.cfg` está en la raíz y no se fija `ANSIBLE_CONFIG`; ejecutados así, no heredan de forma fiable configuración de roles, Vault, inventario y SSH. | Ejecutar desde la raíz o fijar explícitamente configuración y rutas absolutas. |
| 9 | P1 | `scripts/ops/disaster-recovery.sh:351–357` | La reprovisión obtiene un UUID de Ironic pero crea una instancia Nova con flavor genérico, sin vincularla al nodo recuperado. Además `--user-data /tmp/...` se ejecuta dentro de `kolla_toolbox`, aunque el archivo se copia al host y no se asegura su presencia dentro del contenedor. | Vincular explícitamente el despliegue al nodo y transportar el user-data al espacio de archivos del cliente que lo lee. |
| 10 | P2 | `scripts/ops/levantar-todo.sh:71` | La fase final apunta a `50-verification/01_healthcheck.yml`, inexistente; el directorio real es `50-validation`. | Corregir la ruta y comprobar las rutas usadas por los orquestadores. |
| 11 | P2 | `scripts/client/ejecutar-desde-laptop.sh:111–113,151–155` | Fase 7 busca un script inexistente y se omite silenciosamente; `--health` termina invocando otro archivo inexistente bajo `scripts/client`. | Usar `scripts/ops/07-cloud-init.sh` y `scripts/diagnostics/healthcheck.sh`; explicitar dónde debe ejecutarse la fase 7. |
| 12 | P2 | `scripts/bootstrap/setup_keys.sh:8–9` | Crea la llave bajo `scripts/bootstrap/keys` y Vault bajo `scripts/bootstrap/.vault_pass`; los consumidores esperan `ansible/keys/cluster_key` y `.vault_pass` en la raíz. | Centralizar rutas desde la raíz y reutilizarlas. |
| 13 | P2 | `scripts/ops/disaster-recovery.sh:421–427` | El ejemplo `--reprovision nodo --new-mac MAC` inicia la recuperación antes de leer la nueva MAC. | Parsear todas las opciones antes de reprovisionar. |
| 14 | P2 | `scripts/ops/disaster-recovery.sh:154–155,173`; `openstack/globals.yml:30` | Persisten rutas al antiguo directorio `kolla/`, ausente en el árbol revisado. El backup falla en el `cp` final; `node_custom_config` apunta a overrides que no están en esa ubicación. | Actualizar a la estructura `openstack/` y resolver rutas portables. |
| 15 | P2 | `cloud-init/packer/packer.pkr.hcl:39`; `scripts/ops/07-cloud-init.sh` | Las plantillas piden `preseed.cfg` mediante `.HTTPIP/.HTTPPort`, pero no configuran `http_directory`/`http_content` ni incluyen ese preseed. La instalación desatendida no tiene los datos que necesita. | Proporcionar y servir un preseed coherente con usuario y autenticación SSH. |
| 16 | P2 | `network/firewall/apply-nftables-observability.sh:21–46` | La cadena tiene `policy accept` y no rechaza fuentes externas: no restringe los puertos como promete. Nunca existe una fase de confirmación que borre el marcador. Restaurar con `nft -f` un respaldo sin `flush ruleset` tampoco garantiza retirar la tabla añadida. | Implementar restricción explícita y rollback que sustituya el estado, con confirmación y marcador exclusivo por ejecución. |
| 17 | P2 | `ansible/roles/rke2_ha/tasks/main.yml:16–65,77–104` | Las plantillas de configuración no notifican reinicios; `state: started` deja intactos los servicios ya activos. Un cambio de token, endpoint o mirror puede quedar escrito sin aplicarse. | Añadir handlers y un orden de reinicio seguro para el quórum. |
| 18 | P2 | `ansible/roles/monitoring/tasks/main.yml:29–64` | Instalación y arranque centrales ignoran errores. El rol tampoco configura el repositorio de Grafana. Puede terminar exitosamente sin desplegar los servicios pedidos. | Preparar los repositorios necesarios y hacer fallar la ejecución si faltan componentes requeridos. |
| 19 | P2 | `kubernetes/observability/otel/02_otel_operator_and_collectors.yaml:111–115` | El collector agente configura `filelog` para `/var/log/pods`, pero no declara volúmenes hostPath ni mounts para ese directorio. Ese agente no puede leer los logs del host. Existe otro DaemonSet que sí monta `/var/log`; conviene aclarar qué agente debe usarse. | Montar los logs en el collector que los consume o consolidar ambos agentes. |
| 20 | P2 | `ansible/playbooks/50-validation/01_healthcheck.yml`; `scripts/diagnostics/healthcheck.sh` | Los fallos de salud se muestran pero no se acumulan en un resultado fallido. El script considera activa Ironic ante cualquier cuerpo HTTP, incluso una respuesta de error, y usa el bastión como fallback Kubernetes aunque los control planes están en otro grupo. | Comprobar códigos HTTP y estado esperado, consultar el líder real y devolver error si falla un servicio requerido. |
| 21 | P2 | `cloud-init/scripts/generate_configdrive.sh:164–170` | Si no existe `mkisofs` ni `genisoimage`, no genera ISO pero informa éxito y devuelve cero. | Exigir una herramienta disponible y verificar que el archivo final exista y no esté vacío. |

## Validaciones ejecutadas

- `make syntax-check`: correcto; solo comprueba sintaxis, no ejecuta tareas.
- `make lint`: correcto con advertencias de formato YAML; Ansible-lint procesó 26 archivos.
- `bash -n`: correcto para 28 archivos `.sh` fuera de directorios ocultos.
- AST de Python: correcto para el bootstrap y los tres programas embebidos en manifiestos.
- Parser YAML: 46 archivos válidos en los directorios revisados, excluyendo secretos y plantillas Jinja.
- Parser JSON: seis archivos válidos.
- ShellCheck directo sobre los scripts principales y auxiliares: devuelve advertencias; el Makefile excluye varias categorías que CI no excluye. Conviene unificar criterios.
- Kustomize del overlay lab: falla de forma reproducible por referencias externas a la base.
- Reproducción del parseo de `--dry-run`: se sustituyó `ansible-playbook` por un stub temporal; confirmó que la fase se invoca sin las opciones de simulación.

## Límites y comprobaciones pendientes

No se comprobó el estado de servicios, quórum, red, imágenes remotas ni credenciales.
No se levantaron contenedores ni se aplicaron reglas de firewall. No se ejecutó
Packer. La composición Kubernetes requiere además verificar prerrequisitos
externos: CRDs/controlador OpenTelemetry y StorageClass `local-path`, referenciados
pero no instalados por esa composición. El inventario prod es una plantilla y
necesita sus propias variables antes de utilizar los roles.

Orden recomendado: resolver primero simulación y recuperación/backups; después
credenciales y permisos; luego composición Kubernetes y rutas de orquestación;
finalmente convergencia de servicios y pruebas de integración en laboratorio.

# Obtener y documentar logs y trazas de Kubernetes

Actualización: 9 de noviembre de 2026. Entorno objetivo: laboratorio RKE2 de este repositorio.

Este manual permite recopilar evidencia por clúster, namespace, pod y aplicación. Describe procedimientos; no registra una ejecución contra el laboratorio. El diagnóstico de conexiones internas de RKE2 queda pendiente por decisión del usuario.

## 1. Qué vas a obtener

| Evidencia | Qué permite investigar | Dónde se obtiene |
|---|---|---|
| Logs de contenedores | Mensajes, errores y stack traces de la aplicación | `kubectl logs`; Loki si fueron recolectados |
| Eventos y estado | Reinicios, fallos de arranque, scheduling y volúmenes | API de Kubernetes |
| Logs del nodo | Servicio RKE2 y componentes del host | `journalctl` en ese nodo |
| Trazas distribuidas | Operaciones de una petición, duración, dependencias y errores | Tempo o el destino de trazas configurado |

Los logs y las trazas son señales diferentes. `kubectl logs` consulta la salida del contenedor; no descarga las trazas distribuidas. Estas necesitan instrumentación y un sistema que las reciba y conserve. Los eventos de Kubernetes aportan contexto y tampoco son trazas.

Flujo de referencia del proyecto:

```text
Aplicación → stdout/stderr → agente de logs → Loki → consulta/exportación
Aplicación instrumentada → spans OTLP → OTel Collector → Tempo → consulta/exportación
```

Revisión del repositorio: el [gateway OTel](../../kubernetes/observability/otel/02_otel_operator_and_collectors.yaml) recibe OTLP y configura destinos para logs y trazas. Ese archivo no contiene `filelog` ni `k8sattributes`: por sí solo no lee todos los archivos de logs de los pods ni añade todos sus metadatos. Debe comprobarse si otro agente o configuración desplegada realiza esas funciones. Véase la [guía de componentes Kubernetes de OTel](https://opentelemetry.io/docs/platforms/kubernetes/collector/components/).

## 2. Preparar el acceso y una carpeta de evidencia

Ejecuta los comandos desde la laptop con `kubectl` configurado o desde el control plane. En el control plane RKE2 puedes usar `sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml` en lugar de `kubectl`. La [guía de instalación](../../GUIA_DE_INSTALACION.md) explica el acceso desde la laptop.

Comprueba primero el contexto y la aplicación. Un contexto de kubectl no necesariamente coincide con el atributo `k8s.cluster.name` de las trazas.

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get namespaces
kubectl get pods -n aplicaciones --show-labels
kubectl auth can-i get pods --subresource=log -n aplicaciones
```

Elige namespace, selector y ventana. Estos nombres corresponden al ejemplo del repositorio; ajústalos al despliegue real. Mantén esta terminal para los siguientes pasos.

```bash
NS=aplicaciones
SELECTOR='app=backend-api'
SERVICE_NAME=backend-api
START_UTC=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
OUT_DIR="$HOME/evidencias-k8s/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT_DIR"
kubectl config current-context > "$OUT_DIR/contexto.txt"
kubectl get nodes k -o wide > "$OUT_DIR/nodos.txt"
kubectl get pods -n "$NS" -o wide > "$OUT_DIR/pods.txt"
```

`date -d` corresponde a GNU/Linux. Usa UTC en los archivos y anota también la hora local cuando sea útil; Bolivia usa UTC−04:00. La salida de contexto identifica el destino sin exportar el kubeconfig.

## 3. Leer y guardar logs

### Una aplicación y todas sus réplicas

```bash
kubectl logs -n "$NS" -l "$SELECTOR" \
  --all-containers=true --timestamps=true --prefix=true \
  --since-time="$START_UTC" --tail=-1 \
  > "$OUT_DIR/aplicacion.log" 2> "$OUT_DIR/aplicacion.stderr.txt"
```

El selector incluye los pods de la aplicación; el prefijo identifica pod y contenedor. `--tail=-1` evita el recorte de líneas por defecto asociado al uso de un selector. Conserva stderr: permite distinguir una exportación incompleta de una aplicación sin mensajes. Consulta las opciones en la [referencia de kubectl logs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_logs/).

Para observar mensajes nuevos, termina con Ctrl+C:

```bash
kubectl logs -n "$NS" -l "$SELECTOR" \
  --all-containers=true --timestamps=true --prefix=true \
  --since=5m --tail=200 --follow --max-log-requests=10
```

### Un pod, un contenedor y su ejecución anterior

Primero consulta los nombres reales:

```bash
kubectl get pods -n "$NS" -l "$SELECTOR"
POD=REEMPLAZAR_POR_NOMBRE_DEL_POD
kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.spec.containers[*].name}{"\n"}{.spec.initContainers[*].name}{"\n"}'
CONTAINER=api
kubectl logs -n "$NS" "$POD" -c "$CONTAINER" \
  --timestamps=true --since-time="$START_UTC" \
  > "$OUT_DIR/pod-actual.log" 2> "$OUT_DIR/pod-actual.stderr.txt"
kubectl logs -n "$NS" "$POD" -c "$CONTAINER" --previous \
  --timestamps=true --since-time="$START_UTC" \
  > "$OUT_DIR/pod-anterior.log" 2> "$OUT_DIR/pod-anterior.stderr.txt"
```

`--previous` sirve cuando existe una ejecución anterior del contenedor en ese pod; puede devolver un error si nunca reinició. Un init container puede consultarse con su nombre en `-c`. La [arquitectura de logging de Kubernetes](https://kubernetes.io/docs/concepts/cluster-administration/logging/) explica los límites de conservación: los archivos disponibles pueden rotar y un pod eliminado puede requerir consulta al almacén centralizado.

### Todos los pods de un namespace

Este bloque guarda los logs actuales de cada pod en un archivo independiente. No usa un selector que pueda dejar fuera otras aplicaciones.

```bash
kubectl get pods -n "$NS" -o name > "$OUT_DIR/lista-pods.txt"
while IFS= read -r pod_resource; do
  pod_name="${pod_resource#pod/}"
  kubectl logs -n "$NS" "$pod_resource" \
    --all-containers=true --timestamps=true --prefix=true \
    --since-time="$START_UTC" --tail=-1 \
    > "$OUT_DIR/${NS}-${pod_name}.log" \
    2> "$OUT_DIR/${NS}-${pod_name}.stderr.txt"
done < "$OUT_DIR/lista-pods.txt"
```

Para otros namespaces, cambia `NS` y repite el bloque. Para una revisión de todo el clúster, enuméralos con `kubectl get namespaces` y conserva el namespace en cada nombre de archivo. Para consultas frecuentes de muchos pods conviene el almacén centralizado; una extracción puntual no reemplaza su retención.

### Estado, eventos y logs de hosts

```bash
kubectl get events -n "$NS" --sort-by=.metadata.creationTimestamp \
  > "$OUT_DIR/eventos.txt"
kubectl describe pod -n "$NS" "$POD" > "$OUT_DIR/descripcion-pod.txt"
```

Los eventos que devuelve la API tienen su propia conservación y no se filtran por la ventana anterior. En un control plane, los logs del servicio se consultan así; guarda el archivo en ese host y registra de cuál proviene:

```bash
sudo journalctl -u rke2-server --since '30 minutes ago' \
  --utc --no-pager -o short-iso-precise > rke2-server.log
```

En un worker usa `-u rke2-agent`. Los logs de pods de `kube-system` se obtienen mediante el procedimiento de namespace. La [referencia rápida de kubectl](https://kubernetes.io/docs/reference/kubectl/quick-reference/) reúne las consultas de estado y logs.

## 4. Consultar y exportar logs de Loki

Requisito: que un agente haya enviado los logs a Loki. Ver un mensaje con `kubectl logs` no garantiza que esté allí. En Grafana abre Explore, selecciona Loki y ajusta la ventana temporal. El acceso Grafana documentado en el proyecto es `http://192.168.29.25:3000`; comprueba la URL vigente y la conectividad del datasource.

Descubre las etiquetas reales antes de construir la consulta. Según el agente pueden llamarse `namespace`/`pod` o `k8s_namespace_name`/`k8s_pod_name`. Usa estos ejemplos solo si existen esas etiquetas:

```logql
{namespace="aplicaciones"}
{namespace="aplicaciones", app="backend-api"} |~ "(?i)error|exception|timeout"
```

Para guardar la respuesta por API, abre otra terminal y deja activo este túnel local. Comprueba antes que exista el Service:

```bash
kubectl get svc -n observability loki
kubectl port-forward -n observability svc/loki 13100:3100 --address=127.0.0.1
```

En la terminal de evidencia, fija el final de la ventana. Consulta etiquetas y exporta usando la etiqueta confirmada:

```bash
END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -fsS --get http://127.0.0.1:13100/loki/api/v1/labels \
  --data-urlencode "start=$START_UTC" --data-urlencode "end=$END_UTC" \
  -o "$OUT_DIR/loki-etiquetas.json"
LOGQL='{namespace="aplicaciones"}'
curl -fsS --get http://127.0.0.1:13100/loki/api/v1/query_range \
  --data-urlencode "query=$LOGQL" \
  --data-urlencode "start=$START_UTC" --data-urlencode "end=$END_UTC" \
  --data-urlencode 'direction=forward' --data-urlencode 'limit=1000' \
  -o "$OUT_DIR/loki-logs.json"
```

Es una exportación limitada a 1000 entradas: registra ese límite y subdivide la ventana si se alcanza. Los archivos de `kubectl logs` incluyen lo disponible desde el inicio hasta el momento de cada consulta; la exportación Loki usa inicio y final explícitos. Para instalaciones con autenticación o tenants, utiliza el acceso y los encabezados autorizados de ese despliegue. Referencia: [API HTTP de Loki](https://grafana.com/docs/loki/latest/reference/loki-http-api/).

## 5. Buscar trazas de una aplicación

### Comprobar los requisitos

Una traza reúne spans de operaciones relacionadas mediante un `trace_id`. Hace falta instrumentar las aplicaciones participantes, propagar el contexto y exportar al Collector/Tempo. El Operator administra recursos e instrumentación compatible; instalarlo no crea automáticamente spans para toda aplicación. Referencia: [OpenTelemetry Operator](https://opentelemetry.io/docs/platforms/kubernetes/operator/).

```bash
kubectl get pods,svc -n observability
kubectl get opentelemetrycollectors.opentelemetry.io -A
kubectl get instrumentations.opentelemetry.io -A
kubectl get pods -n opentelemetry-operator-system
kubectl get deploy -n "$NS" backend-api \
  -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

Si una CRD no existe, el comando lo indicará; registra el resultado. Si los recursos están en otro namespace, usa los nombres reales. En el proyecto, el endpoint HTTP OTLP previsto es `http://otel-gateway-collector.observability.svc.cluster.local:4318`; confirma el Service generado. El puerto `4317` corresponde a OTLP/gRPC. La presencia de una anotación no demuestra que haya spans: comprueba el pod y el resultado de la exportación.

El manifiesto configura muestreo en la instrumentación y en el Collector. Una petición puede no conservarse; registra la configuración efectiva antes de concluir que el pipeline falla. Si necesitas observar cada petición, prepara una política de prueba en laboratorio y revierte después el cambio.

### Generar tráfico y buscarlo

Usa una operación conocida de una aplicación instrumentada y anota la hora. Para la aplicación de ejemplo puedes dejar este túnel en otra terminal:

```bash
kubectl port-forward -n aplicaciones svc/backend-api 18000:8000 --address=127.0.0.1
```

Desde la terminal de evidencia:

```bash
date -u +%Y-%m-%dT%H:%M:%SZ > "$OUT_DIR/hora-peticion.txt"
curl -sS -D "$OUT_DIR/peticion.headers.txt" \
  -o "$OUT_DIR/peticion.body.txt" \
  -w 'http_code=%{http_code} total_seconds=%{time_total}\n' \
  http://127.0.0.1:18000/api/v1/data > "$OUT_DIR/peticion.resultado.txt"
```

Este acceso prueba el backend a través de port-forward. Para documentar el recorrido por Ingress, repite usando su URL real y registra cuál utilizaste. El backend revisado devuelve datos estáticos: para observar una consulta DB debe existir una operación que realmente la ejecute y cuya biblioteca esté instrumentada.

En Grafana → Explore → Tempo, selecciona la ventana de la petición. Empieza por el nombre de servicio real; añade atributos Kubernetes solo si los spans los contienen:

```traceql
{ resource.service.name = "backend-api" }
{ resource.service.name = "backend-api" && status = error }
{ resource.service.name = "backend-api" && duration > 500ms }
{ resource.k8s.namespace.name = "aplicaciones" }
```

El filtro `duration` anterior busca spans lentos. Para separar varios clústeres se puede añadir `resource.k8s.cluster.name`, si fue configurado. Abre la traza y registra ID, servicios, spans relevantes, tiempos y errores; distingue el primer fallo observado de una causa confirmada. Referencia: [consultas TraceQL](https://grafana.com/docs/tempo/latest/traceql/construct-traceql-queries/).

### Exportar las trazas desde Tempo

Abre otra terminal con el túnel de consulta. `3200` es la API de Tempo del manifiesto, diferente de los puertos de recepción OTLP:

```bash
kubectl get svc -n observability tempo
kubectl port-forward -n observability svc/tempo 13200:3200 --address=127.0.0.1
```

En la terminal de evidencia, busca IDs en los últimos 30 minutos. Este ejemplo requiere Python 3 para calcular los tiempos Unix en segundos:

```bash
SEARCH_START=$(python3 -c 'import time; print(int(time.time())-1800)')
SEARCH_END=$(python3 -c 'import time; print(int(time.time()))')
TRACEQL='{ resource.service.name = "backend-api" }'
curl -fsS --get http://127.0.0.1:13200/api/search \
  --data-urlencode "q=$TRACEQL" \
  --data-urlencode "start=$SEARCH_START" --data-urlencode "end=$SEARCH_END" \
  --data-urlencode 'limit=20' -o "$OUT_DIR/tempo-busqueda.json"
python3 -m json.tool "$OUT_DIR/tempo-busqueda.json"
```

La búsqueda devuelve resultados limitados, no un respaldo de todas las trazas. Copia un `traceID` real de la búsqueda o de Grafana y descarga sus spans:

```bash
TRACE_ID=REEMPLAZAR_POR_TRACE_ID_REAL
curl -fsS -H 'Accept: application/json' \
  "http://127.0.0.1:13200/api/traces/$TRACE_ID" \
  -o "$OUT_DIR/trace-$TRACE_ID.json"
python3 -m json.tool "$OUT_DIR/trace-$TRACE_ID.json" \
  > "$OUT_DIR/trace-$TRACE_ID.legible.json"
```

El endpoint de detalle exporta una traza por ID. Un resultado vacío o un 404 requiere comprobar ventana, ID, muestreo, retención y recepción. Consulta la [API HTTP de Tempo](https://grafana.com/docs/tempo/latest/api_docs/) y contrasta la versión desplegada: el repositorio declara Tempo 2.5.0 y no se ha validado aquí su ejecución.

## 6. Relacionar una traza con sus logs

La aplicación debe incluir el contexto de traza en los mensajes. Un ejemplo del formato esperado, no un resultado obtenido en este laboratorio:

```json
{"level":"ERROR","service":"backend-api","trace_id":"0123456789abcdef0123456789abcdef","span_id":"0123456789abcdef","message":"Tiempo de espera consultando la base de datos"}
```

Si los logs contienen ese ID, búscalo dentro de la misma ventana con Loki. Sustituye el ID del ejemplo:

```logql
{namespace="aplicaciones"} |= "0123456789abcdef0123456789abcdef"
```

También puedes buscar localmente en la exportación:

```bash
rg -F "$TRACE_ID" "$OUT_DIR/aplicacion.log"
```

Sin ID en los logs, la coincidencia por hora, pod y servicio sirve como indicio, pero no demuestra que pertenezcan a la misma petición. Los enlaces automáticos de Tempo a Loki necesitan configuración del datasource; el [archivo actual del proyecto](../../kubernetes/observability/grafana/datasources/datasources.yaml) no declara esa correlación.

## 7. Documentar el resultado

Copia la [plantilla de informe](plantilla-informe-logs-trazas.md) en la carpeta de evidencia y completa los campos:

```bash
cp docs/observability/plantilla-informe-logs-trazas.md "$OUT_DIR/informe.md"
printf 'Evidencias: %s\n' "$OUT_DIR"
```

El comando `cp` se ejecuta desde la raíz del repositorio; adapta la ruta si trabajas desde otro lugar. Conserva mensajes de error de extracción, consultas usadas, sus límites y capturas con ventana temporal visible. No presentes datos de ejemplo como resultados. Revisa y elimina credenciales o datos personales antes de compartir los archivos.

Criterio de cierre: identificar el entorno y la ventana; guardar logs y estado; localizar y exportar al menos una traza real si existe instrumentación; explicar la correlación o su ausencia; distinguir hallazgos de verificaciones pendientes. Si faltan trazas, documentar el requisito ausente también es un resultado útil, pero no equivale a validar el pipeline.

## 8. Cuando no aparecen datos

| Síntoma | Próxima comprobación |
|---|---|
| `kubectl logs` devuelve Forbidden | Contexto y permiso de lectura de `pods/log` en el namespace |
| Logs actuales disponibles, `--previous` falla | Si ese contenedor tiene una ejecución anterior accesible |
| Hay logs en kubectl y no en Loki | Agente, receptor, etiquetas, destino y ventana de ingestión |
| No existen recursos OTel | Instalación del operador, CRD y namespaces reales |
| Hay HTTP 200 de la aplicación y ninguna traza | Instrumentación de esa biblioteca, exportador, muestreo y recepción |
| Hay trazas sin namespace/pod/clúster | Atributos de recursos y enriquecimiento del Collector |
| Grafana falla pero las APIs responden por túnel | URL y conectividad de los datasources desde Grafana |
| Hay traza pero no span DB o Ingress | Operación real y soporte/configuración de instrumentación de cada salto |

Para comprobar el gateway identifica primero su pod con `kubectl get pods -n observability` y consulta sus logs con el procedimiento de la sección 3. Revisa errores de exportación en esa misma ventana. Evita volcar configuración con valores de credenciales como parte del informe.

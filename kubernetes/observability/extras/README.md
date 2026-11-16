# Observabilidad extra del laboratorio

Grafana del nodo 306 publica los paneles en la carpeta **Observabilidad extra**. Desde un PC conectado a la red de administración, abre el túnel y entra a `http://127.0.0.1:3001/dashboards/f/observabilidad-extra` con tu cuenta de Grafana.

```bash
ssh -N -L 127.0.0.1:3001:127.0.0.1:3000 n306@192.168.29.25
```

| Panel | Datos |
| --- | --- |
| 01 · Estado y servicios | Polystat muestra Node Exporter, kubelets, API de Kubernetes, comprobaciones HTTP/TCP, Redis y los endpoints de observabilidad. |
| 02 · Métricas de nodos y Kubernetes | CPU, memoria, disco raíz, interfaces del gateway, consumo por namespace y pod, solicitudes a la API Kubernetes por código. |
| 03 · Logs de aplicaciones | Loki y VictoriaLogs, volumen por contenedor y enlaces a Explore y Logs Drilldown. |
| 04 · Trazas y OpenTelemetry | Spans y trazas recibidas por Tempo, tabla TraceQL y enlace a Explore. |

## Despliegue y comandos

Se ejecutó el CLI del paquete Debian en el nodo 306. Polystat y VictoriaLogs quedaron fijados a las versiones indicadas. Grafana ya tenía Logs Drilldown 1.0.10.

```bash
ssh n306@192.168.29.25
sudo /usr/share/grafana/bin/grafana cli --homepath /usr/share/grafana \
  --pluginsDir /var/lib/grafana/plugins plugins install grafana-polystat-panel 2.1.16
sudo /usr/share/grafana/bin/grafana cli --homepath /usr/share/grafana \
  --pluginsDir /var/lib/grafana/plugins plugins install victoriametrics-logs-datasource 0.34.0
sudo /usr/share/grafana/bin/grafana cli --homepath /usr/share/grafana \
  --pluginsDir /var/lib/grafana/plugins plugins ls
```

Desde la raíz del proyecto, estos comandos reproducen el despliegue por SSH. Se validaron los manifiestos con `apply --dry-run=server` antes de la primera aplicación.

```bash
kube=(sudo -n /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml)
ssh n306@192.168.29.25 "${kube[*]} apply -f -" \
  < kubernetes/observability/extras/logs.yaml
ssh n306@192.168.29.25 "${kube[*]} -n observability rollout status statefulset/victoria-logs --timeout=120s"
ssh n306@192.168.29.25 "${kube[*]} -n observability rollout status daemonset/application-log-collector --timeout=120s"

ansible-playbook ansible/playbooks/40-observability/03_observability_extras.yml --syntax-check
ansible-playbook ansible/playbooks/40-observability/03_observability_extras.yml \
  --limit nodo-306 -e ansible_host=192.168.29.25 \
  -e ansible_ssh_common_args=-oBatchMode=yes -e lab_grafana_lan=10.100.29.30

ssh n306@192.168.29.25 "${kube[*]} apply -f -" \
  < kubernetes/apps/microservices/backend-api.yaml
ssh n306@192.168.29.25 "${kube[*]} -n aplicaciones rollout status deployment/backend-api --timeout=100s"
```

El playbook consulta las direcciones de los servicios Kubernetes, fija los plugins, copia los paneles y aprovisiona VictoriaLogs. Corrige la variable del enlace Loki → Tempo y configura Tempo → Loki para buscar por `trace_id`. Usa las fuentes con UID `Prometheus-BareMetal`, `VictoriaMetrics`, `Loki` y `tempo` del Grafana del 306. Añade las sondas al archivo externo de Prometheus y reutiliza el acceso de lectura a Kubernetes para descubrir ambas réplicas del Collector. Ejecuta `promtool check config` antes de recargar Prometheus por SIGHUP. Reinicia Grafana al cambiar su aprovisionamiento y comprueba su API. El primer intento de recarga se detuvo durante la validación del formato del archivo externo. Se corrigió la clave `scrape_configs` y se repitió el playbook.

El DaemonSet monta `/var/log/pods` en modo lectura, recoge la salida de los contenedores de `aplicaciones` y envía una copia a cada backend. Comienza desde el final de los archivos y conserva sus posiciones de lectura en cada nodo. VictoriaLogs utiliza un volumen local de 8 GiB y retención de siete días. El volumen permanece ligado al nodo donde se aprovisiona. El `backend-api` crea spans en su ruta de datos y escribe el ID de la traza en el log cuando el SDK la muestrea. El Collector aplica su propio muestreo, por lo que una parte de esos IDs aparece en Tempo.

## Comprobaciones operativas

- Grafana respondió en `/api/health`. Los módulos de Polystat, Logs Drilldown y VictoriaLogs respondieron en `/public/plugins/<id>/module.js`. Se comprobaron los cuatro dashboards y la fuente VictoriaLogs en el aprovisionamiento.
- En Prometheus se comprobó `count(probe_success{job=~"observability-extra-http|observability-extra-tcp"} == 1)` y el descubrimiento de las dos réplicas del Collector. Se obtuvieron 18 sondas exitosas, 8 Node Exporter activos y 7 kubelets con cAdvisor. `redis_up` devolvió 1.
- Se hicieron peticiones GET al frontend y al backend, se consultaron los logs en Loki mediante LogQL y en VictoriaLogs mediante LogsQL, y se buscó `backend-api` en Tempo con TraceQL. Se consultaron por ID las trazas coincidentes con los logs. También se enviaron 32 spans sintéticos identificados como `observability-smoke` para verificar el trayecto Collector → Tempo.
- Squid, Nexus mirror y Nexus hosted se miden por apertura TCP. La solicitud a Debian vía Squid agotó el tiempo de espera. Las métricas internas autenticadas de Nexus y los logs del sistema operativo quedan fuera del alcance de estos paneles.
- Grafana 11.5.0 y Tempo 2.5.0 usan la vista **Explore → Tempo**. Para incorporar el Traces Drilldown del catálogo actual hace falta actualizar las versiones y habilitar TraceQL metrics según la versión de Tempo.

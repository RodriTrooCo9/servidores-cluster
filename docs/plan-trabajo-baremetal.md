# Plan de trabajo: plataforma bare metal, observabilidad y aprovisionamiento

Fecha: 9 de noviembre de 2026.

Objetivo: operar el laboratorio, obtener métricas, logs y trazas de una aplicación y demostrar cómo se identifica un fallo bajo carga. Mantener un procedimiento independiente para construir imágenes y aprovisionar equipos físicos o máquinas virtuales.

Este documento organiza tareas pendientes; no certifica el estado actual de los servicios. La revisión se hizo sobre archivos del repositorio y notas aportadas por el usuario, sin acceder al clúster ni al panel. Los manifiestos y manuales existentes son puntos de partida que requieren validación.

## Organización y prioridades

| Bloque | Resultado | Prioridad | Dependencias |
|---|---|---|---|
| A. Inventario y operación | IP, accesos, almacenamiento y uso básico del clúster documentados | P0 | Ninguna |
| B. OpenTelemetry y señales | Operador, colectores, métricas y logs comprobados | P1 | A |
| C. Trazabilidad de aplicaciones | Seguir una petición y localizar un fallo | P1 | B |
| D. Pruebas de carga | Medir rendimiento y correlacionarlo con telemetría | P2 | C |
| E. OpenStack | Manuales de arquitectura, aprovisionamiento físico y creación de VM | P2 | Inventario de A; independiente de B–D |
| F. Packer | Imagen reproducible, arranque y primer acceso comprobados | P2 | Inventario de A; integración con E después de validar la imagen |

P0: resolver primero. P1: demostración funcional. P2: ampliar y automatizar. E y F pueden avanzar de forma independiente a la observabilidad.

## A. Inventario, acceso y operación del clúster

- [ ] **BM-01 — Documentar IP, roles y acceso a los paneles.** Registrar servidores físicos, VMs existentes, redes, interfaces, hostname, IP de administración, IP interna, rol, servicio, puerto y URL. Incluir el acceso aportado por el usuario: [Coroot](http://192.168.29.25:19000/login/). Confirmar qué servicio atiende cada panel antes de describirlo como panel de VMs o almacenamiento. **Aceptación:** cada entrada tiene fecha de comprobación y evidencia; las diferencias con el inventario quedan identificadas. No incluir contraseñas ni tokens.
- [ ] **BM-02 — Elaborar un manual práctico de Kubernetes con kubectl.** Explicar contextos, nodos, namespaces, Deployments, Services, Ingress, pods y eventos. Incluir consultas con `get`, `describe`, `logs`, `logs --previous` y `top`, indicando que este último necesita la API de métricas. **Aceptación:** otra persona puede acceder al contexto correcto, localizar un pod, leer sus logs e identificar un reinicio siguiendo el manual.
- [ ] **BM-03 — Inventariar almacenamiento y crear un dashboard de capacidad.** Identificar discos físicos, almacenamiento de VMs cuando exista, StorageClasses, PV y PVC, capacidad, uso y retención de telemetría. **Aceptación:** panel con filtros disponibles por nodo y namespace, relación entre PVC y aplicación, y una alerta de capacidad probada. Documentar las métricas que aún no se recolecten.

Base: [guía de instalación](../GUIA_DE_INSTALACION.md), [inventario de laboratorio](../inventory/lab/hosts.yml) y [último estado documentado](reference/estado-observado-2026-10-30.md). La inspección anterior no sustituye BM-01.

## B. Operadores y observabilidad con OpenTelemetry

- [ ] **OBS-01 — Crear una práctica sobre operadores de Kubernetes y OTel.** Explicar CRD, recurso personalizado, controlador y reconciliación. Distinguir el Operator, el Collector, las bibliotecas/SDK de instrumentación y los sistemas donde se almacenan las señales. **Aceptación:** manual con un ejemplo que muestre cómo un recurso `OpenTelemetryCollector` genera una carga de trabajo administrada y para qué se usa `Instrumentation`.
- [ ] **OBS-02 — Completar la instalación del OpenTelemetry Operator con Helm.** Preparar una receta con chart y versiones compatibles fijados, `values.yaml`, namespace, permisos y certificados/webhooks según el método elegido. Revisar primero si ya existe un operador y quién administra sus CRD. Después validar los recursos existentes del repositorio. **Aceptación:** instalación o actualización reproducible en laboratorio, operador disponible, CRD compatibles, webhook funcional y procedimiento de reversión documentado.
- [ ] **OBS-03 — Configurar y verificar la recolección de métricas y logs del clúster.** Revisar los receptores, agentes y permisos necesarios para los datos de nodos, Kubernetes y logs de contenedores; definir destinos en VictoriaMetrics/Prometheus y Loki según lo validado. Acordar atributos de clúster, namespace, pod y servicio, evitando etiquetas de cardinalidad innecesaria. **Aceptación:** consultas y paneles con filtros por clúster, namespace y pod; una métrica y un mensaje conocidos aparecen en el destino esperado. Los datos de hosts y VMs conservan sus propios filtros.
- [ ] **OBS-04 — Validar el recorrido de exportación y la persistencia.** Comprobar DNS, conectividad, autenticación, protocolos OTLP, pipelines, recepción en Tempo/Coroot cuando corresponda, retención y PVC. Gestionar credenciales mediante secretos. Revisar el muestreo tanto en la aplicación como en el Collector. **Aceptación:** señal de prueba visible en cada destino configurado, diagnóstico de una exportación fallida y política de retención documentada.

Base: [guía de observabilidad](../GUIA_OBSERVABILIDAD.md), [recursos OTel existentes](../kubernetes/observability/otel/02_otel_operator_and_collectors.yaml), [backends](../kubernetes/observability/backends/01_backends.yaml) y [dashboards](../kubernetes/observability/grafana/dashboards/).

Hallazgo para OBS-02: el archivo OTel contiene recursos `OpenTelemetryCollector` e `Instrumentation`; aplicarlos requiere disponer previamente del operador y sus CRD. Su presencia en el repositorio no demuestra una instalación del operador.

## C. Trazas de aplicaciones y diagnóstico de fallos

- [ ] **TRACE-01 — Instrumentar una aplicación y escribir su manual.** Elegir un lenguaje realmente usado en el proyecto. Documentar la autoinstrumentación compatible y un ejemplo con SDK o biblioteca que añada un span de negocio. Configurar nombre de servicio, exportación OTLP y propagación de contexto. **Aceptación:** una petición genera spans HTTP, un span de negocio y, si hay acceso a una base de datos, el span de su cliente; se explica qué ocurre dentro de cada operación.
- [ ] **TRACE-02 — Construir una demostración navegador → Ingress → Service → pod → base de datos.** Preparar una aplicación que haga una consulta real a la DB, mantener el contexto entre servicios y correlacionar logs con `trace_id`/`span_id` donde exista contexto. Para incluir un span del navegador, instrumentar también el frontend; para incluir un span del Ingress, configurar una implementación compatible. **Aceptación:** se documenta dónde empieza la traza y qué saltos están instrumentados; la petición puede seguirse hasta la consulta a la DB sin atribuir spans a componentes que no los generan.
- [ ] **TRACE-03 — Demostrar cómo localizar un fallo.** Introducir por separado una demora de DB, un error HTTP y una interrupción de una dependencia, en la aplicación de prueba. Registrar síntomas, span afectado, log correlacionado, métricas y recuperación. **Aceptación:** informe con una traza saludable y una fallida, causa sustentada por evidencia y pasos para restaurar el escenario.

Base: [aplicación actual](../kubernetes/apps/microservices/backend-api.yaml) y [manifiestos de aplicaciones](../kubernetes/apps/). El backend revisado responde HTTP con datos estáticos; TRACE-02 debe añadir o seleccionar un caso con consulta real a DB. La anotación de autoinstrumentación existente necesita comprobarse en ejecución.

## D. Pruebas de carga con k6 y JMeter

- [ ] **LOAD-01 — Completar y ejecutar una prueba k6 reproducible.** Validar la instalación de k6 Operator, su CRD `TestRun`, el namespace, las etiquetas reales de los nodos, las versiones de las imágenes y el destino de resultados. Configurar carga baja inicial, incremento, carga sostenida y recuperación. **Aceptación:** ejecución terminada con peticiones/segundo, tasa de error, p95/p99 y consumo de CPU/RAM; umbrales acordados y resultado aprobado/fallido guardado.
- [ ] **LOAD-02 — Completar y validar el escenario JMeter.** Revisar el JMX y el Job existentes, parametrizar URL y carga, y conservar los resultados JTL y un informe. Si se ejecutan varios pods independientes, documentar la carga agregada y cómo se combinan los resultados; comprobar explícitamente la coordinación si se requiere un test distribuido. **Aceptación:** escenario comparable con k6, duración y concurrencia documentadas, informe conservado y limpieza reproducible.
- [ ] **LOAD-03 — Correlacionar carga con métricas, logs y trazas.** Usar identificador de ejecución y la misma ventana temporal. Probar por separado el acceso interno al servicio y la ruta de entrada a través del Ingress; los generadores HTTP no sustituyen la ejecución de JavaScript de un navegador. **Aceptación:** informe identifica el cuello de botella con evidencia y comprueba la recuperación después de retirar la carga o el fallo controlado.

Base: [pruebas existentes](../kubernetes/load-testing/README.md), [k6](../kubernetes/load-testing/k6/) y [JMeter](../kubernetes/load-testing/jmeter/). El escenario k6 revisado usa directamente el DNS del backend: aún debe añadirse y comprobarse el caso que atraviesa el Ingress.

## E. Manuales de OpenStack y aprovisionamiento

- [ ] **OS-01 — Documentar la arquitectura y completar el manual de instalación.** Explicar controlador, redes, Glance, Keystone, Neutron, Ironic y los componentes de cómputo/almacenamiento que realmente se habiliten. Elegir entre Kolla e Ironic standalone para el procedimiento físico y comprobar versiones, interfaces y requisitos. **Aceptación:** inventario y arquitectura coherentes, procedimiento de laboratorio con verificaciones por etapa y alcance de cada alternativa explícito.
- [ ] **OS-02 — Completar el manual para aprovisionar un equipo físico.** Registrar máquina, MAC, imagen, disco, firmware, red y mecanismo de encendido. **Aceptación:** instalación comprobada en un destino de prueba autorizado, arranque desde disco, configuración de red y acceso SSH; evidencias y procedimiento de recuperación conservados.
- [ ] **OS-03 — Crear y validar el manual de una máquina virtual.** Verificar primero que exista un servicio de cómputo con hipervisor para VMs operativo. Documentar proyecto, imagen, flavor, llave, red/subred, reglas de acceso y dirección alcanzable; incluir volumen si se utiliza. **Aceptación:** crear una VM de prueba, acceder por SSH, reiniciarla, consultar consola/estado y eliminar los recursos creados para la prueba. Registrar las IP en BM-01.

Base: [guía OpenStack](../GUIA_OPENSTACK.md), [configuración](../openstack/README.md) y [comparativa de servicios](architecture/openstack/glance_ironic_bifrost_arquitectura_comparativa.md). Ironic aprovisiona equipos físicos. La creación de VMs constituye una ampliación del alcance que debe validarse por separado; activar opciones en un archivo no demuestra que el servicio funcione.

## F. Construcción de imágenes con Packer

- [ ] **IMG-01 — Completar una receta reproducible de construcción de imagen.** Elegir destino VM y/o físico y documentar sus requisitos de formato y firmware. Preparar fuente del SO con checksum, plugins/versiones, instalación desatendida, cloud-init y limpieza de datos temporales. **Aceptación:** plantilla completa, `packer fmt -check`, `packer validate` con entradas preparadas y un build de laboratorio finalizado con checksum del artefacto.
- [ ] **IMG-02 — Validar arranque e integrar la imagen con el aprovisionamiento.** Comprobar arranque, red, cloud-init y SSH primero en un destino de prueba compatible. Publicar en Glance si corresponde y probar el consumo por el procedimiento físico o de VM validado. Crear una variante con agente de observabilidad si se necesita. **Aceptación:** evidencia de primer arranque, identificación de versión de imagen, acceso y señales del agente cuando se incluya; documentar por separado los resultados en VM y hardware físico.

Base: [estado de las plantillas](../cloud-init/README.md), [Packer](../cloud-init/packer/) y [referencia de imagen con Coroot](observability/coroot-debian13-packer.md). Las plantillas existentes no se consideran verificadas hasta completar el build y el arranque.

## Primera iteración propuesta

1. Completar BM-01 y BM-02; identificar el estado real de almacenamiento de BM-03.
2. Ejecutar la práctica OBS-01 y completar instalación/validación del operador en OBS-02.
3. Obtener una métrica y un log conocidos con OBS-03, y una traza con OBS-04/TRACE-01.
4. Completar el caso con DB de TRACE-02 y reproducir un fallo de TRACE-03.
5. Ejecutar una prueba k6 pequeña de LOAD-01 y guardar la correlación de LOAD-03.

La siguiente iteración completa dashboards, JMeter, manuales OpenStack y construcción/integración de imágenes. No se fija duración ni responsables sin conocer disponibilidad.

## Formato para convertir cada tarea en un issue

Usar el identificador y el título anteriores. Añadir responsable, prioridad, dependencias, estado y enlace a evidencias. Estados sugeridos: pendiente → en curso → en validación → terminado; usar bloqueado cuando falte un requisito concreto.

Una tarea se cierra cuando cumple su criterio de aceptación, conserva la evidencia con fecha/entorno y actualiza el manual correspondiente. Tener un YAML o un documento previo no equivale a haber validado el servicio. Los cambios de documentación se verifican revisando enlaces y pasos; los despliegues requieren las comprobaciones de ejecución indicadas en cada tarea.

## Referencias oficiales para desarrollar los manuales

- [OpenTelemetry en Kubernetes](https://opentelemetry.io/docs/platforms/kubernetes/).
- [Charts Helm de OpenTelemetry](https://opentelemetry.io/docs/platforms/kubernetes/helm/).
- [OpenTelemetry Operator y autoinstrumentación](https://github.com/open-telemetry/opentelemetry-operator).
- [Guía de usuario de Ironic 2025.1](https://docs.openstack.org/ironic/2025.1/user/), versión declarada por la configuración Kolla del repositorio; comprobar la instalada antes de aplicarla.

# Informe de logs y trazas

Estado: pendiente de completar con una ejecución real. No sustituir los campos por ejemplos ficticios.

## Entorno y alcance

| Campo | Valor |
|---|---|
| Fecha y responsable | |
| Contexto kubectl y clúster identificado | |
| Inicio y final UTC | |
| Hora local y zona | |
| Namespace | |
| Aplicación / service.name | |
| Pods, contenedores y nodos | |
| Versión o imagen de la aplicación | |
| Destinos de logs y trazas consultados | |

## Operación investigada

- Objetivo o síntoma:
- URL/ruta y método HTTP; indicar si atraviesa Ingress o usa port-forward:
- Hora UTC de la petición, respuesta HTTP y duración:
- Resultado esperado:

## Evidencia obtenida

| Archivo o captura | Origen y consulta/comando | Ventana, límites y resultado |
|---|---|---|
| Logs de aplicación | | |
| Logs de ejecución anterior, si existen | | |
| Eventos y estado del pod | | |
| Exportación Loki, si existe | | |
| Búsqueda Tempo y JSON de traza, si existe | | |
| Logs del host/colector, si son necesarios | | |

## Lectura de la traza

- Trace ID:
- Span ID relevante:
- Servicio y operación:
- Duración y estado del span:
- Dependencia afectada:
- Mensaje o evento de error:
- Correlación con logs: ID coincidente / solo coincidencia temporal / no disponible:
- Componentes sin instrumentación o sin atributos:

## Hallazgos y límites

- Hechos confirmados por evidencia:
- Hipótesis que requieren comprobación:
- Datos ausentes, errores de extracción, muestreo o límites de retención:
- Causa identificada, o motivo por el que no puede establecerse:
- Acción propuesta y forma de verificarla:
- Resultado de la verificación, si se realizó:

## Cierre

- [ ] Entorno, versión y ventana temporal identificados.
- [ ] Archivos y consultas conservados; errores y límites declarados.
- [ ] Traza real exportada o requisito pendiente explicado.
- [ ] Evidencias revisadas antes de compartirlas.
- [ ] Documentación y siguiente tarea actualizadas.

# ADR 0003: Mitigación de Restricción de Almacenamiento SSD de 128 GB

## Estado
Aceptado

Este documento registra objetivos de configuración. Las políticas de limpieza,
cuotas y parámetros efectivos requieren comprobarse en cada servicio.

## Contexto
Todos los servidores físicos (Dell OptiPlex 3020M) disponen de un único disco NVMe/SSD de **128 GB**. El almacenamiento sin control de imágenes de contenedor, registros de Nexus, snapshots de etcd y métricas de Prometheus causaría agotamiento de espacio en disco en cuestión de días.

## Decisión
Implementar una estrategia multidimensional de mitigación de almacenamiento:
1. **Kubernetes Kubelet**: Umbrales agresivos de recolección de basura de imágenes:
   - `image-gc-high-threshold=75`
   - `image-gc-low-threshold=60`
2. **etcd HA**:
   - `auto-compaction-retention=1000`
   - `quota-backend-bytes=2147483648` (Límite estricto de 2 GB)
3. **Sonatype Nexus 3**:
   - Políticas de limpieza automática eliminando imágenes no etiquetadas tras 14 días.
   - Blobstores con cuota blanda de 20-25 GB.
4. **Prometheus y VictoriaMetrics**:
   - Retención máxima local de 15 días / 15 GB (`--storage.tsdb.retention.size=15GB`).
   - Reenvío de métricas frías a almacenamiento centralizado VictoriaMetrics.
5. **Git y Control de Versiones**:
   - Exclusión de imágenes ISO, binarios IPA (638 MB) y volcados de backup en `.gitignore`.

## Consecuencias
- **Positivas**: Limitar la retención y supervisar el consumo ayuda a planificar la capacidad.
- **Negativas**: Necesidad de respaldar externamente métricas y registros históricos que superen la ventana de retención.

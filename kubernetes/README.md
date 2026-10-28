# Manifiestos de Kubernetes y Observabilidad

Este directorio contiene las cargas de trabajo, microservicios y la suite completa de observabilidad desplegada sobre el clúster **RKE2 HA (Cilium eBPF)**.

## Estructura
```text
kubernetes/
├── base/                              # Kustomization base común
│   └── kustomization.yaml
├── overlays/                          # Variaciones por entorno
│   ├── lab/kustomization.yaml         # Entorno de pruebas / staging
│   └── prod/kustomization.yaml        # Entorno de producción
├── apps/                              # Aplicaciones de negocio
│   └── microservices/microservices_stack.yaml # Stack de microservicios e instrumentación
└── observability/                     # Telemetría de clúster
    ├── backends/01_backends.yaml      # VictoriaMetrics, Loki, Tempo
    ├── otel/02_otel_operator_and_collectors.yaml # OpenTelemetry Operator (Gateway, Agent y Auto-Instrumentation)
    ├── grafana/datasources/datasources.yaml # Fuentes de datos como código
    └── alerting/rules/alerts_k8s.yaml # Reglas de alerta para SSD 128 GB y nodos
```

## Despliegue con Kustomize
```bash
# Aplicar entorno de laboratorio
kubectl apply -k kubernetes/overlays/lab

# Aplicar entorno de producción
kubectl apply -k kubernetes/overlays/prod
```

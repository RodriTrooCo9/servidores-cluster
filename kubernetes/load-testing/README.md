# Pruebas de Carga Distribuidas en Clúster RKE2 (k6 y JMeter)

Este directorio contiene las definiciones y scripts para ejecutar pruebas de estrés y rendimiento distribuidas entre nodos físicos (workers) en el clúster RKE2.

## 1. k6 Operator (Recomendado)

### Despliegue del Script y Ejecución
```bash
# 1. Crear / actualizar el ConfigMap con el script de prueba
kubectl -n pruebas-carga create configmap k6-script \
  --from-file=prueba.js=kubernetes/load-testing/k6/prueba.js \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Iniciar la prueba de carga distribuida (3 workers)
kubectl apply -f kubernetes/load-testing/k6/k6-testrun.yaml

# 3. Monitorear los pods runners distribuidos en distintos nodos
kubectl get pods -n pruebas-carga -o wide -w

# 4. Ver logs en tiempo real de los ejecutores
kubectl logs -n pruebas-carga -l k6_cr=prueba-distribuida -f --max-log-requests=10

# 5. Limpiar ejecución finalizada
kubectl delete -f kubernetes/load-testing/k6/k6-testrun.yaml
```

---

## 2. Apache JMeter (Job Distribuido con Anti-Afinidad)

### Despliegue del Plan JMX y Ejecución
```bash
# 1. Crear / actualizar el ConfigMap con el plan JMX
kubectl -n pruebas-carga create configmap jmeter-plan \
  --from-file=prueba.jmx=kubernetes/load-testing/jmeter/prueba.jmx \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Iniciar el Job distribuido (completions: 3, parallelism: 3)
kubectl apply -f kubernetes/load-testing/jmeter/jmeter-job.yaml

# 3. Verificar que los 3 pods corren en nodos físicos distintos
kubectl get pods -n pruebas-carga -l app=jmeter-load -o wide

# 4. Inspeccionar el avance en los logs
kubectl logs -n pruebas-carga -l app=jmeter-load --prefix=true -f

# 5. Limpiar el Job
kubectl delete -f kubernetes/load-testing/jmeter/jmeter-job.yaml
```

---

## 3. Pruebas por Nodo Específico (Node Isolation)

Para medir el rendimiento de un único nodo sin que el balanceador de Cilium/Kube-proxy desvíe tráfico a otros servidores:

1. **Aislar la carga de trabajo en un nodo**:
   Configurar `nodeSelector: kubernetes.io/hostname: worker-01` en el Deployment de la aplicación de prueba.
2. **Configurar afinidad local de tráfico**:
   En el `Service`, agregar:
   ```yaml
   spec:
     internalTrafficPolicy: Local
   ```
   Con esto, solo los pods situados en el mismo nodo físico que recibe la solicitud la procesarán.

# ADR 0002: Adopción de Cilium eBPF con Sustitución Completa de kube-proxy

## Estado
Aceptado

La decisión describe el diseño previsto. El 16 de noviembre de 2026, el
laboratorio ejecutaba Cilium con `kube-proxy-replacement=false` y kube-proxy
seguía activo. [Estado observado](../reference/estado-laboratorio.md)

## Contexto
El clúster Kubernetes RKE2 utiliza tradicionalmente iptables mediante `kube-proxy` para el enrutamiento de Services y ClusterIP. Con el crecimiento de servicios y microservicios, iptables introduce sobrecarga lineal $O(N)$ en el kernel y mayor latencia de red. Debian 13 (Trixie) cuenta con Kernel Linux 6.12+, ofreciendo soporte nativo de última generación para programas eBPF.

## Decisión
Desplegar RKE2 configurando:
- `cni: cilium`
- `disable-kube-proxy: true`
- HelmChartConfig de Cilium con `kubeProxyReplacement: true` activado para gestionar el balanceo de tráfico L4/L7 a través de mapas BPF en memoria en lugar de cadenas de iptables.

## Consecuencias
- El reemplazo requiere validar compatibilidad, conectividad y políticas antes de
  aplicarlo. El rendimiento y el consumo dependen de la carga y deben medirse.

# ADR 0002: Adopción de Cilium eBPF con Sustitución Completa de kube-proxy

## Estado
Aceptado

## Contexto
El clúster Kubernetes RKE2 utiliza tradicionalmente iptables mediante `kube-proxy` para el enrutamiento de Services y ClusterIP. Con el crecimiento de servicios y microservicios, iptables introduce sobrecarga lineal $O(N)$ en el kernel y mayor latencia de red. Debian 13 (Trixie) cuenta con Kernel Linux 6.12+, ofreciendo soporte nativo de última generación para programas eBPF.

## Decisión
Desplegar RKE2 configurando:
- `cni: cilium`
- `disable-kube-proxy: true`
- HelmChartConfig de Cilium con `kubeProxyReplacement: true` activado para gestionar el balanceo de tráfico L4/L7 a través de mapas BPF en memoria en lugar de cadenas de iptables.

## Consecuencias
- **Positivas**: Rendimiento superior $O(1)$, reducción drástica de consumo de CPU por conntrack, observabilidad nativa de tráfico con Hubble eBPF y políticas de red avanzadas L7.
- **Negativas**: Requiere un kernel moderno ($\ge 6.12$) y configuración cuidadosa de las directivas sysctl (`net.core.bpf_jit_enable`).

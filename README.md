# Infraestructura Bare-Metal Edge, OpenStack Ironic & Kubernetes HA

![Debian 13](https://img.shields.io/badge/OS-Debian%2013%20Trixie-A81D33?logo=debian)
![Ansible](https://img.shields.io/badge/Automation-Ansible%20Core-EE0000?logo=ansible)
![Kubernetes](https://img.shields.io/badge/Orchestration-RKE2%20HA-326CE5?logo=kubernetes)
![CNI](https://img.shields.io/badge/CNI-Cilium%20eBPF-F36E21?logo=cilium)
![OpenStack](https://img.shields.io/badge/Provisioning-Ironic%20Standalone-E2231A?logo=openstack)
![Observability](https://img.shields.io/badge/Telemetry-Prometheus%20%7C%20VM%20%7C%20Grafana-F46800?logo=grafana)

Plataforma de infraestructura bare-metal, automatización declarativa y clúster de Kubernetes de Alta Disponibilidad desplegado sobre **8 servidores físicos Dell OptiPlex 3020M** en una subred privada aislada (`10.100.29.0/24`).

---

## 🏗️ Diagrama de Arquitectura y Flujo de Aprovisionamiento

```mermaid
flowchart TD
    subgraph Perimetro ["Perímetro y Entrada Única"]
        DevOps["Estación DevOps\n(192.168.29.16)"] -->|"SSH ProxyJump (:2222)"| Bastion["Nodo 314: Bastion\n(10.100.29.10)\nSquid Proxy (:3128)\nnftables Firewall"]
    end

    subgraph Aprovisionamiento ["Servicios de Despliegue Bare-Metal"]
        PXE["Nodo 306: PXE Controller\n(10.100.29.30)\ndnsmasq (DHCP/TFTP)\nNginx HTTPBoot (:8089)"]
        Nexus["Nodo 315: Nexus 3 OSS\n(10.100.29.20)\nAPT Proxy (:8081)\nDocker Registry (:8082)"]
        Ironic["OpenStack Ironic Standalone\nIPA Ramdisk + Glance (:6385)"]
    end

    subgraph Flota_Fisica ["Servidores Físicos (Dell 3020M | 128 GB SSD)"]
        CP1["Nodo 269: k8s-cp-01 (Líder etcd)"]
        CP2["Nodo 280: k8s-cp-02"]
        CP3["Nodo 320: k8s-cp-03"]
        W1["Nodo 321: k8s-worker-01"]
        W2["Nodo 279: k8s-worker-02"]
    end

    subgraph Plataforma_K8s ["Clúster Kubernetes HA (RKE2 + Cilium eBPF)"]
        Cilium["Cilium eBPF Datapath\n(Sustitución de kube-proxy)"]
        Apps["Microservicios & Cargas de Trabajo"]
    end

    subgraph Observabilidad ["Stack de Telemetría End-to-End"]
        Prom["Prometheus & VictoriaMetrics"]
        Graf["Grafana Dashboards as Code"]
        OTel["OpenTelemetry Collector & Loki"]
    end

    Bastion -->|"Egress Gateway"| Aprovisionamiento
    PXE -->|"1. DHCP por MAC / iPXE"| Flota_Fisica
    Ironic -->|"2. Despliegue de Imagen QCOW2"| Flota_Fisica
    Nexus -->|"3. Caché local APT y Contenedores"| Flota_Fisica
    Flota_Fisica -->|"4. Bootstrap RKE2"| Plataforma_K8s
    Plataforma_K8s -->|"5. Exportación OTLP / Métricas"| Observabilidad
```

---

## ⚡ Quickstart de 10 Líneas

Para verificar, desplegar y auditar la infraestructura desde tu terminal:

```bash
# 1. Crear entorno seguro de claves y contraseñas
echo "tu_password_maestra" > .vault_pass && chmod 600 .vault_pass

# 2. Validar sintaxis y estándares de calidad
make lint

# 3. Comprobar conectividad y telemetría de hardware
make preflight

# 4. Desplegar configuración base y endurecimiento perimetral
make base

# 5. Desplegar servicios centrales (Nexus, PXE, Ironic)
make services

# 6. Desplegar el clúster Kubernetes HA (RKE2 + Cilium)
make platform

# 7. Desplegar la suite de observabilidad
make observability

# 8. Verificar salud integral de la flota
make health
```

---

## 📁 Estructura del Repositorio

```text
infra-scripts/
├── Makefile                   # Punto de entrada unificado para todas las operaciones
├── ansible.cfg                # Configuración canónica de Ansible para la infraestructura
├── inventory/                 # ÚNICA FUENTE DE VERDAD física y lógica
│   ├── nodes.csv              # Matriz de hardware (MACs, IPs, roles, especificaciones)
│   ├── lab/                   # Entorno de pruebas / staging activo
│   │   ├── hosts.yml          # Inventario YAML de Ansible por roles
│   │   └── group_vars/        # Variables (vars.yml, observability.yml, vault.yml)
│   └── prod/                  # Entorno productivo segregado
├── ansible/                   # Automatización declarativa por fases numeradas
│   ├── site.yml               # Orquestador maestro integral
│   ├── playbooks/             # 00-preflight, 10-base, 20-services, 30-platform, etc.
│   └── roles/                 # common, bastion, nexus, pxe_controller, ironic, rke2_ha, monitoring
├── openstack/                 # Aprovisionamiento Kolla-Ansible (Ironic Standalone & Glance)
│   ├── globals.yml, inventory/multinode, config/, secrets/
├── cloud-init/                # Plantillas Packer HCL2, user-data y generador de ConfigDrive
├── nexus/                     # Repositorios, cuotas de disco y políticas de purga como código
├── kubernetes/                # Manifiestos K8s, apps y observabilidad (Kustomize base/overlays)
├── network/                   # dnsmasq DHCP/TFTP, toolchain iPXE custom y reglas nftables
├── scripts/                   # Scripts auxiliares (bootstrap, diagnostics, ops, client)
├── artifacts/                 # [GITIGNORED] Binarios IPA, ISOs e imágenes con script de descarga
├── backups/                   # [GITIGNORED] Snapshots y volcados temporales de DR
└── docs/                      # Documentación completa, runbooks, referencias y ADRs
```

Para consultar la documentación completa, diagramas y runbooks operativos, accede al [**Índice Maestro de Documentación (`docs/README.md`)**](docs/README.md).

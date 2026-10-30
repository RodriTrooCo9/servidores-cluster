# 🛠️ Guías de Instalación Oficiales y Operativas del Proyecto

Este documento consolida las **guías de instalación oficiales y los procedimientos operativos exactos** para cada una de las tecnologías instaladas en la infraestructura Bare-Metal, Kubernetes HA, OpenStack y Observabilidad.

---

## 📑 Índice de Guías

1. [Capa 0: Estación de Trabajo DevOps (Laptop de Control)](#1-capa-0-estación-de-trabajo-devops)
2. [Capa 1: Hardware Bare-Metal y Firmware BIOS](#2-capa-1-hardware-bare-metal-y-firmware-bios)
3. [Capa 2: Fabricación de Imagen Dorada (Packer, QEMU, Cloud-Init)](#3-capa-2-fabricación-de-imagen-dorada)
4. [Capa 3: Perímetro y Seguridad Base (Bastión: SSH, Squid, nftables, Chrony)](#4-capa-3-perímetro-y-seguridad-base)
5. [Capa 4: Repositorios Centrales (Sonatype Nexus 3 y PostgreSQL 16)](#5-capa-4-repositorios-centrales)
6. [Capa 5: Aprovisionamiento de Red (PXE, dnsmasq, iPXE, Nginx HTTPBoot)](#6-capa-5-aprovisionamiento-de-red)
7. [Capa 6: Gestión Bare-Metal OpenStack (Kolla, Ironic, Glance, MariaDB)](#7-capa-6-gestión-bare-metal-openstack)
8. [Capa 7: Plataforma Kubernetes HA (RKE2, etcd, Cilium eBPF, Ingress, cert-manager)](#8-capa-7-plataforma-kubernetes-ha)
9. [Capa 8: Suite de Monitoreo Host (Prometheus, Grafana, Alertmanager, Exporters)](#9-capa-8-suite-de-monitoreo-host)
10. [Capa 9: Observabilidad eBPF Distribuida (Coroot CE, ClickHouse, Node Agent)](#10-capa-9-observabilidad-ebpf-distribuida)
11. [Capa 10: Telemetría de Contenedores K8s (VictoriaMetrics, Loki, Tempo, OpenTelemetry)](#11-capa-10-telemetría-de-contenedores-k8s)
12. [Capa 11: Cargas de Trabajo y Microservicios (Redis, Python APIs, Nginx Frontend)](#12-capa-11-cargas-de-trabajo-y-microservicios)

---

## 1. Capa 0: Estación de Trabajo DevOps

Herramientas necesarias en la laptop Linux (Debian 12/13 o Ubuntu 22.04/24.04) para orquestar la flota.

### 1.1 Ansible Core (v2.17+)
* **Documentación Oficial de Instalación**: [Ansible Installation Guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
* **Instalación en la Laptop**:
  ```bash
  sudo apt-get update && sudo apt-get install -y python3-pip python3-venv git openssh-client
  python3 -m pip install --user "ansible-core>=2.17"
  ansible-galaxy collection install ansible.posix community.general
  ```
* **Verificación**:
  ```bash
  ansible --version
  ```

### 1.2 HashiCorp Packer (v1.10+)
* **Documentación Oficial de Instalación**: [Packer Install](https://developer.hashicorp.com/packer/install)
* **Instalación en la Laptop**:
  ```bash
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y packer
  packer plugins install github.com/hashicorp/qemu
  ```
* **Verificación**:
  ```bash
  packer version
  ```

### 1.3 QEMU / KVM y Herramientas de Disco
* **Documentación Oficial de Instalación**: [QEMU System Emulation](https://www.qemu.org/docs/master/system/index.html) | [Debian QEMU Wiki](https://wiki.debian.org/QEMU)
* **Instalación en la Laptop**:
  ```bash
  sudo apt-get install -y qemu-system-x86 qemu-utils ovmf cloud-image-utils
  ```
* **Verificación**:
  ```bash
  qemu-img --version && test -e /dev/kvm && echo "KVM Disponible"
  ```

### 1.4 Kubectl y OpenStackClient
* **Documentación Oficial**: [Kubectl Install](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) | [OpenStackClient](https://docs.openstack.org/python-openstackclient/latest/)
* **Instalación en la Laptop**:
  ```bash
  # Kubectl
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo apt-get update && sudo apt-get install -y kubectl
  
  # OpenStack Client
  python3 -m pip install --user python-openstackclient
  ```
* **Verificación**:
  ```bash
  kubectl version --client && openstack --version
  ```

---

## 2. Capa 1: Hardware Bare-Metal y Firmware BIOS

Configuración inicial requerida en cada uno de los 8 micro-PCs Dell OptiPlex 3020M.

* **Documentación Oficial Dell**: [Dell 3020M Manual de Servicio](https://dl.dell.com/manuals/all-products/esuprt_desktop/esuprt_optiplex_desktop/optiplex-3020-desktop_owner's%20manual3_es-mx.pdf) | [Dell UEFI Network Boot](https://www.dell.com/support/kbdoc/es-es/000143830/how-to-enable-boot-from-networks-pxe-on-uefi-boot-modes)
* **Procedimiento Físico**:
  1. Conectar teclado, monitor y cable de red en la interfaz integrada Realtek RTL8111G (`enp2s0`).
  2. Encender el equipo y presionar repetidamente **F2** para entrar al BIOS Setup.
  3. Aplicar los siguientes parámetros:
     * **System Configuration** $\rightarrow$ `Integrated NIC`: **Enabled w/PXE**
     * **System Configuration** $\rightarrow$ `SATA Operation`: **AHCI**
     * **Security** $\rightarrow$ `Secure Boot`: **Disabled**
     * **General** $\rightarrow$ `Boot Sequence`: Seleccionar **UEFI** (dejar NIC IPv4 como primer dispositivo de red).
     * **Power Management** $\rightarrow$ `AC Recovery`: **Power On** (para reencendido automático tras corte eléctrico).
     * **Power Management** $\rightarrow$ `Deep Sleep Control`: **Disabled**.
  4. Guardar cambios (F10) y reiniciar.
* **Verificación (una vez arrancado Linux)**:
  ```bash
  sudo dmidecode -s bios-version  # Retorna: A05 (o versión homologada)
  ```

---

## 3. Capa 2: Fabricación de Imagen Dorada

Generación inmutable de la imagen Debian 13 (Trixie) con agente eBPF Coroot precocinado.

* **Documentación Oficial**: [Packer QEMU Builder](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu) | [Cloud-Init NoCloud](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
* **Archivo de Configuración**: `cloud-init/packer/debian13-coroot.pkr.hcl`
* **Procedimiento de Construcción (Laptop)**:
  ```bash
  # 1. Compilación mediante QEMU acelerado por KVM
  packer build \
    -var "image_path=https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64.qcow2" \
    -var "image_checksum=file:https://cloud.debian.org/images/cloud/trixie/daily/latest/SHA512SUMS" \
    cloud-init/packer/debian13-coroot.pkr.hcl

  # 2. Compresión optimizada para transporte de red
  qemu-img convert -c -O qcow2 output-debian13-coroot/debian13-coroot.qcow2 output-debian13-coroot/debian13-coroot-compressed.qcow2
  ```
* **Verificación de la Imagen**:
  ```bash
  qemu-img check output-debian13-coroot/debian13-coroot-compressed.qcow2
  # Salida esperada: "No errors were found on the image."
  ```

---

## 4. Capa 3: Perímetro y Seguridad Base

Despliegue en el nodo Bastión (`10.100.29.10`) y configuración base en la flota.

### 4.1 Configuración Base Debian (`common`)
* **Playbook**: `ansible/playbooks/10-base/01_os_base.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml
  ```
* **Qué instala**: `sudo`, `curl`, `wget`, `jq`, `chrony`, configuración de `/etc/hosts` estática y `/etc/systemd/network/10-lan-static.network`.

### 4.2 Endurecimiento de Bastión (OpenSSH, Squid, nftables, Chrony)
* **Documentación Oficial**:
  * OpenSSH: [Mozilla OpenSSH Hardening](https://infosec.mozilla.org/guidelines/openssh.html)
  * Squid: [Squid Configuration Manual](https://www.squid-cache.org/Doc/config/)
  * nftables: [nftables Wiki Quick Reference](https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes)
  * Chrony: [Chrony Documentation](https://chrony-project.org/documentation.html)
* **Playbook**: `ansible/playbooks/10-base/02_bastion_hardening.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/02_bastion_hardening.yml
  ```
* **Verificación**:
  ```bash
  ssh -o ProxyJump=n306@192.168.29.25 aget-ic@10.100.29.10 "sudo systemctl is-active ssh squid nftables chrony"
  # Salida esperada: 4 líneas "active"
  ```

---

## 5. Capa 4: Repositorios Centrales

Despliegue en el Nodo 315 (`10.100.29.20`).

### 5.1 PostgreSQL 16
* **Documentación Oficial de Instalación**: [PostgreSQL Debian Apt](https://www.postgresql.org/download/linux/debian/)
* **Instalación Automatizada**: Integrada en `ansible/roles/nexus/tasks/main.yml`.
* **Comandos equivalentes manuales**:
  ```bash
  sudo apt-get install -y postgresql-16 postgresql-contrib python3-psycopg2
  sudo -u postgres psql -c "CREATE USER nexus WITH ENCRYPTED PASSWORD '<PASSWORD>';"
  sudo -u postgres psql -c "CREATE DATABASE nexus OWNER nexus;"
  ```

### 5.2 Sonatype Nexus 3 OSS
* **Documentación Oficial de Instalación**: [Sonatype Nexus Installation](https://help.sonatype.com/en/system-requirements.html) | [PostgreSQL Support](https://help.sonatype.com/en/configuring-nexus-repository-for-postgresql.html)
* **Playbook**: `ansible/playbooks/20-services/01_nexus.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/01_nexus.yml
  ```
* **Puertos y Servicios**:
  * `:8081` $\rightarrow$ Nexus Web UI / APT Repositories
  * `:8082` $\rightarrow$ Nexus Docker Group (Pull unificado)
  * `:8083` $\rightarrow$ Nexus Docker Hosted (Push privado)
* **Verificación**:
  ```bash
  curl -fsS -o /dev/null -w "%{http_code}\n" http://10.100.29.20:8081/service/rest/v1/status
  # Salida esperada: 200
  ```

---

## 6. Capa 5: Aprovisionamiento de Red

Despliegue en el Nodo 306 (`10.100.29.30`).

### 6.1 dnsmasq (DHCP & TFTP)
* **Documentación Oficial**: [dnsmasq Doc](https://thekelleys.org.uk/dnsmasq/doc.html) | [Debian PXE Guide](https://wiki.debian.org/HowToPXE#Dnsmasq)
* **Instalación y Configuración**:
  * Plantilla: `ansible/roles/pxe_controller/templates/dnsmasq.conf.j2`
  * Paquete: `sudo apt-get install -y dnsmasq`
  * Parámetros clave:
    * `dhcp-ignore=tag:!known` (blindaje estricto: solo entrega IP a MACs del inventario).
    * `dhcp-boot=tag:efi-x86_64,ipxe.efi`
    * `dhcp-boot=tag:ipxe,http://10.100.29.30:8089/boot.ipxe`

### 6.2 iPXE Custom Bootloader
* **Documentación Oficial**: [iPXE Build Targets](https://ipxe.org/appnote/buildtargets)
* **Compilación en Staging**:
  ```bash
  # Script nativo del repo
  sudo ./network/ipxe/compilar-ipxe-custom.sh
  ```
* **Binarios generados**: `/tftpboot/ipxe.efi` (UEFI x86_64) y `/tftpboot/undionly.kpxe` (BIOS Legacy).

### 6.3 Nginx HTTPBoot
* **Documentación Oficial**: [Nginx Serving Static Content](https://docs.nginx.com/nginx/admin-guide/web-server/serving-static-content/)
* **Playbook**: `ansible/playbooks/20-services/02_pxe_controller.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml
  ```
* **Verificación**:
  ```bash
  curl -fsI http://10.100.29.30:8089/boot.ipxe
  # Salida esperada: HTTP/1.1 200 OK
  ```

---

## 7. Capa 6: Gestión Bare-Metal OpenStack

Despliegue contenerizado en el Nodo 306 (`192.168.29.25` / `10.100.29.30`).

* **Documentación Oficial**:
  * Kolla-Ansible: [Kolla Quickstart](https://docs.openstack.org/kolla-ansible/2025.1/user/quickstart.html)
  * Ironic Bare-Metal: [Ironic Installation Guide](https://docs.openstack.org/ironic/2025.1/install/)
  * Glance: [Glance Image Service](https://docs.openstack.org/glance/2025.1/)
* **Servicios Contenerizados**: `ironic_api`, `ironic_conductor`, `ironic_inspector`, `glance_api`, `keystone`, `mariadb`, `rabbitmq`, `kolla_toolbox`.
* **Playbooks y Comandos de Despliegue**:
  ```bash
  # 1. Levantar contenedores Kolla existentes en el Nodo 306
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo docker start \$(sudo docker ps -a -q)"

  # 2. Descargar artefactos Ironic Python Agent (IPA)
  ./artifacts/download_ipa.sh

  # 3. Registrar imagen dorada en Glance
  scp -i ansible/keys/cluster_key output-debian13-coroot/debian13-coroot-compressed.qcow2 n306@192.168.29.25:/tmp/debian13-coroot.qcow2
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "source /etc/kolla/admin-openrc.sh && openstack image create debian13-coroot-lab --disk-format qcow2 --container-format bare --public --file /tmp/debian13-coroot.qcow2 && rm -f /tmp/debian13-coroot.qcow2"

  # 4. Desplegar endpoints y configuración de Ironic con Ansible
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml
  ```
* **Verificación**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "source /etc/kolla/admin-openrc.sh && openstack endpoint list --service ironic -c Enabled -f value"
  # Salida esperada: True
  ```

---

## 8. Capa 7: Plataforma Kubernetes HA

Despliegue del clúster RKE2 de 3 Control Planes (nodos 269, 280, 320) y 2 Workers (321, 279).

### 8.1 RKE2 (Rancher Kubernetes Engine 2)
* **Documentación Oficial de Instalación**: [RKE2 High Availability Installation](https://docs.rke2.io/install/ha)
* **Instalación del Binario**:
  ```bash
  curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="v1.30.2+rke2r1" sh -
  ```
* **Configuración (`/etc/rancher/rke2/config.yaml`)**:
  ```yaml
  token: "<RKE2_TOKEN_SECRETO>"
  tls-san:
    - "10.100.29.100"
    - "k8s.lab.local"
  cni: cilium
  disable:
    - rke2-canal
    - rke2-kube-proxy
  etcd-expose-metrics: true
  write-kubeconfig-mode: "0640"
  ```

### 8.2 Cilium CNI eBPF
* **Documentación Oficial de Instalación**: [Cilium without Kube-Proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
* **Parámetros Automáticos de RKE2**:
  RKE2 despliega Cilium directamente mediante HelmChart Controller al detectar `cni: cilium` y la supresión de `kube-proxy`.
* **Playbook Automatizado del Clúster**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml
  ```
* **Extracción de Kubeconfig a la Laptop**:
  ```bash
  mkdir -p ~/.kube
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "sudo cat /etc/rancher/rke2/rke2.yaml" | sed "s/127.0.0.1/10.100.29.101/g" > ~/.kube/config
  chmod 600 ~/.kube/config
  ```
* **Verificación del Clúster**:
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -n kube-system -l k8s-app=cilium
  # Salida esperada: Todos los nodos en "Ready" y pods Cilium en "Running"
  ```

---

## 9. Capa 8: Suite de Monitoreo Host

Despliegue de métricas en el host controlador (Nodo 306) y exportadores en la flota.

* **Documentación Oficial**:
  * Prometheus: [Prometheus Installation](https://prometheus.io/docs/prometheus/latest/installation/)
  * Grafana: [Grafana Debian Install](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/)
  * Node Exporter: [Node Exporter Guide](https://prometheus.io/docs/guides/node-exporter/)
  * Alertmanager: [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
  * Blackbox Exporter: [Blackbox Exporter Repo](https://github.com/prometheus/blackbox_exporter)
* **Playbook Maestro**: `ansible/playbooks/40-observability/01_monitoring.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml
  ```
* **Puertos de la Suite**:
  * `:9090` $\rightarrow$ Prometheus TSDB
  * `:3000` $\rightarrow$ Grafana Web UI
  * `:9093` $\rightarrow$ Alertmanager
  * `:9115` $\rightarrow$ Blackbox Exporter (Sondeos ICMP/HTTP)
  * `:9100` $\rightarrow$ Node Exporter (Activo en los 8 nodos)
* **Verificación**:
  ```bash
  curl -fsS http://10.100.29.30:9090/-/ready && curl -fsI http://10.100.29.30:3000/login
  ```

---

## 10. Capa 9: Observabilidad eBPF Distribuida

### 10.1 Coroot CE y ClickHouse (Servidor Central en Nodo 306)
* **Documentación Oficial**: [Coroot Docker Compose Install](https://coroot.com/docs/metric-monitoring/install/docker-compose)
* **Comando de Despliegue (Nodo 306)**:
  ```bash
  ssh -i ansible/keys/cluster_key n306@192.168.29.25 "cd /opt/coroot && sudo docker compose -f compose.yaml up -d"
  ```
* **Puerto**: `:19000` (Interfaz Web de Coroot)
* **Verificación**:
  ```bash
  curl -fsI http://192.168.29.25:19000/
  # Salida esperada: HTTP/1.1 200 OK
  ```

### 10.2 Coroot Node Agent v1.37.0 (En toda la Flota Bare-Metal)
* **Documentación Oficial**: [Coroot Node Agent Setup](https://github.com/coroot/coroot-node-agent#options)
* **Playbook**: `ansible/playbooks/40-observability/02_coroot_agent.yml`
* **Ejecución**:
  ```bash
  ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/02_coroot_agent.yml
  ```
* **Puerto**: `:10300` (Agente eBPF)
* **Verificación**:
  ```bash
  ansible baremetal -i inventory/lab/hosts.yml -m command -a "systemctl is-active coroot-node-agent"
  # Salida esperada: "active" en todos los nodos
  ```

---

## 11. Capa 10: Telemetría de Contenedores K8s

Despliegue nativo con Kustomize en el namespace `observability`.

### 11.1 VictoriaMetrics, Grafana Loki y Grafana Tempo
* **Documentación Oficial**:
  * VictoriaMetrics: [Single-Server VM](https://docs.victoriametrics.com/single-server-victoriametrics/)
  * Grafana Loki: [Loki Install](https://grafana.com/docs/loki/v3.1.x/setup/install/)
  * Grafana Tempo: [Tempo Getting Started](https://grafana.com/docs/tempo/v2.5.x/getting-started/)
* **Manifiesto**: `kubernetes/observability/backends/01_backends.yaml`
* **Despliegue**:
  ```bash
  kubectl apply -k kubernetes/observability/backends
  ```
* **Verificación**:
  ```bash
  kubectl get statefulset -n observability
  # Salida esperada: loki, tempo, victoriametrics en 1/1 READY
  ```

### 11.2 OpenTelemetry Operator y Collector
* **Documentación Oficial**: [OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator) | [Collector Config](https://opentelemetry.io/docs/collector/configuration/)
* **Manifiesto**: `kubernetes/observability/otel/02_otel_operator_and_collectors.yaml`
* **Despliegue**:
  ```bash
  kubectl apply -k kubernetes/observability/otel
  ```
* **Verificación**:
  ```bash
  kubectl get deployment -n observability otel-gateway-collector
  # Salida esperada: 2/2 READY
  ```

### 11.3 Coroot Cluster Agent
* **Documentación Oficial**: [Coroot Cluster Agent](https://github.com/coroot/coroot-cluster-agent)
* **Manifiesto**: `kubernetes/observability/coroot/03_coroot_cluster_agent.yaml`
* **Despliegue**:
  ```bash
  kubectl apply -k kubernetes/observability/coroot
  ```
* **Verificación**:
  ```bash
  kubectl get pods -n coroot
  # Salida esperada: coroot-cluster-agent en estado Running
  ```

---

## 12. Capa 11: Cargas de Trabajo y Microservicios

Despliegue de aplicaciones de demostración en el namespace `aplicaciones`.

### 12.1 Stack de Microservicios y Redis
* **Documentación Oficial**: [Redis Quickstart](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/) | [Kustomize Overlays](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/#overlays)
* **Manifiesto Kustomize**: `kubernetes/overlays/lab/kustomization.yaml`
* **Cargas de Trabajo Desplegadas**:
  * `redis:7-alpine` (Caché en memoria) con `redis_exporter`
  * `backend-api` (Python 3.11 FastAPI / OTel Instrumentado)
  * `orders-service` (Python 3.11)
  * `notifications-service` (Python 3.11)
  * `frontend-web` (Nginx 1.27-alpine)
  * `traffic-simulator` (curl worker)
* **Despliegue**:
  ```bash
  kubectl apply -k kubernetes/overlays/lab
  ```
* **Verificación**:
  ```bash
  kubectl get pods -n aplicaciones -o wide
  curl -fsS http://192.168.29.25:30080/api/v1/data
  # Salida esperada: {"status": "ok", "service": "backend-api"}
  ```

---

## 13. Matriz Rápida: Dónde Está Cada Instalador en el Repositorio

| Componente | Tipo de Instalador | Ruta Exacta en el Repo | Comando de Instalación Rápido |
| :--- | :--- | :--- | :--- |
| **Estación Cliente** | Script Bash | `scripts/client/setup-client-workstation.sh` | `./scripts/client/setup-client-workstation.sh` |
| **Imagen Dorada** | Packer HCL2 | `cloud-init/packer/debian13-coroot.pkr.hcl` | `packer build ... debian13-coroot.pkr.hcl` |
| **SO Base Flota** | Playbook Ansible | `ansible/playbooks/10-base/01_os_base.yml` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/01_os_base.yml` |
| **Bastión Perimetral** | Rol Ansible | `ansible/roles/bastion` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/10-base/02_bastion_hardening.yml` |
| **Nexus 3 & Postgres** | Rol Ansible | `ansible/roles/nexus` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/01_nexus.yml` |
| **PXE & dnsmasq** | Rol Ansible | `ansible/roles/pxe_controller` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/02_pxe_controller.yml` |
| **iPXE Custom** | Script Bash | `network/ipxe/compilar-ipxe-custom.sh` | `sudo ./network/ipxe/compilar-ipxe-custom.sh` |
| **OpenStack Ironic** | Rol Ansible | `ansible/roles/ironic` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/20-services/03_ironic_deploy.yml` |
| **ConfigDrives Baremetal** | Script Bash | `cloud-init/scripts/generate_configdrive.sh` | `./cloud-init/scripts/generate_configdrive.sh <NODO>` |
| **RKE2 Clúster HA** | Rol Ansible | `ansible/roles/rke2_ha` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml` |
| **Monitoreo Host** | Rol Ansible | `ansible/roles/monitoring` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/01_monitoring.yml` |
| **Coroot eBPF Agent** | Rol Ansible | `ansible/roles/coroot_node_agent` | `ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/40-observability/02_coroot_agent.yml` |
| **Coroot Server** | Docker Compose | `/opt/coroot/compose.yaml` (nodo 306) | `sudo docker compose -f compose.yaml up -d` |
| **Backends K8s** | Kustomize | `kubernetes/observability/backends` | `kubectl apply -k kubernetes/observability/backends` |
| **OpenTelemetry** | Kustomize | `kubernetes/observability/otel` | `kubectl apply -k kubernetes/observability/otel` |
| **Coroot K8s Agent** | Kustomize | `kubernetes/observability/coroot` | `kubectl apply -k kubernetes/observability/coroot` |
| **Microservicios** | Kustomize | `kubernetes/overlays/lab` | `kubectl apply -k kubernetes/overlays/lab` |

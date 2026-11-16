# Imagen Debian 13 con Packer y agente Coroot

La construcción y el primer arranque siguen pendientes de validación en el hardware destino. Para instalar y operar el servidor Coroot y agentes en equipos existentes, consulta [Instalar Coroot primero](instalar-coroot-primero.md). El laboratorio ya tiene Coroot en el nodo 306.

## 8. Construir una imagen con Packer

Esta sección es para **nuevas máquinas** y sirve como punto de partida para crear la receta de Packer en un directorio dedicado.

Usar una imagen Debian 13 **generic amd64**, con kernel estándar, para los Dell
bare-metal. La variante `genericcloud` utiliza un kernel con menos controladores.
Descargar desde la [infraestructura Debian](https://cloud.debian.org/images/cloud/trixie/)
y consultar sus [tipos de imágenes](https://wiki.debian.org/Cloud).

En una estación Linux de construcción con KVM, Packer y su plugin QEMU:

```bash
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-utils xorriso openssh-client curl
test -r /dev/kvm && test -w /dev/kvm
packer version
mkdir -p /tmp/coroot-image-build/seed
cd /tmp/coroot-image-build
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
sha512sum --ignore-missing --check SHA512SUMS
# Conservar imagen y manifiesto juntos. El checksum comprueba integridad;
# para verificar procedencia, validar también la firma Debian del manifiesto.
test -s debian-13-generic-amd64.qcow2
ssh-keygen -t ed25519 -N '' -f build_key
```

Crear seed exclusivo de construcción. Esta llave no es la llave de producción:

```bash
cat > seed/meta-data <<'EOF'
instance-id: packer-coroot-build
local-hostname: packer-coroot-build
EOF
cat > seed/user-data <<EOF
#cloud-config
users:
  - name: packer
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat build_key.pub)
write_files:
  - path: /etc/sudoers.d/90-packer
    permissions: '0440'
    content: |
      packer ALL=(ALL) NOPASSWD:ALL
EOF
```

Descargar el binario versionado del agente para incorporarlo como artefacto:

```bash
read -r -p 'Versión del agente, incluyendo v: ' AGENT_VERSION
[[ "$AGENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
curl -fsSL "https://github.com/coroot/coroot-node-agent/releases/download/${AGENT_VERSION}/coroot-node-agent-amd64" \
  -o coroot-node-agent
chmod 0755 coroot-node-agent
sha256sum coroot-node-agent > coroot-node-agent.sha256
```

Registrar ese checksum sirve para repetir el artefacto aprobado; no reemplaza
una firma o checksum publicado por el proveedor. Para builds posteriores,
verificar el checksum registrado antes de usar la copia almacenada en Nexus.

Crear `coroot-node-agent.service`:

```ini
[Unit]
Description=Coroot node agent (imagen del proyecto)
Wants=network-online.target
After=network-online.target
ConditionPathExists=/etc/coroot-node-agent/agent.env

[Service]
EnvironmentFile=/etc/coroot-node-agent/agent.env
ExecStart=/usr/local/bin/coroot-node-agent
Restart=always
RestartSec=5
Delegate=yes
LimitNOFILE=1048576
TasksMax=infinity

[Install]
WantedBy=multi-user.target
```

Esta unidad usa rutas diferentes al instalador de la
[guía de Coroot](instalar-coroot-primero.md). Elige un método por host.

Crear `debian13-coroot.pkr.hcl`:

```hcl
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "image_path" { type = string }
variable "image_checksum" { type = string }

source "qemu" "debian13" {
  iso_url              = var.image_path
  iso_checksum         = var.image_checksum
  disk_image           = true
  output_directory     = "output-debian13-coroot"
  vm_name              = "debian13-coroot.qcow2"
  format               = "qcow2"
  disk_size            = "20G"
  accelerator          = "kvm"
  headless             = true
  memory               = 2048
  cpus                 = 2
  disk_interface       = "virtio"
  net_device           = "virtio-net"
  cd_files             = ["seed/user-data", "seed/meta-data"]
  cd_label             = "cidata"
  ssh_username         = "packer"
  ssh_private_key_file = "build_key"
  ssh_timeout          = "15m"
  shutdown_command     = "sudo sh -c 'rm -f /home/packer/.ssh/authorized_keys /etc/sudoers.d/90-packer; usermod -s /usr/sbin/nologin packer; cloud-init clean --logs --machine-id --seed; shutdown -P now'"
}

build {
  sources = ["source.qemu.debian13"]
  provisioner "shell" {
    inline = ["sudo cloud-init status --wait"]
  }
  provisioner "file" {
    source      = "coroot-node-agent"
    destination = "/tmp/coroot-node-agent"
  }
  provisioner "file" {
    source      = "coroot-node-agent.service"
    destination = "/tmp/coroot-node-agent.service"
  }
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl",
      "sudo install -m 0755 /tmp/coroot-node-agent /usr/local/bin/coroot-node-agent",
      "sudo install -m 0644 /tmp/coroot-node-agent.service /etc/systemd/system/coroot-node-agent.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable coroot-node-agent",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /var/lib/dbus/machine-id"
    ]
  }
}
```

El servicio queda habilitado pero no arranca hasta que exista su configuración.
No se incorpora endpoint, API key ni identidad de un nodo real a la imagen.
El usuario temporal queda sin llave, sin sudo y con shell deshabilitada al apagar.
El seed `cidata` de construcción no debe adjuntarse a los nodos desplegados.
Referencia del builder: [Packer QEMU](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu).

```bash
packer init debian13-coroot.pkr.hcl
packer fmt debian13-coroot.pkr.hcl
checksum="sha512:$(sha512sum debian-13-generic-amd64.qcow2 | awk '{print $1}')"
packer validate -var "image_path=$PWD/debian-13-generic-amd64.qcow2" \
  -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
packer build -var "image_path=$PWD/debian-13-generic-amd64.qcow2" \
  -var "image_checksum=$checksum" debian13-coroot.pkr.hcl
qemu-img check output-debian13-coroot/debian13-coroot.qcow2
sha256sum output-debian13-coroot/debian13-coroot.qcow2
```

Fijar la versión concreta del plugin QEMU utilizada cuando se apruebe el build.
Este ejemplo requiere probarse con el firmware, disco y NIC de los equipos
destino; el arranque en QEMU no certifica compatibilidad bare-metal.

## 9. Primer arranque con Cloud-Init

Combinar este fragmento con el user-data que ya configura usuario, llave y red.
No crear dos claves `write_files` o `runcmd`: agregar sus elementos a las listas
existentes del `user-data` o generador realmente usado.

```yaml
#cloud-config
write_files:
  - path: /etc/coroot-node-agent/agent.env
    owner: root:root
    permissions: '0600'
    content: |
      COLLECTOR_ENDPOINT=http://10.100.29.40:19000
      SCRAPE_INTERVAL=15s
      LISTEN=127.0.0.1:19080
runcmd:
  - [systemctl, daemon-reload]
  - [systemctl, enable, --now, coroot-node-agent]
```

Si se habilita API key, inyectarla desde Vault en el despliegue; proteger también
el user-data/config-drive y eliminar las copias temporales. No servir un user-data
con secretos desde `/httpboot` sin controles de acceso. Preferir inyectar la API
key posteriormente por Ansible mediante SSH y `no_log: true`.

El proyecto tiene varios caminos de generación: plantilla Jinja y generador Bash. Cambiar la plantilla no actualiza automáticamente los
otros caminos. Aplicar el fragmento en el que se vaya a ejecutar y revisar el
user-data resultante antes de aprovisionar.

Probar una instancia nueva y verificar:

```bash
sudo cloud-init status --wait
sudo systemctl is-active coroot-node-agent
sudo journalctl -u coroot-node-agent -n 100 --no-pager
cat /etc/machine-id
hostnamectl
```

Dos clones deben tener identidad y claves SSH de host diferentes. No publicar
la imagen como aprobada si conserva la identidad o acceso del build.

## 10. Publicar en Glance y usar con Ironic

Desde una estación con cliente OpenStack y su OpenRC cargado:

```bash
openstack token issue -c expires -f value
openstack image create debian13-coroot-lab \
  --disk-format qcow2 --container-format bare --private \
  --file output-debian13-coroot/debian13-coroot.qcow2
openstack image show debian13-coroot-lab -c id -c status -c size
```

El cliente debe poder leer esa ruta local. Si se ejecuta dentro de `kolla_toolbox`,
primero copiar la imagen al contenedor o montar su directorio de forma explícita.

Selecciona explícitamente un equipo de prueba y sigue los pasos de validación
de Ironic antes de usar esta imagen en hardware.
[Guía de aprovisionamiento físico](../../GUIA_OPENSTACK.md)

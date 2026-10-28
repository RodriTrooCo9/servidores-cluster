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

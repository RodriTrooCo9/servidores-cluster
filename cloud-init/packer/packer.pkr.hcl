packer {
  required_version = ">= 1.8.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "nexus_ip" {
  type    = string
  default = "10.100.29.20"
}

variable "admin_user" {
  type    = string
  default = "debian"
}

source "qemu" "debian_baremetal" {
  iso_url          = "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso"
  iso_checksum     = "none"
  output_directory = "output-debian"
  vm_name          = "debian-13-baremetal.qcow2"
  disk_size        = "20G"
  format           = "qcow2"
  disk_interface   = "virtio"
  cpus             = 2
  memory           = 2048
  accelerator      = "kvm"
  headless         = true
  ssh_username     = var.admin_user
  ssh_password     = "temporaryPackerPass2026!"
  ssh_timeout      = "20m"
  boot_wait        = "5s"
  boot_command = [
    "<esc><wait>",
    "install auto=true priority=critical preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]
}

build {
  sources = ["source.qemu.debian_baremetal"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y cloud-init cloud-initramfs-growpart gdisk curl openssh-server",
      "sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo cloud-init clean --logs"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "mkdir -p /httpboot/images",
      "cp output-debian/debian-13-baremetal.qcow2 /httpboot/images/",
      "sha256sum /httpboot/images/debian-13-baremetal.qcow2 > /httpboot/images/debian-13-baremetal.qcow2.sha256",
      "rm -rf output-debian"
    ]
  }
}

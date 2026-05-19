packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.0"
    }
  }
}

variable "ubuntu_version" {
  type    = string
  default = "24.04"
}

locals {
  iso_checksums = {
    "24.04" = "5c3ddb00f60bc455dac0862fabe9d8bacec46c33ac1751143c5c3683404b110d" # Ubuntu 24.04 Cloud (проверьте актуальную)
  }
  iso_urls = {
    "24.04" = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  }
}

source "qemu" "ubuntu" {
  vm_name = "k8s-${var.ubuntu_version}-custom.qcow2"

  disk_image   = true
  iso_url      = local.iso_urls[var.ubuntu_version]
  iso_checksum = "sha256:${local.iso_checksums[var.ubuntu_version]}"

  # Параметры системы
  memory           = 2048
  cpus             = 2
  accelerator      = "kvm"
  disk_size        = "20G"
  disk_compression = true
  format           = "qcow2"

  # Настройка загрузки и cloud-init
  # Мы смонтируем ISO-диск с данными cloud-init
  cd_files = ["./cloud-init/user-data", "./cloud-init/meta-data"]
  cd_label = "cidata"

  ssh_username     = "ubuntu"
  ssh_password     = "packer"
  ssh_timeout      = "10m"
  shutdown_command = "sudo cloud-init clean --logs --machine-id && sudo shutdown -P now"

  boot_wait  = "5s"
  headless   = false # Ставьте true если не нужен GUI
  net_device = "virtio-net"
}

build {
  sources = ["source.qemu.ubuntu"]

  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done",
      "sudo cloud-init status --wait || true",
      "echo '=== cloud-init status --long ==='",
      "sudo cloud-init status --long || true",
      "echo '=== /var/log/cloud-init-output.log (last 30 lines) ==='",
      "sudo tail -30 /var/log/cloud-init-output.log"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y qemu-guest-agent ansible",
      "sudo systemctl enable qemu-guest-agent"
    ]
  }

  provisioner "ansible-local" {
    playbook_file = "../playbook.yml"
    playbook_dir  = ".."
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",
      "sudo fstrim -v / || true",
      "sudo dd if=/dev/zero of=/zerofill bs=1M 2>/dev/null || true",
      "sudo rm -f /zerofill"
    ]
  }
}
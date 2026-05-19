# Указываем необходимые плагины
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.0"
    }
  }
}

# Переменные для версии Ubuntu
variable "ubuntu_version" {
  type    = string
  default = "24.04"
}

locals {
  # Проверяем контрольную сумму для скачиваемого ISO/образа
  iso_checksums = {
    "24.04" = "5c3ddb00f60bc455dac0862fabe9d8bacec46c33ac1751143c5c3683404b110d" # Ubuntu 24.04 Cloud (проверьте актуальную)
  }
  iso_urls = {
    "24.04" = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  }
}

source "qemu" "ubuntu" {
  # Название итогового файла
  vm_name = "ubuntu-${var.ubuntu_version}-custom.qcow2"

  # Указываем, что мы используем готовый образ диска, а не установочный ISO
  disk_image   = true
  iso_url      = local.iso_urls[var.ubuntu_version]
  iso_checksum = "sha256:${local.iso_checksums[var.ubuntu_version]}"

  # Параметры системы
  memory           = 2048
  accelerator      = "kvm" # Ускоритель. Если не работает KVM, ставьте "tcg"
  disk_size        = "10G"
  disk_compression = true
  format           = "qcow2" # Явно указываем формат вывода

  # Настройка загрузки и cloud-init
  # Мы смонтируем ISO-диск с данными cloud-init
  cd_files = ["./cloud-init/user-data", "./cloud-init/meta-data"]
  cd_label = "cidata"

  # Настройки подключения (SSH)
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

  # Ждем, пока cloud-init завершит первичную настройку внутри ВМ
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 5; done",
      "sudo cloud-init status --wait"
    ]
  }

  # Пример: обновляем пакеты и устанавливаем свой софт
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y qemu-guest-agent curl",
      "sudo systemctl enable qemu-guest-agent"
    ]
  }
}
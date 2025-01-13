#This Terraform configuration file defines a set of virtual machines (VMs) to be created in a Proxmox virtual environment.
resource "proxmox_virtual_environment_vm" "talos_cp" {
  for_each    = { for idx in range(var.num_control_planes) : idx => idx }
  name        = "tls-cp-0${each.key + 1}"
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = var.prx_node
  on_boot     = true

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr1"
  }

  disk {
    datastore_id = "local-btrfs"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = 20
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-btrfs"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each    = { for idx in range(var.num_workers) : idx => idx }
  depends_on  = [proxmox_virtual_environment_vm.talos_cp]
  name        = "tls-wr-0${each.key + 1}"
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = var.prx_node
  on_boot     = true

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr1"
  }

  disk {
    datastore_id = "local-btrfs"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = 20
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-btrfs"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}
# Storage VM: Debian 13 with Garage + Zot, configured via cloud-init.
# Two disks: system (small, OS), data (large, /var/lib/storage for blobs and metadata).

resource "proxmox_virtual_environment_vm" "storage" {
  name        = var.hostname
  description = "Storage host (Garage + Zot), managed by Terraform"
  tags        = ["terraform", "storage", "garage", "zot"]
  node_name   = var.prx_node
  on_boot     = true

  cpu {
    cores = var.vm_resources.cores
    type  = "host"
  }

  memory {
    dedicated = var.vm_resources.memory_mb
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = var.prx_network_bridge
  }

  # System disk — root filesystem from the Debian cloud image.
  disk {
    datastore_id = var.prx_datastore_vm
    file_id      = proxmox_virtual_environment_download_file.debian_cloud.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = var.vm_resources.system_disk_gb
  }

  # Data disk — gets mounted at /var/lib/storage by cloud-init (XFS, label "storage").
  disk {
    datastore_id = var.prx_datastore_vm
    file_format  = "raw"
    interface    = "virtio1"
    size         = var.vm_resources.data_disk_gb
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id      = var.prx_datastore_vm
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
    meta_data_file_id = proxmox_virtual_environment_file.cloud_meta.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # The image URL embeds the Debian version; bumping it should not recreate the VM.
      # Upgrades are done in-place via apt.
      disk[0].file_id,
    ]
  }
}

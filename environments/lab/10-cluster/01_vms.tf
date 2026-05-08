# Proxmox VMs for Talos control-plane and worker nodes.
# VM name == Talos hostname == dnsmasq DNS record:  <vm_name>.<dns_domain>
# Hostname is set in machineconfig (see 02_talos.tf); Talos sends it in DHCP option 12.

locals {
  cp_node_names     = [for i in range(var.num_control_planes) : format("tls-cp-%02d", i + 1)]
  worker_node_names = [for i in range(var.num_workers) : format("tls-wr-%02d", i + 1)]

  cp_fqdns     = [for n in local.cp_node_names : "${n}.${var.dns_domain}"]
  worker_fqdns = [for n in local.worker_node_names : "${n}.${var.dns_domain}"]
}

resource "proxmox_virtual_environment_vm" "talos_cp" {
  for_each = { for i, n in local.cp_node_names : n => i }

  name        = each.key
  description = "Talos control-plane, managed by Terraform"
  tags        = ["terraform", "talos", "control-plane", var.cluster_name]
  node_name   = var.prx_node
  on_boot     = true

  cpu {
    cores = var.cp_resources.cores
    type  = "host"
  }

  memory {
    dedicated = var.cp_resources.memory_mb
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = var.prx_network_bridge
  }

  disk {
    datastore_id = var.prx_datastore_vm
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = var.cp_resources.disk_gb
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.prx_datastore_vm
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
      # The Talos image URL embeds the version — we don't want VM recreation on a version bump.
      # Talos version upgrades are done via talos_machine_configuration_apply (in-place upgrade).
      disk[0].file_id,
    ]
  }
}

# Worker — same logic as cp, just different resources. See the disk[0].file_id comment above.
resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each = { for i, n in local.worker_node_names : n => i }

  # No explicit depends_on — Proxmox creates CP and worker VMs in parallel, which speeds up apply.

  name        = each.key
  description = "Talos worker, managed by Terraform"
  tags        = ["terraform", "talos", "worker", var.cluster_name]
  node_name   = var.prx_node
  on_boot     = true

  cpu {
    cores = var.worker_resources.cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_resources.memory_mb
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = var.prx_network_bridge
  }

  disk {
    datastore_id = var.prx_datastore_vm
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = var.worker_resources.disk_gb
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.prx_datastore_vm
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
      disk[0].file_id,
    ]
  }
}

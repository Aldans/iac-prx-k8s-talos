# Storage stack — Garage + Zot on a single Proxmox VM. Delegated to modules/storage.
# See ../../../modules/storage/README.md for the design and behaviour.

module "storage" {
  source = "../../../modules/storage"

  prx_node            = var.prx_node
  prx_datastore_image = var.prx_datastore_image
  prx_datastore_vm    = var.prx_datastore_vm
  prx_network_bridge  = var.prx_network_bridge

  dns_domain = var.dns_domain
  hostname   = var.hostname

  vm_resources = var.vm_resources

  debian_image_url = var.debian_image_url
  garage_version   = var.garage_version
  zot_version      = var.zot_version

  garage_buckets            = var.garage_buckets
  garage_state_bucket       = var.garage_state_bucket
  garage_oci_bucket         = var.garage_oci_bucket
  garage_replication_factor = var.garage_replication_factor

  admin_ssh_pubkey = var.admin_ssh_pubkey
}

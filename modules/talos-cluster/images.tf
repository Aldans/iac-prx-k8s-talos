# Talos nocloud image, downloaded from factory.talos.dev into the specified Proxmox datastore.
# Schematic ID is a hash of the system-extensions bundle (qemu-guest-agent is required).
#
# `overwrite = false` keeps Proxmox from re-downloading an image that already exists.
# `prevent_destroy = true` means `terraform destroy` will NOT remove the image — saving
# the multi-minute re-download on the next apply. A version bump (var.talos_version)
# re-downloads transparently because the file_name changes.

locals {
  talos_image_url = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/nocloud-amd64.raw.gz"
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  content_type            = "iso"
  datastore_id            = var.prx_datastore_image
  node_name               = var.prx_node
  file_name               = "talos-${var.talos_version}-nocloud-amd64.img"
  url                     = local.talos_image_url
  decompression_algorithm = "gz"
  overwrite               = false

  lifecycle {
    prevent_destroy = true
  }
}

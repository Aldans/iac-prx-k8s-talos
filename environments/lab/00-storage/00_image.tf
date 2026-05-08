# Debian cloud image used as the base for the storage VM.
#
# `overwrite = false` keeps Proxmox from re-downloading an image that already
# exists in the datastore.
# `prevent_destroy = true` means `terraform destroy` will NOT remove the image
# — saving the multi-minute re-download on every cycle.
#
# To actually delete the image: temporarily comment out the lifecycle block
# (or run `terraform state rm proxmox_virtual_environment_download_file.debian_cloud`),
# then destroy or remove it manually from Proxmox storage.

resource "proxmox_virtual_environment_download_file" "debian_cloud" {
  content_type            = "iso"
  datastore_id            = var.prx_datastore_image
  node_name               = var.prx_node
  file_name               = "debian-13-genericcloud-amd64.img"
  url                     = var.debian_image_url
  decompression_algorithm = null
  overwrite               = false

  lifecycle {
    prevent_destroy = true
  }
}

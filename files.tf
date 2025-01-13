locals {
  talos = {
    version = "v1.9.1"
    #image_id = "79eba9197a2e536e3cdcc6d1c65ea601db3ce267cf3b7bf7c19c35e42d921e77"
    #image_id = "86867748ba095188590b4131440b3fe98c22d0d8b40f774118c8e10b0e68a131"
    image_id = "a94b8fd8d150036c370a87ff93f97d32363eb775780ec96596dd0f01a541b146" # amddrv,qemuAgent
    name = "nocloud-amd64.raw.gz"
  }
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  content_type            = "iso"
  datastore_id            = "local-btrfs"
  node_name               = "${var.prx_node}"
  file_name               = "talos-${local.talos.version}-nocloud-amd64.img"
  url                     = "https://factory.talos.dev/image/${local.talos.image_id}/${local.talos.version}/${local.talos.name}"
  decompression_algorithm = "gz"
  overwrite               = false
}

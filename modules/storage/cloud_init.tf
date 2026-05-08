# Render the cloud-init YAML and upload it as a Proxmox snippet.
# The VM in vm.tf attaches it as user_data + meta_data.

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = var.prx_datastore_image
  node_name    = var.prx_node

  source_raw {
    file_name = "${var.hostname}-cloud-init.yaml"
    data = templatefile("${path.module}/templates/cloud-config.yaml.tftpl", {
      hostname                  = var.hostname
      fqdn                      = local.fqdn
      admin_ssh_pubkey          = var.admin_ssh_pubkey
      garage_version            = var.garage_version
      zot_version               = var.zot_version
      garage_rpc_secret         = random_id.garage_rpc_secret.hex
      garage_replication_factor = var.garage_replication_factor
      garage_access_key_id      = local.garage_access_key_id
      garage_secret_access_key  = local.garage_secret_access_key
      garage_buckets            = var.garage_buckets
      garage_oci_bucket         = var.garage_oci_bucket
      zot_cert_pem              = tls_self_signed_cert.zot.cert_pem
      zot_key_pem               = tls_private_key.zot.private_key_pem
    })
  }
}

# Cloud-init meta-data with local-hostname.
# When user_data_file_id is set, bpg/proxmox does NOT auto-populate local-hostname
# in the cidata meta-data — leaving cloud-init to think the hostname is "localhost",
# which is then sent in DHCP option 12 BEFORE our user-data fires `hostname:` directive.
# Result: dnsmasq never registers the VM under <hostname>.<dns_domain>.
# We fix it by providing meta-data ourselves with local-hostname filled in.
resource "proxmox_virtual_environment_file" "cloud_meta" {
  content_type = "snippets"
  datastore_id = var.prx_datastore_image
  node_name    = var.prx_node

  source_raw {
    file_name = "${var.hostname}-meta-data.yaml"
    data      = <<-YAML
      instance-id: ${var.hostname}
      local-hostname: ${var.hostname}
    YAML
  }
}

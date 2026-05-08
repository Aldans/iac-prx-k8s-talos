# State-migration declarations for the Phase 2 modularization.
# See ../10-cluster/moved.tf for the same pattern in the cluster stack.

# ───────── Round 2.4 — modules/storage ─────────

moved {
  from = proxmox_virtual_environment_download_file.debian_cloud
  to   = module.storage.proxmox_virtual_environment_download_file.debian_cloud
}

moved {
  from = random_id.garage_rpc_secret
  to   = module.storage.random_id.garage_rpc_secret
}

moved {
  from = random_id.garage_access_key_id_suffix
  to   = module.storage.random_id.garage_access_key_id_suffix
}

moved {
  from = random_id.garage_secret_access_key
  to   = module.storage.random_id.garage_secret_access_key
}

moved {
  from = tls_private_key.zot
  to   = module.storage.tls_private_key.zot
}

moved {
  from = tls_self_signed_cert.zot
  to   = module.storage.tls_self_signed_cert.zot
}

moved {
  from = proxmox_virtual_environment_file.cloud_config
  to   = module.storage.proxmox_virtual_environment_file.cloud_config
}

moved {
  from = proxmox_virtual_environment_file.cloud_meta
  to   = module.storage.proxmox_virtual_environment_file.cloud_meta
}

moved {
  from = proxmox_virtual_environment_vm.storage
  to   = module.storage.proxmox_virtual_environment_vm.storage
}

# State-migration declarations for the Phase 2 modularization.
#
# Every `moved {}` block tells Terraform that a resource previously addressed at the
# `from` location now lives at the `to` location — Terraform updates state without
# destroy/recreate. After a few applies, when state is fully settled, these blocks
# can be deleted.
#
# Reference: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring

# ───────── Round 2.1 — modules/cilium ─────────

moved {
  from = null_resource.wait_apiserver
  to   = module.cilium.null_resource.wait_apiserver
}

moved {
  from = helm_release.cilium
  to   = module.cilium.helm_release.cilium
}

# ───────── Round 2.2 — modules/flux-bootstrap ─────────

moved {
  from = tls_private_key.flux
  to   = module.flux_bootstrap.tls_private_key.flux
}

moved {
  from = github_repository.flux
  to   = module.flux_bootstrap.github_repository.flux
}

moved {
  from = github_repository_deploy_key.flux
  to   = module.flux_bootstrap.github_repository_deploy_key.flux
}

moved {
  from = flux_bootstrap_git.this
  to   = module.flux_bootstrap.flux_bootstrap_git.this
}

# ───────── Round 2.3 — modules/talos-cluster ─────────

moved {
  from = proxmox_virtual_environment_download_file.talos_nocloud_image
  to   = module.talos_cluster.proxmox_virtual_environment_download_file.talos_nocloud_image
}

moved {
  from = proxmox_virtual_environment_vm.talos_cp
  to   = module.talos_cluster.proxmox_virtual_environment_vm.talos_cp
}

moved {
  from = proxmox_virtual_environment_vm.talos_worker
  to   = module.talos_cluster.proxmox_virtual_environment_vm.talos_worker
}

moved {
  from = talos_machine_secrets.this
  to   = module.talos_cluster.talos_machine_secrets.this
}

moved {
  from = talos_machine_configuration_apply.cp
  to   = module.talos_cluster.talos_machine_configuration_apply.cp
}

moved {
  from = talos_machine_configuration_apply.worker
  to   = module.talos_cluster.talos_machine_configuration_apply.worker
}

moved {
  from = talos_machine_bootstrap.this
  to   = module.talos_cluster.talos_machine_bootstrap.this
}

moved {
  from = talos_cluster_kubeconfig.this
  to   = module.talos_cluster.talos_cluster_kubeconfig.this
}

moved {
  from = local_file.kubeconfig
  to   = module.talos_cluster.local_file.kubeconfig
}

moved {
  from = local_file.talosconfig
  to   = module.talos_cluster.local_file.talosconfig
}

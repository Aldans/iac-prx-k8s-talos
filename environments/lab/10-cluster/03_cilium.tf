# Cilium CNI — delegated to modules/cilium.
# See ../../../modules/cilium/README.md for the design and behaviour.

module "cilium" {
  source = "../../../modules/cilium"

  cluster_name   = var.cluster_name
  cilium_version = var.cilium_version
  pod_cidr       = var.pod_cidr
  cilium_devices = var.cilium_devices

  # The kubeconfig produced by talos_cluster_kubeconfig (see 02_talos.tf).
  # When local_file.kubeconfig is regenerated (e.g. var.dns_domain changes),
  # content_sha256 changes → wait_apiserver re-runs.
  kubeconfig_path = local_file.kubeconfig.filename
  kubeconfig_sha  = local_file.kubeconfig.content_sha256

  # The kubeconfig_path/_sha inputs already create implicit deps on local_file
  # and talos_cluster_kubeconfig. We additionally hold the module back until the
  # control-plane is fully bootstrapped so Cilium does not race a half-up cluster.
  depends_on = [
    talos_machine_configuration_apply.cp,
    talos_machine_configuration_apply.worker,
    talos_machine_bootstrap.this,
  ]
}

# Flux CD bootstrap — delegated to modules/flux-bootstrap.
# See ../../../modules/flux-bootstrap/README.md for the design and behaviour.

module "flux_bootstrap" {
  source = "../../../modules/flux-bootstrap"

  cluster_name = var.cluster_name
  github_repo  = var.github_repo
  flux_path    = var.flux_path

  # Apply order: bootstrap only after Cilium is healthy (CNI required for the
  # source-controller pods) and the cluster has reported healthy.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    data.talos_cluster_health.this,
  ]
}

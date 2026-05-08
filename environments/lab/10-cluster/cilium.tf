# Cilium CNI — delegated to modules/cilium.
# See ../../../modules/cilium/README.md for the design and behaviour.

module "cilium" {
  source = "../../../modules/cilium"

  cluster_name   = var.cluster_name
  cilium_version = var.cilium_version
  pod_cidr       = var.pod_cidr
  cilium_devices = var.cilium_devices

  # Cilium serves `kind: Ingress` itself — no ingress-nginx in this cluster.
  # The LB service it creates picks up its IP from CiliumLoadBalancerIPPool
  # (managed in home-lab-flux/infrastructure/controllers/cilium-lb).
  ingress_enabled = var.cilium_ingress_enabled

  # Cilium agents ARP-announce LB IPs from the IP pool (scoped via
  # CiliumL2AnnouncementPolicy in the Flux repo). Without this the
  # cilium-ingress LB has an EXTERNAL-IP but no one resolves it.
  l2_announcements_enabled = var.cilium_l2_announcements_enabled

  # Kubeconfig from the talos-cluster module. content_sha256 changes when the
  # config is regenerated (e.g. var.dns_domain change → new cluster_endpoint),
  # which retriggers cilium's wait_apiserver provisioner.
  kubeconfig_path = module.talos_cluster.kubeconfig_path
  kubeconfig_sha  = module.talos_cluster.kubeconfig_sha

  # depends_on = [module.talos_cluster] is implicit through the kubeconfig_*
  # inputs, but listed for documentation and to gate intra-module resources too.
  depends_on = [module.talos_cluster]
}

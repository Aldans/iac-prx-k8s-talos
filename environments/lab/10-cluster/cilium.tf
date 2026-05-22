# Cilium CNI — delegated to modules/cilium.
# See ../../../modules/cilium/README.md for the design and behaviour.

module "cilium" {
  source = "../../../modules/cilium"

  cluster_name   = var.cluster_name
  cilium_version = var.cilium_version
  pod_cidr       = var.pod_cidr
  cilium_devices = var.cilium_devices

  # Classic Ingress controller — disabled in favour of Gateway API below.
  # Keep var-level toggle so a different env can pick the other side.
  ingress_enabled = var.cilium_ingress_enabled

  # Gateway API native support. Requires Gateway API CRDs (installed via
  # home-lab-flux/infrastructure/controllers/gateway-api-crds/). Cilium
  # creates `cilium` GatewayClass automatically when this flips on.
  gateway_api_enabled = var.cilium_gateway_api_enabled

  # Cilium agents ARP-announce LB IPs from the IP pool (scoped via
  # CiliumL2AnnouncementPolicy in the Flux repo). Without this the
  # cilium-ingress / cilium-gateway LB has an EXTERNAL-IP but no one resolves it.
  l2_announcements_enabled = var.cilium_l2_announcements_enabled

  # Phase 2 observability: expose Cilium + Hubble Prometheus metrics and render
  # their ServiceMonitor objects. The Prometheus Operator CRDs must already be
  # in the cluster (Flux: infrastructure/controllers/prometheus-operator-crds)
  # — they are. Flipping this rolls the Cilium data plane (null_resource
  # .cilium_rollout) — a brief CNI + Gateway blip, plan for a maintenance window.
  monitoring_enabled = var.enable_monitoring

  # Kubeconfig from the talos-cluster module. content_sha256 changes when the
  # config is regenerated (e.g. var.dns_domain change → new cluster_endpoint),
  # which retriggers cilium's wait_apiserver provisioner.
  kubeconfig_path = module.talos_cluster.kubeconfig_path
  kubeconfig_sha  = module.talos_cluster.kubeconfig_sha

  # depends_on = [module.talos_cluster] is implicit through the kubeconfig_*
  # inputs, but listed for documentation and to gate intra-module resources too.
  depends_on = [module.talos_cluster]
}

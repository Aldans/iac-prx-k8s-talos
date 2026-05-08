# Stack-level resources that don't fit cleanly into a single module — they wire
# multiple modules together at runtime.

# Final cluster-health check — runs AFTER Cilium because nodes never become Ready
# without a CNI, so this would deadlock if scheduled before Cilium.
#
# IMPORTANT: provider siderolabs/talos 0.7.1 parses control_plane_nodes /
# worker_nodes / endpoints of this data source through netip.ParseAddr — IPs only,
# NOT FQDNs (unlike talos_client_configuration where FQDN works). Hence we pass IPs.
data "talos_cluster_health" "this" {
  depends_on = [
    module.cilium,
    module.talos_cluster,
  ]

  client_configuration = module.talos_cluster.client_configuration
  endpoints            = values(module.talos_cluster.control_plane_initial_ips)
  control_plane_nodes  = values(module.talos_cluster.control_plane_initial_ips)
  worker_nodes         = values(module.talos_cluster.worker_initial_ips)

  timeouts = {
    read = "10m"
  }
}

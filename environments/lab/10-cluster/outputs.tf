###############################################################################
# Cluster credentials
###############################################################################

output "talosconfig" {
  description = "Talos client config (for talosctl). Also written to ./talosconfig."
  value       = module.talos_cluster.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig (for kubectl). Also written to ./kubeconfig."
  value       = module.talos_cluster.kubeconfig
  sensitive   = true
}

###############################################################################
# Cluster topology
###############################################################################

output "cluster_name" {
  description = "Cluster name."
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint (FQDN)."
  value       = module.talos_cluster.cluster_endpoint
}

output "control_plane_fqdns" {
  description = "FQDNs of all control-plane nodes."
  value       = module.talos_cluster.control_plane_fqdns
}

output "worker_fqdns" {
  description = "FQDNs of all worker nodes."
  value       = module.talos_cluster.worker_fqdns
}

output "control_plane_initial_ips" {
  description = "Initial IPs of CP nodes (from qemu-agent, before DNS settles). Handy for debugging the first apply."
  value       = module.talos_cluster.control_plane_initial_ips
}

output "worker_initial_ips" {
  description = "Initial IPs of worker nodes."
  value       = module.talos_cluster.worker_initial_ips
}

###############################################################################
# Flux / GitOps
###############################################################################

output "flux_repository_url" {
  description = "URL of the Git repository Flux watches."
  value       = module.flux_bootstrap.repository_url
}

output "flux_repository_ssh_url" {
  description = "SSH URL used by Flux for git operations."
  value       = module.flux_bootstrap.repository_ssh_url
}

output "flux_path" {
  description = "Path inside the repository that Flux watches."
  value       = module.flux_bootstrap.flux_path
}

###############################################################################
# Cloudflare Tunnel
###############################################################################

output "cloudflare_tunnel_id" {
  description = "UUID of the Cloudflare Tunnel — same value the cloudflared Deployment reads via the TUNNEL_ID ConfigMap."
  value       = module.cloudflare_tunnel.tunnel_id
}

output "cloudflare_tunnel_cname_target" {
  description = "Tunnel CNAME target (<tunnel-id>.cfargotunnel.com). Point extra DNS records here to route additional zones into the tunnel."
  value       = module.cloudflare_tunnel.tunnel_cname_target
}

output "public_apps" {
  description = "FQDN → CF Access status map for all apps exposed via the tunnel."
  value = {
    hubble = {
      fqdn   = module.app_hubble.fqdn
      access = module.app_hubble.access_enabled
    }
    grafana = {
      fqdn   = module.app_grafana.fqdn
      access = module.app_grafana.access_enabled
    }
  }
}

###############################################################################
# Monitoring (Phase 2)
###############################################################################

output "grafana_admin_password" {
  description = "Generated Grafana admin password (user: admin). Retrieve with: terraform output -raw grafana_admin_password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

###############################################################################
# Persistent storage (Proxmox CCM + CSI)
###############################################################################

output "proxmox_csi_namespace" {
  description = "Namespace holding the shared Proxmox config Secret. The CCM + CSI HelmReleases (Flux) deploy here. Null when enable_proxmox_csi = false."
  value       = one(module.proxmox_csi[*].namespace)
}

output "proxmox_csi_config_secret_name" {
  description = "Name of the shared Proxmox config Secret. Wire as existingConfigSecret in the CCM and CSI HelmReleases. Null when enable_proxmox_csi = false."
  value       = one(module.proxmox_csi[*].config_secret_name)
}

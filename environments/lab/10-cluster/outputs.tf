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

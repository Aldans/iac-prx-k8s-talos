###############################################################################
# Cluster credentials
###############################################################################

output "talosconfig" {
  description = "Talos client config (for talosctl). Also written to ./talosconfig."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig (for kubectl). Also written to ./kubeconfig."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
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
  value       = local.cluster_endpoint
}

output "control_plane_fqdns" {
  description = "FQDNs of all control-plane nodes."
  value       = local.cp_fqdns
}

output "worker_fqdns" {
  description = "FQDNs of all worker nodes."
  value       = local.worker_fqdns
}

output "control_plane_initial_ips" {
  description = "Initial IPs of CP nodes (from qemu-agent, before DNS settles). Handy for debugging the first apply."
  value       = local.cp_initial_ips
}

output "worker_initial_ips" {
  description = "Initial IPs of worker nodes."
  value       = local.worker_initial_ips
}

###############################################################################
# Flux / GitOps
###############################################################################

output "flux_repository_url" {
  description = "URL of the Git repository Flux watches."
  value       = github_repository.flux.html_url
}

output "flux_repository_ssh_url" {
  description = "SSH URL used by Flux for git operations."
  value       = github_repository.flux.ssh_clone_url
}

output "flux_path" {
  description = "Path inside the repository that Flux watches."
  value       = local.flux_path
}

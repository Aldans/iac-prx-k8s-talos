###############################################################################
# Cluster identity
###############################################################################

output "cluster_endpoint" {
  description = "API server endpoint as written into kubeconfig — https://<first-cp>.<dns>:6443."
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
  description = "Initial IPs of CP nodes (from qemu-agent, before DNS settles). Map of name → IP."
  value       = local.cp_initial_ips
}

output "worker_initial_ips" {
  description = "Initial IPs of worker nodes. Map of name → IP."
  value       = local.worker_initial_ips
}

###############################################################################
# Credentials (sensitive)
###############################################################################

output "kubeconfig" {
  description = "Kubeconfig (raw YAML) for kubectl."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client config (raw YAML) for talosctl."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client_configuration object — needed by data.talos_cluster_health and other Talos data sources at the parent."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

###############################################################################
# Local files
###############################################################################

output "kubeconfig_path" {
  description = "Filesystem path of the local kubeconfig file written by this module. Consumers (cilium / flux modules, provider configs) reference this."
  value       = local_file.kubeconfig.filename
}

output "talosconfig_path" {
  description = "Filesystem path of the local talosconfig file."
  value       = local_file.talosconfig.filename
}

output "kubeconfig_sha" {
  description = "SHA-256 of the kubeconfig — useful as a trigger for downstream provisioners (e.g. cilium's wait_apiserver) so they re-run when kubeconfig changes."
  value       = local_file.kubeconfig.content_sha256
}

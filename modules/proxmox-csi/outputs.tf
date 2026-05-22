output "namespace" {
  description = "Namespace holding the shared Proxmox config Secret. The CCM and CSI HelmReleases (Flux) must be deployed here."
  value       = var.kubernetes_namespace
}

output "config_secret_name" {
  description = "Name of the Secret carrying config.yaml — wire it into the `existingConfigSecret` value of both the CCM and CSI HelmReleases."
  value       = kubernetes_secret.proxmox_config.metadata[0].name
}

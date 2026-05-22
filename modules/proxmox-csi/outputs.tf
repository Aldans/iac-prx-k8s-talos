output "namespace" {
  description = "Namespace holding the shared Proxmox config Secret. The CCM and CSI HelmReleases (Flux) must be deployed here."
  value       = var.kubernetes_namespace
}

output "config_secret_name" {
  description = "Name of the config.yaml Secret — identical in every namespace it is created in (csi-proxmox, kube-system). Wire it into the `existingConfigSecret` value of both the CCM and CSI HelmReleases."
  value       = var.config_secret_name
}

output "helm_release_id" {
  description = "ID of the Cilium Helm release. Useful as a depends_on hook for resources that must run only after Cilium is ready (e.g. talos_cluster_health, flux_bootstrap_git)."
  value       = helm_release.cilium.id
}

output "namespace" {
  description = "Kubernetes namespace Cilium is installed into."
  value       = helm_release.cilium.namespace
}

output "version" {
  description = "Cilium chart version actually applied."
  value       = helm_release.cilium.version
}

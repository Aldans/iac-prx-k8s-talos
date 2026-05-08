output "private_key_pem" {
  description = "PEM-encoded private key for the Flux SSH deploy key. Consumed by the parent's `provider \"flux\"` config (`git.ssh.private_key`)."
  value       = tls_private_key.flux.private_key_pem
  sensitive   = true
}

output "repository_url" {
  description = "HTML URL of the GitOps repository on GitHub."
  value       = github_repository.flux.html_url
}

output "repository_ssh_url" {
  description = "SSH clone URL of the GitOps repository — what Flux uses to pull manifests."
  value       = github_repository.flux.ssh_clone_url
}

output "repository_full_name" {
  description = "<owner>/<repo> — the canonical GitHub identifier."
  value       = github_repository.flux.full_name
}

output "flux_path" {
  description = "Path inside the GitOps repository that Flux watches."
  value       = local.flux_path
}

output "bootstrap_id" {
  description = "ID of the flux_bootstrap_git resource. Useful as a depends_on anchor for downstream resources that should run only after Flux is bootstrapped (e.g. seeding apps via github_repository_file)."
  value       = flux_bootstrap_git.this.id
}

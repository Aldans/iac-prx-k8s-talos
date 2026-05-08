# Flux CD — bootstrap from Terraform.
#
# Pipeline:
#   1. Generate an ECDSA key pair for the Flux ↔ GitHub SSH session.
#   2. Create a private GitHub repository ${var.github_owner}/${var.github_repo}.
#      auto_init=true creates the initial commit and main branch — without it, SSH clone fails.
#   3. Register the public key as a deploy key with write access
#      (write is needed for Flux Image Automation later; if you don't need it, set read_only=true).
#   4. flux_bootstrap_git installs Flux controllers into the cluster,
#      pushes the gotk-* manifests into clusters/<cluster_name>/flux-system/ in the repo,
#      and creates the GitRepository + Kustomization that sync that path back into the cluster.
#
# After apply: commit manifests under clusters/<cluster_name>/ and Flux applies them automatically.

locals {
  flux_path = coalesce(var.flux_path, "clusters/${var.cluster_name}")
}

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository" "flux" {
  name        = var.github_repo
  description = "GitOps repository for Flux cluster ${var.cluster_name}, managed by Terraform"
  visibility  = "private"
  auto_init   = true # creates initial commit + main branch; without it Flux cannot clone

  has_issues   = false
  has_projects = false
  has_wiki     = false
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.cluster_name}"
  repository = github_repository.flux.name
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false # write is required by Flux Image Automation (if you enable it later)
}

# Main bootstrap resource. Pushes manifests to the repo and applies them in the cluster.
# Depends on Cilium and on cluster health so Flux is installed into an already-working cluster.
resource "flux_bootstrap_git" "this" {
  depends_on = [
    github_repository_deploy_key.flux,
    module.cilium,
    local_file.kubeconfig,
    data.talos_cluster_health.this,
  ]

  embedded_manifests = true
  path               = local.flux_path

  # Pin the Flux version here if you need reproducibility. Default = provider picks latest 2.x.
  # version = "v2.4.0"
}

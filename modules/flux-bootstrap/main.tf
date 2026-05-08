# Flux CD bootstrap.
#
# Pipeline:
#   1. Generate an ECDSA key pair for the Flux ↔ GitHub SSH session.
#   2. Create a private GitHub repository ${owner}/${var.github_repo}.
#      auto_init=true creates the initial commit and main branch — without it,
#      SSH clone fails on the empty repo.
#   3. Register the public key as a deploy key (write access by default — needed
#      for Flux Image Automation; opt out via var.deploy_key_read_only).
#   4. flux_bootstrap_git installs Flux controllers into the cluster, pushes the
#      gotk-* manifests into <flux_path>/flux-system/, and creates the
#      GitRepository + Kustomization that sync that path back into the cluster.
#
# After apply: commit manifests under <flux_path>/ and Flux applies them.
#
# Provider configuration is the parent's responsibility:
#   - provider "github"  needs token + owner
#   - provider "flux"    needs the kubeconfig of the target cluster + the
#     private key from this module (output `private_key_pem`).

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
  auto_init   = var.auto_init_repo

  has_issues   = false
  has_projects = false
  has_wiki     = false

  lifecycle {
    # The repo holds the cluster's complete GitOps history: every manifest
    # version, every config drift, every commit you ever pushed. Recreating
    # the cluster (destroy → apply) MUST NOT delete this — the cluster is
    # ephemeral, the manifests are not.
    #
    # To actually decommission the repo, see modules/flux-bootstrap/README.md
    # → "Decommissioning the GitOps repo".
    prevent_destroy = true
  }
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.cluster_name}"
  repository = github_repository.flux.name
  key        = tls_private_key.flux.public_key_openssh
  read_only  = var.deploy_key_read_only
}

# Main bootstrap. Pushes manifests to the repo and applies them in the cluster.
resource "flux_bootstrap_git" "this" {
  depends_on = [
    github_repository_deploy_key.flux,
  ]

  embedded_manifests = true
  path               = local.flux_path
}

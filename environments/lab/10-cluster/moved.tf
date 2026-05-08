# State-migration declarations for the Phase 2 modularization.
#
# Every `moved {}` block tells Terraform that a resource previously addressed at the
# `from` location now lives at the `to` location — Terraform updates state without
# destroy/recreate. After a few applies, when state is fully settled, these blocks
# can be deleted.
#
# Reference: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring

# ───────── Round 2.1 — modules/cilium ─────────

moved {
  from = null_resource.wait_apiserver
  to   = module.cilium.null_resource.wait_apiserver
}

moved {
  from = helm_release.cilium
  to   = module.cilium.helm_release.cilium
}

# ───────── Round 2.2 — modules/flux-bootstrap ─────────

moved {
  from = tls_private_key.flux
  to   = module.flux_bootstrap.tls_private_key.flux
}

moved {
  from = github_repository.flux
  to   = module.flux_bootstrap.github_repository.flux
}

moved {
  from = github_repository_deploy_key.flux
  to   = module.flux_bootstrap.github_repository_deploy_key.flux
}

moved {
  from = flux_bootstrap_git.this
  to   = module.flux_bootstrap.flux_bootstrap_git.this
}

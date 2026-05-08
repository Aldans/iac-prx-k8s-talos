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

# Cloudflare Tunnel — delegated to modules/cloudflare-tunnel.
# See ../../../modules/cloudflare-tunnel/README.md for the design rationale.
#
# Provisions on the Cloudflare side:
#   - Zero Trust tunnel (locally-managed, routes live in Flux's config.yaml)
#   - Wildcard CNAME *.${public_subdomain}.${public_domain}
#
# Provisions in the cluster:
#   - Namespace `cloudflared`
#   - Secret  `cloudflared-credentials`   (credentials.json)
#   - ConfigMap `cloudflared-tunnel-id`   (TUNNEL_ID env)
#
# The cloudflared Deployment + the routes ConfigMap are owned by Flux —
# see home-lab-flux/infrastructure/controllers/cloudflared/.

module "cloudflare_tunnel" {
  source = "../../../modules/cloudflare-tunnel"

  account_id    = var.cloudflare_account_id
  public_domain = var.public_domain
  tunnel_name   = "${var.cluster_name}-home-lab"

  # Apply order: only after the cluster is healthy (otherwise the kubernetes
  # provider has no API server to talk to). The Cloudflare resources do not
  # depend on the cluster, but the in-cluster Secret/ConfigMap do.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    data.talos_cluster_health.this,
  ]
}

###############################################################################
# Public apps — one module instance per app exposed to the Internet.
###############################################################################

# Hubble UI. Cluster-wide network flow visualization — no built-in auth, so
# Cloudflare Access is mandatory.
module "app_hubble" {
  source = "../../../modules/cloudflare-public-app"

  account_id          = var.cloudflare_account_id
  zone_id             = module.cloudflare_tunnel.zone_id
  tunnel_cname_target = module.cloudflare_tunnel.tunnel_cname_target

  app_name         = "hubble"
  public_subdomain = var.public_subdomain
  public_domain    = var.public_domain

  access = {
    enabled        = true
    allowed_emails = var.admin_emails
  }
}

# Grafana — observability dashboards (Phase 2). Grafana has its own login, but
# it is an admin-tier surface, so Cloudflare Access gates it as well. The
# in-cluster HTTPRoute and the cloudflared tunnel route are owned by Flux
# (home-lab-flux infrastructure/controllers/monitoring/ and cloudflared/).
module "app_grafana" {
  source = "../../../modules/cloudflare-public-app"

  account_id          = var.cloudflare_account_id
  zone_id             = module.cloudflare_tunnel.zone_id
  tunnel_cname_target = module.cloudflare_tunnel.tunnel_cname_target

  app_name         = "grafana"
  public_subdomain = var.public_subdomain
  public_domain    = var.public_domain

  access = {
    enabled        = true
    allowed_emails = var.admin_emails
  }
}

# Headlamp — Kubernetes UI / cluster visualization (Phase 3). Headlamp acts as
# its in-cluster ServiceAccount (RBAC → cluster-admin), so it has no built-in
# auth — identity is verified by Cloudflare Access at the edge. Admin-tier
# surface ⇒ CF Access is MANDATORY. We deliberately do NOT wire Headlamp's own
# OIDC: it would re-introduce the session/refresh-rotate class of issues we
# solved for Grafana via auth.jwt (see ../headlamp-deploy-plan.md §7 pitfall #2).
# Cluster-side resources (HelmRelease, ClusterRoleBinding, HTTPRoute) are owned
# by Flux — home-lab-flux/infrastructure/controllers/headlamp/.
module "app_headlamp" {
  source = "../../../modules/cloudflare-public-app"

  account_id          = var.cloudflare_account_id
  zone_id             = module.cloudflare_tunnel.zone_id
  tunnel_cname_target = module.cloudflare_tunnel.tunnel_cname_target

  app_name         = "headlamp"
  public_subdomain = var.public_subdomain
  public_domain    = var.public_domain

  access = {
    enabled        = true
    allowed_emails = var.admin_emails
  }
}

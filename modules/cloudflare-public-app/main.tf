locals {
  # `<app>.<subdomain>.<domain>` when subdomain is set; `<app>.<domain>` otherwise.
  subdomain_label = var.public_subdomain != null && var.public_subdomain != "" ? "${var.public_subdomain}." : ""
  fqdn            = "${var.app_name}.${local.subdomain_label}${var.public_domain}"

  # Record name is the part below the zone — strip the trailing `.<domain>`.
  record_name = "${var.app_name}${var.public_subdomain != null && var.public_subdomain != "" ? ".${var.public_subdomain}" : ""}"
}

# Per-app DNS record. CF auto-issues a hostname-specific edge cert when proxied,
# even on the Free plan — that's what makes deep subdomains (e.g. `*.apps.<zone>`)
# work without Advanced Certificate.
resource "cloudflare_dns_record" "app" {
  zone_id = var.zone_id
  name    = local.record_name
  content = var.tunnel_cname_target
  type    = "CNAME"
  proxied = true
  ttl     = 1 # automatic when proxied=true
  comment = "Managed by Terraform (modules/cloudflare-public-app) — app=${var.app_name}"

  lifecycle {
    # zone_id often arrives via a chain of data sources (data.cloudflare_zone →
    # module.cloudflare_tunnel.zone_id). Any upstream re-read — e.g. a Talos
    # machineconfig change rippling through data.talos_cluster_health — turns
    # zone_id "known after apply" and would force a destroy+create of this
    # record, briefly dropping the app's DNS. The public zone is stable for the
    # life of the stack, so pin the value after first create.
    ignore_changes = [zone_id]
  }
}

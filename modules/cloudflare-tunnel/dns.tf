# Zone lookup — needed for the `zone_id` output, which downstream modules
# (cloudflare-public-app, …) use when creating per-app DNS records.
#
# We do NOT create a wildcard CNAME `*.<subdomain>.<domain>` here. Free-tier
# Cloudflare Universal SSL covers only the apex + one wildcard level (`*.<zone>`);
# a two-level wildcard like `*.apps.<zone>` is not served a matching edge cert
# and TLS handshake fails. Per-app records (cloudflare-public-app module) get
# hostname-scoped certs automatically.

data "cloudflare_zone" "this" {
  filter = {
    name = var.public_domain
  }
}

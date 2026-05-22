# Total TLS — auto-issued hostname certs for every proxied record — would go
# here, but Cloudflare ties it to Advanced Certificate Manager (ACM), which
# is a paid add-on (~$10/mo on top of Free plan). Not used.
#
# Free-plan workaround: place public apps at `<app>.<public_domain>` (single-
# level wildcard, covered by Universal SSL) rather than `<app>.apps.<domain>`
# (two-level wildcard, not covered). See `public_subdomain` in the
# 10-cluster variables.tf.
#
# To enable Total TLS later (e.g. after upgrading to a paid plan), add:
#
#   resource "cloudflare_total_tls" "this" {
#     zone_id               = data.cloudflare_zone.this.id
#     enabled               = true
#     certificate_authority = "lets_encrypt"
#   }
#
# Then add Zone › SSL and Certificates › Edit scope to the CF API token.

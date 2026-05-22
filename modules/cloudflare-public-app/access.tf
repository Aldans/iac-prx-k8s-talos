# Cloudflare Zero Trust Access — optional SSO in front of the app.
#
# When access.enabled = true: create an Access application bound to the app's
# hostname, with a single inline allow-policy that includes the configured
# emails / domains.
#
# Identity providers (Google, GitHub, OTP, etc.) are configured once at the
# account level (CF Zero Trust → Settings → Authentication) and inherited by
# every Access application — this module does not manage IdPs.

resource "cloudflare_zero_trust_access_application" "app" {
  count = var.access.enabled ? 1 : 0

  account_id                = var.account_id
  name                      = "${var.app_name} (${var.public_domain})"
  domain                    = local.fqdn
  type                      = "self_hosted"
  session_duration          = var.access.session_duration
  app_launcher_visible      = true
  auto_redirect_to_identity = false

  policies = [
    {
      decision = "allow"
      name     = "${var.app_name}-allow"
      include = concat(
        [for e in var.access.allowed_emails : { email = { email = e } }],
        [for d in var.access.allowed_email_domains : { email_domain = { domain = d } }],
      )
    },
  ]
}

# `modules/cloudflare-public-app`

Per-app Cloudflare resources for an in-cluster service exposed through the
shared tunnel:

1. **DNS record** — CNAME `<app>.<subdomain>.<domain>` → tunnel's
   `cfargotunnel.com` target, proxied. CF auto-issues a hostname-specific
   edge certificate (works on Free plan, unlike two-level wildcards).
2. **Cloudflare Access (optional)** — Zero Trust SSO gate in front of the
   app. Allow-by-email or allow-by-domain.

Pair with the `cloudflare-tunnel` module: that module owns the tunnel + the
shared in-cluster credentials; this module owns one app's public surface.

## Why per-app records instead of a wildcard

Cloudflare's Free Universal SSL covers a single wildcard depth (the apex +
`*.example.com`). A two-level wildcard like `*.apps.example.com` is **not**
covered — TLS handshake fails with "no matching certificate". For Free-tier
home labs, the workaround is to register one DNS record per app — CF then
issues a hostname-scoped edge cert automatically. Alternatives (paid
Advanced Certificate, origin TLS in the cluster, single-level hostnames) are
documented in `home-lab-flux/infrastructure/controllers/cloudflared/README.md`.

## Usage

```hcl
module "app_hubble" {
  source = "../../../modules/cloudflare-public-app"

  account_id          = var.cloudflare_account_id
  zone_id             = module.cloudflare_tunnel.zone_id
  tunnel_cname_target = module.cloudflare_tunnel.tunnel_cname_target

  app_name         = "hubble"
  public_subdomain = var.public_subdomain   # "apps"
  public_domain    = var.public_domain      # "dvlab.top"

  # SSO gate — only listed users can reach the app.
  access = {
    enabled        = true
    allowed_emails = ["you@example.com"]
  }
}

# Public route in cloudflared's config.yaml (Flux repo):
#   - hostname: ${module.app_hubble.fqdn}
#     service: http://cilium-gateway-lab.gateway.svc.cluster.local:80
#     originRequest:
#       httpHostHeader: hubble.apps.lab.lan
```

## Access (Zero Trust) — what you get

When `access.enabled = true` the request flow becomes:

```
Browser
  → CF edge (TLS)
  → CF Access (auth check — redirect to IdP if no session)
  → tunnel → cluster Gateway → app
```

Without `enabled = true`, the app is wide open to the public Internet (just
behind CF WAF + DDoS). **Use Access for any admin-style app** (Hubble UI,
Grafana, Plex admin, etc.) — those have no built-in auth.

Identity providers are set up once at the account level (CF Zero Trust →
Settings → Authentication). One-time-PIN over email works out of the box and
is the simplest starter IdP.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.app](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_zero_trust_access_application.app](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_application) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access"></a> [access](#input\_access) | Cloudflare Zero Trust Access configuration. When `enabled = true`, an Access<br/>application is created in front of the app — visitors must authenticate<br/>against one of the listed identity providers (configured at the Account<br/>level in CF Zero Trust → Settings → Authentication) before reaching the<br/>tunnel. At least one of `allowed_emails` / `allowed_email_domains` must be<br/>non-empty when enabled — otherwise the policy denies everything.<br/><br/>- session\_duration:    how long a successful auth stays valid (e.g. 24h, 168h).<br/>- allowed\_emails:      explicit list of authorised email addresses.<br/>- allowed\_email\_domains: e.g. ["example.com"] — anyone in that workspace.<br/>- bypass\_service\_tokens: when true, requests carrying a valid service token<br/>  skip auth — useful for healthchecks or machine-to-machine. | <pre>object({<br/>    enabled               = optional(bool, false)<br/>    session_duration      = optional(string, "24h")<br/>    allowed_emails        = optional(list(string), [])<br/>    allowed_email_domains = optional(list(string), [])<br/>    bypass_service_tokens = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID — required for Zero Trust Access resources. | `string` | n/a | yes |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | App identifier. Used as the leftmost label of the hostname and as the resource display name (e.g. `hubble` → hubble.apps.dvlab.top). | `string` | n/a | yes |
| <a name="input_public_domain"></a> [public\_domain](#input\_public\_domain) | Cloudflare-managed zone the record is created in (e.g. `dvlab.top`). | `string` | n/a | yes |
| <a name="input_public_subdomain"></a> [public\_subdomain](#input\_public\_subdomain) | Optional subdomain segment between app\_name and public\_domain. Default `apps` yields `<app>.apps.<domain>`. Set to null/empty to put the app one level deep (`<app>.<domain>` — useful for short URLs). | `string` | `"apps"` | no |
| <a name="input_tunnel_cname_target"></a> [tunnel\_cname\_target](#input\_tunnel\_cname\_target) | CNAME target the DNS record points at — `<tunnel-id>.cfargotunnel.com`. Usually from the cloudflare-tunnel module output. | `string` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID of the public domain. Usually passed from the cloudflare-tunnel module output. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_application_id"></a> [access\_application\_id](#output\_access\_application\_id) | ID of the Access application — null when access is disabled. Use it to attach extra policies / service tokens later. |
| <a name="output_access_enabled"></a> [access\_enabled](#output\_access\_enabled) | Whether Cloudflare Access is gating this app. |
| <a name="output_dns_record_id"></a> [dns\_record\_id](#output\_dns\_record\_id) | ID of the Cloudflare DNS record. Handy for troubleshooting or for referencing in higher-level modules. |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Public FQDN of the app — what users visit (e.g. hubble.apps.dvlab.top). |
<!-- END_TF_DOCS -->

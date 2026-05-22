###############################################################################
# Identity
###############################################################################

variable "account_id" {
  type        = string
  description = "Cloudflare account ID — required for Zero Trust Access resources."

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "account_id: 32 hex characters."
  }
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID of the public domain. Usually passed from the cloudflare-tunnel module output."
}

variable "tunnel_cname_target" {
  type        = string
  description = "CNAME target the DNS record points at — `<tunnel-id>.cfargotunnel.com`. Usually from the cloudflare-tunnel module output."
}

variable "app_name" {
  type        = string
  description = "App identifier. Used as the leftmost label of the hostname and as the resource display name (e.g. `hubble` → hubble.apps.dvlab.top)."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.app_name))
    error_message = "app_name: lowercase letters, digits and hyphens only, up to 32 characters."
  }
}

variable "public_subdomain" {
  type        = string
  description = "Optional subdomain segment between app_name and public_domain. Default `apps` yields `<app>.apps.<domain>`. Set to null/empty to put the app one level deep (`<app>.<domain>` — useful for short URLs)."
  default     = "apps"
}

variable "public_domain" {
  type        = string
  description = "Cloudflare-managed zone the record is created in (e.g. `dvlab.top`)."
}

###############################################################################
# Cloudflare Access (optional)
###############################################################################

variable "access" {
  type = object({
    enabled               = optional(bool, false)
    session_duration      = optional(string, "24h")
    allowed_emails        = optional(list(string), [])
    allowed_email_domains = optional(list(string), [])
    bypass_service_tokens = optional(bool, false)
  })
  default     = {}
  description = <<-EOT
    Cloudflare Zero Trust Access configuration. When `enabled = true`, an Access
    application is created in front of the app — visitors must authenticate
    against one of the listed identity providers (configured at the Account
    level in CF Zero Trust → Settings → Authentication) before reaching the
    tunnel. At least one of `allowed_emails` / `allowed_email_domains` must be
    non-empty when enabled — otherwise the policy denies everything.

    - session_duration:    how long a successful auth stays valid (e.g. 24h, 168h).
    - allowed_emails:      explicit list of authorised email addresses.
    - allowed_email_domains: e.g. ["example.com"] — anyone in that workspace.
    - bypass_service_tokens: when true, requests carrying a valid service token
      skip auth — useful for healthchecks or machine-to-machine.
  EOT

  validation {
    condition     = !var.access.enabled || length(var.access.allowed_emails) > 0 || length(var.access.allowed_email_domains) > 0
    error_message = "access: when enabled = true, provide allowed_emails or allowed_email_domains (an empty include list would deny everyone)."
  }
}

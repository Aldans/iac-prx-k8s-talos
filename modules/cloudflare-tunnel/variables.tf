###############################################################################
# Cloudflare account / zone
###############################################################################

variable "account_id" {
  type        = string
  description = "Cloudflare account ID. Find at: Cloudflare dashboard → right sidebar → 'Account ID'."

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.account_id))
    error_message = "account_id: 32 hex characters."
  }
}

variable "public_domain" {
  type        = string
  description = "Public zone in Cloudflare under which the tunnel hostnames are created. The zone must already exist in the account."

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.public_domain))
    error_message = "public_domain: a valid FQDN, e.g. 'example.com'."
  }
}

###############################################################################
# Tunnel
###############################################################################

variable "tunnel_name" {
  type        = string
  description = "Display name for the Cloudflare Tunnel resource. Shown in the Zero Trust dashboard."
}

###############################################################################
# In-cluster placement
###############################################################################

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace where the cloudflared credentials Secret and tunnel-id ConfigMap are written. Must match the namespace the cloudflared Deployment runs in (managed by Flux)."
  default     = "cloudflared"
}

variable "create_namespace" {
  type        = bool
  description = "When true, the module creates the namespace itself. Default is true so the Secret and ConfigMap can land before Flux first-reconciles the Deployment. Flux is configured not to manage the namespace (no namespace.yaml in infrastructure/controllers/cloudflared/), so there is no ownership conflict."
  default     = true
}

variable "credentials_secret_name" {
  type        = string
  description = "Name of the Secret holding credentials.json — mounted by the cloudflared Deployment."
  default     = "cloudflared-credentials"
}

variable "tunnel_id_configmap_name" {
  type        = string
  description = "Name of the ConfigMap that exposes TUNNEL_ID as an env var to the cloudflared Deployment. Decoupling the tunnel ID from the config.yaml lets routes stay in Flux as pure GitOps artefacts."
  default     = "cloudflared-tunnel-id"
}

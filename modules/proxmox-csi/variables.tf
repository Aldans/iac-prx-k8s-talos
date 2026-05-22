###############################################################################
# Proxmox API connection
#
# The same credential block is consumed by BOTH the Proxmox Cloud Controller
# Manager (CCM) and the Proxmox CSI plugin — they share one config.yaml.
###############################################################################

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint, including scheme and the /api2/json suffix — e.g. https://proxmox.lab.lan:8006/api2/json. Same value as the bpg/proxmox provider's `endpoint`."

  validation {
    condition     = can(regex("^https?://[^/]+/api2/json/?$", var.proxmox_endpoint))
    error_message = "proxmox_endpoint: must look like https://host[:port]/api2/json."
  }
}

variable "proxmox_token_id" {
  type        = string
  sensitive   = true
  description = "Proxmox API token ID in `user@realm!token-name` form (the part before '=' in the bpg provider's api_token)."

  validation {
    condition     = can(regex("^[^=]+![^=]+$", var.proxmox_token_id))
    error_message = "proxmox_token_id: must look like 'user@realm!token-name'."
  }
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret (the UUID after '=' in the bpg provider's api_token)."

  validation {
    condition     = can(regex("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", var.proxmox_token_secret))
    error_message = "proxmox_token_secret: must be a UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)."
  }
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification when CCM/CSI talk to the Proxmox API. Proxmox VE ships a self-signed certificate by default, so this is normally true for a home lab."
  default     = true
}

variable "proxmox_region" {
  type        = string
  description = <<-EOT
    Region name written into the shared config.yaml. CCM stamps each node's
    `spec.providerID` as `proxmox://<region>/<vmid>` and the matching
    `topology.kubernetes.io/region` label; the CSI plugin parses the region
    back out of providerID to pick the right Proxmox cluster entry. Set this
    to the Kubernetes cluster name so the two stay in lock-step.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,64}$", var.proxmox_region))
    error_message = "proxmox_region: letters, digits, dots, hyphens and underscores only."
  }
}

###############################################################################
# In-cluster placement
###############################################################################

variable "kubernetes_namespace" {
  type        = string
  description = "Namespace holding the shared Proxmox config Secret. Both the CCM and CSI HelmReleases (managed by Flux) must run in this namespace so their `existingConfigSecret` reference resolves."
  default     = "csi-proxmox"
}

variable "create_namespace" {
  type        = bool
  description = "When true the module creates the namespace itself (labelled pod-security=privileged — the CSI node DaemonSet is a privileged pod). Keep true so the Secret can land before Flux first-reconciles the HelmReleases. Flux must NOT also manage this namespace, or ownership conflicts."
  default     = true
}

variable "config_secret_name" {
  type        = string
  description = "Name of the Secret that carries config.yaml. Referenced verbatim as `existingConfigSecret` by both the CCM and CSI HelmReleases."
  default     = "proxmox-cloud-config"
}

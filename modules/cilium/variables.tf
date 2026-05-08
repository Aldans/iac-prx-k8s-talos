variable "cluster_name" {
  type        = string
  description = "Cilium cluster name (passed into helm values as cluster.name)."
}

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version."

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.cilium_version))
    error_message = "cilium_version: MAJOR.MINOR.PATCH, e.g. 1.17.2."
  }
}

variable "pod_cidr" {
  type        = string
  description = "CIDR for Cilium pod networks (ipv4NativeRoutingCIDR)."

  validation {
    condition     = can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr: must be a valid IPv4 CIDR."
  }
}

variable "cilium_devices" {
  type        = string
  description = "Network interfaces Cilium uses for native routing. Glob patterns supported (eth+, ens+)."
  default     = "eth0"
}

variable "kubeconfig_path" {
  type        = string
  description = "Filesystem path of a kubeconfig that grants access to the target cluster. Consumed both by the wait_apiserver provisioner and by the helm provider configured in the parent."
}

variable "kubeconfig_sha" {
  type        = string
  description = "SHA-256 of the kubeconfig contents — used as the trigger for the wait_apiserver provisioner. When the kubeconfig is regenerated (e.g. cluster_endpoint changes) the wait re-runs."
}

variable "wait_attempts" {
  type        = number
  description = "How many 5-second polling iterations wait_apiserver does before giving up (default = 60 → 5 minutes)."
  default     = 60
}

variable "k8s_service_host" {
  type        = string
  description = "Address Cilium uses to reach the API server. Default `localhost` exploits Talos KubePrism so Cilium does not depend on a single CP being alive."
  default     = "localhost"
}

variable "k8s_service_port" {
  type        = number
  description = "Port Cilium uses to reach the API server. Default 7445 = Talos KubePrism."
  default     = 7445
}

###############################################################################
# Built-in Cilium Ingress controller (Envoy-based).
# When enabled, Cilium serves `kind: Ingress` resources directly — no separate
# ingress-nginx / Traefik / etc. needed. cert-manager works as usual; just
# point ClusterIssuer solvers at `ingressClassName: cilium`.
#
# Docs: https://docs.cilium.io/en/stable/network/servicemesh/ingress/
###############################################################################

variable "ingress_enabled" {
  type        = bool
  description = "Enable Cilium's built-in Ingress controller. Replaces ingress-nginx for the same `kind: Ingress` API. Requires kubeProxyReplacement (already on)."
  default     = false
}

variable "ingress_default" {
  type        = bool
  description = "Register the Cilium IngressClass as the cluster default. When true, `kind: Ingress` resources without an explicit ingressClassName route to Cilium. Ignored when ingress_enabled = false."
  default     = true
}

variable "ingress_loadbalancer_mode" {
  type        = string
  description = "How Cilium provisions LB services for Ingress. `shared` = one LB service for ALL Ingresses (recommended for home labs — fewer external IPs). `dedicated` = per-Ingress LB. Ignored when ingress_enabled = false."
  default     = "shared"

  validation {
    condition     = contains(["shared", "dedicated"], var.ingress_loadbalancer_mode)
    error_message = "ingress_loadbalancer_mode: must be 'shared' or 'dedicated'."
  }
}

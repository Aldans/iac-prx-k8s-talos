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

###############################################################################
# L2 announcements — required for `Service: LoadBalancer` external IPs to be
# reachable on the LAN. Cilium agents send gratuitous ARP for IPs allocated
# from CiliumLoadBalancerIPPool, scoped by CiliumL2AnnouncementPolicy.
#
# CRDs (CiliumLoadBalancerIPPool, CiliumL2AnnouncementPolicy) ship with the
# Cilium chart by default, but the runtime feature toggle is OFF unless this
# value is set. Without it, LB IPs allocate but never resolve via ARP.
#
# Docs: https://docs.cilium.io/en/stable/network/l2-announcements/
###############################################################################

variable "l2_announcements_enabled" {
  type        = bool
  description = "Enable Cilium L2 announcements feature. Required when using CiliumLoadBalancerIPPool + CiliumL2AnnouncementPolicy to make LB IPs reachable on the LAN."
  default     = false
}

variable "l2_announcements_lease_duration" {
  type        = string
  description = "How long a node holds the L2 lease for an announced IP before it expires. Format: Go duration string. Default 15s strikes a balance between failover speed and API server load."
  default     = "15s"
}

variable "k8s_client_qps" {
  type        = number
  description = "K8s API client QPS for cilium-agent. Bumped from default 5 → 10 when L2 announcements are on, since lease polling generates additional requests. Set higher (50+) for clusters with many announced IPs."
  default     = 10
}

variable "k8s_client_burst" {
  type        = number
  description = "K8s API client burst capacity for cilium-agent. See k8s_client_qps."
  default     = 20
}

###############################################################################
# Gateway API — modern replacement for `kind: Ingress`. Cilium ships native
# Gateway API support since 1.14; same Envoy data plane that powers Ingress.
#
# Gateway API CRDs (gateway.networking.k8s.io/v1: Gateway, GatewayClass,
# HTTPRoute) are NOT installed by the Cilium chart — they must be installed
# separately (in this repo: home-lab-flux/infrastructure/controllers/
# gateway-api-crds/). Without the CRDs present, Cilium agent will hang on
# init waiting for them, exactly like the envoyconfig CRDs gotcha.
#
# Docs: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/
###############################################################################

variable "gateway_api_enabled" {
  type        = bool
  description = "Enable Cilium's native Gateway API support. Requires Gateway API CRDs to be installed in the cluster (out of scope for this module — managed in the GitOps repo)."
  default     = false
}

variable "gateway_api_create_class" {
  type        = bool
  description = "Whether the chart creates the `cilium` GatewayClass automatically. Set false if multiple Cilium installations share a cluster (rare). Ignored when gateway_api_enabled = false."
  default     = true
}

variable "gateway_api_secrets_namespace" {
  type        = string
  description = "Namespace where Cilium will look up TLS secrets referenced by Gateway listeners. Empty (default) means same-namespace as the Gateway. Ignored when gateway_api_enabled = false."
  default     = ""
}

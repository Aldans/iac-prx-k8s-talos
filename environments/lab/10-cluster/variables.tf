###############################################################################
# Cluster identity
###############################################################################

variable "cluster_name" {
  type        = string
  description = "Talos/Kubernetes cluster name. Used as the hostname prefix for nodes and as the Flux path (clusters/<cluster_name>)."
  default     = "tl01"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.cluster_name))
    error_message = "cluster_name: lowercase letters, digits and hyphens only, up to 32 characters."
  }
}

variable "dns_domain" {
  type        = string
  description = "DNS domain that dnsmasq on the Proxmox host registers VM hostnames into (via expand-hosts + domain). Node FQDN: <vm_name>.<dns_domain>."
  default     = "lab.lan"
}

###############################################################################
# Proxmox
###############################################################################

variable "prx" {
  type = object({
    endpoint  = string
    username  = string
    password  = string
    api_token = string
  })
  sensitive   = true
  description = "Proxmox API endpoint and credentials. api_token must be in the form `user@realm!token-name=<uuid>` (bpg/proxmox format)."

  validation {
    condition     = can(regex("^[^=]+![^=]+=[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$", var.prx.api_token))
    error_message = "prx.api_token must be in the form 'user@realm!token-name=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' (UUID after '=')."
  }
}

variable "prx_node" {
  type        = string
  description = "Name of the Proxmox cluster node where VMs will be created."
  default     = "mf"
}

variable "prx_datastore_image" {
  type        = string
  description = "Datastore for the downloaded Talos image (typically 'local' — the ISO storage)."
  default     = "local"
}

variable "prx_datastore_vm" {
  type        = string
  description = "Datastore for VM disks."
  default     = "local-zfs"
}

variable "prx_network_bridge" {
  type        = string
  description = "Proxmox network bridge for VMs (the one with dnsmasq + DHCP)."
  default     = "vmbr1"

  validation {
    condition     = can(regex("^vmbr\\d+$", var.prx_network_bridge))
    error_message = "prx_network_bridge: must match vmbr<N>, e.g. vmbr0, vmbr1."
  }
}

###############################################################################
# Talos / Kubernetes versions
###############################################################################

variable "talos_version" {
  type        = string
  description = "Talos OS version (image tag on factory.talos.dev)."
  default     = "v1.13.0"

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version: must be vMAJOR.MINOR.PATCH, e.g. v1.13.0."
  }
}

variable "talos_schematic_id" {
  type        = string
  description = "Schematic ID from factory.talos.dev (hash of the system-extensions bundle). Identical across Talos versions for the same extensions. Generate one at https://factory.talos.dev/"
  default     = "aeec243e3a4c2a14f9ba74b1a8c7662f03eea658a7ea5f1c26fdd491280c88f8"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.talos_schematic_id))
    error_message = "talos_schematic_id: 64 hex characters (sha256)."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for Talos. Passed to data.talos_machine_configuration.kubernetes_version — the provider picks the right image tags for kube-apiserver, scheduler, controller-manager, kubelet."
  default     = "1.34.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version: MAJOR.MINOR.PATCH without 'v' prefix, e.g. 1.34.0."
  }
}

###############################################################################
# Cluster topology
###############################################################################

variable "num_control_planes" {
  type        = number
  description = "Number of control-plane nodes. 3 is recommended for HA."
  default     = 3

  validation {
    condition     = var.num_control_planes >= 1 && var.num_control_planes <= 9
    error_message = "num_control_planes: between 1 and 9. Use 3 or 5 for HA."
  }
}

variable "num_workers" {
  type        = number
  description = "Number of worker nodes."
  default     = 3

  validation {
    condition     = var.num_workers >= 0 && var.num_workers <= 99
    error_message = "num_workers: between 0 and 99."
  }
}

variable "cp_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  description = "Resources for each control-plane VM."
  default = {
    cores     = 8
    memory_mb = 8192
    disk_gb   = 60
  }
}

variable "worker_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  description = "Resources for each worker VM."
  default = {
    cores     = 12
    memory_mb = 16000
    disk_gb   = 120
  }
}

###############################################################################
# Cilium
###############################################################################

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version."
  default     = "1.17.2"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.cilium_version))
    error_message = "cilium_version: MAJOR.MINOR.PATCH, e.g. 1.17.2."
  }
}

variable "pod_cidr" {
  type        = string
  description = "CIDR for Cilium pod networks (ipv4NativeRoutingCIDR)."
  default     = "10.244.0.0/16"

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

variable "cilium_ingress_enabled" {
  type        = bool
  description = "Enable Cilium's classic Ingress controller (`kind: Ingress`). Set false when migrating to Gateway API — keep one or the other to avoid two LB services competing for the same listener."
  default     = false
}

variable "cilium_gateway_api_enabled" {
  type        = bool
  description = "Enable Cilium's native Gateway API support (`kind: Gateway` / `kind: HTTPRoute`). Modern replacement for the classic Ingress controller; CRDs are installed via the GitOps repo (infrastructure/controllers/gateway-api-crds/)."
  default     = true
}

variable "cilium_l2_announcements_enabled" {
  type        = bool
  description = "Enable L2 announcements so that LoadBalancer IPs allocated from CiliumLoadBalancerIPPool are reachable on the LAN. Required when using cilium-ingress / cilium-gateway + cilium-lb."
  default     = true
}

###############################################################################
# OCI Registry mirror (optional)
###############################################################################

variable "registry_mirror" {
  type = object({
    endpoint             = string
    insecure_skip_verify = optional(bool, false)
    ca_cert              = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Optional pull-through OCI registry mirror. When set, Talos containerd is
    configured to fetch from this endpoint first for ghcr.io / docker.io /
    registry.k8s.io / quay.io. Vendor-neutral — works with Garage+Zot, Harbor,
    Hetzner Container Registry, AWS ECR, Docker Hub Pro mirror, etc.

    - endpoint: full URL incl. scheme and (optional) port. Example: "https://lab-storage.lab.lan:5000".
    - insecure_skip_verify: true if the mirror uses a self-signed certificate
      and you do not want to distribute its CA. Trade-off: TLS verification is
      disabled for THIS mirror only (not for upstream registries).
    - ca_cert: PEM-encoded CA bundle to trust the mirror; mutually exclusive
      with insecure_skip_verify in practice.
  EOT

  validation {
    condition     = var.registry_mirror == null || can(regex("^https?://[^/]+$|^https?://[^/]+/[^/]*$", var.registry_mirror.endpoint))
    error_message = "registry_mirror.endpoint must look like https://host[:port] or https://host[:port]/path."
  }
}

###############################################################################
# Flux / GitHub
###############################################################################

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token. Required scopes: repo (create + push), admin:public_key (deploy key)."
}

variable "github_owner" {
  type        = string
  description = "GitHub user or organization that owns the Flux repo."
}

variable "github_repo" {
  type        = string
  description = "Name of the GitHub repository that Flux will watch. Created by Terraform as a private repo."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo: letters, digits, dots, hyphens and underscores only."
  }
}

variable "flux_branch" {
  type        = string
  description = "Branch in the GitHub repo that Flux watches."
  default     = "main"
}

variable "flux_path" {
  type        = string
  description = "Path inside the Git repo that Flux watches. Defaults to clusters/<cluster_name> when null."
  default     = null
}

###############################################################################
# Proxmox CSI / CCM toggle
###############################################################################

variable "enable_proxmox_csi" {
  type        = bool
  default     = true
  description = <<-EOT
    When true, deploys the shared Proxmox config Secret + namespace (via
    modules/proxmox-csi) AND runs the kubelet with --cloud-provider=external.
    The two must always move together: enabling one without the other either
    leaves nodes tainted `uninitialized` forever (CCM absent) or makes the CSI
    Secret land before the namespace exists (module absent).
    Toggle to false only in environments without the Proxmox CCM/CSI HelmReleases.
  EOT
}

###############################################################################
# Cloudflare (public tunnel)
###############################################################################

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Cloudflare API token. Required scopes:
      - Account › Cloudflare Tunnel › Edit
      - Zone › DNS › Edit (limited to the public domain's zone)
      - Zone › Zone › Read (limited to the public domain's zone)
    Create at: Cloudflare dashboard → My Profile → API Tokens → Custom Token.
  EOT
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID — find it in the right sidebar of the Cloudflare dashboard."

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_account_id))
    error_message = "cloudflare_account_id: 32 hex characters."
  }
}

variable "public_domain" {
  type        = string
  description = "Public Cloudflare-managed zone. App hostnames are exposed under <app>.<public_subdomain>.<public_domain>."
}

variable "public_subdomain" {
  type        = string
  description = <<-EOT
    Optional subdomain level between app names and the public domain. Empty
    string (default) places apps at `<app>.<public_domain>` so they fall under
    Universal SSL's single-level wildcard (`*.<zone>`) — required on Free plan.

    Setting a non-empty value (e.g. "apps") yields `<app>.apps.<public_domain>`
    — DNS works but TLS handshake fails on Free plan because Universal SSL does
    not cover two-level wildcards. To use a non-empty value, enable Cloudflare
    ACM / Total TLS or buy an Advanced Certificate Pack (both ~$10/mo).
  EOT
  default     = ""
}

variable "admin_emails" {
  type        = list(string)
  description = "Email addresses allowed through Cloudflare Access on admin-tier apps (Hubble UI, Grafana, etc.). Each email must be registered as a login identity on the CF Zero Trust dashboard side (One-Time PIN works out of the box — CF sends a code at login time, no pre-registration needed)."

  validation {
    condition     = length(var.admin_emails) > 0
    error_message = "admin_emails must contain at least one address — otherwise Access policies deny everyone."
  }
}

###############################################################################
# Monitoring (Phase 2)
###############################################################################

variable "enable_monitoring" {
  type        = bool
  default     = true
  description = <<-EOT
    Master toggle for the Phase 2 observability stack's Terraform surface.
    When true:
      - modules/cilium renders Cilium + Hubble Prometheus metrics and their
        ServiceMonitor objects (monitoring_enabled);
      - modules/talos-cluster binds kube-controller-manager / kube-scheduler
        metrics on 0.0.0.0 so they are scrapeable (controlplane_metrics).
    Both are machineconfig / Helm-values changes — flipping this rolls the
    Cilium data plane and the CP machineconfig. The `monitoring` namespace and
    its Secrets (monitoring.tf) and the Grafana public-app (cloudflare.tf) are
    created unconditionally — same as the cloudflared tunnel surface.
  EOT
}

variable "loki_s3" {
  type = object({
    access_key_id     = string
    secret_access_key = string
  })
  sensitive   = true
  description = <<-EOT
    Garage S3 credentials for Loki's chunk store (bucket `loki-chunks`).
    monitoring.tf turns these into the `loki-s3-credentials` Secret in the
    `monitoring` namespace; the Loki HelmRelease (home-lab-flux) consumes them
    as the AWS SDK env vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).

    Create a least-privilege key on the storage VM:
      garage key create loki
      garage bucket allow --read --write loki-chunks --key loki
      garage key info --show-secret loki

    Endpoint / bucket / region are not secret and are set in the Loki
    HelmRelease values, not here.
  EOT

  validation {
    condition     = can(regex("^GK[0-9a-f]{24}$", var.loki_s3.access_key_id))
    error_message = "loki_s3.access_key_id: a Garage key id — 'GK' followed by 24 hex characters."
  }

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.loki_s3.secret_access_key))
    error_message = "loki_s3.secret_access_key: a Garage secret key — 64 lowercase hex characters."
  }
}

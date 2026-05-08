###############################################################################
# Cluster identity
###############################################################################

variable "cluster_name" {
  type        = string
  description = "Talos/Kubernetes cluster name."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.cluster_name))
    error_message = "cluster_name: lowercase letters, digits and hyphens only, up to 32 characters."
  }
}

variable "dns_domain" {
  type        = string
  description = "DNS domain that dnsmasq on the Proxmox host registers VM hostnames into. Node FQDN: <vm_name>.<dns_domain>."
}

variable "cp_hostname_prefix" {
  type        = string
  description = "Hostname prefix for control-plane nodes. Final names: <cp_hostname_prefix>-01, -02, …"
  default     = "tls-cp"
}

variable "worker_hostname_prefix" {
  type        = string
  description = "Hostname prefix for worker nodes. Final names: <worker_hostname_prefix>-01, -02, …"
  default     = "tls-wr"
}

###############################################################################
# Proxmox
###############################################################################

variable "prx_node" {
  type        = string
  description = "Proxmox cluster node where VMs will be created."
}

variable "prx_datastore_image" {
  type        = string
  description = "Datastore for the downloaded Talos image."
  default     = "local"
}

variable "prx_datastore_vm" {
  type        = string
  description = "Datastore for VM disks."
  default     = "local-zfs"
}

variable "prx_network_bridge" {
  type        = string
  description = "Proxmox network bridge for VMs."
  default     = "vmbr1"

  validation {
    condition     = can(regex("^vmbr\\d+$", var.prx_network_bridge))
    error_message = "prx_network_bridge: must match vmbr<N>."
  }
}

###############################################################################
# Talos / Kubernetes versions
###############################################################################

variable "talos_version" {
  type        = string
  description = "Talos OS version (factory.talos.dev image tag)."

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version: must be vMAJOR.MINOR.PATCH, e.g. v1.13.0."
  }
}

variable "talos_schematic_id" {
  type        = string
  description = "Schematic ID from factory.talos.dev (sha256 of the system-extensions bundle)."

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.talos_schematic_id))
    error_message = "talos_schematic_id: 64 hex characters."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for Talos. The provider picks the right tags for kube-apiserver / scheduler / controller-manager / kubelet."

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version: MAJOR.MINOR.PATCH without 'v' prefix."
  }
}

###############################################################################
# Cluster topology
###############################################################################

variable "num_control_planes" {
  type        = number
  description = "Number of control-plane nodes. 3 is recommended for HA."

  validation {
    condition     = var.num_control_planes >= 1 && var.num_control_planes <= 9
    error_message = "num_control_planes: between 1 and 9."
  }
}

variable "num_workers" {
  type        = number
  description = "Number of worker nodes."

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
}

variable "worker_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  description = "Resources for each worker VM."
}

###############################################################################
# Networking-related (used for IP filtering and certSANs)
###############################################################################

variable "pod_cidr" {
  type        = string
  description = "CIDR for pod networks. Used to filter pod IPs out of qemu-agent's report when collecting node initial IPs."

  validation {
    condition     = can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr: must be a valid IPv4 CIDR."
  }
}

###############################################################################
# Optional registry mirror (passed straight to Talos machine config)
###############################################################################

variable "registry_mirror" {
  type = object({
    endpoint             = string
    insecure_skip_verify = optional(bool, false)
    ca_cert              = optional(string, null)
  })
  default     = null
  description = "Optional pull-through OCI registry mirror. See modules/talos-cluster/README.md for the full schema."

  validation {
    condition     = var.registry_mirror == null || can(regex("^https?://[^/]+$|^https?://[^/]+/[^/]*$", var.registry_mirror.endpoint))
    error_message = "registry_mirror.endpoint must look like https://host[:port] or https://host[:port]/path."
  }
}

###############################################################################
# Local-file output paths
###############################################################################

variable "kubeconfig_filename" {
  type        = string
  description = "Where to write the local kubeconfig file. Defaults to <stack-root>/kubeconfig."
  default     = null
}

variable "talosconfig_filename" {
  type        = string
  description = "Where to write the local talosconfig file. Defaults to <stack-root>/talosconfig."
  default     = null
}

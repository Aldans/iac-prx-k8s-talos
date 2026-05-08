###############################################################################
# Proxmox
###############################################################################

variable "prx_node" {
  type        = string
  description = "Proxmox cluster node where the storage VM will be created."
}

variable "prx_datastore_image" {
  type        = string
  description = "Datastore for the downloaded Debian cloud image."
  default     = "local"
}

variable "prx_datastore_vm" {
  type        = string
  description = "Datastore for VM disks."
  default     = "local-zfs"
}

variable "prx_network_bridge" {
  type        = string
  description = "Proxmox network bridge for the VM (must reach the cluster network)."
  default     = "vmbr1"

  validation {
    condition     = can(regex("^vmbr\\d+$", var.prx_network_bridge))
    error_message = "prx_network_bridge: must match vmbr<N>."
  }
}

###############################################################################
# DNS
###############################################################################

variable "dns_domain" {
  type        = string
  description = "DNS domain (must match the dnsmasq domain= on the Proxmox host)."
}

variable "hostname" {
  type        = string
  description = "VM hostname. The VM is reachable as <hostname>.<dns_domain> via dnsmasq."
  default     = "lab-storage"
}

###############################################################################
# VM resources
###############################################################################

variable "vm_resources" {
  type = object({
    cores          = number
    memory_mb      = number
    system_disk_gb = number
    data_disk_gb   = number
  })
  description = "Resources for the storage VM. data_disk_gb is the dedicated data disk for Garage + Zot blobs."
}

###############################################################################
# Software versions
###############################################################################

variable "debian_image_url" {
  type        = string
  description = "Debian cloud image URL. Tested with Debian 13 (trixie) generic-cloud."
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

variable "garage_version" {
  type        = string
  description = "Garage release version (https://garagehq.deuxfleurs.fr/download/)."
  default     = "v1.0.1"
}

variable "zot_version" {
  type        = string
  description = "Zot registry release version. v2.1.3+ is required for working sync onDemand (PR #2903 + #3156)."
  default     = "v2.1.16"
}

###############################################################################
# Storage configuration
###############################################################################

variable "garage_buckets" {
  type        = list(string)
  description = "Buckets to create in Garage. terraform-state and oci-blobs are required by the cluster stack; the rest reserve room for Velero / Loki / etcd snapshots."
  default = [
    "terraform-state",
    "oci-blobs",
    "velero-backups",
    "loki-chunks",
    "etcd-snapshots",
  ]
}

variable "garage_state_bucket" {
  type        = string
  description = "Bucket name used by the cluster stack as a Terraform S3 backend."
  default     = "terraform-state"
}

variable "garage_oci_bucket" {
  type        = string
  description = "Bucket used by Zot as the blob store."
  default     = "oci-blobs"
}

variable "garage_replication_factor" {
  type        = number
  description = "Garage replication factor. 1 for single-node lab; 3 for a real cluster."
  default     = 1
}

variable "tfstate_key_prefix" {
  type        = string
  description = "Prefix used in the generated `backend_s3_hcl` snippet — i.e. the cluster stack's state lands at <bucket>/<prefix>/terraform.tfstate."
  default     = "kubernetes_iac"
}

###############################################################################
# Access
###############################################################################

variable "admin_ssh_pubkey" {
  type        = string
  description = "SSH public key authorised for the 'admin' user on the storage VM. Troubleshooting only — Terraform does not SSH in."
  sensitive   = true
}

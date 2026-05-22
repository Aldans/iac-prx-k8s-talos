# Proxmox persistent-storage layer — delegated to modules/proxmox-csi.
# See ../../../modules/proxmox-csi/README.md for the design rationale.
#
# Provisions in the cluster:
#   - Namespace `csi-proxmox` (pod-security: privileged)
#   - Secret `proxmox-cloud-config` (config.yaml — shared Proxmox API block)
#
# The CCM + CSI HelmReleases and the `proxmox-zfs` StorageClass are owned by
# Flux — see home-lab-flux/infrastructure/controllers/proxmox-{ccm,csi}/.
#
# Coupled change: modules/talos-cluster runs kubelet with
# --cloud-provider=external (external_cloud_provider = true in talos_cluster.tf)
# so the Proxmox CCM can initialize nodes. The two must move together.

locals {
  # Split the bpg/proxmox combined token once; CCM/CSI need the two halves.
  # var.prx validation guarantees exactly one '=' (uuid secret never contains '=').
  prx_api_parts = split("=", var.prx.api_token)
}

module "proxmox_csi" {
  source = "../../../modules/proxmox-csi"

  count = var.enable_proxmox_csi ? 1 : 0

  proxmox_endpoint = var.prx.endpoint

  # The bpg/proxmox provider takes a combined `user@realm!token-name=UUID`
  # token. CCM/CSI want the two halves separately.
  proxmox_token_id     = local.prx_api_parts[0]
  proxmox_token_secret = local.prx_api_parts[1]

  # region is baked into providerID (proxmox://<region>/<vmid>) by the CCM and
  # parsed back by the CSI plugin — keep it equal to the cluster name.
  proxmox_region = var.cluster_name

  # Apply order: only after the cluster is healthy, otherwise the kubernetes
  # provider has no API server to talk to. Same gate as module.cloudflare_tunnel.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    data.talos_cluster_health.this,
  ]
}

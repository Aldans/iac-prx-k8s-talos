# Proxmox CSI storage layer — Terraform half.
#
# Splits along the project's TF/Flux line: Terraform provisions the cloud-side
# credential (the Proxmox API token) and the namespace; Flux owns the in-cluster
# workload (the CCM + CSI HelmReleases). Same pattern as modules/cloudflare-tunnel.
#
# What lives here:
#   1. Namespace `csi-proxmox`, labelled pod-security=privileged — the CSI node
#      plugin is a privileged DaemonSet (host mounts into the kubelet plugin dir).
#   2. A Secret holding config.yaml — the Proxmox API connection block shared by
#      BOTH the Cloud Controller Manager and the CSI plugin.
#
# The HelmReleases reference this Secret through their `existingConfigSecret`
# value — see home-lab-flux/infrastructure/controllers/proxmox-{ccm,csi}/.

locals {
  # config.yaml — the exact schema CCM and CSI expect. A single `clusters` entry:
  # one Proxmox cluster == one region. region must equal what CCM bakes into
  # providerID, hence var.proxmox_region (= the Kubernetes cluster name).
  proxmox_config_yaml = yamlencode({
    clusters = [
      {
        url          = var.proxmox_endpoint
        insecure     = var.proxmox_insecure
        token_id     = var.proxmox_token_id
        token_secret = var.proxmox_token_secret
        region       = var.proxmox_region
      }
    ]
  })
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
    # The CSI node plugin runs privileged (hostPath mounts, mount propagation).
    # Without this the namespace's default `restricted` PSS would reject it.
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
      "app.kubernetes.io/managed-by"       = "terraform"
    }
  }
}

# Shared Proxmox API config. Mounted by the CCM container at its configFile path
# and by the CSI controller at /etc/proxmox/config.yaml.
resource "kubernetes_secret" "proxmox_config" {
  metadata {
    name      = var.config_secret_name
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "proxmox-csi"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    "config.yaml" = local.proxmox_config_yaml
  }

  depends_on = [kubernetes_namespace.this]
}

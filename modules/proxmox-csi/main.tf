# Proxmox CSI storage layer — Terraform half.
#
# Splits along the project's TF/Flux line: Terraform provisions the cloud-side
# credential (the Proxmox API token) and the namespace; Flux owns the in-cluster
# workload (the CCM + CSI HelmReleases). Same pattern as modules/cloudflare-tunnel.
#
# What lives here:
#   1. Namespace `csi-proxmox`, labelled pod-security=privileged — the CSI node
#      plugin is a privileged DaemonSet (host mounts into the kubelet plugin dir).
#   2. The config.yaml Secret — the Proxmox API connection block — created in
#      TWO namespaces: `csi-proxmox` (read by the CSI plugin) and `kube-system`
#      (read by the CCM). The CCM's Helm chart is not namespace-agnostic: it
#      authenticates as the SA `proxmox-cloud-controller-manager` in kube-system
#      (the chart creates the SA there and generates its kubeconfig from it), so
#      the CCM HelmRelease must run in kube-system — and `existingConfigSecret`
#      resolves within the release namespace.
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

  # The config Secret is needed in both the CSI namespace and kube-system (CCM).
  # kube-system always exists — only var.kubernetes_namespace is created below.
  secret_namespaces = toset([var.kubernetes_namespace, "kube-system"])
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

# Shared Proxmox API config. One Secret per namespace in local.secret_namespaces:
# the CSI controller reads it at /etc/proxmox/config.yaml in csi-proxmox; the CCM
# reads its copy in kube-system.
resource "kubernetes_secret" "proxmox_config" {
  for_each = local.secret_namespaces

  metadata {
    name      = var.config_secret_name
    namespace = each.key
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

# The Secret was single-instance before Fix A; map the existing state entry onto
# the csi-proxmox key so the for_each move is in-place, not destroy+create.
# Literal key — var.kubernetes_namespace defaults to (and is deployed as) csi-proxmox.
moved {
  from = kubernetes_secret.proxmox_config
  to   = kubernetes_secret.proxmox_config["csi-proxmox"]
}

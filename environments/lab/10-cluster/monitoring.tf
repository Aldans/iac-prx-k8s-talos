# Observability stack (Phase 2) — Terraform half.
#
# Splits along the project's TF/Flux line: Terraform provisions the namespace
# and the sensitive credentials; Flux owns the in-cluster workload — the
# kube-prometheus-stack + Loki + Grafana Alloy HelmReleases (see home-lab-flux
# infrastructure/controllers/monitoring/). Same pattern as modules/cloudflare-
# tunnel and modules/proxmox-csi.
#
# What lives here:
#   1. Namespace `monitoring`, labelled pod-security=privileged — node-exporter
#      (hostNetwork/hostPID) and the Alloy DaemonSet (host log mounts) would be
#      rejected by the default `restricted` Pod Security Standard otherwise.
#   2. Secret `loki-s3-credentials` — Garage S3 creds for Loki's chunk store.
#   3. Secret `grafana-admin` — generated Grafana admin login.
#
# The Secrets are created here so they exist before Flux first-reconciles the
# HelmReleases that consume them.

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      # node-exporter and Alloy run with elevated privileges.
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
      "app.kubernetes.io/managed-by"       = "terraform"
    }
  }

  # The kubernetes provider needs a reachable API server. Gate on the same
  # cluster-health check as module.cloudflare_tunnel / module.proxmox_csi.
  depends_on = [data.talos_cluster_health.this]
}

# Garage S3 credentials for Loki's chunk store (bucket loki-chunks). Loki's S3
# client falls back to the AWS SDK default credential chain when the storage
# config omits the keys — so they are delivered as the AWS_* env vars. The Loki
# HelmRelease mounts this Secret via `extraEnvFrom`. Endpoint / bucket / region
# are not sensitive and are set directly in the HelmRelease values.
resource "kubernetes_secret" "loki_s3" {
  metadata {
    name      = "loki-s3-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "loki"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    AWS_ACCESS_KEY_ID     = var.loki_s3.access_key_id
    AWS_SECRET_ACCESS_KEY = var.loki_s3.secret_access_key
  }

  # Explicit cluster-health gate — mirrors module.cloudflare_tunnel /
  # module.proxmox_csi. The namespace reference already orders this after the
  # namespace, but the explicit gate keeps the resource from being scheduled
  # against an unreachable API server (e.g. after a `terraform import`).
  depends_on = [data.talos_cluster_health.this]
}

# Grafana admin password — generated, never stored in Git. Retrieve with:
#   terraform output -raw grafana_admin_password
resource "random_password" "grafana_admin" {
  length  = 24
  special = false # avoid shell-quoting pain when copy-pasting the password
}

# Grafana admin login. The kube-prometheus-stack Grafana sub-chart reads it via
# `grafana.admin.existingSecret` (userKey: admin-user, passwordKey: admin-password).
resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "grafana"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }

  depends_on = [data.talos_cluster_health.this]
}

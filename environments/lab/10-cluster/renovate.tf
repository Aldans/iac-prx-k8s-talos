# Renovate — self-hosted dependency-update bot. Runs as a CronJob in the cluster;
# Flux owns the workload (home-lab-flux infrastructure/controllers/renovate/).
# Terraform owns only the namespace and the GitHub-token Secret — same TF/Flux
# split as monitoring.tf and modules/proxmox-csi.
#
# The Secret must exist before Flux first-reconciles the CronJob, so it is
# created here, gated on cluster health like the other in-cluster secrets.

resource "kubernetes_namespace" "renovate" {
  metadata {
    name = "renovate"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [data.talos_cluster_health.this]
}

# GitHub fine-grained PAT, scoped to both repos with Contents / Pull requests /
# Workflows / Issues = Read and write. Renovate reads it as RENOVATE_TOKEN — the
# CronJob pulls it in via envFrom (see the Flux manifests).
resource "kubernetes_secret" "renovate_credentials" {
  metadata {
    name      = "renovate-credentials"
    namespace = kubernetes_namespace.renovate.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "renovate"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    RENOVATE_TOKEN = var.renovate_github_token
  }

  depends_on = [data.talos_cluster_health.this]
}

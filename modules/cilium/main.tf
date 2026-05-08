# Cilium as CNI + kube-proxy replacement.
#
# How we avoid the "Cilium hangs" failure mode:
#   1. Talos bootstrap returns as soon as etcd is initialized — that does NOT mean the API
#      server is answering yet.
#   2. So before Helm we run null_resource.wait_apiserver — a bash polling loop hitting
#      kubectl get --raw=/readyz (5 min default, 5-second retry), no hardcoded sleeps.
#   3. helm_release.cilium runs with wait=true and atomic=true — Helm waits for all Cilium
#      pods to become Ready and rolls back on timeout.
#
# data.talos_cluster_health (in the parent) runs AFTER this module — without a CNI the
# nodes never reach Ready and the health check would deadlock.

resource "null_resource" "wait_apiserver" {
  triggers = {
    kubeconfig = var.kubeconfig_sha
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -eu
      export KUBECONFIG="${var.kubeconfig_path}"
      MAX_ATTEMPTS=${var.wait_attempts}
      for i in $(seq 1 $MAX_ATTEMPTS); do
        if kubectl get --raw='/readyz' >/dev/null 2>&1; then
          echo "[wait_apiserver] API server ready after $i attempts"
          exit 0
        fi
        echo "[wait_apiserver] not ready yet ($i/$MAX_ATTEMPTS), retrying in 5s..."
        sleep 5
      done
      echo "[wait_apiserver] timeout after $((MAX_ATTEMPTS * 5))s"
      exit 1
    EOT
  }
}

resource "helm_release" "cilium" {
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = var.cilium_version
  namespace        = "kube-system"
  create_namespace = false # kube-system already exists, created by Talos.

  # Helm waits until all Cilium pods are Ready.
  # atomic = true → automatic rollback if the timeout is hit.
  wait                       = true
  atomic                     = true
  timeout                    = 600
  disable_openapi_validation = true

  values = [
    templatefile("${path.module}/templates/values.yaml.tftpl", {
      cluster_name                    = var.cluster_name
      k8s_service_host                = var.k8s_service_host
      k8s_service_port                = var.k8s_service_port
      pod_cidr                        = var.pod_cidr
      devices                         = var.cilium_devices
      ingress_enabled                 = var.ingress_enabled
      ingress_default                 = var.ingress_default
      ingress_loadbalancer_mode       = var.ingress_loadbalancer_mode
      l2_announcements_enabled        = var.l2_announcements_enabled
      l2_announcements_lease_duration = var.l2_announcements_lease_duration
      k8s_client_qps                  = var.k8s_client_qps
      k8s_client_burst                = var.k8s_client_burst
    })
  ]

  depends_on = [
    null_resource.wait_apiserver,
  ]
}

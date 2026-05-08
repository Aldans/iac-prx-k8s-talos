# Cilium as CNI + kube-proxy replacement.
#
# How we avoid the "Cilium hangs" failure mode:
#   1. talos_machine_bootstrap returns as soon as etcd is initialized — that does NOT mean
#      the API server is answering yet.
#   2. So before Helm we run null_resource.wait_apiserver — a bash polling loop hitting
#      kubectl get --raw=/readyz (up to 5 min, 5-second retry), no hardcoded sleeps.
#   3. helm_release.cilium runs with wait=true and atomic=true — Helm waits for all Cilium
#      pods to become Ready and rolls back on timeout.
#
# data.talos_cluster_health (see 02_talos.tf) runs AFTER Cilium — without a CNI the nodes
# never reach Ready and the health check would deadlock.

locals {
  # Talos KubePrism — a local TCP load-balancer at 127.0.0.1:7445 on every node, balancing
  # toward all CP API servers. Cilium goes through it instead of using the kubeconfig server
  # so it does not depend on whether the first CP is alive.
  cilium_k8s_service_host = "localhost"
  cilium_k8s_service_port = 7445
}

resource "null_resource" "wait_apiserver" {
  depends_on = [
    talos_cluster_kubeconfig.this,
    local_file.kubeconfig,
  ]

  triggers = {
    kubeconfig = local_file.kubeconfig.content_sha256
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -eu
      export KUBECONFIG="${local_file.kubeconfig.filename}"
      MAX_ATTEMPTS=60
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
    templatefile("${path.module}/helm/cilium/cilium-values.yaml.tftpl", {
      cluster_name     = var.cluster_name
      k8s_service_host = local.cilium_k8s_service_host
      k8s_service_port = local.cilium_k8s_service_port
      pod_cidr         = var.pod_cidr
      devices          = var.cilium_devices
    })
  ]

  depends_on = [
    null_resource.wait_apiserver,
    local_file.kubeconfig,
    talos_machine_configuration_apply.cp,
    talos_machine_configuration_apply.worker,
    talos_machine_bootstrap.this,
  ]
}

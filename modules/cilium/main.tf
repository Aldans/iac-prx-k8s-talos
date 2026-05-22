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

# Rendered Helm values, hoisted into a local so we can both pass them to the
# helm_release and feed their hash into the rollout-restart trigger below.
locals {
  cilium_values = templatefile("${path.module}/templates/values.yaml.tftpl", {
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
    gateway_api_enabled             = var.gateway_api_enabled
    gateway_api_create_class        = var.gateway_api_create_class
    gateway_api_secrets_namespace   = var.gateway_api_secrets_namespace
    monitoring_enabled              = var.monitoring_enabled
  })

  cilium_values_sha = sha256(local.cilium_values)
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

  values = [local.cilium_values]

  depends_on = [
    null_resource.wait_apiserver,
  ]
}

# See variable rollout_on_values_change for the rationale (Helm chart does
# not stamp a config-checksum on the cilium pod template, so a values-only
# change does not roll the pods → new config sits inactive in ConfigMap).
resource "null_resource" "cilium_rollout" {
  count = var.rollout_on_values_change ? 1 : 0

  triggers = {
    values_sha = local.cilium_values_sha
  }

  # Run AFTER helm has applied the new values to the ConfigMap; otherwise
  # we'd restart pods to pick up an unchanged ConfigMap.
  depends_on = [helm_release.cilium]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -eu
      export KUBECONFIG="${var.kubeconfig_path}"
      echo "[cilium-rollout] values changed → rolling Cilium components"

      # Operator first: it registers CRDs (e.g. ciliumenvoyconfigs,
      # gateway-api derived resources) that newly-enabled features depend on.
      # Agents started before the operator finishes registering CRDs hang in
      # init forever waiting for them.
      kubectl -n kube-system rollout restart deploy/cilium-operator
      kubectl -n kube-system rollout status  deploy/cilium-operator --timeout=${var.rollout_operator_timeout}

      # Now the agents. ds/cilium-envoy is restarted in parallel; it doesn't
      # depend on the operator but is part of the same data plane.
      kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
      kubectl -n kube-system rollout status  ds/cilium        --timeout=${var.rollout_daemonset_timeout}
      kubectl -n kube-system rollout status  ds/cilium-envoy  --timeout=${var.rollout_daemonset_timeout}

      echo "[cilium-rollout] done"
    EOT
  }
}

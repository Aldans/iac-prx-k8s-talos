resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
  depends_on       = [talos_cluster_kubeconfig.kubeconfig]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename = "${path.module}/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = local_file.kubeconfig.filename
  }
}

resource "helm_release" "cilium" {
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = "1.16.5"
  namespace        = "kube-system"
  create_namespace = true
  values = [file("./helm/cilium/cilium-values.yaml")]
  depends_on = [
    talos_machine_configuration_apply.cp_config_apply,
    talos_machine_configuration_apply.worker_config_apply,
    talos_machine_bootstrap.bootstrap,
    talos_cluster_kubeconfig.kubeconfig,
    time_sleep.wait_60_seconds
  ]
}

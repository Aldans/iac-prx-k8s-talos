# Talos cluster (image + VMs + machineconfig + bootstrap + kubeconfig).
# Delegated to modules/talos-cluster. See ../../../modules/talos-cluster/README.md.

module "talos_cluster" {
  source = "../../../modules/talos-cluster"

  cluster_name = var.cluster_name
  dns_domain   = var.dns_domain

  prx_node            = var.prx_node
  prx_datastore_image = var.prx_datastore_image
  prx_datastore_vm    = var.prx_datastore_vm
  prx_network_bridge  = var.prx_network_bridge

  talos_version      = var.talos_version
  talos_schematic_id = var.talos_schematic_id
  kubernetes_version = var.kubernetes_version

  num_control_planes = var.num_control_planes
  num_workers        = var.num_workers
  cp_resources       = var.cp_resources
  worker_resources   = var.worker_resources

  pod_cidr        = var.pod_cidr
  registry_mirror = var.registry_mirror
}

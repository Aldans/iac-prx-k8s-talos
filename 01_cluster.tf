# This resource creates a new Talos machine secrets resource. 
locals {
  cp_vm_dependencies = [
    for idx in range(var.num_control_planes) : proxmox_virtual_environment_vm.talos_cp[idx]
  ]
  worker_vm_dependencies = [
    for idx in range(var.num_workers) : proxmox_virtual_environment_vm.talos_worker[idx]
  ]
}

resource "talos_machine_secrets" "machine_secrets" {}

# This data block retrieves the client configuration for the Talos cluster.
data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [element(flatten(proxmox_virtual_environment_vm.talos_cp[0].ipv4_addresses), 1)]
}

# This data block retrieves the machine configuration for the control plane nodes from the Talos provider.
data "talos_machine_configuration" "machineconfig_cp" {
  depends_on       = [local.cp_vm_dependencies]
  for_each         = { for idx, vm in proxmox_virtual_environment_vm.talos_cp : idx => vm }
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${element(flatten(each.value.ipv4_addresses), 1)}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

# This data block retrieves the machine configuration for the worker nodes from the Talos provider.
data "talos_machine_configuration" "machineconfig_worker" {
  depends_on       = [proxmox_virtual_environment_vm.talos_worker]
  for_each         = { for idx, vm in proxmox_virtual_environment_vm.talos_worker : idx => vm }
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${element(flatten(each.value.ipv4_addresses), 1)}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

# This resource applies the machine configuration for the control plane nodes.
resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each                   = { for idx, vm in proxmox_virtual_environment_vm.talos_cp : idx => vm }
  depends_on                 = [proxmox_virtual_environment_vm.talos_cp]
  #depends_on                 = [local.cp_vm_dependencies]
  client_configuration       = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp[each.key].machine_configuration
  node                       = element(flatten(each.value.ipv4_addresses), 1)
  timeouts = {
    create = "1m"
    update = "1m"
    delete = "1m"
    read   = "1m"
  }
}

# This resource applies the machine configuration for the worker nodes.
resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each                   = { for idx, vm in proxmox_virtual_environment_vm.talos_worker : idx => vm }
  depends_on                 = [proxmox_virtual_environment_vm.talos_worker]
  client_configuration       = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker[each.key].machine_configuration
  node                       = element(flatten(each.value.ipv4_addresses), 1)
  timeouts = {
    create = "1m"
    update = "1m"
    delete = "1m"
    read   = "1m"
  }
}

# This resource bootstraps the Talos control plane node.
resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = element(flatten(proxmox_virtual_environment_vm.talos_cp[0].ipv4_addresses), 1)
}

 #This data block retrieves the health status of the Talos cluster.
# data "talos_cluster_health" "health" {
#    depends_on           = [
#      helm_release.cilium
# #     talos_machine_configuration_apply.cp_config_apply,
# #     talos_machine_configuration_apply.worker_config_apply
#    ]
#    client_configuration = data.talos_client_configuration.talosconfig.client_configuration
#    control_plane_nodes  = [for vm in proxmox_virtual_environment_vm.talos_cp : element(flatten(vm.ipv4_addresses), 1)]
#    worker_nodes         = [for vm in proxmox_virtual_environment_vm.talos_worker : element(flatten(vm.ipv4_addresses), 1)]
#    endpoints            = data.talos_client_configuration.talosconfig.endpoints
# }

# This resource retrieves the kubeconfig for the Talos cluster.
resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap] #, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = element(flatten(proxmox_virtual_environment_vm.talos_cp[0].ipv4_addresses), 1)
}

# Output the Talos configuration and kubeconfig.
output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

# Output the kubeconfig for the Talos cluster.
output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}

output "control_plane_ips" {
  value = [for vm in proxmox_virtual_environment_vm.talos_cp : element(flatten(vm.ipv4_addresses), 1)]
}

output "worker_ips" {
  value = [for vm in proxmox_virtual_environment_vm.talos_worker : element(flatten(vm.ipv4_addresses), 1)]
}

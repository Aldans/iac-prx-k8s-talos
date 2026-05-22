# `modules/talos-cluster`

Brings up a Talos Kubernetes cluster on Proxmox: downloads the Talos image, creates control-plane and worker VMs, applies machine configuration, bootstraps etcd, pulls kubeconfig + talosconfig.

This is the foundation module of the cluster stack. Cilium (CNI) and Flux (GitOps) build on top of it.

```
input: cluster_name, dns_domain, prx_*, talos_version, kubernetes_version,
       num_*, *_resources, pod_cidr, registry_mirror?
    ↓
proxmox_virtual_environment_download_file.talos_nocloud_image
    ↓
proxmox_virtual_environment_vm.talos_{cp,worker}            ← for_each over hostname-prefixed names
    ↓
talos_machine_secrets.this
    ↓
data.talos_machine_configuration.{cp,worker}                ← per-node hostname patch + cert SANs
    ↓
talos_machine_configuration_apply.{cp,worker}               ← via temporary DHCP IP
    ↓
talos_machine_bootstrap.this                                 ← etcd init on first CP
    ↓
talos_cluster_kubeconfig.this                                ← pulls kubeconfig
    ↓
local_file.{kubeconfig,talosconfig}                          ← written to ${path.root}/ by default
    ↓
output: cluster_endpoint, kubeconfig_path, talosconfig_path,
        kubeconfig_sha, control_plane_fqdns, worker_fqdns,
        control_plane_initial_ips, worker_initial_ips,
        kubeconfig (sensitive), talosconfig (sensitive),
        client_configuration (sensitive)
```

## Provider configuration (parent's responsibility)

This module **does not configure providers**. The parent stack must declare:

```hcl
provider "proxmox" {
  endpoint  = var.prx.endpoint
  api_token = var.prx.api_token
  insecure  = true   # if Proxmox uses a self-signed cert
  ssh {
    agent    = true
    username = var.prx.username
    password = var.prx.password
  }
}
```

The Talos provider auto-configures from `talos_machine_secrets.this` — no explicit `provider "talos"` block needed.

## Networking model

- VM name = Talos hostname = DNS name: `${prefix}-{cp,wr}-XX.${dns_domain}`.
- The first machineconfig apply uses the temporary DHCP IP from qemu-agent. Talos then re-requests DHCP carrying its proper hostname → dnsmasq registers `<hostname>.<dns_domain>`.
- Control-plane endpoint baked into kubeconfig and certs: `https://<first-cp>.<dns_domain>:6443`. Single-CP failure mode: external `kubectl` cannot connect (etcd quorum keeps working internally). Full HA needs a Talos VIP — backlogged.
- `talos_cert_sans` contains all CP/worker FQDNs **and** their initial DHCP IPs, so `talosctl` can connect to either form without x509 errors.

## External cloud provider

`external_cloud_provider = true` patches the machineconfig of every node with
`machine.kubelet.extraArgs: { cloud-provider: external }`. This is required by
an out-of-tree cloud-controller-manager — in this repo, the Proxmox CCM (see
`modules/proxmox-csi`), which the Proxmox CSI plugin depends on for node
`providerID`.

With the flag on, each kubelet applies the
`node.cloudprovider.kubernetes.io/uninitialized:NoSchedule` taint at boot; the
CCM clears it once the node is initialized. Leave the flag `false` for any
cluster without an external CCM, or the nodes stay tainted forever.

Flipping the flag rolls a new machineconfig to every node (brief kubelet
restart / node re-register) — apply it in a maintenance window.

## Output files

`local_file.kubeconfig` and `local_file.talosconfig` are written to the **stack root** (`${path.root}/{kubeconfig,talosconfig}`) by default — i.e. next to the `.tf` files of whoever calls this module. Override via `var.{kubeconfig,talosconfig}_filename`.

## Usage

```hcl
module "talos_cluster" {
  source = "../../../modules/talos-cluster"

  cluster_name       = var.cluster_name
  dns_domain         = var.dns_domain
  prx_node           = var.prx_node
  prx_datastore_image = var.prx_datastore_image
  prx_datastore_vm   = var.prx_datastore_vm
  prx_network_bridge = var.prx_network_bridge

  talos_version       = var.talos_version
  talos_schematic_id  = var.talos_schematic_id
  kubernetes_version  = var.kubernetes_version

  num_control_planes = var.num_control_planes
  num_workers        = var.num_workers
  cp_resources       = var.cp_resources
  worker_resources   = var.worker_resources

  pod_cidr        = var.pod_cidr
  registry_mirror = var.registry_mirror

  # Required when the cluster runs an external CCM (here: the Proxmox CCM).
  external_cloud_provider = true
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.69.0 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | >= 0.7.0, < 0.8.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_local"></a> [local](#provider\_local) | 2.8.0 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.106.0 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.7.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [local_file.kubeconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [local_file.talosconfig](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [proxmox_virtual_environment_download_file.talos_nocloud_image](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file) | resource |
| [proxmox_virtual_environment_vm.talos_cp](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [proxmox_virtual_environment_vm.talos_worker](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.cp](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_configuration_apply.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.cp](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Talos/Kubernetes cluster name. | `string` | n/a | yes |
| <a name="input_controlplane_metrics"></a> [controlplane\_metrics](#input\_controlplane\_metrics) | When true, kube-controller-manager and kube-scheduler are patched to bind<br/>their secure metrics port on 0.0.0.0 (cluster.controllerManager /<br/>cluster.scheduler extraArgs `bind-address`). Talos binds them on 127.0.0.1<br/>by default, so Prometheus running off-host cannot scrape them.<br/><br/>Applies to control-plane nodes only. Toggling this rolls a new<br/>machineconfig to every CP node (kube-controller-manager / kube-scheduler<br/>static pods restart). The 10-cluster stack sets this true for the Phase 2<br/>observability stack. | `bool` | `false` | no |
| <a name="input_cp_hostname_prefix"></a> [cp\_hostname\_prefix](#input\_cp\_hostname\_prefix) | Hostname prefix for control-plane nodes. Final names: <cp\_hostname\_prefix>-01, -02, … | `string` | `"tls-cp"` | no |
| <a name="input_cp_resources"></a> [cp\_resources](#input\_cp\_resources) | Resources for each control-plane VM. | <pre>object({<br/>    cores     = number<br/>    memory_mb = number<br/>    disk_gb   = number<br/>  })</pre> | n/a | yes |
| <a name="input_dns_domain"></a> [dns\_domain](#input\_dns\_domain) | DNS domain that dnsmasq on the Proxmox host registers VM hostnames into. Node FQDN: <vm\_name>.<dns\_domain>. | `string` | n/a | yes |
| <a name="input_external_cloud_provider"></a> [external\_cloud\_provider](#input\_external\_cloud\_provider) | When true, every node's kubelet starts with `--cloud-provider=external`<br/>(machine.kubelet.extraArgs). Required by an out-of-tree cloud-controller-<br/>manager (here: the Proxmox CCM) — without it the kubelet never applies the<br/>`node.cloudprovider.kubernetes.io/uninitialized` taint and the CCM cannot<br/>stamp `providerID` / topology labels onto the node.<br/><br/>Leave false for a cluster with no external CCM, otherwise nodes stay tainted<br/>`uninitialized` forever. The 10-cluster stack sets this true because it<br/>deploys the Proxmox CCM (see modules/proxmox-csi). | `bool` | `false` | no |
| <a name="input_kubeconfig_filename"></a> [kubeconfig\_filename](#input\_kubeconfig\_filename) | Where to write the local kubeconfig file. Defaults to <stack-root>/kubeconfig. | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for Talos. The provider picks the right tags for kube-apiserver / scheduler / controller-manager / kubelet. | `string` | n/a | yes |
| <a name="input_num_control_planes"></a> [num\_control\_planes](#input\_num\_control\_planes) | Number of control-plane nodes. 3 is recommended for HA. | `number` | n/a | yes |
| <a name="input_num_workers"></a> [num\_workers](#input\_num\_workers) | Number of worker nodes. | `number` | n/a | yes |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | CIDR for pod networks. Used to filter pod IPs out of qemu-agent's report when collecting node initial IPs. | `string` | n/a | yes |
| <a name="input_prx_datastore_image"></a> [prx\_datastore\_image](#input\_prx\_datastore\_image) | Datastore for the downloaded Talos image. | `string` | `"local"` | no |
| <a name="input_prx_datastore_vm"></a> [prx\_datastore\_vm](#input\_prx\_datastore\_vm) | Datastore for VM disks. | `string` | `"local-zfs"` | no |
| <a name="input_prx_network_bridge"></a> [prx\_network\_bridge](#input\_prx\_network\_bridge) | Proxmox network bridge for VMs. | `string` | `"vmbr1"` | no |
| <a name="input_prx_node"></a> [prx\_node](#input\_prx\_node) | Proxmox cluster node where VMs will be created. | `string` | n/a | yes |
| <a name="input_registry_mirror"></a> [registry\_mirror](#input\_registry\_mirror) | Optional pull-through OCI registry mirror. See modules/talos-cluster/README.md for the full schema. | <pre>object({<br/>    endpoint             = string<br/>    insecure_skip_verify = optional(bool, false)<br/>    ca_cert              = optional(string, null)<br/>  })</pre> | `null` | no |
| <a name="input_talos_schematic_id"></a> [talos\_schematic\_id](#input\_talos\_schematic\_id) | Schematic ID from factory.talos.dev (sha256 of the system-extensions bundle). | `string` | n/a | yes |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos OS version (factory.talos.dev image tag). | `string` | n/a | yes |
| <a name="input_talosconfig_filename"></a> [talosconfig\_filename](#input\_talosconfig\_filename) | Where to write the local talosconfig file. Defaults to <stack-root>/talosconfig. | `string` | `null` | no |
| <a name="input_worker_hostname_prefix"></a> [worker\_hostname\_prefix](#input\_worker\_hostname\_prefix) | Hostname prefix for worker nodes. Final names: <worker\_hostname\_prefix>-01, -02, … | `string` | `"tls-wr"` | no |
| <a name="input_worker_resources"></a> [worker\_resources](#input\_worker\_resources) | Resources for each worker VM. | <pre>object({<br/>    cores     = number<br/>    memory_mb = number<br/>    disk_gb   = number<br/>  })</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_configuration"></a> [client\_configuration](#output\_client\_configuration) | Talos client\_configuration object — needed by data.talos\_cluster\_health and other Talos data sources at the parent. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | API server endpoint as written into kubeconfig — https://<first-cp>.<dns>:6443. |
| <a name="output_control_plane_fqdns"></a> [control\_plane\_fqdns](#output\_control\_plane\_fqdns) | FQDNs of all control-plane nodes. |
| <a name="output_control_plane_initial_ips"></a> [control\_plane\_initial\_ips](#output\_control\_plane\_initial\_ips) | Initial IPs of CP nodes (from qemu-agent, before DNS settles). Map of name → IP. |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Kubeconfig (raw YAML) for kubectl. |
| <a name="output_kubeconfig_path"></a> [kubeconfig\_path](#output\_kubeconfig\_path) | Filesystem path of the local kubeconfig file written by this module. Consumers (cilium / flux modules, provider configs) reference this. |
| <a name="output_kubeconfig_sha"></a> [kubeconfig\_sha](#output\_kubeconfig\_sha) | SHA-256 of the kubeconfig — useful as a trigger for downstream provisioners (e.g. cilium's wait\_apiserver) so they re-run when kubeconfig changes. |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Talos client config (raw YAML) for talosctl. |
| <a name="output_talosconfig_path"></a> [talosconfig\_path](#output\_talosconfig\_path) | Filesystem path of the local talosconfig file. |
| <a name="output_worker_fqdns"></a> [worker\_fqdns](#output\_worker\_fqdns) | FQDNs of all worker nodes. |
| <a name="output_worker_initial_ips"></a> [worker\_initial\_ips](#output\_worker\_initial\_ips) | Initial IPs of worker nodes. Map of name → IP. |
<!-- END_TF_DOCS -->

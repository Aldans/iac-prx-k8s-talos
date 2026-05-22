# `modules/proxmox-csi`

Terraform half of the cluster's persistent-storage layer. Provisions the
cloud-side credential that both the **Proxmox Cloud Controller Manager (CCM)**
and the **Proxmox CSI plugin** need:

1. Namespace `csi-proxmox`, labelled `pod-security.kubernetes.io/enforce=privileged`
   — the CSI node plugin is a privileged DaemonSet (it host-mounts into the
   kubelet plugin directory).
2. A `Secret` carrying `config.yaml` — one Proxmox API connection block, shared
   verbatim by the CCM and the CSI plugin.

The in-cluster workloads (CCM + CSI HelmReleases, StorageClass) are owned by
Flux — see `home-lab-flux/infrastructure/controllers/proxmox-ccm/` and
`proxmox-csi/`. Same TF/Flux split as `modules/cloudflare-tunnel`.

## Why a CCM is mandatory (not optional)

The Proxmox CSI plugin attaches a zvol to the correct VM by reading the node's
`spec.providerID` (`proxmox://<region>/<vmid>`) and calling the Proxmox API with
that VMID. **Talos' kubelet does not set `providerID`**, and the field is
immutable once the node has registered — it cannot be patched in afterwards.

The Proxmox CCM fills that gap: it matches each Kubernetes node to its Proxmox
VM, stamps `spec.providerID` plus the `topology.kubernetes.io/region|zone`
labels, and clears the `node.cloudprovider.kubernetes.io/uninitialized` taint.
Without the CCM the CSI plugin can create a zvol but never attach it.

## Talos prerequisite — `cloud-provider=external`

For the CCM to process a node, that node's kubelet must start with
`--cloud-provider=external` (otherwise the kubelet never applies the
`uninitialized` taint and the CCM skips the node). This is a machineconfig
change owned by `modules/talos-cluster` — toggled on with its
`external_cloud_provider` input, which the `10-cluster` stack sets to `true`.

Applying that change rolls a new machineconfig to every node → the kubelet
restarts and nodes briefly re-register. Do it in a maintenance window.

## Talos notes for the CSI node plugin

Checked against the upstream Talos guidance for `proxmox-csi-plugin`:

- **No `machine.kubelet.extraMounts`** — Talos already bind-mounts
  `/var/lib/kubelet` with shared propagation, which is all a block-volume CSI
  node plugin needs. `extraMounts` is only required by drivers staging volumes
  outside that path.
- **No Talos system extension** — zvols are attached as `virtio-scsi` block
  devices and formatted `ext4` by the node plugin's own bundled tooling. No
  `iscsi-tools` / extra extension required (that would be needed for iSCSI).

## `region` ↔ `providerID` contract

`var.proxmox_region` is written into `config.yaml`. The CCM bakes it into every
`providerID` as `proxmox://<region>/<vmid>`; the CSI plugin parses it back out
to select the matching `clusters[]` entry. The `10-cluster` stack sets it to
the Kubernetes cluster name so the two never drift.

## Usage

```hcl
module "proxmox_csi" {
  source = "../../../modules/proxmox-csi"

  proxmox_endpoint     = var.prx.endpoint
  proxmox_token_id     = split("=", var.prx.api_token)[0]   # user@realm!token-name
  proxmox_token_secret = split("=", var.prx.api_token)[1]   # the UUID secret
  proxmox_region       = var.cluster_name

  depends_on = [
    # Cluster + CNI must be up so the kubernetes provider has an API server.
    module.talos_cluster,
    module.cilium,
    data.talos_cluster_health.this,
  ]
}
```

The parent stack supplies the `kubernetes` provider — this module does not
configure it.

## Proxmox token privileges

Phase 1 reuses the existing Terraform admin token (`var.prx.api_token`). A
least-privilege follow-up is to mint a dedicated `kubernetes-csi@pve` token with
the upstream-recommended `CSI` role (`VM.Audit`, `VM.Config.Disk`,
`Datastore.Allocate`, `Datastore.AllocateSpace`, `Datastore.Audit`).

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.36 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.38.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_namespace.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.proxmox_config](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_config_secret_name"></a> [config\_secret\_name](#input\_config\_secret\_name) | Name of the Secret that carries config.yaml. Referenced verbatim as `existingConfigSecret` by both the CCM and CSI HelmReleases. | `string` | `"proxmox-cloud-config"` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | When true the module creates the namespace itself (labelled pod-security=privileged — the CSI node DaemonSet is a privileged pod). Keep true so the Secret can land before Flux first-reconciles the HelmReleases. Flux must NOT also manage this namespace, or ownership conflicts. | `bool` | `true` | no |
| <a name="input_kubernetes_namespace"></a> [kubernetes\_namespace](#input\_kubernetes\_namespace) | Namespace holding the shared Proxmox config Secret. Both the CCM and CSI HelmReleases (managed by Flux) must run in this namespace so their `existingConfigSecret` reference resolves. | `string` | `"csi-proxmox"` | no |
| <a name="input_proxmox_endpoint"></a> [proxmox\_endpoint](#input\_proxmox\_endpoint) | Proxmox API endpoint, including scheme and the /api2/json suffix — e.g. https://proxmox.lab.lan:8006/api2/json. Same value as the bpg/proxmox provider's `endpoint`. | `string` | n/a | yes |
| <a name="input_proxmox_insecure"></a> [proxmox\_insecure](#input\_proxmox\_insecure) | Skip TLS verification when CCM/CSI talk to the Proxmox API. Proxmox VE ships a self-signed certificate by default, so this is normally true for a home lab. | `bool` | `true` | no |
| <a name="input_proxmox_region"></a> [proxmox\_region](#input\_proxmox\_region) | Region name written into the shared config.yaml. CCM stamps each node's<br/>`spec.providerID` as `proxmox://<region>/<vmid>` and the matching<br/>`topology.kubernetes.io/region` label; the CSI plugin parses the region<br/>back out of providerID to pick the right Proxmox cluster entry. Set this<br/>to the Kubernetes cluster name so the two stay in lock-step. | `string` | n/a | yes |
| <a name="input_proxmox_token_id"></a> [proxmox\_token\_id](#input\_proxmox\_token\_id) | Proxmox API token ID in `user@realm!token-name` form (the part before '=' in the bpg provider's api\_token). | `string` | n/a | yes |
| <a name="input_proxmox_token_secret"></a> [proxmox\_token\_secret](#input\_proxmox\_token\_secret) | Proxmox API token secret (the UUID after '=' in the bpg provider's api\_token). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_config_secret_name"></a> [config\_secret\_name](#output\_config\_secret\_name) | Name of the Secret carrying config.yaml — wire it into the `existingConfigSecret` value of both the CCM and CSI HelmReleases. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace holding the shared Proxmox config Secret. The CCM and CSI HelmReleases (Flux) must be deployed here. |
<!-- END_TF_DOCS -->

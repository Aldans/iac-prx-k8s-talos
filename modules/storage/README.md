# `modules/storage`

Single-VM **Garage + Zot** storage host on Proxmox: an S3-compatible object store and an OCI registry running side-by-side on Debian 13. Used by the cluster stack as:

- the **Terraform state backend** (`terraform-state` bucket, S3 protocol on `:3900`)
- the **OCI registry mirror** for `ghcr.io` / `docker.io` / `registry.k8s.io` / `quay.io` (`:5000`, self-signed TLS)

```
input: prx_*, dns_domain, hostname, vm_resources, garage_*, zot_*, admin_ssh_pubkey
    ↓
proxmox_virtual_environment_download_file.debian_cloud   ← Debian 13 image
    ↓
random_id.garage_*                                        ← RPC secret + S3 access key + secret
tls_private_key.zot + tls_self_signed_cert.zot            ← Zot HTTPS cert (10-year validity)
    ↓
proxmox_virtual_environment_file.{cloud_config,cloud_meta}  ← cloud-init snippets
    ↓
proxmox_virtual_environment_vm.storage                    ← VM with system + data disks
    ↓
output: fqdn, garage_s3_endpoint, zot_endpoint,
        garage_state_bucket, garage_oci_bucket, garage_buckets,
        garage_access_key_id (sensitive), garage_secret_access_key (sensitive),
        zot_ca_cert, backend_s3_hcl (sensitive), registry_mirror_tfvars_snippet
```

## Provider configuration (parent's responsibility)

```hcl
provider "proxmox" {
  endpoint  = var.prx.endpoint
  api_token = var.prx.api_token
  insecure  = true
  ssh {
    agent    = true
    username = var.prx.username
    password = var.prx.password
  }
}
```

## Bootstrap order (chicken-and-egg)

This module's state is **local** to the calling stack — Garage cannot host its own state file. Mitigation:
- chmod 600 the state right after the first apply,
- back it up periodically (NAS / encrypted USB / `terraform state pull > backup.tfstate`).

## Wiring the cluster stack

After `terraform apply`, fetch the snippets and paste them into the cluster stack:

```bash
just output lab 00-storage -raw backend_s3_hcl > environments/lab/10-cluster/backend.s3.hcl
chmod 600 environments/lab/10-cluster/backend.s3.hcl
just output lab 00-storage -raw registry_mirror_tfvars_snippet
# (append into environments/lab/10-cluster/credentials.auto.tfvars)
```

Then `terraform init -migrate-state` in the cluster stack to move state into Garage.

## Buckets created

| Bucket | Purpose |
|---|---|
| `terraform-state` | Cluster stack's S3 backend. |
| `oci-blobs` | Backend for Zot. |
| `velero-backups` | Reserved for Velero. |
| `loki-chunks` | Reserved for Loki. |
| `etcd-snapshots` | Reserved for periodic Talos etcd snapshots. |

Override `var.garage_buckets` to change the set.

## Usage

```hcl
module "storage" {
  source = "../../../modules/storage"

  prx_node           = var.prx_node
  prx_network_bridge = var.prx_network_bridge

  dns_domain = var.dns_domain
  hostname   = var.hostname

  vm_resources = var.vm_resources

  admin_ssh_pubkey = var.admin_ssh_pubkey
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.69.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.106.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [proxmox_virtual_environment_download_file.debian_cloud](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file) | resource |
| [proxmox_virtual_environment_file.cloud_config](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_file.cloud_meta](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file) | resource |
| [proxmox_virtual_environment_vm.storage](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [random_id.garage_access_key_id_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_id.garage_rpc_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_id.garage_secret_access_key](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [tls_private_key.zot](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.zot](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_ssh_pubkey"></a> [admin\_ssh\_pubkey](#input\_admin\_ssh\_pubkey) | SSH public key authorised for the 'admin' user on the storage VM. Troubleshooting only — Terraform does not SSH in. | `string` | n/a | yes |
| <a name="input_debian_image_url"></a> [debian\_image\_url](#input\_debian\_image\_url) | Debian cloud image URL. Tested with Debian 13 (trixie) generic-cloud. | `string` | `"https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"` | no |
| <a name="input_dns_domain"></a> [dns\_domain](#input\_dns\_domain) | DNS domain (must match the dnsmasq domain= on the Proxmox host). | `string` | n/a | yes |
| <a name="input_garage_buckets"></a> [garage\_buckets](#input\_garage\_buckets) | Buckets to create in Garage. terraform-state and oci-blobs are required by the cluster stack; the rest reserve room for Velero / Loki / etcd snapshots. | `list(string)` | <pre>[<br/>  "terraform-state",<br/>  "oci-blobs",<br/>  "velero-backups",<br/>  "loki-chunks",<br/>  "etcd-snapshots"<br/>]</pre> | no |
| <a name="input_garage_oci_bucket"></a> [garage\_oci\_bucket](#input\_garage\_oci\_bucket) | Bucket used by Zot as the blob store. | `string` | `"oci-blobs"` | no |
| <a name="input_garage_replication_factor"></a> [garage\_replication\_factor](#input\_garage\_replication\_factor) | Garage replication factor. 1 for single-node lab; 3 for a real cluster. | `number` | `1` | no |
| <a name="input_garage_state_bucket"></a> [garage\_state\_bucket](#input\_garage\_state\_bucket) | Bucket name used by the cluster stack as a Terraform S3 backend. | `string` | `"terraform-state"` | no |
| <a name="input_garage_version"></a> [garage\_version](#input\_garage\_version) | Garage release version (https://garagehq.deuxfleurs.fr/download/). | `string` | `"v1.0.1"` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | VM hostname. The VM is reachable as <hostname>.<dns\_domain> via dnsmasq. | `string` | `"lab-storage"` | no |
| <a name="input_prx_datastore_image"></a> [prx\_datastore\_image](#input\_prx\_datastore\_image) | Datastore for the downloaded Debian cloud image. | `string` | `"local"` | no |
| <a name="input_prx_datastore_vm"></a> [prx\_datastore\_vm](#input\_prx\_datastore\_vm) | Datastore for VM disks. | `string` | `"local-zfs"` | no |
| <a name="input_prx_network_bridge"></a> [prx\_network\_bridge](#input\_prx\_network\_bridge) | Proxmox network bridge for the VM (must reach the cluster network). | `string` | `"vmbr1"` | no |
| <a name="input_prx_node"></a> [prx\_node](#input\_prx\_node) | Proxmox cluster node where the storage VM will be created. | `string` | n/a | yes |
| <a name="input_tfstate_key_prefix"></a> [tfstate\_key\_prefix](#input\_tfstate\_key\_prefix) | Prefix used in the generated `backend_s3_hcl` snippet — i.e. the cluster stack's state lands at <bucket>/<prefix>/terraform.tfstate. | `string` | `"kubernetes_iac"` | no |
| <a name="input_vm_resources"></a> [vm\_resources](#input\_vm\_resources) | Resources for the storage VM. data\_disk\_gb is the dedicated data disk for Garage + Zot blobs. | <pre>object({<br/>    cores          = number<br/>    memory_mb      = number<br/>    system_disk_gb = number<br/>    data_disk_gb   = number<br/>  })</pre> | n/a | yes |
| <a name="input_zot_version"></a> [zot\_version](#input\_zot\_version) | Zot registry release version. v2.1.3+ is required for working sync onDemand (PR #2903 + #3156). | `string` | `"v2.1.16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backend_s3_hcl"></a> [backend\_s3\_hcl](#output\_backend\_s3\_hcl) | Ready-to-paste contents for the cluster stack's backend.s3.hcl. `terraform output -raw backend_s3_hcl > ../10-cluster/backend.s3.hcl`. |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Full DNS name of the storage host. |
| <a name="output_garage_access_key_id"></a> [garage\_access\_key\_id](#output\_garage\_access\_key\_id) | Garage S3 access key id ('terraform' account). Use in backend.s3.hcl access\_key. |
| <a name="output_garage_admin_endpoint"></a> [garage\_admin\_endpoint](#output\_garage\_admin\_endpoint) | Garage admin API endpoint (port 3903) — bucket/key management. |
| <a name="output_garage_buckets"></a> [garage\_buckets](#output\_garage\_buckets) | All buckets created in Garage. |
| <a name="output_garage_oci_bucket"></a> [garage\_oci\_bucket](#output\_garage\_oci\_bucket) | Bucket used by Zot for blob storage. |
| <a name="output_garage_s3_endpoint"></a> [garage\_s3\_endpoint](#output\_garage\_s3\_endpoint) | Garage S3 API endpoint (HTTP, port 3900). Use as Terraform S3 backend endpoint. |
| <a name="output_garage_secret_access_key"></a> [garage\_secret\_access\_key](#output\_garage\_secret\_access\_key) | Garage S3 secret. Use in backend.s3.hcl secret\_key. |
| <a name="output_garage_state_bucket"></a> [garage\_state\_bucket](#output\_garage\_state\_bucket) | Bucket reserved for Terraform state. |
| <a name="output_registry_mirror_tfvars_snippet"></a> [registry\_mirror\_tfvars\_snippet](#output\_registry\_mirror\_tfvars\_snippet) | Ready-to-paste registry\_mirror block for the cluster stack's credentials.auto.tfvars. |
| <a name="output_zot_ca_cert"></a> [zot\_ca\_cert](#output\_zot\_ca\_cert) | Self-signed certificate for Zot. Pass to var.registry\_mirror.ca\_cert in the cluster stack if you prefer real TLS verification over insecure\_skip\_verify. |
| <a name="output_zot_endpoint"></a> [zot\_endpoint](#output\_zot\_endpoint) | Zot OCI registry endpoint (HTTPS, port 5000). Use as registry\_mirror.endpoint in the cluster stack. |
<!-- END_TF_DOCS -->

# `00-storage` — Garage + Zot

Foundation layer of the home-lab. Provisions a single Proxmox VM that runs:

- **Garage** — S3-compatible object storage ([garagehq.deuxfleurs.fr](https://garagehq.deuxfleurs.fr/)) on `:3900`.
- **Zot** — OCI registry with on-demand pull-through mirroring ([zotregistry.dev](https://zotregistry.dev/)) on `:5000`.

Both reachable as `<hostname>.<dns_domain>` (default: `lab-storage.lab.lan`) via dnsmasq DNS on the Proxmox host.

| Bucket | Purpose |
|---|---|
| `terraform-state` | S3 backend for the `10-cluster` stack. |
| `oci-blobs` | Backend for Zot (image blobs land here). |
| `velero-backups` | Reserved for future Velero backups of the cluster. |
| `loki-chunks` | Reserved for future Loki log chunks. |
| `etcd-snapshots` | Reserved for periodic Talos etcd snapshots. |

> **State is local here.** Chicken-and-egg: Garage is the S3 backend for everything else, but it doesn't exist on first apply. The state file lives next to the .tf code (`chmod 600`) and should be backed up periodically (NAS / encrypted USB / `terraform state pull > backup.tfstate`).

---

## Prerequisites

- Working Proxmox host with the same network / dnsmasq setup as `10-cluster`. The storage VM uses DHCP and registers under its hostname.
- Proxmox API token with `VM.Allocate`, `Datastore.AllocateSpace`, `SDN.Use`, plus `Datastore.AllocateTemplate` for image downloads.
- An SSH public key — used for emergency access to the storage VM (Terraform itself does not SSH in).

This stack uses Debian 13 cloud-image; it is independent of the Talos image used by `10-cluster`.

---

## Deploy

From the repo root:

```bash
cp environments/lab/00-storage/credentials.auto.tfvars-exemple \
   environments/lab/00-storage/credentials.auto.tfvars
chmod 600 environments/lab/00-storage/credentials.auto.tfvars
$EDITOR environments/lab/00-storage/credentials.auto.tfvars   # at minimum: prx, admin_ssh_pubkey

just init lab 00-storage
just apply lab 00-storage

chmod 600 environments/lab/00-storage/terraform.tfstate*       # protect the local state
```

The VM boots, cloud-init installs Garage + Zot, creates buckets, imports the pre-issued S3 access keys, and starts both services. Total time: ~5 minutes.

After apply, grab the snippets you'll paste into `10-cluster`:

```bash
# 1) Backend config for 10-cluster
just output lab 00-storage -raw backend_s3_hcl > environments/lab/10-cluster/backend.s3.hcl
chmod 600 environments/lab/10-cluster/backend.s3.hcl

# 2) registry_mirror snippet for 10-cluster credentials
just output lab 00-storage -raw registry_mirror_tfvars_snippet
# (append the printed block into environments/lab/10-cluster/credentials.auto.tfvars)
```

---

## Wire the cluster

After `00-storage` is applied:

### Migrate cluster state into Garage

```bash
cd environments/lab/10-cluster
terraform init -backend-config=backend.s3.hcl -migrate-state
# Terraform asks for confirmation; type 'yes'.
```

`10-cluster` now keeps its state in Garage's `terraform-state` bucket with native locking (Terraform 1.10+ `use_lockfile = true`).

### Activate the registry mirror

In `environments/lab/10-cluster/credentials.auto.tfvars` add:

```hcl
registry_mirror = {
  endpoint             = "https://lab-storage.lab.lan:5000"
  insecure_skip_verify = true
}
```

Then `just apply lab 10-cluster`. Talos rolls a machineconfig patch onto every node; containerd starts hitting the local Zot first for `ghcr.io`, `docker.io`, `registry.k8s.io`, `quay.io`, `gcr.io`. The first pull warms Zot's cache; subsequent pulls (e.g. cluster recreation) come from LAN at gigabit speeds.

---

## Roll back

Stop using the mirror without destroying the storage VM:

```hcl
# environments/lab/10-cluster/credentials.auto.tfvars — comment out:
# registry_mirror = { ... }
```
```bash
just apply lab 10-cluster
# then reboot all nodes — see top-level README "OCI registry mirror" section for why
```

Migrate state back to local (only if you also plan to drop Garage):

```bash
cd environments/lab/10-cluster
terraform init -backend-config=backend.local.hcl -migrate-state -reconfigure
# where backend.local.hcl is empty (default backend is local)
```

Destroy the storage VM after you've migrated state away:

```bash
just destroy lab 00-storage
```

---

## Architecture

```
Proxmox VM (lab-storage)
├── Debian 13 cloud-image
├── /var/lib/storage              ← XFS, label "storage", on /dev/vdb
│   ├── garage/meta               ← SQLite metadata
│   ├── garage/data               ← object data
│   └── zot                       ← Zot's local cache (S3 backend = Garage)
├── Garage v1.0.1
│   ├── :3900  S3 API             ← used by Terraform backend & by Zot
│   ├── :3901  RPC                ← internal
│   └── :3903  Admin API          ← bucket/key management
└── Zot v2.1.2
    └── :5000  HTTPS              ← OCI registry, self-signed cert
```

Cluster nodes (Talos) point their containerd `machine.registries.mirrors` at `https://lab-storage.lab.lan:5000` with `insecureSkipVerify=true`.

---

## Caveats

- **Single instance.** SPOF for the lab. Garage natively supports multi-node clusters — add nodes and bump `garage_replication_factor`.
- **HTTP on Garage S3 API (`:3900`).** Traffic is internal LAN. Add a reverse proxy (Caddy / Nginx) with Let's Encrypt if you want HTTPS for tfstate access.
- **Self-signed TLS for Zot.** Cluster nodes accept it via `insecure_skip_verify`. For real TLS, distribute the CA via `var.registry_mirror.ca_cert` (PEM) — Talos will trust it.
- **First image pull is still WAN.** Zot is a pull-through cache; subsequent pulls are LAN.
- **State backup is on you.** This stack's state is local. If the storage VM dies and the state is gone too — recovery is harder. Keep a periodic copy elsewhere.

---

## Inputs and outputs

The section below is auto-generated by the `terraform_docs` pre-commit hook. Edit `variables.tf` / `outputs.tf` instead.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 0.69.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../../modules/storage | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_ssh_pubkey"></a> [admin\_ssh\_pubkey](#input\_admin\_ssh\_pubkey) | SSH public key authorised for the 'admin' user on the storage VM. Used for troubleshooting only — Terraform itself does not SSH in. | `string` | n/a | yes |
| <a name="input_debian_image_url"></a> [debian\_image\_url](#input\_debian\_image\_url) | Debian cloud image URL. Tested with Debian 13 (trixie) generic-cloud. | `string` | `"https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"` | no |
| <a name="input_dns_domain"></a> [dns\_domain](#input\_dns\_domain) | DNS domain (must match the dnsmasq domain= on the Proxmox host). Same value as in kubernetes\_iac/. | `string` | `"lab.lan"` | no |
| <a name="input_garage_buckets"></a> [garage\_buckets](#input\_garage\_buckets) | Buckets to create in Garage. terraform-state and oci-blobs are required for the cluster project; the rest reserve room for Velero, Loki, etcd snapshots. | `list(string)` | <pre>[<br/>  "terraform-state",<br/>  "oci-blobs",<br/>  "velero-backups",<br/>  "loki-chunks",<br/>  "etcd-snapshots"<br/>]</pre> | no |
| <a name="input_garage_oci_bucket"></a> [garage\_oci\_bucket](#input\_garage\_oci\_bucket) | Bucket used by Zot as the blob store. | `string` | `"oci-blobs"` | no |
| <a name="input_garage_replication_factor"></a> [garage\_replication\_factor](#input\_garage\_replication\_factor) | Garage replication factor. 1 for single-node lab; 3 for a real cluster. | `number` | `1` | no |
| <a name="input_garage_state_bucket"></a> [garage\_state\_bucket](#input\_garage\_state\_bucket) | Bucket name used by the cluster project as a Terraform S3 backend. | `string` | `"terraform-state"` | no |
| <a name="input_garage_version"></a> [garage\_version](#input\_garage\_version) | Garage release version (https://garagehq.deuxfleurs.fr/download/). | `string` | `"v1.0.1"` | no |
| <a name="input_hostname"></a> [hostname](#input\_hostname) | VM hostname. The VM is reachable as <hostname>.<dns\_domain> via dnsmasq. | `string` | `"lab-storage"` | no |
| <a name="input_prx"></a> [prx](#input\_prx) | Proxmox API endpoint and credentials. Same shape as in kubernetes\_iac/. | <pre>object({<br/>    endpoint  = string<br/>    username  = string<br/>    password  = string<br/>    api_token = string<br/>  })</pre> | n/a | yes |
| <a name="input_prx_datastore_image"></a> [prx\_datastore\_image](#input\_prx\_datastore\_image) | Datastore for the downloaded Debian cloud image. | `string` | `"local"` | no |
| <a name="input_prx_datastore_vm"></a> [prx\_datastore\_vm](#input\_prx\_datastore\_vm) | Datastore for VM disks. | `string` | `"local-zfs"` | no |
| <a name="input_prx_network_bridge"></a> [prx\_network\_bridge](#input\_prx\_network\_bridge) | Proxmox network bridge for the VM (must reach the cluster network). | `string` | `"vmbr1"` | no |
| <a name="input_prx_node"></a> [prx\_node](#input\_prx\_node) | Proxmox cluster node where the storage VM will be created. | `string` | `"mf"` | no |
| <a name="input_vm_resources"></a> [vm\_resources](#input\_vm\_resources) | Resources for the storage VM. data\_disk\_gb is the dedicated data disk for Garage + Zot blobs. | <pre>object({<br/>    cores          = number<br/>    memory_mb      = number<br/>    system_disk_gb = number<br/>    data_disk_gb   = number<br/>  })</pre> | <pre>{<br/>  "cores": 2,<br/>  "data_disk_gb": 180,<br/>  "memory_mb": 4096,<br/>  "system_disk_gb": 20<br/>}</pre> | no |
| <a name="input_zot_version"></a> [zot\_version](#input\_zot\_version) | Zot registry release version (https://github.com/project-zot/zot/releases). v2.1.3+ is required for working sync onDemand (PR #2903 + #3156). | `string` | `"v2.1.16"` | no |

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
| <a name="output_garage_state_bucket"></a> [garage\_state\_bucket](#output\_garage\_state\_bucket) | Bucket reserved for Terraform state (configure as backend.s3.hcl). |
| <a name="output_registry_mirror_tfvars_snippet"></a> [registry\_mirror\_tfvars\_snippet](#output\_registry\_mirror\_tfvars\_snippet) | Ready-to-paste registry\_mirror block for the cluster stack's credentials.auto.tfvars. |
| <a name="output_zot_ca_cert"></a> [zot\_ca\_cert](#output\_zot\_ca\_cert) | Self-signed certificate for Zot. Pass to var.registry\_mirror.ca\_cert in the cluster stack if you prefer real TLS verification over insecure\_skip\_verify. |
| <a name="output_zot_endpoint"></a> [zot\_endpoint](#output\_zot\_endpoint) | Zot OCI registry endpoint (HTTPS, port 5000). Use as registry\_mirror.endpoint in the cluster stack. |
<!-- END_TF_DOCS -->

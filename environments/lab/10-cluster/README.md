# Terraform: Proxmox + Talos + Cilium + Flux GitOps

Fully automated Kubernetes home-lab bootstrap. After a single `terraform apply`:

- **Proxmox** provisions VMs (CP + workers, count is configurable)
- **Talos OS** configures the nodes and brings up the control plane
- **Cilium** is installed as the CNI with kube-proxy replacement and Hubble UI
- **Flux** is bootstrapped from a private GitHub repo and syncs `clusters/<cluster_name>/`

Right after apply the cluster is empty (only `kube-system` + `flux-system`). Further app management goes **via GitOps**: commit YAML to the repo and Flux applies it.

---

## Prerequisites

### 1. Proxmox

- Proxmox VE with storage configured (`local` for ISO, `local-zfs` or another for VM disks)
- API token with permissions: `VM.Allocate`, `Datastore.AllocateSpace`, `SDN.Use`, `VM.Audit`, `VM.Config.Disk`, `Datastore.Allocate`, `Datastore.Audit`
  - The last four (`VM.Audit`, `VM.Config.Disk`, `Datastore.Allocate`, `Datastore.Audit`) are required by the Proxmox CCM and CSI plugin. If you set `enable_proxmox_csi = false` you can omit them.
- SSH agent with access to the Proxmox node (`agent = true` in the provider)

### 2. Networking: dnsmasq + DHCP + DNS

In this configuration node FQDNs are derived from the VM name + `var.dns_domain`. For that to work, `dnsmasq` on the Proxmox host must look like:

```ini
# /etc/dnsmasq.conf on Proxmox
domain-needed
bogus-priv
expand-hosts
domain=lab.lan                         # ← must match var.dns_domain
no-resolv
server=1.1.1.1
interface=vmbr1                        # ← must match var.prx_network_bridge
dhcp-range=10.0.0.20,10.0.0.240,255.255.255.0,72h
dhcp-option=option:router,10.0.0.1
dhcp-option=3,10.0.0.2
dhcp-authoritative
listen-address=127.0.0.1,10.0.0.2
```

`expand-hosts + domain=` is the key combo: dnsmasq automatically registers `<hostname>.<domain>` records, where `<hostname>` is taken from DHCP option 12 that Talos sends after the machineconfig is applied.

Restart dnsmasq after edits: `systemctl restart dnsmasq`.

### 3. Talos image schematic

Get a schematic ID at https://factory.talos.dev — pick:
- arch: `amd64`
- platform: `nocloud`
- target: `cloud`
- extensions: `qemu-guest-agent` (required), `amd-ucode`, `amdgpu` (matching your hardware)

The default in `variables.tf` is the schematic ID for a typical AMD home-lab. If your hardware differs, generate your own and override it in `credentials.auto.tfvars`.

### 4. GitHub Personal Access Token

The token is used to create a private repo and register the deploy key. Create one at https://github.com/settings/tokens with scopes:

- `repo` (full control)
- `admin:public_key`

### 5. Cloudflare

Public ingress is provided via a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — no open ports or public IP required. You need:

- **`cloudflare_api_token`** — a Custom Token (not a Global API Key). Create it at: Cloudflare dashboard → My Profile → API Tokens → Create Custom Token. Required permission scopes:
  - Account › Cloudflare Tunnel › Edit
  - Zone › DNS › Edit _(limited to the zone for `public_domain`)_
  - Zone › Zone › Read _(limited to the zone for `public_domain`)_
- **`cloudflare_account_id`** — 32-character hex ID shown in the right sidebar of the Cloudflare dashboard.
- **`public_domain`** — a DNS zone that already exists and is managed in your Cloudflare account (e.g. `example.com`). Terraform will create DNS CNAME records inside it. The zone must be active (orange-cloud) before apply.
- **`admin_emails`** — list of email addresses allowed through Cloudflare Access on admin-tier apps (Hubble UI, etc.). One-Time PIN works out of the box — Cloudflare emails a code at login time; no pre-registration is needed beyond listing the addresses here.

### 6. Remote state backend (S3-compatible)

The Terraform state contains every secret in this project: Talos machine secrets, kubeconfig, the GitHub PAT, the Flux SSH deploy key. Storing it locally means **file loss = lost cluster control** and **file leak = full compromise**. The repo is configured for an S3-compatible remote backend with native locking (Terraform 1.10+, no DynamoDB needed).

**Pick a backend:**
- **Garage** (recommended for the home lab) — see the sibling project `../storage_bootstrap/`. Lightweight, AGPLv3, runs on a single LXC. Doubles as the OCI registry mirror (`var.registry_mirror`).
- **MinIO**, **AWS S3**, **Cloudflare R2** — anything that speaks the S3 API works.

**Wire it up:**

```bash
cp backend.s3.hcl.example backend.s3.hcl
chmod 600 backend.s3.hcl                      # contains the access/secret keys
$EDITOR backend.s3.hcl                        # fill bucket / endpoint / keys

terraform init -backend-config=backend.s3.hcl
```

`backend.s3.hcl` is gitignored — only the `.example` template is committed. The bucket needs to exist beforehand; for Garage:

```bash
ssh admin@<storage-host> garage bucket create terraform-state
ssh admin@<storage-host> garage key new --name kubernetes-iac
ssh admin@<storage-host> garage bucket allow --read --write --owner terraform-state --key kubernetes-iac
```

**Migrating an existing local state to S3** (one-time): create `backend.s3.hcl`, then `terraform init -backend-config=backend.s3.hcl -migrate-state`. Terraform pushes the local state up and you can delete `terraform.tfstate*` locally.

---

## Install

```bash
# 1. Copy the example configs and fill in your values
cp credentials.auto.tfvars-exemple credentials.auto.tfvars
chmod 600 credentials.auto.tfvars
$EDITOR credentials.auto.tfvars

cp backend.s3.hcl.example backend.s3.hcl       # see Prerequisites #6
chmod 600 backend.s3.hcl
$EDITOR backend.s3.hcl

# 2. Init and validate
terraform init -backend-config=backend.s3.hcl -upgrade
terraform validate

# 3. Bootstrap
terraform apply
```

Typical timing (3 CP + 3 worker, average home-lab):
- Talos image download: 1–3 min
- Proxmox VM creation: 1–2 min
- Apply machine config + bootstrap: 1–2 min
- Wait apiserver + Cilium ready: 2–4 min
- Talos cluster health: 1–2 min
- Flux bootstrap: 1–2 min

**Total: 7–15 minutes**.

After apply, save the configs:

```bash
# Already written locally as ./kubeconfig and ./talosconfig (via local_file).
# To use the standard paths:
cp kubeconfig ~/.kube/config
cp talosconfig ~/.talos/config
```

Sanity checks:

```bash
kubectl get nodes -o wide
cilium status
flux check
flux get sources git -A
```

---

## If `<github_owner>/<github_repo>` already exists

Terraform creates the repo via the `github_repository` resource. If it already exists, apply fails with `422: Repository creation failed`. Options:

**a) Delete the old repo** on GitHub (Settings → Danger Zone → Delete repository) — TF will create it from scratch.

**b) Import the existing one**:
```bash
terraform import 'module.flux_bootstrap.github_repository.flux' <repo_name>
```

**c) Use a different name** — change `github_repo` in `credentials.auto.tfvars`.

---

## Architectural decisions

See `CLAUDE.md` for details. Highlights:

- **DNS instead of IP**: every Talos operation after the initial apply uses FQDNs, not the volatile IPs from qemu-agent. Hostname goes into the Talos machineconfig → propagated via DHCP → dnsmasq registers it.
- **Robust Cilium wait**: instead of `time_sleep` we rely on `null_resource.wait_apiserver` (kubectl polling) + `helm_release.cilium { wait = true, atomic = true }`. No hardcoded sleeps.
- **`data.talos_cluster_health` runs AFTER Cilium**: without a CNI nodes never reach Ready, so the health check would deadlock if scheduled earlier.

---

## Persistent storage (Proxmox CCM + CSI)

`proxmox-csi.tf` (`module.proxmox_csi`) provisions namespace `csi-proxmox` and a
`Secret` with the Proxmox API config shared by the Proxmox Cloud Controller
Manager and the CSI plugin. The kubelet runs with `--cloud-provider=external`
(`external_cloud_provider = true` in `talos_cluster.tf`) so the CCM can stamp
`providerID` onto each node — a hard prerequisite for the CSI plugin.

The CCM/CSI HelmReleases and the default `proxmox-zfs` StorageClass live in the
Flux repo (`infrastructure/controllers/proxmox-{ccm,csi}/`). The Proxmox API
token is reused from `var.prx.api_token`. See `modules/proxmox-csi/README.md`.

> ⚠️ Enabling `external_cloud_provider` rolls a new machineconfig to every node
> (kubelet restart, brief re-register). Apply in a maintenance window.

---

## Monitoring (Phase 2 — observability stack)

`monitoring.tf` provisions the Terraform half of the observability stack, on the
same TF/Flux split as the Cloudflare and Proxmox CSI layers — Terraform owns the
namespace and the sensitive credentials, Flux owns the workload:

- namespace `monitoring` (labelled pod-security=privileged — node-exporter and
  the Alloy DaemonSet need it);
- `Secret/loki-s3-credentials` — Garage S3 keys for Loki's chunk store;
- `Secret/grafana-admin` — generated Grafana admin login.

The `kube-prometheus-stack` + Loki + Grafana Alloy HelmReleases live in the Flux
repo (`infrastructure/controllers/monitoring/`). Grafana is exposed publicly via
`module.app_grafana` (`cloudflare.tf`) behind Cloudflare Access.

`var.enable_monitoring` (default `true`) gates the metrics-exposure changes:
Cilium/Hubble Prometheus metrics (`modules/cilium`) and the
kube-controller-manager / kube-scheduler `bind-address` patch
(`modules/talos-cluster`).

**Prerequisite — Loki S3 key.** Loki needs a Garage S3 key with read+write on
the `loki-chunks` bucket. Create it on the storage VM and put the result into
`var.loki_s3` in `credentials.auto.tfvars`:

```bash
garage key create loki
garage bucket allow --read --write loki-chunks --key loki
garage key info --show-secret loki
```

**After apply — retrieve the Grafana admin password:**

```bash
terraform output -raw grafana_admin_password
```

> ⚠️ `enable_monitoring` flips a Cilium values change (`null_resource.cilium_rollout`
> rolls the whole data plane — brief CNI + Gateway blip) and a CP machineconfig
> change (kube-controller-manager / kube-scheduler restart). Apply in a
> maintenance window.

---

## OCI registry mirror (optional)

The cluster supports a **vendor-neutral pull-through OCI registry mirror** to cut WAN traffic on cluster recreation cycles (Cilium, Flux controllers, kube-system, etc.). Driven by the `var.registry_mirror` variable; works with Garage+Zot, Harbor, Hetzner CR, AWS ECR, or any OCI-compatible registry.

A complete Garage + Zot stack is provided in the sibling project `../storage_bootstrap/` — see its README for setup. After it's up, copy the registry endpoint into `credentials.auto.tfvars` and apply.

### Enable

```hcl
# credentials.auto.tfvars
registry_mirror = {
  endpoint             = "https://lab-storage.lab.lan:5000"
  insecure_skip_verify = true                              # for self-signed certs
  # ca_cert            = file("./registry-ca.pem")         # alternative: trust the CA
}
```

```bash
terraform apply
```

Talos rolls the new machineconfig out to every node. **No reboot required for activation** — containerd hot-reloads `hosts.toml` files on disk. Verify it's working by tailing the registry's logs while a fresh image is pulled (cache hit on the second pull is the proof).

### Disable (rollback to direct upstream pulls)

1. **Comment out** the `registry_mirror` block in `credentials.auto.tfvars`.
2. **`terraform apply`** — the patch is removed from the machineconfig, but Talos does **NOT** delete the on-disk `/etc/cri/conf.d/hosts/<host>/hosts.toml` files left behind by the previous `machine.files` patch.
3. **Reboot every node**, one at a time, to wipe stale `hosts.toml` and regenerate from the (now empty) registries config:

   ```bash
   for ip in $(terraform output -json control_plane_initial_ips worker_initial_ips \
                | jq -r '.[][]'); do
     talosctl --talosconfig=./talosconfig -n "$ip" reboot
     # wait for the node to come back Ready before moving on:
     until kubectl --kubeconfig=./kubeconfig get nodes \
              | awk -v ip="$ip" '$0 ~ ip && $2=="Ready"' | grep -q .; do
       sleep 5
     done
   done
   ```

### Quick off without re-applying

For a temporary bypass (e.g. debugging "is this issue caused by the mirror?"):

```bash
ssh admin@<storage-vm> sudo systemctl stop zot
```

containerd retries the mirror, fails fast, and falls back to upstream. Re-enable: `sudo systemctl start zot`.

### Why a reboot is needed for full disable

`var.registry_mirror` injects the mirror config in two places:

1. **`machine.registries.mirrors`** — Talos generates `hosts.toml` from this. Removing the variable makes Talos generate empty `hosts.toml` next time. ✅ self-cleaning.
2. **`machine.files`** with explicit `hosts.toml` content (workaround for [Talos provider 0.7.x emitting `capabilities=['pull','resolve']` instead of just `['pull']`](https://github.com/siderolabs/terraform-provider-talos/)). When the variable is null, the `machine.files` entries vanish from the patch — but the **files already on disk stay**. Talos has no `op: remove` for `machine.files`. Reboot regenerates the filesystem layer cleanly.

---

## Pre-commit hooks

The repo ships a [`.pre-commit-config.yaml`](./.pre-commit-config.yaml) that gates every commit on:

- **Generic hygiene** ([`pre-commit/pre-commit-hooks`](https://github.com/pre-commit/pre-commit-hooks)): trailing whitespace, end-of-file fixer, merge-conflict markers, added-large-files (> 1 MB), YAML/JSON syntax, private-key detector.
- **Secret scanning** ([`gitleaks`](https://github.com/gitleaks/gitleaks)): catches accidentally staged tokens/keys before they ever leave your machine.
- **Terraform** ([`antonbabenko/pre-commit-terraform`](https://github.com/antonbabenko/pre-commit-terraform)): `terraform fmt`, `terraform validate`, `tflint` (driven by [`.tflint.hcl`](./.tflint.hcl)), `terraform-docs` (auto-regenerates the *Inputs and outputs* section between the `BEGIN_TF_DOCS / END_TF_DOCS` markers).

### One-time setup

```bash
brew install pre-commit gitleaks terraform-docs tflint   # toolchain
pre-commit install                                        # registers .git/hooks/pre-commit
```

### Run on demand

```bash
pre-commit run --all-files                                # full sweep, e.g. after a big refactor
pre-commit autoupdate                                     # bump hook revs to latest tags
```

If a hook auto-fixes a file (whitespace, `terraform_docs`, …) the commit is aborted with an explanation; `git add` the modified files and commit again.

---

## Claude Code automation

The project is integrated with Claude Code — a ready-to-use sub-agent crew lives in `.claude/`:

**Subagents** (`/agents` for the list):
- `terraform-security-auditor`, `terraform-reviewer`, `infra-validator`, `docs-sync-checker` — read-only diagnostics
- `terraform-staff-engineer` — applies edits to `.tf` (self-validates via `infra-validator`)
- `infra-tester` — `terraform plan`, `tflint`/`checkov`, e2e cluster checks

**Slash commands** (only the summary is printed; details live under `.claude/state/`):
- `/audit` — all auditors run in parallel
- `/fix [HIGH|MEDIUM|all|#1,#3]` — apply fixes from last-audit
- `/test [pre|post|auto]` — static or e2e
- `/cycle` — `/audit` → `/fix HIGH` → `/test`, one consolidated report
- `/deploy-prep` — final pre-`terraform apply` check (cycle + connectivity)
- `/post-deploy` — final post-apply checklist (e2e + Flux sync + GitOps next steps)

**Hooks** (`.claude/settings.json`):
- `SessionStart` — at session start Claude sees the project status (credentials present, which CLIs are installed, whether the cluster is up) and the list of available commands.
- `PostToolUse` (Edit/Write on `*.tf|*.tftpl`) — auto `terraform fmt -recursive` + `validate`. On failure the error is injected into Claude's context via `additionalContext` and Claude fixes it itself.
- `Stop` — if the session edited ≥3 .tf files, prints a soft reminder about `/test` or `/cycle`.

`terraform apply` is intentionally not automated — it is destructive and requires a human decision.

---

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Apply hangs on `wait_apiserver` | `talosctl --talosconfig=./talosconfig health`, `talosctl dmesg --follow` |
| Apply fails on `helm_release.cilium` | `kubectl get pods -n kube-system -l k8s-app=cilium`, `kubectl logs -n kube-system <cilium-pod>` |
| Apply fails on `data.talos_cluster_health` | `kubectl get nodes -o wide` — are they all Ready? `kubectl get events -A` |
| Apply fails on `flux_bootstrap_git` | `gh auth status`, `gh repo deploy-key list -R <owner>/<repo>` |
| Talos hostname does not appear in DNS | Check `expand-hosts + domain=` in `/etc/dnsmasq.conf`; `talosctl dmesg \| grep dhcp` |

---

## Recommended GitOps repo layout

After apply, `clusters/<cluster_name>/flux-system/` is created (gotk components). Extend the layout, for example:

```
clusters/<cluster_name>/
├── flux-system/                 # generated by Flux
├── apps.yaml                    # Kustomization → ../../apps/<env>
└── infra.yaml                   # Kustomization → ../../infra/<env>

apps/
├── base/<app>/                  # manifests
└── <env>/kustomization.yaml     # per-environment patches

infra/
└── <component>/                 # ingress, cert-manager, monitoring, ...
```

Any commit to this structure is picked up by Flux within the configured interval (default 1 min for GitRepository, 10 min for Kustomization).

---

## Cluster teardown

```bash
terraform destroy
```

Destroys: Proxmox VMs, the GitHub repo, all local files (`./kubeconfig`, `./talosconfig`, `./terraform.tfstate*`).

### Resources protected by `prevent_destroy`

The following resources carry `lifecycle { prevent_destroy = true }` and will block `terraform destroy` until the lock is removed — saving costly re-creation:

| Resource | File | Reason |
|---|---|---|
| `proxmox_virtual_environment_download_file.talos_nocloud_image` | `00_images.tf` | ~256 MB Talos image; re-downloading from factory.talos.dev takes 1-2 min |

**To actually destroy a protected resource**:

```bash
# Option 1: temporarily comment out the lifecycle block, then destroy.
$EDITOR 00_images.tf   # remove the lifecycle { prevent_destroy = true } block
terraform destroy

# Option 2: drop it from state without touching the live resource.
terraform state rm proxmox_virtual_environment_download_file.talos_nocloud_image
terraform destroy
# Then remove the image manually from Proxmox UI / API if desired.
```

A Talos version bump (`var.talos_version`) re-downloads the image automatically — `prevent_destroy` does not interfere because the `file_name` changes, so Terraform creates a *new* resource and leaves the protected old one alone (delete it manually if you want to free disk space).

---

## Inputs and outputs

The section below is auto-generated by [terraform-docs](https://terraform-docs.io/) via the `terraform_docs` pre-commit hook (see [`.pre-commit-config.yaml`](./.pre-commit-config.yaml)). Do not edit it by hand — your changes will be overwritten on the next commit.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |
| <a name="requirement_flux"></a> [flux](#requirement\_flux) | ~> 1.8 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.12 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 3.1.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.36 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.5 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | 0.69.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | 0.7.1 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.38.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.7.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_app_grafana"></a> [app\_grafana](#module\_app\_grafana) | ../../../modules/cloudflare-public-app | n/a |
| <a name="module_app_headlamp"></a> [app\_headlamp](#module\_app\_headlamp) | ../../../modules/cloudflare-public-app | n/a |
| <a name="module_app_hubble"></a> [app\_hubble](#module\_app\_hubble) | ../../../modules/cloudflare-public-app | n/a |
| <a name="module_cilium"></a> [cilium](#module\_cilium) | ../../../modules/cilium | n/a |
| <a name="module_cloudflare_tunnel"></a> [cloudflare\_tunnel](#module\_cloudflare\_tunnel) | ../../../modules/cloudflare-tunnel | n/a |
| <a name="module_flux_bootstrap"></a> [flux\_bootstrap](#module\_flux\_bootstrap) | ../../../modules/flux-bootstrap | n/a |
| <a name="module_proxmox_csi"></a> [proxmox\_csi](#module\_proxmox\_csi) | ../../../modules/proxmox-csi | n/a |
| <a name="module_talos_cluster"></a> [talos\_cluster](#module\_talos\_cluster) | ../../../modules/talos-cluster | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_namespace.monitoring](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_namespace.renovate](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.grafana_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_secret.loki_s3](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [kubernetes_secret.renovate_credentials](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [random_password.grafana_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [talos_cluster_health.this](https://registry.terraform.io/providers/siderolabs/talos/0.7.1/docs/data-sources/cluster_health) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_emails"></a> [admin\_emails](#input\_admin\_emails) | Email addresses allowed through Cloudflare Access on admin-tier apps (Hubble UI, Grafana, etc.). Each email must be registered as a login identity on the CF Zero Trust dashboard side (One-Time PIN works out of the box — CF sends a code at login time, no pre-registration needed). | `list(string)` | n/a | yes |
| <a name="input_cilium_devices"></a> [cilium\_devices](#input\_cilium\_devices) | Network interfaces Cilium uses for native routing. Glob patterns supported (eth+, ens+). | `string` | `"eth0"` | no |
| <a name="input_cilium_gateway_api_enabled"></a> [cilium\_gateway\_api\_enabled](#input\_cilium\_gateway\_api\_enabled) | Enable Cilium's native Gateway API support (`kind: Gateway` / `kind: HTTPRoute`). Modern replacement for the classic Ingress controller; CRDs are installed via the GitOps repo (infrastructure/controllers/gateway-api-crds/). | `bool` | `true` | no |
| <a name="input_cilium_ingress_enabled"></a> [cilium\_ingress\_enabled](#input\_cilium\_ingress\_enabled) | Enable Cilium's classic Ingress controller (`kind: Ingress`). Set false when migrating to Gateway API — keep one or the other to avoid two LB services competing for the same listener. | `bool` | `false` | no |
| <a name="input_cilium_l2_announcements_enabled"></a> [cilium\_l2\_announcements\_enabled](#input\_cilium\_l2\_announcements\_enabled) | Enable L2 announcements so that LoadBalancer IPs allocated from CiliumLoadBalancerIPPool are reachable on the LAN. Required when using cilium-ingress / cilium-gateway + cilium-lb. | `bool` | `true` | no |
| <a name="input_cilium_version"></a> [cilium\_version](#input\_cilium\_version) | Cilium Helm chart version. | `string` | `"1.17.2"` | no |
| <a name="input_cloudflare_account_id"></a> [cloudflare\_account\_id](#input\_cloudflare\_account\_id) | Cloudflare account ID — find it in the right sidebar of the Cloudflare dashboard. | `string` | n/a | yes |
| <a name="input_cloudflare_api_token"></a> [cloudflare\_api\_token](#input\_cloudflare\_api\_token) | Cloudflare API token. Required scopes:<br/>  - Account › Cloudflare Tunnel › Edit<br/>  - Zone › DNS › Edit (limited to the public domain's zone)<br/>  - Zone › Zone › Read (limited to the public domain's zone)<br/>Create at: Cloudflare dashboard → My Profile → API Tokens → Custom Token. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Talos/Kubernetes cluster name. Used as the hostname prefix for nodes and as the Flux path (clusters/<cluster\_name>). | `string` | `"tl01"` | no |
| <a name="input_cp_resources"></a> [cp\_resources](#input\_cp\_resources) | Resources for each control-plane VM. | <pre>object({<br/>    cores     = number<br/>    memory_mb = number<br/>    disk_gb   = number<br/>  })</pre> | <pre>{<br/>  "cores": 8,<br/>  "disk_gb": 60,<br/>  "memory_mb": 8192<br/>}</pre> | no |
| <a name="input_dns_domain"></a> [dns\_domain](#input\_dns\_domain) | DNS domain that dnsmasq on the Proxmox host registers VM hostnames into (via expand-hosts + domain). Node FQDN: <vm\_name>.<dns\_domain>. | `string` | `"lab.lan"` | no |
| <a name="input_enable_monitoring"></a> [enable\_monitoring](#input\_enable\_monitoring) | Master toggle for the Phase 2 observability stack's Terraform surface.<br/>When true:<br/>  - modules/cilium renders Cilium + Hubble Prometheus metrics and their<br/>    ServiceMonitor objects (monitoring\_enabled);<br/>  - modules/talos-cluster binds kube-controller-manager / kube-scheduler<br/>    metrics on 0.0.0.0 so they are scrapeable (controlplane\_metrics).<br/>Both are machineconfig / Helm-values changes — flipping this rolls the<br/>Cilium data plane and the CP machineconfig. The `monitoring` namespace and<br/>its Secrets (monitoring.tf) and the Grafana public-app (cloudflare.tf) are<br/>created unconditionally — same as the cloudflared tunnel surface. | `bool` | `true` | no |
| <a name="input_enable_proxmox_csi"></a> [enable\_proxmox\_csi](#input\_enable\_proxmox\_csi) | When true, deploys the shared Proxmox config Secret + namespace (via<br/>modules/proxmox-csi) AND runs the kubelet with --cloud-provider=external.<br/>The two must always move together: enabling one without the other either<br/>leaves nodes tainted `uninitialized` forever (CCM absent) or makes the CSI<br/>Secret land before the namespace exists (module absent).<br/>Toggle to false only in environments without the Proxmox CCM/CSI HelmReleases. | `bool` | `true` | no |
| <a name="input_flux_branch"></a> [flux\_branch](#input\_flux\_branch) | Branch in the GitHub repo that Flux watches. | `string` | `"main"` | no |
| <a name="input_flux_path"></a> [flux\_path](#input\_flux\_path) | Path inside the Git repo that Flux watches. Defaults to clusters/<cluster\_name> when null. | `string` | `null` | no |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | GitHub user or organization that owns the Flux repo. | `string` | n/a | yes |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | Name of the GitHub repository that Flux will watch. Created by Terraform as a private repo. | `string` | n/a | yes |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | GitHub Personal Access Token. Required scopes: repo (create + push), admin:public\_key (deploy key). | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for Talos. Passed to data.talos\_machine\_configuration.kubernetes\_version — the provider picks the right image tags for kube-apiserver, scheduler, controller-manager, kubelet. | `string` | `"1.34.0"` | no |
| <a name="input_loki_s3"></a> [loki\_s3](#input\_loki\_s3) | Garage S3 credentials for Loki's chunk store (bucket `loki-chunks`).<br/>monitoring.tf turns these into the `loki-s3-credentials` Secret in the<br/>`monitoring` namespace; the Loki HelmRelease (home-lab-flux) consumes them<br/>as the AWS SDK env vars (AWS\_ACCESS\_KEY\_ID / AWS\_SECRET\_ACCESS\_KEY).<br/><br/>Create a least-privilege key on the storage VM:<br/>  garage key create loki<br/>  garage bucket allow --read --write loki-chunks --key loki<br/>  garage key info --show-secret loki<br/><br/>Endpoint / bucket / region are not secret and are set in the Loki<br/>HelmRelease values, not here. | <pre>object({<br/>    access_key_id     = string<br/>    secret_access_key = string<br/>  })</pre> | n/a | yes |
| <a name="input_num_control_planes"></a> [num\_control\_planes](#input\_num\_control\_planes) | Number of control-plane nodes. 3 is recommended for HA. | `number` | `3` | no |
| <a name="input_num_workers"></a> [num\_workers](#input\_num\_workers) | Number of worker nodes. | `number` | `3` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | CIDR for Cilium pod networks (ipv4NativeRoutingCIDR). | `string` | `"10.244.0.0/16"` | no |
| <a name="input_prx"></a> [prx](#input\_prx) | Proxmox API endpoint and credentials. api\_token must be in the form `user@realm!token-name=<uuid>` (bpg/proxmox format). | <pre>object({<br/>    endpoint  = string<br/>    username  = string<br/>    password  = string<br/>    api_token = string<br/>  })</pre> | n/a | yes |
| <a name="input_prx_datastore_image"></a> [prx\_datastore\_image](#input\_prx\_datastore\_image) | Datastore for the downloaded Talos image (typically 'local' — the ISO storage). | `string` | `"local"` | no |
| <a name="input_prx_datastore_vm"></a> [prx\_datastore\_vm](#input\_prx\_datastore\_vm) | Datastore for VM disks. | `string` | `"local-zfs"` | no |
| <a name="input_prx_network_bridge"></a> [prx\_network\_bridge](#input\_prx\_network\_bridge) | Proxmox network bridge for VMs (the one with dnsmasq + DHCP). | `string` | `"vmbr1"` | no |
| <a name="input_prx_node"></a> [prx\_node](#input\_prx\_node) | Name of the Proxmox cluster node where VMs will be created. | `string` | `"mf"` | no |
| <a name="input_public_domain"></a> [public\_domain](#input\_public\_domain) | Public Cloudflare-managed zone. App hostnames are exposed under <app>.<public\_subdomain>.<public\_domain>. | `string` | n/a | yes |
| <a name="input_public_subdomain"></a> [public\_subdomain](#input\_public\_subdomain) | Optional subdomain level between app names and the public domain. Empty<br/>string (default) places apps at `<app>.<public_domain>` so they fall under<br/>Universal SSL's single-level wildcard (`*.<zone>`) — required on Free plan.<br/><br/>Setting a non-empty value (e.g. "apps") yields `<app>.apps.<public_domain>`<br/>— DNS works but TLS handshake fails on Free plan because Universal SSL does<br/>not cover two-level wildcards. To use a non-empty value, enable Cloudflare<br/>ACM / Total TLS or buy an Advanced Certificate Pack (both ~$10/mo). | `string` | `""` | no |
| <a name="input_registry_mirror"></a> [registry\_mirror](#input\_registry\_mirror) | Optional pull-through OCI registry mirror. When set, Talos containerd is<br/>configured to fetch from this endpoint first for ghcr.io / docker.io /<br/>registry.k8s.io / quay.io. Vendor-neutral — works with Garage+Zot, Harbor,<br/>Hetzner Container Registry, AWS ECR, Docker Hub Pro mirror, etc.<br/><br/>- endpoint: full URL incl. scheme and (optional) port. Example: "https://lab-storage.lab.lan:5000".<br/>- insecure\_skip\_verify: true if the mirror uses a self-signed certificate<br/>  and you do not want to distribute its CA. Trade-off: TLS verification is<br/>  disabled for THIS mirror only (not for upstream registries).<br/>- ca\_cert: PEM-encoded CA bundle to trust the mirror; mutually exclusive<br/>  with insecure\_skip\_verify in practice. | <pre>object({<br/>    endpoint             = string<br/>    insecure_skip_verify = optional(bool, false)<br/>    ca_cert              = optional(string, null)<br/>  })</pre> | `null` | no |
| <a name="input_renovate_github_token"></a> [renovate\_github\_token](#input\_renovate\_github\_token) | GitHub fine-grained PAT for the self-hosted Renovate bot. Scoped to both repos with Contents / Pull requests / Workflows / Issues = Read and write. Delivered as the renovate-credentials Secret (RENOVATE\_TOKEN). | `string` | n/a | yes |
| <a name="input_talos_schematic_id"></a> [talos\_schematic\_id](#input\_talos\_schematic\_id) | Schematic ID from factory.talos.dev (hash of the system-extensions bundle). Identical across Talos versions for the same extensions. Generate one at https://factory.talos.dev/ | `string` | `"aeec243e3a4c2a14f9ba74b1a8c7662f03eea658a7ea5f1c26fdd491280c88f8"` | no |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos OS version (image tag on factory.talos.dev). | `string` | `"v1.13.0"` | no |
| <a name="input_worker_resources"></a> [worker\_resources](#input\_worker\_resources) | Resources for each worker VM. | <pre>object({<br/>    cores     = number<br/>    memory_mb = number<br/>    disk_gb   = number<br/>  })</pre> | <pre>{<br/>  "cores": 12,<br/>  "disk_gb": 120,<br/>  "memory_mb": 16000<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudflare_tunnel_cname_target"></a> [cloudflare\_tunnel\_cname\_target](#output\_cloudflare\_tunnel\_cname\_target) | Tunnel CNAME target (<tunnel-id>.cfargotunnel.com). Point extra DNS records here to route additional zones into the tunnel. |
| <a name="output_cloudflare_tunnel_id"></a> [cloudflare\_tunnel\_id](#output\_cloudflare\_tunnel\_id) | UUID of the Cloudflare Tunnel — same value the cloudflared Deployment reads via the TUNNEL\_ID ConfigMap. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | API server endpoint (FQDN). |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Cluster name. |
| <a name="output_control_plane_fqdns"></a> [control\_plane\_fqdns](#output\_control\_plane\_fqdns) | FQDNs of all control-plane nodes. |
| <a name="output_control_plane_initial_ips"></a> [control\_plane\_initial\_ips](#output\_control\_plane\_initial\_ips) | Initial IPs of CP nodes (from qemu-agent, before DNS settles). Handy for debugging the first apply. |
| <a name="output_flux_path"></a> [flux\_path](#output\_flux\_path) | Path inside the repository that Flux watches. |
| <a name="output_flux_repository_ssh_url"></a> [flux\_repository\_ssh\_url](#output\_flux\_repository\_ssh\_url) | SSH URL used by Flux for git operations. |
| <a name="output_flux_repository_url"></a> [flux\_repository\_url](#output\_flux\_repository\_url) | URL of the Git repository Flux watches. |
| <a name="output_grafana_admin_password"></a> [grafana\_admin\_password](#output\_grafana\_admin\_password) | Generated Grafana admin password (user: admin). Retrieve with: terraform output -raw grafana\_admin\_password |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Kubeconfig (for kubectl). Also written to ./kubeconfig. |
| <a name="output_proxmox_csi_config_secret_name"></a> [proxmox\_csi\_config\_secret\_name](#output\_proxmox\_csi\_config\_secret\_name) | Name of the shared Proxmox config Secret. Wire as existingConfigSecret in the CCM and CSI HelmReleases. Null when enable\_proxmox\_csi = false. |
| <a name="output_proxmox_csi_namespace"></a> [proxmox\_csi\_namespace](#output\_proxmox\_csi\_namespace) | Namespace holding the shared Proxmox config Secret. The CCM + CSI HelmReleases (Flux) deploy here. Null when enable\_proxmox\_csi = false. |
| <a name="output_public_apps"></a> [public\_apps](#output\_public\_apps) | FQDN → CF Access status map for all apps exposed via the tunnel. |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Talos client config (for talosctl). Also written to ./talosconfig. |
| <a name="output_worker_fqdns"></a> [worker\_fqdns](#output\_worker\_fqdns) | FQDNs of all worker nodes. |
| <a name="output_worker_initial_ips"></a> [worker\_initial\_ips](#output\_worker\_initial\_ips) | Initial IPs of worker nodes. |
<!-- END_TF_DOCS -->

---

## References

- https://www.talos.dev/v1.13/talos-guides/install/cloud-platforms/proxmox/
- https://docs.cilium.io/en/stable/installation/k8s-install-helm/
- https://fluxcd.io/flux/installation/bootstrap/github/
- https://registry.terraform.io/providers/bpg/proxmox/latest/docs
- https://registry.terraform.io/providers/siderolabs/talos/latest/docs
- https://registry.terraform.io/providers/fluxcd/flux/latest/docs

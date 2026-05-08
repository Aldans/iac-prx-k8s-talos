# CLAUDE.md

Context file for AI assistants working on this monorepo. Helps grasp the project quickly without re-discovering everything.

## Project goal

Terraform monorepo for a self-hosted Kubernetes home lab on Proxmox. Two layered stacks bring it up end-to-end:

1. **`environments/<env>/00-storage`** — Garage (S3-compatible object store) + Zot (OCI registry mirror) on a Proxmox VM. Provides remote Terraform state for the next stack and an LAN image cache for the cluster.
2. **`environments/<env>/10-cluster`** — Talos OS VMs → Cilium CNI → Flux CD GitOps. After `apply` the cluster is ready and watching a GitHub repo for app manifests.

GitOps manifests live in a separate sibling repo at `../home-lab-flux/` (Phase 3). `10-cluster` creates the GitHub repo via `flux_bootstrap_git`; you push the baseline (cilium-lb + cert-manager + ingress-nginx + apps/skeleton) from `home-lab-flux/`, Flux syncs it. See `../home-lab-flux/README.md`.

Stack:
- **Proxmox VE** — hypervisor (one or more physical nodes)
- **Talos OS** — immutable OS for K8s nodes (no SSH, everything via `talosctl`)
- **Cilium** — CNI with kube-proxy replacement, Hubble UI, native routing
- **Flux CD** — GitOps controller, bootstrapped via the `fluxcd/flux` Terraform provider
- **Garage + Zot** — S3 backend + OCI mirror, decoupled and replaceable (any S3 / any OCI registry works the same way)

Networking model — **DHCP + DNS via `dnsmasq` on the Proxmox host**. Hostnames sent in DHCP option 12 land in DNS automatically thanks to `expand-hosts + domain=…`. This lets every Talos `node`/`endpoint` field address nodes by FQDN (e.g. `tls-cp-01.lab.lan`) instead of brittle IPs.

## Repo layout

```
.
├── environments/<env>/
│   ├── 00-storage/                    # Garage + Zot bootstrap. Local TF state (chicken-and-egg).
│   │   ├── 00_image.tf … 04_vm.tf
│   │   ├── cloud-init/cloud-config.yaml.tftpl
│   │   ├── credentials.auto.tfvars[-exemple]
│   │   └── README.md
│   └── 10-cluster/                    # Talos + Cilium + Flux. Remote TF state in 00-storage's Garage.
│       ├── 00_images.tf … 04_flux.tf
│       ├── providers.tf variables.tf outputs.tf
│       ├── helm/cilium/cilium-values.yaml.tftpl
│       ├── backend.s3.hcl[.example]   # gitignored; .example is the template
│       ├── credentials.auto.tfvars[-exemple]
│       └── README.md                  # cluster deep-dive, troubleshooting
├── modules/                           # reusable modules (Phase 2 — empty for now)
├── tests/                             # native TF tests (`*.tftest.hcl`)
├── docs/adr/                          # Architecture Decision Records
├── .github/workflows/                 # CI (Phase 4)
├── .claude/                           # agents, slash commands, hooks
├── .pre-commit-config.yaml .tflint.hcl .editorconfig
├── Justfile                           # `just <recipe>` — wraps the common terraform flows
└── README.md CLAUDE.md TODO.md
```

The numeric prefixes inside a stack (`00_images.tf`, `01_vms.tf`, …) are **just reading order** — Terraform builds the graph from references. Numeric prefixes on **stack directories** (`00-storage`, `10-cluster`), on the other hand, do imply apply order.

## Apply order (one-time bootstrap)

```bash
# Stack 1: storage. State is local — chmod-protect afterwards.
just init lab 00-storage
just apply lab 00-storage
chmod 600 environments/lab/00-storage/terraform.tfstate*

# Wire 10-cluster's S3 backend at the just-provisioned Garage.
cp environments/lab/10-cluster/backend.s3.hcl{.example,}
chmod 600 environments/lab/10-cluster/backend.s3.hcl
$EDITOR environments/lab/10-cluster/backend.s3.hcl   # access keys from `terraform output -state environments/lab/00-storage/terraform.tfstate`

# Stack 2: cluster.
just init lab 10-cluster
just apply lab 10-cluster

just save lab    # kubeconfig + talosconfig → ~/.kube + ~/.talos
just status      # nodes + cilium + flux
```

## Solving the "Cilium hangs" failure mode (10-cluster)

**Symptom** (in the previous version): right after `talos_machine_bootstrap` Helm tries to install Cilium, gets `connection refused` from the API server, and the cluster gets stuck.

**Root cause**: `talos_machine_bootstrap` returns as soon as etcd is initialized, which **does not** mean the API server is answering. A hardcoded `time_sleep 120s` is a guess. And `data.talos_cluster_health` cannot be used **before Cilium** — it waits for nodes to be Ready, but nodes never reach Ready without a CNI = deadlock.

**The current solution:**

```
talos_machine_bootstrap
    ↓
null_resource.wait_apiserver       # bash polling: kubectl get --raw='/readyz'
    ↓                                up to 5 min, retry every 5 s
helm_release.cilium                # wait=true, atomic=true, timeout=600
    ↓                                Helm waits for Cilium pods to become Ready
data.talos_cluster_health          # safe now — CNI is up
    ↓
flux_bootstrap_git
```

No hardcoded timeouts — only real probes.

## Known limitations

- **Single-endpoint kubeconfig**: `cluster_endpoint` points at the first CP's FQDN. If that CP physically dies, external `kubectl` cannot connect (etcd quorum inside the cluster keeps working). Full HA needs a Talos VIP — backlogged (TODO #9).
- **GitHub repo creation**: if `${github_owner}/${github_repo}` already exists, `apply` fails with 422. Workaround: `terraform import module.flux_bootstrap.github_repository.flux ${repo_name}` or delete the old repo first.
- **`00-storage` state is local**: chicken-and-egg — Garage stores state but Garage itself does not exist yet on first apply. Mitigations: chmod 600, periodic backup of `environments/<env>/00-storage/terraform.tfstate*` to NAS / encrypted USB.

## Protected resources (prevent_destroy)

Two resources intentionally refuse `terraform destroy` to avoid accidental data loss:

- `module.talos_cluster.proxmox_virtual_environment_download_file.talos_nocloud_image` — saves the multi-minute Talos image download on rebuild.
- `module.flux_bootstrap.github_repository.flux` — the cluster's GitOps history. Talos is ephemeral; the repo is not.

Destroying either requires `terraform state rm <addr>` first (Terraform stops tracking it, then destroy proceeds for everything else). Full procedure with rebuild-import flow is in `modules/flux-bootstrap/README.md`.

## Networking conventions (10-cluster)

- VM name = Talos hostname = DNS name:
  - `tls-cp-XX.${var.dns_domain}` — control plane
  - `tls-wr-XX.${var.dns_domain}` — worker
- The hostname is set inside Talos via the `machine.network.hostname` config patch — Talos forwards it in DHCP option 12, dnsmasq registers the DNS record.
- The **first machine-config apply** uses the temporary IP from qemu-agent; everything afterwards goes by FQDN.

## Versions (pinned)

| Component | Version | Note |
|---|---|---|
| Talos | `v1.13.0` | `var.talos_version` |
| Kubernetes | `1.34.x` | Talos picks the right tags; pinned in machineconfig |
| Cilium | `1.17.2` | `helm_release.cilium.version` |
| Flux | latest 2.x chart | via provider |
| provider bpg/proxmox | `0.69.0` | stable — do not bump without reading the changelog |
| provider siderolabs/talos | `0.7.1` | stable |
| provider hashicorp/helm | `3.1.1` | new (3.x) syntax |
| provider fluxcd/flux | `~> 1.8` | |
| provider integrations/github | `~> 6.12` | |
| provider hashicorp/kubernetes | `~> 2.36` | (3.x is a major bump — separate upgrade task) |
| provider hashicorp/tls | `~> 4.0` | for the Flux SSH deploy key |
| provider hashicorp/local | `~> 2.5` | for the local_file kubeconfig/talosconfig |
| provider hashicorp/null | `~> 3.2` | for null_resource.wait_apiserver |

## Working conventions

- **Never** use `element(flatten(ipv4_addresses), N)` — too brittle, qemu-agent returns addresses in unpredictable order. Use FQDN from `var.dns_domain` instead.
- **Never** rely on `time_sleep` to wait for K8s readiness. Use `null_resource` with a polling provisioner or `helm_release.wait = true`.
- **Never** hardcode `cluster.name` inside `cilium-values.yaml` — use `templatefile()` with `var.cluster_name`.
- Secrets live exclusively in `credentials.auto.tfvars` per stack (gitignored, `chmod 600`). In code, only `var.*` with `sensitive = true`.
- **Pre-commit hooks** (`.pre-commit-config.yaml`) gate every commit: gitleaks, `terraform fmt/validate/tflint`, `terraform-docs` (regenerates *Inputs and outputs* between `<!-- BEGIN_TF_DOCS -->` markers in each stack's `README.md`), plus generic hygiene. Edits inside the markers will be overwritten — change `variables.tf`/`outputs.tf` instead. Setup: `brew install pre-commit gitleaks terraform-docs tflint just && pre-commit install`.
- **GitHub Actions CI** (`.github/workflows/terraform-checks.yml`) is the server-side mirror — runs the same checks on every PR + push to `main`, plus `checkov` for security baseline. `terraform plan` is deliberately not in CI: the Garage S3 backend lives on the home-lab LAN and is unreachable from GitHub-hosted runners. Adding plan-on-PR later requires a self-hosted runner.
- **Multi-env via copy, not Terraform workspaces.** New env: `cp -a environments/lab environments/staging`, edit tfvars + backend key. Workspaces share configuration but split state — when env-specific patches diverge, that's a footgun.

## Debugging paths

- Apply fails on `wait_apiserver` → `talosctl --talosconfig=environments/lab/10-cluster/talosconfig health` and `talosctl dmesg`.
- Apply fails on `helm_release.cilium` → `kubectl get pods -n kube-system -l k8s-app=cilium`, then `kubectl logs -n kube-system <cilium-pod> -c cilium-agent`.
- Apply fails on `flux_bootstrap_git` → `gh auth status`, `gh repo deploy-key list -R ${owner}/${repo}`.
- Cluster state: `just status` (nodes + cilium + flux at a glance).

## Agent crew and hooks

`.claude/` houses a full multi-agent setup. **Agents and slash commands operate on individual stack directories** — pass `cwd` or run from the stack root.

**Agents** (`.claude/agents/`):
- `terraform-security-auditor` — security review
- `terraform-reviewer` — code quality
- `infra-validator` — fmt/validate/lock/versions
- `docs-sync-checker` — README / CLAUDE / example sync
- `terraform-staff-engineer` — applies edits + self-validates (calls infra-validator via the `Agent` tool)
- `infra-tester` — plan/tflint/checkov + e2e (kubectl/cilium/flux)

**Slash commands** (`.claude/commands/`):
- `/audit` — 4 auditors in parallel → `.claude/state/last-audit.md`
- `/fix [scope]` — staff-engineer applies fixes (scope = HIGH | HIGH+MEDIUM | all | #1,#3)
- `/test [mode]` — infra-tester in pre-apply / post-apply / auto
- `/cycle` — `/audit` → `/fix HIGH` → `/test`
- `/deploy-prep` — final readiness gate before `terraform apply`
- `/post-deploy` — after `apply`: e2e + Flux sync + GitOps next steps

**Hooks** (`.claude/settings.json`):
- `SessionStart` → checks `credentials.auto.tfvars`, CLIs (`terraform`/`jq`/`talosctl`), infra state (kubeconfig present or not), prints slash-command list
- `PostToolUse` Edit/Write on `*.tf|*.tftpl` → auto `terraform fmt -recursive` + `validate` for the stack containing the file
- `Stop` → if ≥3 `.tf` files were edited, soft reminder about `/test` or `/cycle`

**Intentionally NOT automated:**
- `terraform apply` / `destroy` — destructive, always manual
- Auto-running `/audit` after every fix — recursion risk

## What to do after apply

The cluster is empty — only `flux-system` and `kube-system`. Apps are added **via GitOps only**: push manifests into `${github_repo}` under `clusters/${cluster_name}/` (or directories pulled in from there: `apps/`, `infra/`), and Flux applies them.

Typical layout in the Flux repo:
```
clusters/${cluster_name}/
  ├── flux-system/         # generated by flux_bootstrap_git
  ├── infra.yaml           # Kustomization → infra/
  └── apps.yaml            # Kustomization → apps/
infra/
  └── ingress-nginx/
apps/
  └── my-app/
```

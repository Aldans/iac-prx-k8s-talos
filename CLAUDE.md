# CLAUDE.md

Context file for Claude Code. Helps Claude grasp the project quickly without re-discovering everything.

## Project goal

Terraform IaC for **fully automated** Kubernetes home-lab bootstrap on Proxmox. After `terraform apply` the user gets a ready-to-use GitOps cluster: just commit manifests to the GitHub repository and Flux syncs them into the cluster.

Stack:
- **Proxmox VE** — hypervisor (one or more physical nodes)
- **Talos OS** — immutable OS for K8s nodes (no SSH, everything via `talosctl`)
- **Cilium** — CNI with kube-proxy replacement, Hubble UI, native routing
- **Flux CD** — GitOps controller, bootstrapped directly via the `fluxcd/flux` Terraform provider

Networking model — **DHCP + DNS via `dnsmasq` on the Proxmox host**. Hostnames sent in DHCP option 12 land in DNS automatically thanks to `expand-hosts + domain=…`. This lets every Talos `node`/`endpoint` field address nodes by FQDN (e.g. `tls-cp-01.lab.lan`) instead of brittle IPs.

## File layout (after refactor)

```
.
├── 00_images.tf               # Talos image download into Proxmox storage
├── 01_vms.tf                  # CP / worker VMs (for_each over num_*)
├── 02_talos.tf                # machine_secrets, configs, bootstrap, kubeconfig
├── 03_cilium.tf               # wait_apiserver + helm_release.cilium
├── 04_flux.tf                 # github_repository + deploy key + flux_bootstrap_git
├── providers.tf               # ALL required_providers + provider blocks
├── variables.tf               # all input variables with defaults
├── outputs.tf                 # all outputs (kubeconfig, talosconfig, IPs/FQDNs)
├── credentials.auto.tfvars    # secrets (gitignored)
├── credentials.auto.tfvars-exemple
└── helm/
    └── cilium/
        └── cilium-values.yaml.tftpl  # values template, cluster.name = var.cluster_name
```

The numeric prefix represents the logical reading order, not dependency — Terraform builds the graph itself via `depends_on` and references.

## How to deploy

### Prerequisites

1. **Proxmox API token** with `VM.Allocate`, `Datastore.AllocateSpace`, `SDN.Use`.
2. **dnsmasq on Proxmox** configured with `expand-hosts + domain=<your-domain>` (see README).
3. **Talos schematic ID** for the desired extensions (qemu-guest-agent is required) — generate at https://factory.talos.dev.
4. **GitHub Personal Access Token** with `repo` (private repo create + push) and `admin:public_key` (deploy key).

### Commands

```bash
terraform init -upgrade
terraform validate
terraform apply
```

After a successful apply:
```bash
terraform output -raw kubeconfig > ~/.kube/config
terraform output -raw talosconfig > ~/.talos/config
```

`local_file` resources also write `./kubeconfig` and `./talosconfig` next to the project — both are in `.gitignore`.

## Solving the "Cilium hangs" failure mode

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

No hardcoded timeouts — only real probes. If anything fails, it fails fast with a meaningful error.

## Known limitations

- **Single-endpoint kubeconfig**: `cluster_endpoint` points at the first CP's FQDN. If that CP physically dies, external `kubectl` cannot connect (etcd quorum inside the cluster keeps working). Full HA needs a Talos VIP — backlogged (requires a reserved IP in the dnsmasq DHCP range).
- **GitHub repo is created by TF**: if `${github_owner}/${github_repo}` already exists, `terraform apply` fails. Workaround: `terraform import github_repository.flux ${repo_name}` or delete the old repo manually.
- **State stored locally** (`./terraform.tfstate`). Every secret lives there — Talos machine secrets, kubeconfig, GitHub token, SSH deploy key. Do not commit, do not share. Future plan: move to an S3/MinIO backend.

## Networking conventions

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
- Secrets live exclusively in `credentials.auto.tfvars` (in `.gitignore`). In code, only `var.*` with `sensitive = true`.
- **Pre-commit hooks** (`.pre-commit-config.yaml`) gate every commit: gitleaks, `terraform fmt/validate/tflint`, `terraform-docs` (regenerates the *Inputs and outputs* block in `README.md` between `<!-- BEGIN_TF_DOCS -->` markers), plus generic hygiene (trailing-ws, EOF, large-files, private-key, etc.). Edits inside the markers will be overwritten — change `variables.tf` / `outputs.tf` instead. Setup: `brew install pre-commit gitleaks terraform-docs tflint && pre-commit install`.

## Debugging paths

- If apply fails on `wait_apiserver` — check `talosctl --talosconfig=./talosconfig health` and `talosctl dmesg`.
- If apply fails on `helm_release.cilium` — `kubectl get pods -n kube-system -l k8s-app=cilium` for status, then `kubectl logs -n kube-system <cilium-pod> -c cilium-agent`.
- If apply fails on `flux_bootstrap_git` — verify the GitHub token (`gh auth status`) and the deploy key (`gh repo deploy-key list -R ${owner}/${repo}`).
- Cluster state: `kubectl get nodes -o wide`, `cilium status`, `flux check`, `flux get sources git -A`, `flux get kustomizations -A`.

## Agent crew and hooks

`.claude/` houses a full multi-agent setup:

**Agents** (`.claude/agents/`):
- `terraform-security-auditor` — security review
- `terraform-reviewer` — code quality
- `infra-validator` — fmt/validate/lock/versions
- `docs-sync-checker` — README / CLAUDE / example sync
- `terraform-staff-engineer` — applies edits + self-validates (calls infra-validator via the `Agent` tool)
- `infra-tester` — plan/tflint/checkov + e2e (kubectl/cilium/flux)

**Slash commands** (`.claude/commands/`):
- `/audit` — 4 auditors in parallel → `.claude/state/last-audit.md`
- `/fix [scope]` — staff-engineer applies fixes from last-audit (scope = HIGH | HIGH+MEDIUM | all | #1,#3)
- `/test [mode]` — infra-tester in pre-apply / post-apply / auto mode
- `/cycle` — `/audit` → `/fix HIGH` → `/test`, single consolidated report
- `/deploy-prep` — final readiness gate before `terraform apply`: cycle + connectivity (Proxmox API, GitHub PAT, Talos image, DNS)
- `/post-deploy` — after `terraform apply`: e2e + Flux GitRepository/Kustomization sync + GitOps next steps

**Hooks** (`.claude/settings.json`):
- `SessionStart` → checks credentials.auto.tfvars, presence of `terraform`/`jq`/optional CLIs, infra state (kubeconfig present or not), and prints the slash-command list
- `PostToolUse` Edit/Write on `*.tf|*.tftpl` → auto `terraform fmt` + `validate`. On error the message is injected into Claude's context via `additionalContext` and Claude fixes it itself
- `Stop` → if the session edited ≥3 .tf files, prints a soft reminder about `/test` or `/cycle`

**Intentionally NOT automated:**
- `terraform apply` / `destroy` — destructive, always manual
- Auto-running `/audit` after every fix — recursion risk (fix → audit → new findings → fix …)

## What to do after apply

The cluster is empty — only `flux-system` and `kube-system`. Apps are added **via GitOps only**: push manifests into `${github_repo}` under `clusters/${cluster_name}/` (or directories pulled in from there: `apps/`, `infra/`), and Flux applies them.

A typical layout:
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

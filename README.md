# home-lab-infra

Terraform monorepo for a self-hosted Kubernetes home lab on Proxmox. Layered into independent **stacks** that can be applied (and destroyed) one at a time:

| Stack | Contents | State |
|---|---|---|
| **`environments/<env>/00-storage`** | Garage (S3-compatible state + blob store) + Zot (OCI registry mirror) on a single Proxmox VM | local (chicken-and-egg with the bucket itself) |
| **`environments/<env>/10-cluster`** | Talos VMs → Cilium CNI → Flux GitOps → kubeconfig/talosconfig | remote in `00-storage`'s Garage bucket |

GitOps manifests live in a **separate sibling repo** at [`../home-lab-flux/`](../home-lab-flux/) — `10-cluster` creates the GitHub repo via `flux_bootstrap_git`, you push the baseline (cilium-lb + cert-manager + ingress-nginx + apps skeleton) from `home-lab-flux/`, Flux syncs it. See [`../home-lab-flux/README.md`](../home-lab-flux/README.md) for the layout and bootstrap workflow.

---

## Layout

```
.
├── environments/                       ← stacks (one Terraform working dir each)
│   └── lab/
│       ├── 00-storage/                 ← Garage + Zot bootstrap
│       └── 10-cluster/                 ← Talos + Cilium + Flux
├── modules/                            ← reusable modules (Phase 2 — empty for now)
├── tests/                              ← native TF tests (`*.tftest.hcl`)
├── docs/
│   └── adr/                            ← Architecture Decision Records
├── .github/workflows/                  ← CI (Phase 4)
├── .claude/                            ← Claude Code agents, slash commands, hooks
├── .pre-commit-config.yaml             ← gitleaks + terraform fmt/validate/tflint/docs
├── .tflint.hcl                         ← TFLint config
├── .editorconfig
├── Justfile                            ← `just <recipe>` for common workflows
├── CLAUDE.md                           ← context for AI assistants
└── TODO.md                             ← prioritized backlog
```

Each stack has its own README with the deep-dive (variables, outputs, deploy steps, gotchas).

---

## Apply order (one-time bootstrap)

```bash
# 1. Bring up Garage + Zot. State is local — chmod-protect and back it up.
just init lab 00-storage
just apply lab 00-storage
chmod 600 environments/lab/00-storage/terraform.tfstate*

# 2. Plug Garage into Terraform state for the cluster stack.
cp environments/lab/10-cluster/backend.s3.hcl.example \
   environments/lab/10-cluster/backend.s3.hcl
chmod 600 environments/lab/10-cluster/backend.s3.hcl
$EDITOR environments/lab/10-cluster/backend.s3.hcl   # endpoint + access keys from 00-storage outputs

# 3. Bring up the cluster.
just init lab 10-cluster
just apply lab 10-cluster

# 4. Save kubeconfig + talosconfig.
just save lab
just status
```

For the deep checklist — variables, validation, troubleshooting — see the per-stack READMEs:

- [`environments/lab/00-storage/README.md`](environments/lab/00-storage/README.md)
- [`environments/lab/10-cluster/README.md`](environments/lab/10-cluster/README.md)

---

## Day-to-day workflow

Everything common is wrapped in the [`Justfile`](./Justfile):

```bash
just                          # list all recipes
just plan lab 10-cluster      # cd + terraform plan
just apply lab 10-cluster
just save lab                 # ./kubeconfig + ./talosconfig → ~/.kube + ~/.talos
just status                   # nodes + cilium + flux at a glance
just lint                     # pre-commit run --all-files
```

---

## Adding a new environment

```bash
cp -a environments/lab environments/staging
$EDITOR environments/staging/00-storage/credentials.auto.tfvars
$EDITOR environments/staging/10-cluster/credentials.auto.tfvars
$EDITOR environments/staging/10-cluster/backend.s3.hcl   # different state key
```

Every env owns its own state, its own VMs, and its own Flux repo.

> **Why explicit env directories instead of Terraform workspaces?** Workspaces share the configuration but split state by name — a footgun when the env diverges (`var.cilium_devices = "ens+"` only on prod, etc.). Explicit directories make the diff visible and grep-able.

---

## Tooling

| Tool | Role |
|---|---|
| **Terraform ≥ 1.10** | IaC engine. Native S3 locking via `use_lockfile` (no DynamoDB). |
| **pre-commit** | Auto-runs `gitleaks`, `terraform fmt/validate/tflint/docs`, hygiene hooks on every `git commit`. See [`.pre-commit-config.yaml`](.pre-commit-config.yaml). |
| **GitHub Actions** | Server-side mirror of pre-commit + checkov security scan. Runs on every PR and push to `main`. See [`.github/workflows/terraform-checks.yml`](.github/workflows/terraform-checks.yml). |
| **just** | Workflow runner — `just <recipe>`. |
| **Claude Code** | Multi-agent crew under `.claude/` (auditors, staff-engineer, infra-tester) with slash commands `/audit`, `/fix`, `/test`, `/cycle`, `/deploy-prep`, `/post-deploy`. |

Setup once on a new clone:

```bash
brew install terraform pre-commit gitleaks terraform-docs tflint just
pre-commit install
```

---

## Status & roadmap

Backlog is in [`TODO.md`](./TODO.md). Closed so far:

- ✅ #1 Remote state backend (Garage S3 + native locking)
- ✅ #2 Pre-commit hooks
- ✅ #5 GitHub Actions CI (fmt + validate + tflint + gitleaks + checkov)
- ✅ #6 Reusable modules (`modules/{cilium,flux-bootstrap,talos-cluster,storage}`)
- ✅ #7 GitOps template baseline (sibling repo `../home-lab-flux/` — cilium-lb + cert-manager + ingress-nginx)
- ✅ #11 terraform-docs auto-generation

Next:

- 🟡 #3 Dedicated `terraform@pve` Proxmox user (replace `root@pam`)
- 🔴 #4 etcd backup strategy
- 🟢 #10 Architecture Decision Records

---

## License

Personal home-lab project. No license — ask before reusing.

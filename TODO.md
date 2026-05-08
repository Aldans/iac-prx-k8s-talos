# TODO — improvements roadmap

Prioritized backlog of professional-grade improvements for this home-lab IaC.
Based on the post-deploy review (2026-05-07).

> **2026-05-08 — Monorepo restructure: Phase 1 ✅** Both `kubernetes_iac` and
> `storage_bootstrap` now live in a single repo as
> `environments/lab/{00-storage,10-cluster}`. Top-level `README.md` is
> navigation; per-stack READMEs hold the deep-dive. Justfile + `.editorconfig`
> added. Phase 2 (extract `modules/*`) is TODO #6 below.

Legend:
- 🔴 **P0** — must-have for serious operation
- 🟡 **P1** — significant value
- 🟢 **P2** — polish & maturity
- 🔵 **P3** — advanced

---

## 🔴 P0 — Critical for serious operation

### 1. Remote state backend ✅ DONE (2026-05-07)
**Problem:** `terraform.tfstate` lives locally and contains every secret (Talos machine secrets, kubeconfig, GitHub PAT, SSH deploy key). File loss = lost cluster control. File leak = full compromise.

**Implemented:**
- `backend "s3" {}` in `providers.tf` (partial config) + `backend.s3.hcl` (gitignored, `chmod 600`) for credentials.
- Native Terraform 1.10+ locking via `use_lockfile = true` — no DynamoDB needed.
- Currently points at Garage in the home-lab (`../storage_bootstrap/`); any S3-compatible backend works.
- Setup documented in `README.md` → *Prerequisites → #5 Remote state backend*; template in `backend.s3.hcl.example`.

---

### 2. Pre-commit hooks ✅ DONE (2026-05-07)
**Problem:** Nothing prevents accidentally committing secrets, broken HCL or unformatted files.

**Implemented:** `.pre-commit-config.yaml` wires:
- `gitleaks` (secret scanning)
- `terraform_fmt`, `terraform_validate`, `terraform_tflint` (config in `.tflint.hcl`)
- `terraform_docs` (regenerates *Inputs and outputs* in README between `<!-- BEGIN_TF_DOCS -->` markers — covers item #11)
- `end-of-file-fixer`, `trailing-whitespace`, `check-merge-conflict`, `check-added-large-files`, `check-yaml`, `check-json`, `detect-private-key`

Setup: see *Pre-commit hooks* in `README.md`.

This also closes **#11 (terraform-docs auto-generation)** — the markers and hook are wired up.

---

### 3. Dedicated Proxmox `terraform@pve` user
**Problem:** Currently the provider uses `root@pam` — a Terraform leak grants root on the hypervisor.

**Solution:**
- Create a Proxmox user `terraform@pve` and a role with the minimum required permissions: `VM.Allocate`, `VM.Config.*`, `VM.Audit`, `VM.PowerMgmt`, `Datastore.AllocateSpace`, `Datastore.Audit`, `SDN.Use`.
- Issue an API token for that user.
- Update `credentials.auto.tfvars-exemple` and document `pveum` commands in the README.

**Effort:** 1 hour.

---

### 4. etcd backup strategy
**Problem:** A CP catastrophe (disk failure, ZFS pool loss, fat-finger destroy) wipes everything. No recovery point.

**Solution:**
- Schedule `talosctl etcd snapshot` to MinIO/S3 (every 6h).
- Implement either as a CronJob via FluxCD (using `talosctl` in a pod) or as a systemd timer on the Proxmox host.
- Document the restore procedure in `docs/disaster-recovery.md`.

**Effort:** 2-3 hours.

---

## 🟡 P1 — Significant value

### 5. CI/CD pipeline (GitHub Actions)
**Problem:** Quality checks run only locally; PRs may merge without verification.

**Solution:** `.github/workflows/`:
- `terraform-checks.yml` — fmt, validate, tflint, checkov, trivy, gitleaks on every PR.
- `terraform-plan.yml` — `terraform plan` posted as a PR comment.
- (Advanced) Atlantis or Terraform Cloud for PR-driven apply.

**Effort:** 2-3 hours.

---

### 6. Reusable modules — Phase 2 of the monorepo restructure
**Problem:** Each `environments/lab/{00-storage,10-cluster}` still has all logic inline. Spinning up `staging` means full file-by-file copy.

**Solution:** Extract from `10-cluster`:
- `modules/talos-cluster/` — VMs + machine secrets + machine config + bootstrap + kubeconfig
- `modules/cilium/` — CNI Helm release + `wait_apiserver`
- `modules/flux-bootstrap/` — `github_repository` + deploy key + `flux_bootstrap_git`

And from `00-storage`:
- `modules/storage/` — Garage + Zot VM with cloud-init

After extraction the env roots become 30-line compositions. New env = copy of one root + tfvars.

**Effort:** 4-6 hours.

---

### 7. GitOps template repo
**Problem:** The Flux repository is empty after bootstrap; the user has to design the layout and pick components.

**Solution:** A separate repo `flux-template-mf` with a working baseline:
- `cert-manager` + Let's Encrypt issuer.
- `ingress-nginx` (or Cilium L7 ingress).
- `external-secrets-operator` + 1Password/Vault provider.
- `kube-prometheus-stack` (Prometheus + Grafana + Alertmanager + Hubble metrics).
- `loki-stack` (logs).
- `sealed-secrets` for bootstrap secrets.
- `velero` (backup of K8s objects to MinIO).

This becomes the "starter pack" pulled in via Flux Kustomizations.

**Effort:** 1-2 days.

---

### 8. Renovate / Dependabot
**Problem:** Provider versions drift (today: `bpg/proxmox 0.69.0` is 37 minors behind latest). Talos and Cilium chart versions also drift. Manual upgrades are easy to forget.

**Solution:** `.github/renovate.json` watching:
- Terraform providers in `.terraform.lock.hcl`.
- `var.talos_version`, `var.cilium_version` (regex-driven version-ranges).
- Helm chart versions in the Flux repo.
- Renovate opens PRs with version bumps; CI tests them; user reviews and merges.

**Effort:** 30 min.

---

## 🟢 P2 — Polish & maturity

### 9. Talos VIP for true HA control plane
**Problem:** `cluster_endpoint` points at `tls-cp-01.lab.lan`. If CP[0] dies, external `kubectl` cannot connect (etcd quorum is fine internally).

**Solution:**
- Reserve a static IP in dnsmasq DHCP range (e.g. `10.172.19.250`).
- Add `machine.network.interfaces[].vip.ip` in the Talos config patch — Talos handles VIP failover between CPs.
- Change `local.cluster_endpoint` to use the VIP FQDN.

**Effort:** 1-2 hours + dnsmasq tweak.

---

### 10. Architecture Decision Records (ADRs)
**Problem:** Decisions like "FQDN over IP", "certSANs", "KubePrism over VIP for now" live only in scattered code comments and in this conversation. Future-you (or new contributors) will not have the context.

**Solution:** `docs/adr/` with 5 initial records:
- ADR-001: FQDN-based addressing for Talos resources.
- ADR-002: Robust Cilium wait via `wait_apiserver` polling.
- ADR-003: `data.talos_cluster_health` placement after Cilium.
- ADR-004: `certSANs` for talosctl FQDN connectivity.
- ADR-005: Provider version pinning policy.

**Effort:** 1-2 hours.

---

### 11. terraform-docs auto-generation ✅ DONE (2026-05-07, via #2)
**Problem:** README sections about variables/outputs drift from `variables.tf` / `outputs.tf`.

**Implemented:** `BEGIN_TF_DOCS / END_TF_DOCS` markers in `README.md` under *Inputs and outputs*; the `terraform_docs` pre-commit hook regenerates the section on every commit.

---

### 12. Project hygiene
- `CHANGELOG.md` with conventional commits / release-please.
- `CONTRIBUTING.md` with PR guidelines.
- GitHub branch protection on `main` (PR-only, CI required, signed commits).
- `.editorconfig` for consistent indentation across editors.
- GPG-signed commits.

**Effort:** 1-2 hours total.

---

## 🔵 P3 — Advanced

### 13. Terratest integration tests
Real infra tests in Go that apply → verify → destroy a temporary cluster on every PR. Catches regressions that `terraform plan` cannot.

**Effort:** 1-2 days.

---

### 14. Multi-cluster / multi-environment
Workspace-based separation: dev/staging/prod with `var.environment`. Separate `cp_resources` per env.

**Effort:** 1 day.

---

### 15. SOPS / sealed-secrets workflow
Encrypted manifests in the Flux repo so secrets can be committed safely.

**Effort:** half a day.

---

### 16. OIDC auth for kubectl
Replace static-token kubeconfig with Dex/Authentik + OIDC. Centralised user management, MFA, audit.

**Effort:** 1-2 days.

---

### 17. Pod Security Standards + CiliumNetworkPolicies
Default-deny network policy + namespace-level Pod Security labels. CIS-aligned baseline.

**Effort:** half a day.

---

### 18. kube-bench periodic CIS compliance check
Automated CIS audits via `kube-bench` CronJob; results to Prometheus.

**Effort:** 1-2 hours.

---

## Combined infrastructure ideas

### Shared storage backbone: Garage + Zot (recommended)

Rather than shipping two separate stacks for "remote state" (P0 #1) and "image acceleration" (the Cilium pull pain), they can share a storage layer.

#### Stack of choice

- **Garage** (https://garagehq.deuxfleurs.fr/) as the S3-compatible storage backbone.
  - Truly AGPLv3 open source (no enterprise feature lock-in like MinIO).
  - Single Rust binary, ~256 MB RAM at idle, geo-aware by design.
  - Buckets: `terraform-state`, `oci-blobs`, future `velero-backups`, `loki-chunks`, `etcd-snapshots`.
- **Zot** (https://zotregistry.dev/) as the OCI registry.
  - Single Go binary, ~30 MB RAM, S3 backend out of the box.
  - Pull-through mirror for `ghcr.io`, `docker.io`, `registry.k8s.io`, `quay.io`.
  - Built-in image scanning (Trivy) and cosign verification — useful for hardening later.
- Both fit into a single LXC or VM (≈4 GB RAM, ~200 GB disk).

#### How the cluster picks it up

Talos `machine.registries.mirrors` redirects Containerd to the local Zot, with self-signed TLS handled by `insecureSkipVerify = true` (this only weakens TLS verification for the LAN registry, not for the cluster as a whole):

```yaml
machine:
  registries:
    mirrors:
      ghcr.io:
        endpoints:
          - https://registry.lab.lan
      docker.io:
        endpoints:
          - https://registry.lab.lan
      registry.k8s.io:
        endpoints:
          - https://registry.lab.lan
      quay.io:
        endpoints:
          - https://registry.lab.lan
    config:
      registry.lab.lan:
        tls:
          insecureSkipVerify: true
```

This goes into `local.common_machine_config_patch` in `02_talos.tf` and is applied automatically through `talos_machine_configuration_apply`.

#### Wins

- **One stack solves two problems** (P0 #1 state backend + image acceleration).
- **Cilium pull drops from WAN minutes to LAN seconds** on the second cluster bootstrap (warm cache).
- **Foundation for everything else**: Velero backups, Loki chunks, etcd snapshots all reuse the same Garage cluster.
- **Truly open source** — Garage is AGPLv3 without enterprise carve-outs; survives the MinIO licensing trend.

#### Caveats

- TLS for Zot — self-signed in the simplest setup; Talos handles `insecureSkipVerify` cleanly.
- Single-node Garage is a SPOF; acceptable in a home lab, but Garage natively scales to a multi-node cluster (zone-aware replica placement).
- Talos machine-config update is required to wire mirrors in — reapplied automatically by Terraform.
- Garage has no native Web UI; manage via CLI (`garage bucket list`, `garage key new`) or community projects (`garage-webui`).

#### Considered alternatives

| Option | Verdict |
|---|---|
| **MinIO + Zot** | Works fine; mature; rich Web Console. **Downside**: license trend trims community features (admin replication, ILM UI). Garage is cleaner long-term. |
| **SeaweedFS** | Lightweight and fast, but S3 compatibility has gaps; Velero/Loki edge cases reported. Pick if you want object + file + block in one. |
| **Ceph (RGW)** | Industrial-grade but needs 3+ nodes, 8+ GB RAM each. Overkill for a single-host home lab. Revisit on lab v2. |
| **Distribution registry** | Classic Docker registry; lacks Zot's OCI-native feel and built-in scan/cosign. Acceptable fallback. |
| **Harbor** | Full enterprise platform (Postgres + Redis + 5 services). Overkill unless you need RBAC + replication + scan UI. |
| **Spegel (in-cluster P2P)** | Complementary, not a replacement. Add later: Zot fronts the WAN, Spegel propagates blobs node-to-node inside the cluster via mTLS gRPC. |

#### Tentative implementation plan

1. **Stage 1 — bootstrap module** (≈3-4 h): a separate Terraform root or `modules/storage/` that provisions a Proxmox VM/LXC with Garage + Zot, generates a self-signed TLS cert via `tls_self_signed_cert`, exposes outputs (endpoint, access keys).
2. **Stage 2 — wire state backend** (≈1 h): add a `terraform { backend "s3" { ... } }` block to the cluster project, point at Garage with `use_lockfile = true` (TF 1.10+ native locking — no DynamoDB needed), `terraform init -migrate-state`.
3. **Stage 3 — wire registry mirror** (≈1 h): extend `local.common_machine_config_patch` with `machine.registries.mirrors`, `terraform apply` rolls it out across all nodes.
4. **(Later)** add Spegel as a Flux HelmRelease for in-cluster P2P propagation.

# TODO — improvements roadmap

Prioritized backlog of professional-grade improvements for this home-lab IaC.
Based on the post-deploy review (2026-05-07).

> **2026-05-08 — Monorepo restructure: Phase 1 ✅** Both `kubernetes_iac` and
> `storage_bootstrap` now live in a single repo as
> `environments/lab/{00-storage,10-cluster}`. Top-level `README.md` is
> navigation; per-stack READMEs hold the deep-dive. Justfile + `.editorconfig`
> added. Phase 2 (extract `modules/*`) is TODO #6 below.

> **2026-05-10 — Cloudflare Tunnel baseline ✅** Added `cloudflared` Deployment
> in `home-lab-flux/infrastructure/controllers/cloudflared/`. Named-tunnel
> mode (token-based, routes managed in CF Zero Trust dashboard). 2 replicas,
> read-only rootfs, non-root, metrics on :2000. Tunnel token is the only
> manual step — `kubectl create secret`, NOT in git. Migrate to locally-
> managed config (config.yaml + credentials.json) once sealed-secrets lands
> (TODO #7-followup). Closes the "no public IP" gap for the home lab.

> **2026-05-17 — Hubble UI publicly exposed end-to-end ✅** First app live:
> `https://hubble.dvlab.top` — TLS via Universal SSL `*.dvlab.top`, CF Access
> with email-OTP (`seopakc.05@gmail.com`), cloudflared HTTPS-upstream to
> Cilium Gateway, in-cluster HTTPRoute `apps/base/hubble-ui` serves the
> request unchanged. Two follow-up fixes during testing:
>
> 1. **cloudflared was hitting the http listener (:80)** while HTTPRoutes
>    attach only to the https section → 404. Fixed by switching the route
>    `service` to `https://cilium-gateway-lab.gateway.svc.cluster.local:443`
>    with `noTLSVerify: true` + `originServerName` for SNI.
> 2. **cloudflared does NOT auto-reload `config.yaml`** — needs `kubectl
>    rollout restart deployment cloudflared`. Earlier README/comment claim
>    about inotify-reload was wrong; corrected in Flux PR #7.

> **2026-05-14 — TLS reality check + single-level hostnames ✅** Per-app
> records on the *two-level* depth (`<app>.apps.<zone>`) still failed TLS
> handshake — `ERR_SSL_VERSION_OR_CIPHER_MISMATCH`. Root cause: Free Universal
> SSL covers `<zone>` + `*.<zone>` only, NOT hostname-specific certs at
> deeper levels. Auto-issuance for arbitrary depth needs **Total TLS** (lives
> inside paid ACM, ~$10/mo). Cert-manager in-cluster does NOT help — browser
> talks to CF edge first, so the edge cert is what matters.
>
> Decision: stay on Free plan, move apps to single-level `<app>.<public_domain>`
> (covered by Universal SSL's `*.dvlab.top`). Changed default of
> `var.public_subdomain` from `"apps"` to `""`. Migrated hubble:
> `hubble.apps.dvlab.top` → `hubble.dvlab.top` (1 destroy + 1 add on DNS,
> 1 update in-place on Access app).
>
> `cloudflare_total_tls` resource removed from `modules/cloudflare-tunnel/`
> (file `tls.tf` kept as a documented stub for future paid-plan re-enable).
> Flux PR #5 updated cloudflared routing table. `originRequest.httpHostHeader`
> still rewrites to `hubble.apps.lab.lan` — internal Gateway routing
> untouched, only the public-side hostname changed.

> **2026-05-14 — Per-app public pattern ✅** Tested the wildcard CNAME end-to-
> end: TLS handshake failed because Free Universal SSL covers only one
> wildcard level (`*.dvlab.top`), not two-level (`*.apps.dvlab.top`). Switched
> to per-app DNS records:
> - New module `modules/cloudflare-public-app/` — creates one CNAME per app +
>   optional `cloudflare_zero_trust_access_application` (SSO gate via CF
>   Access; allow-by-email / allow-by-domain).
> - Wildcard `*.apps` CNAME destroyed via `terraform apply` (1 destroy, 0 add).
> - `public_subdomain` variable moved from `cloudflare-tunnel` module to
>   `10-cluster` root — `cloudflare-tunnel` is now purely tunnel-side.
> - `cloudflare-tunnel` keeps `data.cloudflare_zone` (exposes `zone_id`) so
>   downstream `cloudflare-public-app` instances reuse it.
> - Adding a public app is now two steps: `module "app_xxx" { ... }` in
>   `10-cluster/cloudflare.tf` (`terraform apply`) + ingress rule in
>   `home-lab-flux/.../cloudflared/configmap.yaml` (`git push`).
>
> Alternative paths still on the table if per-app records become annoying at
> scale: paid Advanced Certificate ($10/mo, wildcard works), Total TLS, or
> origin TLS via cert-manager DNS-01.

> **2026-05-14 — Cloudflare Tunnel — full IaC ✅** Promoted the baseline to a
> proper two-layer setup:
> - **Terraform** (`modules/cloudflare-tunnel/` + `environments/lab/10-cluster/cloudflare.tf`):
>   provisions the CF Tunnel (`config_src=local`), the wildcard CNAME
>   `*.apps.dvlab.top`, and writes `cloudflared-credentials` Secret +
>   `cloudflared-tunnel-id` ConfigMap into the cluster.
> - **Flux** (`infrastructure/controllers/cloudflared/configmap.yaml`):
>   `config.yaml` holds the route table (pure GitOps). The Deployment runs
>   `cloudflared tunnel run $(TUNNEL_ID)`, where `TUNNEL_ID` comes from the
>   TF-managed ConfigMap via `envFrom`. This decouples routes (Flux) from
>   tunnel identity (TF).
> - Renamed `claudeflare_*` → `cloudflare_*` in `credentials.auto.tfvars`.
>   Added `cloudflare/cloudflare ~> 5.0` and `hashicorp/random ~> 3.6`
>   providers to `10-cluster/providers.tf`.
> - Side-fix: `provider "kubernetes"` in `10-cluster/providers.tf` referenced
>   the moved `local_file.kubeconfig` (pre-existing dangling ref from the
>   Phase-2 module split); switched to `module.talos_cluster.kubeconfig_path`
>   to match `provider "helm"`. `terraform validate` now passes.
> - Catch-all `http_status:404` is the only default route — adding public
>   apps = PR to `configmap.yaml`. See `cloudflared/README.md` for the
>   `httpHostHeader`-rewrite vs second-Gateway-listener trade-off.

> **2026-05-08 — Cilium ConfigMap-only upgrade gotcha ✅ RESOLVED.** Original
> issue: `terraform apply` that flips Cilium feature flags updates
> `cilium-config` ConfigMap but the chart does not stamp a checksum on the
> pod template, so DaemonSet hash is unchanged and pods don't restart →
> new feature inactive until manual `kubectl rollout restart`. Hit this 3×
> while shipping Cilium Ingress, L2 announcements, and Gateway API.
>
> Fix:
> - `modules/cilium` now has `null_resource.cilium_rollout` triggered by
>   `sha256(rendered_helm_values)`. After every helm upgrade, it runs
>   rollout-restart in the right order (operator → ds/cilium → ds/cilium-envoy)
>   with sane timeouts. Toggle: `var.rollout_on_values_change` (default true).
> - `Justfile` recipe `just rollout-cilium` covers the manual fallback
>   (auto-rollout disabled, rollout failed mid-apply, ConfigMap edited
>   out-of-band).

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

### 5. CI/CD pipeline (GitHub Actions) ✅ DONE (2026-05-08)
**Problem:** Quality checks run only locally; PRs may merge without verification.

**Implemented:** `.github/workflows/terraform-checks.yml` runs on every PR and push to `main`:
- `fmt` — `terraform fmt -check -recursive` (blocking)
- `validate` — `terraform init -backend=false && validate` over each stack and each module (blocking; matrix job)
- `tflint` — same `.tflint.hcl` as local pre-commit, walks every stack and module (blocking)
- `gitleaks` — full-history secret scan (blocking)
- `checkov` — Terraform-aware security baseline (`soft_fail: true` initially — comments on PR but does not block merge; flip to hard-fail after triaging the first PR's findings)

**Not yet:** `terraform plan` on PR. Garage S3 backend lives on the home-lab LAN, unreachable from GitHub-hosted runners. Adding plan-on-PR later requires a self-hosted runner on the Proxmox host. Tracked as a follow-up.

**Follow-up tasks** (out of scope for this PR):
- Configure GitHub branch protection on `main`: require all CI checks green, no force-push, signed commits.
- After the first PR runs, triage `checkov` findings and flip `soft_fail` to `false`.
- Replace the deprecated `proxmox_virtual_environment_download_file` resource with `proxmox_download_file` (warning surfaced by `terraform validate` on bpg/proxmox 0.106+).

---

### 6. Reusable modules ✅ DONE (2026-05-08, Phase 2 of the monorepo restructure)
**Problem:** Each `environments/lab/{00-storage,10-cluster}` still has all logic inline. Spinning up `staging` means full file-by-file copy.

**Implemented:** Four modules, all stacks now thin compositions.

| Module | Resources | Stack root reduced to |
|---|---|---|
| `modules/cilium` | 2 (`wait_apiserver`, `helm_release`) + helm template | `cilium.tf` ~20 lines |
| `modules/flux-bootstrap` | 4 (key, repo, deploy key, bootstrap) | `flux.tf` ~20 lines |
| `modules/talos-cluster` | ~24 (image, VMs, secrets, machine_configs, bootstrap, kubeconfig) | `talos_cluster.tf` ~30 lines |
| `modules/storage` | 9 (image, randoms, TLS, cloud-init, VM) | `main.tf` ~30 lines |

State migration done via `moved {}` blocks in each stack's `moved.tf` — verified `terraform plan = 0/0/0` after each round. Adding a new env (`staging`) is now `cp -a environments/lab environments/staging` + tfvars edits.

---

### 7. GitOps template repo ✅ DONE (2026-05-08, baseline only)
**Problem:** The Flux repository is empty after bootstrap; the user has to design the layout and pick components.

**Implemented:** Sibling repo `../home-lab-flux/` (separate git workspace). Standard Flux multi-tenancy layout:

```
clusters/lab/                     ← entry-point Kustomizations: infrastructure.yaml + apps.yaml
infrastructure/
  ├── sources/                    ← HelmRepositories (jetstack, ingress-nginx)
  ├── controllers/                ← cilium-lb, cert-manager, ingress-nginx (Helm releases)
  └── configs/cluster-issuers/    ← selfsigned + LE staging (LE prod stub commented out)
apps/{base,lab}/                  ← user-app skeleton
```

Validated locally: 20/20 yaml parse, kustomize build all subtrees green, kubectl --dry-run=client accepts cluster-level Kustomizations.

**Workflow** (in `../home-lab-flux/README.md`): `terraform apply lab 10-cluster` → repo created on GitHub → `git remote add origin … && git pull --rebase && git push -u origin main` → Flux syncs in ~1 minute.

**Customisations needed before first push** (placeholders in code, called out in README):
- LB IP-pool range (must fit dnsmasq DHCP exclusion zone)
- L2 announcement interface name (`eth0` default)
- ACME email (Let's Encrypt contact)

### 7-followup. GitOps baseline expansion (NOT done)
The remaining components from the original wishlist are deferred until there is a concrete need — each carries non-trivial decisions (which secret backend? which storage class? which monitoring vendor?). Add when needed:
- `external-secrets-operator` (+ 1Password / Vault / SOPS provider)
- `kube-prometheus-stack` (Prometheus + Grafana + Alertmanager + Hubble metrics)
- `loki-stack` (logs)
- `sealed-secrets` for bootstrap secrets
- `velero` (K8s object backup to Garage)
- `letsencrypt-prod` ClusterIssuer (uncomment after staging is verified end-to-end)

This becomes the "starter pack" pulled in via Flux Kustomizations.

**Effort:** 1-2 days.

---

### 8. Renovate / Dependabot ✅ DONE (2026-06-16)
**Problem:** Provider versions drift (`bpg/proxmox 0.69.0` was ~40 minors behind). Talos, Cilium and Helm chart versions also drift. Manual upgrades are easy to forget.

**Implemented:** Self-hosted Renovate as an in-cluster CronJob (NOT the Mend App / Dependabot) — namespace `renovate`, weekly Mon 06:00 `America/Los_Angeles`. GitHub token Terraform-managed (`environments/lab/10-cluster/renovate.tf`); CronJob + global config in Flux (`home-lab-flux/infrastructure/controllers/renovate/`). Watches **both** repos via a root `renovate.json` in each:
- Terraform providers (`iac-prx-k8s-talos`) + GitHub Actions + pre-commit hooks.
- Flux Helm chart versions + container images (`flux-mf`); `flux`/`kubernetes` managers pointed at `infrastructure/**` (their defaults miss it).
- `customManagers` (regex) for the version vars the built-in TF manager can't see: `talos_version`, `cilium_version`, `garage_version`, `zot_version`.
- Approval-gated **Dependency Dashboards** (`dependencyDashboardApproval`) — no PR floods; low-risk automerge for GitHub Actions / pre-commit patch+digest only. `terraform apply` and PR merges stay manual.
- `flux-mf` also gained a `validate` CI (kustomize build + kubeconform) so chart/image bumps are caught before merge, not at reconcile.

First update round landed (GitHub Actions majors, `cloudflared`, `kube-prometheus-stack 85.4.0`, headlamp plugin digest pins). Deferred (review per changelog): provider `proxmox`/`kubernetes`/`talos` majors, `cilium`/`loki`/`kube-prometheus-stack` majors, `cert-manager`; Talos OS + storage-VM bumps need a maintenance window.

**Note:** plan + grabel'i in `../renovate-deploy-plan.md` (sibling of the repo).

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

---
description: Final post-apply checklist — e2e via infra-tester + Flux GitRepository/Kustomization sync verification. GitOps next-steps hints.
argument-hint: ""
---

The user has just run `terraform apply` and invokes `/post-deploy` to verify the result.

Goal: confirm the cluster is up correctly and Flux really syncs from the repository. Provide concrete next steps for adding apps via GitOps.

## Steps

### 1. Verify artefacts exist

```bash
test -f kubeconfig || echo "MISSING_KUBECONFIG"
test -f talosconfig || echo "MISSING_TALOSCONFIG"
```

If either is missing, apply did not complete. Abort and ask the user to inspect `terraform show` or the most recent apply log.

### 2. /test post via infra-tester

Delegate:
```
Agent(subagent_type: infra-tester, prompt: "Run a post-apply (Mode B) test. The cluster was just deployed; please run all e2e checks: talosctl health, kubectl get nodes, cilium status, flux check, GitRepository, Kustomization. Report in the standard format.")
```

Save the report to `.claude/state/last-test.md`.

### 3. Extra Flux checks

Inline Bash (don't use a sub-agent — these are simple one-liners):

```bash
export KUBECONFIG=./kubeconfig

# 3a. Flux GitRepository ready
kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
# Expect "True"

# 3b. Kustomization ready
kubectl -n flux-system get kustomization flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
# Expect "True"

# 3c. flux-system pods
kubectl -n flux-system get pods --no-headers | awk '{print $1, $3}'
# Should all be Running

# 3d. SSH deploy key wired into the repo?
kubectl -n flux-system get secret flux-system -o jsonpath='{.data.identity}' 2>/dev/null | head -c 20
# Non-empty = key is in the cluster

# 3e. Latest reconcile of Kustomization
kubectl -n flux-system get kustomization flux-system -o jsonpath='{.status.lastAppliedRevision}'
# Should be a SHA from the main branch
```

### 4. Cilium checks (if cilium CLI is installed)

```bash
which cilium && cilium status --kubeconfig=./kubeconfig 2>&1 | head -20
```

If `cilium connectivity test --quiet` is available, do NOT run it by default (5+ min, spins up test pods). Run only on explicit request.

### 5. Pod restarts

```bash
kubectl get pods -A --no-headers | awk '$5+0 > 0 {print $1, $2, "restarts:", $5}'
# Should be empty. If not — list of pods with restart counts.
```

### 6. Final report

```
🟢/🟡/🔴 post-deploy

E2E (from infra-tester): <verdict>

Talos:
  health                      ✅ / ❌
  nodes Ready                 N/N

Cilium:
  pods                        ✅ X/X Running
  status (cli)                ✅ OK / not installed

Flux:
  GitRepository ready         ✅ True / ❌
  Kustomization ready         ✅ True / ❌
  reconcile revision          <sha>
  flux-system pods            ✅ all Running

Pod restarts (any ns)         ✅ 0 / ⚠️ <count>

GitOps readiness: 🟢 / 🟡 / 🔴

Next steps:
1. Bootstrap the initial layout in <repo_url>:
   clusters/<cluster_name>/apps.yaml         (Kustomization → ../../apps/base)
   clusters/<cluster_name>/infra.yaml        (Kustomization → ../../infra/base)
   apps/base/<my-app>/                       (your manifests)
   infra/base/<component>/                   (ingress, cert-manager, etc.)

2. Push to the main branch — Flux syncs within ~1 min (GitRepository interval).

3. Monitoring:
   flux logs -A --tail 50
   flux get all -A
   kubectl events -A --sort-by=.lastTimestamp | tail -20

Artefacts:
- .claude/state/last-test.md
```

## Principles

- If something critical broke (Flux GitRepository not Ready, nodes NotReady), make the report explicitly 🔴 NOT HEALTHY with top-3 actions.
- Do not run `kubectl delete`, `flux uninstall`, `terraform destroy`.
- Do NOT run `cilium connectivity test` automatically (slow).
- If the kubeconfig is broken (timeout, x509 error), ask the user to verify DHCP/dnsmasq and that the cluster_endpoint FQDN resolves.
- Do not duplicate what infra-tester already covered — focus on Flux-specific bits.

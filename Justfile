# home-lab-infra — Justfile
# Run `just` (no args) to list all recipes. https://just.systems/man/

set positional-arguments

# === Defaults ===============================================================

# List all recipes
default:
    @just --list

# === Per-stack Terraform commands ===========================================
# Usage: `just plan lab 10-cluster`, `just apply lab 00-storage`

# terraform init for a stack. Auto-picks `backend.s3.hcl` if present (10-cluster);
# otherwise falls back to local-state init (00-storage).
init env stack:
    cd environments/{{env}}/{{stack}} && \
      if [ -f backend.s3.hcl ]; then \
        terraform init -backend-config=backend.s3.hcl -upgrade ; \
      else \
        terraform init -upgrade ; \
      fi

# terraform validate
validate env stack:
    cd environments/{{env}}/{{stack}} && terraform validate

# terraform plan (extra args after stack are passed through)
plan env stack *args:
    cd environments/{{env}}/{{stack}} && terraform plan {{args}}

# terraform apply
apply env stack *args:
    cd environments/{{env}}/{{stack}} && terraform apply {{args}}

# terraform destroy — refuses without confirmation flag
destroy env stack *args:
    cd environments/{{env}}/{{stack}} && terraform destroy {{args}}

# terraform output (raw, JSON, or named output)
output env stack *args:
    cd environments/{{env}}/{{stack}} && terraform output {{args}}

# === Cluster shortcuts (10-cluster) =========================================

# Save kubeconfig + talosconfig from <env>/10-cluster into ~/.kube and ~/.talos
save env="lab":
    cd environments/{{env}}/10-cluster && \
      terraform output -raw kubeconfig > ~/.kube/config && \
      terraform output -raw talosconfig > ~/.talos/config && \
      chmod 600 ~/.kube/config ~/.talos/config && \
      echo "✅ Saved kubeconfig + talosconfig from {{env}}/10-cluster to ~/.kube/ and ~/.talos/"

# Cluster status: nodes + cilium + flux. Assumes ~/.kube/config is current cluster.
status:
    @echo "=== Nodes ==="
    @kubectl get nodes -o wide
    @echo
    @echo "=== Cilium ==="
    @cilium status --wait-duration 5s || true
    @echo
    @echo "=== Flux ==="
    @flux check
    @flux get sources git -A
    @flux get kustomizations -A

# Manually rollout-restart Cilium (operator first, then ds/cilium and ds/cilium-envoy).
# modules/cilium does this automatically on values change (var.rollout_on_values_change),
# but use this recipe when:
#  - the auto-rollout is disabled (var.rollout_on_values_change = false)
#  - kubectl rollout failed mid-apply and you want to retry without `terraform apply`
#  - the cilium-config ConfigMap was edited out-of-band and pods need to pick it up
rollout-cilium:
    @echo "=== rollout-restart cilium-operator ==="
    kubectl -n kube-system rollout restart deploy/cilium-operator
    kubectl -n kube-system rollout status  deploy/cilium-operator --timeout=180s
    @echo "=== rollout-restart ds/cilium and ds/cilium-envoy ==="
    kubectl -n kube-system rollout restart ds/cilium ds/cilium-envoy
    kubectl -n kube-system rollout status  ds/cilium       --timeout=300s
    kubectl -n kube-system rollout status  ds/cilium-envoy --timeout=300s
    @echo "✅ Cilium rolled."

# === Repo-wide ===============================================================

# Run all pre-commit hooks on every file
lint:
    pre-commit run --all-files

# Bump pre-commit hook revisions to latest tags
update-hooks:
    pre-commit autoupdate

# Format all Terraform recursively (pre-commit handles this on commit; manual fallback)
fmt:
    terraform fmt -recursive

#!/usr/bin/env bash
# SessionStart hook: inspects the project environment and tells Claude (via
# additionalContext) what is ready, what is not, and which commands are available.
# No blocking — purely informational.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

# Accumulate context lines.
LINES=()

# 1. Check credentials.auto.tfvars
if [ ! -f credentials.auto.tfvars ]; then
  LINES+=("⚠️ credentials.auto.tfvars is missing. Copy: cp credentials.auto.tfvars-exemple credentials.auto.tfvars and fill it in.")
else
  # Also check that the file is not still a blank template.
  if grep -q "your-proxmox-host\|your-password\|ghp_xxxxxxxxxxxx" credentials.auto.tfvars 2>/dev/null; then
    LINES+=("⚠️ credentials.auto.tfvars still contains placeholders (your-proxmox-host / ghp_xxxx) — fill them with real values.")
  fi
fi

# 2. Tooling check
MISSING_TOOLS=()
for cmd in terraform jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING_TOOLS+=("$cmd")
  fi
done

OPTIONAL_MISSING=()
for cmd in kubectl talosctl flux cilium tflint checkov trivy; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    OPTIONAL_MISSING+=("$cmd")
  fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  LINES+=("❌ Required tools missing: $(IFS=', '; echo "${MISSING_TOOLS[*]}")")
fi

if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
  LINES+=("ℹ️ Optional for post-deploy/security: $(IFS=', '; echo "${OPTIONAL_MISSING[*]}") — install if you plan to use /test post or security scans.")
fi

# 3. Infrastructure state
if [ -f kubeconfig ] && [ -f talosconfig ]; then
  LINES+=("🟢 kubeconfig and talosconfig are present — cluster is deployed. Use /test post for e2e checks or /post-deploy for the full checklist.")
elif [ -f terraform.tfstate ]; then
  LINES+=("🟡 terraform.tfstate is present, but kubeconfig/talosconfig are not — apply may have failed midway. Check: terraform show.")
else
  LINES+=("⚪ Cluster not deployed yet. Before apply: /deploy-prep (full readiness check).")
fi

# 4. Command hint
LINES+=("📋 Available slash commands: /audit /fix /test /cycle /deploy-prep /post-deploy")

# Join lines.
CONTEXT=$(printf '%s\n' "${LINES[@]}")

# Stay silent when there's nothing to say.
if [ -z "$CONTEXT" ]; then
  exit 0
fi

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'

exit 0

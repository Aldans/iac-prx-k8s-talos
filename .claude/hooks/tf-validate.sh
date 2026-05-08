#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write on *.tf|*.tftpl, run fmt + validate.
# If validate fails, inject the error into Claude's context via additionalContext —
# Claude fixes it on the next step.
#
# We deliberately do NOT trigger /audit or any heavy work here — that would recurse.
# Local gate-check only.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Skip silently when the edit isn't a .tf/.tftpl file (out of scope).
case "$FILE_PATH" in
  *.tf|*.tftpl) ;;
  *) exit 0 ;;
esac

cd "$PROJECT_DIR" || exit 0

# 1. Silent format. Do not fail the hook on fmt errors (validate gives a clearer message).
terraform fmt -recursive >/dev/null 2>&1 || true

# 2. Validate. Parse the JSON output.
VALIDATE_JSON=$(terraform validate -json 2>&1 || true)
VALID=$(printf '%s' "$VALIDATE_JSON" | jq -r '.valid // false' 2>/dev/null || echo "false")

if [ "$VALID" = "true" ]; then
  exit 0
fi

# 3. Collect diagnostics. Errors + warnings, capped at 10.
ERRORS=$(printf '%s' "$VALIDATE_JSON" | jq -r '
  (.diagnostics // [])
  | map(select(.severity == "error" or .severity == "warning"))
  | .[0:10]
  | map("\(.severity | ascii_upcase): \(.summary)\(if .detail then "\n  " + .detail else "" end)\(if .range then "\n  at " + .range.filename + ":" + (.range.start.line | tostring) else "" end)")
  | join("\n\n")
' 2>/dev/null || echo "(failed to parse diagnostics)")

if [ -z "$ERRORS" ]; then
  ERRORS="$VALIDATE_JSON"
fi

# 4. Inject context for Claude.
jq -n --arg msg "⚠️ terraform validate failed after your edit to $FILE_PATH:

$ERRORS

Fix the errors in the file you just edited. If anything is unclear, read the file in full." '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $msg
  }
}'

exit 0

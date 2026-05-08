---
description: Run infra-tester. Auto mode detects whether a kubeconfig is present. The argument overrides.
argument-hint: "[auto | pre | post]"
---

The user invoked the command with argument `$ARGUMENTS`.

If `$ARGUMENTS` is empty or not in the list, treat mode = `auto` (default).

Modes:
- `auto` — detect by the presence of a working ./kubeconfig
- `pre` — static only (fmt, validate, plan, tflint, checkov)
- `post` — e2e only (kubectl, talosctl, cilium, flux)

## Steps

### 1. Delegate to infra-tester

One Agent call:
- `subagent_type: infra-tester`
- prompt: the requested mode + a reference to `.claude/state/last-fix.md` if it exists (context about what was just edited)

Example prompt:

```
Run infra-tester in auto mode.
Context: fixes from /fix were just applied (see .claude/state/last-fix.md). Pay attention to those files when analysing the plan output.
Return the report in the standard format.
```

### 2. Save the report

To `.claude/state/last-test.md`.

### 3. Show ONLY the summary to the user

```
✅/⚠️/🔴 test complete (mode: <A pre-apply / B post-apply>)

Static:
  fmt ✅ | validate ✅ | plan ✅ <add N / change M / destroy K>

E2E (post mode):
  nodes <X/Y Ready> | cilium ✅ | flux ✅

CRITICAL: <count>
HIGH: <count>

Verdict: READY_FOR_APPLY / BLOCKED / DEGRADED / HEALTHY

Top-3 actions:
1. ...
2. ...

Full report: .claude/state/last-test.md
Next: <if READY> apply manually: terraform apply
      <if DEGRADED> review the top-3 / run /audit
```

## Special cases

- If `plan` shows destroys on critical resources (`talos_machine_secrets`, `local_file.kubeconfig`), **highlight that in red** as a separate line in the summary.
- If `plan` is blocked because credentials are missing or invalid, **do not count this as fail** — tell the user they need to set up credentials.

## Principles

- DO NOT run apply/destroy.
- DO NOT modify files.
- If `post` mode is requested but the cluster does not respond, degrade to `pre` and inform the user.

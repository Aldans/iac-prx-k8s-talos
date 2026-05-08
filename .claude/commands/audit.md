---
description: Full IaC audit — 4 agents in parallel (security/review/validation/docs). Consolidated report at .claude/state/last-audit.md + archive at .claude/audit-history/<ts>/.
argument-hint: ""
---

The user invoked `/audit`. Run all four project-level sub-agents **in parallel**, collect their reports, synthesize a consolidated report, save it to state + archive, and **print only the summary** to the user.

## Steps

### 1. Run 4 agents in parallel (one message, four `Agent` calls)

- `subagent_type: terraform-security-auditor` — prompt: "Run a security audit. Report in the standard format."
- `subagent_type: terraform-reviewer` — prompt: "Run a code review across all .tf files. Report in the standard format."
- `subagent_type: infra-validator` — prompt: "Run every technical check (fmt, validate, lock, versions, .gitignore, cleanup). Report in the standard format."
- `subagent_type: docs-sync-checker` — prompt: "Verify README.md, CLAUDE.md and credentials.auto.tfvars-exemple are in sync with the current code. Report in the standard format."

### 2. Synthesize the consolidated report (markdown)

```markdown
# /audit — <YYYY-MM-DD HH:MM>

## 🔴 Blocking (HIGH)
| # | Source | File | Issue | Action |
|---|---|---|---|---|

## 🟡 Recommended (MEDIUM)
<table>

## 🟢 Nice-to-have (LOW/INFO)
<table>

## Per-agent (short summary each)
- **Security**: HIGH=N, MEDIUM=M, LOW=K. Highlights: ...
- **Review**: HIGH=N. Highlights: ...
- **Validation**: PASS / FAIL. Highlights: ...
- **Docs**: GOOD / DRIFT. Highlights: ...

## ✅ What looks good
- ...

## Recommendations
1. <prioritised action>
```

### 3. Save the report

- To `.claude/state/last-audit.md` (overwritten each run).
- To `.claude/audit-history/<YYYY-MM-DD-HHMMSS>/` create 5 files:
  - `summary.md` — your consolidated report
  - `security.md` — raw output from security-auditor
  - `review.md` — raw output from reviewer
  - `validation.md` — raw output from validator
  - `docs.md` — raw output from docs-checker

Use `date +"%Y-%m-%d-%H%M%S"` via Bash for the timestamp.

### 4. Show ONLY this to the user

```
✅/⚠️/🔴 audit complete

🔴 Blocking: N
🟡 Recommended: M
🟢 Nice-to-have: K

Top-3 actions:
1. ...
2. ...
3. ...

Full report: .claude/state/last-audit.md
Archive: .claude/audit-history/<ts>/
Next: /fix HIGH (to apply blockers) or /test (to test as is).
```

## Principles

- **Do not duplicate findings** between agents in the summary.
- If everyone came back clean, print "✅ All checks passed" and still save state.
- **Do not run** apply / destroy.
- Do not edit files — that is `/fix`.

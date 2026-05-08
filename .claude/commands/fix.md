---
description: Apply fixes from last-audit via terraform-staff-engineer. The scope argument controls filtering.
argument-hint: "[HIGH | HIGH+MEDIUM | all | #1,#3,#5]"
---

The user invoked the command with argument `$ARGUMENTS`.

If `$ARGUMENTS` is empty, treat scope = `HIGH` (default).

Allowed values:
- `HIGH` — only blocking findings from last-audit
- `HIGH+MEDIUM` — also include serious findings
- `all` — everything, including nice-to-have
- `#1,#3,#5` — specific items by number from last-audit
- if last-audit is missing, suggest running `/audit` first

## Steps

### 1. Read `.claude/state/last-audit.md`
If the file is missing, say "Run /audit first" and stop.

### 2. Filter tasks by scope
Build a list of concrete edits, each one as `<severity>#<N>: <file>:<line> — <issue>. Fix: <hint>`.

### 3. Delegate to staff-engineer

One Agent call:
- `subagent_type: terraform-staff-engineer`
- prompt: the full task list + a reference to `.claude/state/last-audit.md` for context + the requested report format

Example prompt:

```
Apply the following fixes from last-audit (see .claude/state/last-audit.md for details):

- HIGH#2: 02_talos.tf:115-128 — talos_machine_configuration_apply.cp uses cp_initial_ips on every apply. Fix: add lifecycle { ignore_changes = [node] }.
- HIGH#5: .gitignore — `*.tfvars` is missing. Fix: add it with the `*-exemple` exception.
- ...

After all edits, MUST run infra-validator (as described in your system prompt).
Return the report in the standard format.
```

### 4. Save the staff-engineer's report

To `.claude/state/last-fix.md` (with a timestamp at the top).

### 5. Show ONLY the summary to the user

```
✅/⚠️ fix complete

Applied: N changes across M files
Validator: ✅ pass / ❌ <issue>

Files changed:
- <file1> (<change count>)
- <file2> (...)

Skipped: <count> (see last-fix.md for the reason)

Full report: .claude/state/last-fix.md
Next: /test (check nothing broke) or a fresh /audit.
```

## Principles

- **Do not edit yourself** — delegate to the staff-engineer.
- Do not run apply/destroy.
- If the staff-engineer returned FAIL, show it to the user and ask how to proceed.
- If `HIGH` was requested but last-audit reports HIGH=0, say "no blockers" and do not invoke staff-engineer for nothing.

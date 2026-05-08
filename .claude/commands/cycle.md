---
description: Full cycle — /audit → /fix HIGH → /test. One consolidated report. Does NOT run apply.
argument-hint: ""
---

Command: `/cycle`

The full autonomous run of the agent crew:
1. `/audit` (4 agents in parallel)
2. If HIGH > 0 → `/fix HIGH` (staff-engineer + validator)
3. `/test` (infra-tester) — final validation
4. One consolidated report to the user

## Steps

### Step 1: /audit
Run the `audit.md` logic end-to-end (4 parallel agents, save state). BUT **do not print** the regular summary — hold it for the final report.

### Step 2: /fix HIGH (when applicable)
Read `.claude/state/last-audit.md`. Count HIGH blockers.

- If HIGH > 0 — run `fix.md` logic with scope HIGH.
- If HIGH == 0 — skip and continue to Step 3.

Again — **do not print** the fix summary, accumulate it.

### Step 3: /test auto
Run `test.md` logic in auto mode. Context for the tester: edits from Step 2 were just applied (if any).

Do not print the summary, accumulate it.

### Step 4: Final report

```markdown
# /cycle — <YYYY-MM-DD HH:MM>

## TL;DR
- Audit: 🔴 N blockers / 🟡 M / 🟢 K
- Fix: ✅ N applied / ❌ failed (if it ran)
- Test: <verdict>

## Cycle walkthrough

### 1️⃣ Audit
<5-7 lines of main highlights>

### 2️⃣ Fix
<3-5 lines of what was applied>

### 3️⃣ Test
<3-5 lines of verdict + top issues>

## Bottom line
<overall status — ready for apply / manual actions required / blockers>

## Manual actions for the user
1. ...
2. ...

## Artefacts
- .claude/state/last-audit.md
- .claude/state/last-fix.md
- .claude/state/last-test.md
- .claude/audit-history/<ts>/
```

## Principles

- Print the summary once at the end — **do not flood** with intermediate reports.
- DO NOT run apply / destroy.
- If any step has a catastrophic failure (e.g. validate fails and staff-engineer cannot fix it), abort the cycle and print whatever report you have.
- The final report must be short and actionable. If the user wants details, they read the state files.

# `.claude/state/`

Files in this directory hold **inter-agent state** for slash commands. They are **transient** — every run of `/audit`, `/fix`, `/test`, `/cycle` overwrites the matching file.

| File | Written by | Read by |
|---|---|---|
| `last-audit.md` | `/audit` (main thread aggregates 4 auditor reports) | `/fix` to know what to repair |
| `last-fix.md` | `/fix` (staff-engineer + validator outcome) | `/cycle` for the final summary |
| `last-test.md` | `/test` (infra-tester) | `/cycle` for the final summary |

The files survive Claude Code restarts. Long-term audit history lives in `.claude/audit-history/<timestamp>/`.

`.claude/settings.local.json` is in `.gitignore` via a narrow rule. The state files themselves can be committed if you want a shared history.

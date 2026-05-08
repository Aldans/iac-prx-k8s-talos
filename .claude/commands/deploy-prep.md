---
description: Final readiness gate before terraform apply — /cycle + Proxmox/GitHub connectivity + credentials check. One READY/NOT_READY report with concrete action items.
argument-hint: ""
---

The user invoked `/deploy-prep` — the last gate before `terraform apply`.

Goal: confirm everything is in place for a successful apply. **Do NOT run apply yourself.**

## Steps (sequential)

### 1. Full /cycle
Run the `cycle.md` logic end-to-end (audit + fix HIGH + test). Do not print intermediate reports to chat.

When it finishes, read `.claude/state/last-test.md` for the verdict (`READY_FOR_APPLY` / `BLOCKED` / etc) and the plan summary.

### 2. Connectivity checks

Via Bash:

#### 2a. credentials.auto.tfvars is filled in
```bash
test -f credentials.auto.tfvars || echo "MISSING"
grep -c "your-proxmox-host\|your-password\|ghp_xxxxxxxxxxxx\|your-github-user\|00000000-0000-0000-0000-000000000000" credentials.auto.tfvars 2>/dev/null
# Should be 0 — otherwise placeholders are still in place.
```

#### 2b. Proxmox API reachable

Extract the endpoint:
```bash
PRX_ENDPOINT=$(grep -oE 'endpoint\s*=\s*"[^"]+"' credentials.auto.tfvars | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
```

Test reachability (skip TLS verification — Proxmox typically uses self-signed certs):
```bash
curl -sk --max-time 10 -o /dev/null -w "%{http_code}\n" "$PRX_ENDPOINT/version"
# 401 (no token) or 200 means the API is answering.
# Timeout / DNS error / connection refused → Proxmox is unreachable.
```

#### 2c. GitHub PAT is valid
```bash
GITHUB_TOKEN=$(grep -oE 'github_token\s*=\s*"[^"]+"' credentials.auto.tfvars | sed -E 's/.*"([^"]+)".*/\1/')

# Verify the token works
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" \
     -o /dev/null -w "%{http_code}\n" https://api.github.com/user
# 200 = OK, 401 = invalid token, 403 = rate-limit / scope issue

# Check scopes (need: repo + admin:public_key)
curl -s -I -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user 2>&1 | grep -i 'x-oauth-scopes\|x-accepted-oauth'
```

#### 2d. Talos image reachable
```bash
SCHEMATIC=$(grep -oE 'talos_schematic_id\s*=\s*"[a-f0-9]+"' credentials.auto.tfvars | sed -E 's/.*"([^"]+)".*/\1/')
SCHEMATIC=${SCHEMATIC:-aeec243e3a4c2a14f9ba74b1a8c7662f03eea658a7ea5f1c26fdd491280c88f8}
TALOS_VER=$(grep -oE 'talos_version\s*=\s*"v[0-9.]+"' credentials.auto.tfvars | sed -E 's/.*"([^"]+)".*/\1/')
TALOS_VER=${TALOS_VER:-v1.13.0}

curl -sI --max-time 10 -o /dev/null -w "%{http_code}\n" \
  "https://factory.talos.dev/image/$SCHEMATIC/$TALOS_VER/nocloud-amd64.raw.gz"
# Expect 200 or 302
```

#### 2e. dnsmasq on the Proxmox host (optional)
If `dns_domain = lab.lan` (or whatever):
```bash
DNS_DOMAIN=$(grep -oE 'dns_domain\s*=\s*"[^"]+"' credentials.auto.tfvars | sed -E 's/.*"([^"]+)".*/\1/')
DNS_DOMAIN=${DNS_DOMAIN:-lab.lan}
# Sanity check — nothing should resolve, but the resolver should respond.
nslookup nonexistent-host.$DNS_DOMAIN 2>&1 | grep -q "can't find\|NXDOMAIN" && echo "DNS_OK" || echo "DNS_UNREACHABLE"
```

### 3. Final verdict

Combine everything. Verdicts:
- **🟢 READY_FOR_APPLY**: every check ✅, /cycle returned READY_FOR_APPLY, plan is clean.
- **🟡 READY_WITH_WARNINGS**: critical checks ✅, but LOW issues remain (e.g. scanners not installed).
- **🔴 NOT_READY**: any critical check ❌.

### 4. Show the user a compact report

```
🟢/🟡/🔴 deploy-prep

/cycle: <verdict>

Connectivity:
  credentials.auto.tfvars     ✅/❌ (placeholders found: N)
  Proxmox API <endpoint>      ✅ HTTP <code> / ❌ <reason>
  GitHub PAT                  ✅ scope=<scopes> / ❌ <code>
  Talos image                 ✅ HTTP 200 / ❌ <reason>
  DNS resolver (optional)     ✅ / ❓ unreachable

Readiness: 🟢 READY / 🟡 WITH WARNINGS / 🔴 NOT READY

If READY — run:
  terraform apply

If NOT_READY:
1. <concrete action>
2. ...

Artefacts:
- .claude/state/last-audit.md, last-fix.md, last-test.md
- /tmp/tfplan.out (full plan)
```

## Principles

- Do not run apply / destroy.
- Do not modify credentials.auto.tfvars (the user's secrets).
- If /cycle fails on any step, abort and emit a partial report.
- Use `--max-time 10` on curl checks so the command does not hang.
- Never log Proxmox/GitHub tokens to chat — print only their status (OK/FAIL).

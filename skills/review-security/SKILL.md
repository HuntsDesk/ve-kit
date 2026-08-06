---
name: review-security
description: Security audit of the .claude/ configuration layer — secrets leaked in agent/skill bodies, overly broad permissions, deny list gaps, hook script shell injection, MCP server tool grants, dangerous agent instructions. Distinct from the built-in /security-review which audits code changes. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# .claude/ Security Review Protocol

Audits security posture of the Claude Code configuration layer. Scope is deliberately narrow: `.claude/` files + settings. Does NOT review app code (that's what `/security-review` is for).

Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md).

**Owner**: `docs-manager` (once registered) or `general-purpose` fallback. Coordinate with `code-reviewer` for findings that require pattern validation.

## When to invoke

- After adding new MCP servers or hooks
- When granting a new agent broad tool permissions
- Periodic audit (quarterly or after any security-relevant incident)
- Before sharing the project with new teammates
- After modifying `settings.json` / `settings.local.json`

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Secret scanning in `.claude/`

Grep recursively under `.claude/` for high-signal secret patterns:

- `sk-[a-zA-Z0-9]{20,}` — Anthropic/OpenAI style keys
- `AIza[0-9A-Za-z_-]{35}` — Google API keys
- `AKIA[0-9A-Z]{16}` — AWS access keys
- `ghp_[a-zA-Z0-9]{36}` — GitHub tokens
- `xox[baprs]-[a-zA-Z0-9-]+` — Slack tokens
- `-----BEGIN (RSA )?PRIVATE KEY-----` — private keys
- `postgres://[^:]+:[^@]+@` — Postgres connection strings with embedded passwords
- Any hardcoded password inside a hook script

**Severity**: critical if found. Immediately flag and recommend: (1) rotate the secret, (2) move to Secret Manager or env vars, (3) scrub git history if committed.

Scan locations:
- `.claude/agents/*.md`
- `.claude/skills/**/*.md`
- `.claude/rules/*.md`
- `.claude/hooks/*.sh`
- `.claude/settings.json` (should reference env vars, never contain secrets)
- `.claude/settings.local.json`

## Step 2 — Permission audit: settings.json / settings.local.json

Read both files. For each, evaluate:

**Allow list red flags**:
- `Bash(*)` — inherently broad; safe ONLY with a robust deny list (verify)
- `Write(**)` — allows writing anywhere; flag high unless intentional
- `Edit(**)` — same
- `WebFetch(*)` — can exfiltrate; low risk on trusted machines but flag for awareness
- `mcp__*__*` — per-server wildcards; verify MCP server isn't high-risk
- Tool grants without qualifiers on specific tools (e.g., `Bash` without `(...)` = everything)

**Deny list coverage** (per BOOTSTRAP.md + your ops):
- Destructive rm patterns present?
- Git force-push, reset --hard, clean, delete main/dev branch?
- Database drops (`DROP DATABASE`, `DROP SCHEMA`, `TRUNCATE * CASCADE`, `dropdb`)?
- Cloud provider deletions (gcloud projects delete, compute instances delete, sql instances delete)?
- GitHub (`gh repo delete`, `gh repo archive`)?
- Docker (`docker system prune -a`, postgres container removal, volume rm)?
- Any platform-specific devastating ops unique to your project?

Flag **gaps** as high (missing common pattern) or medium (missing platform-specific pattern).

**defaultMode**:
- `defaultMode: bypassPermissions` — flag critical in team-shared settings.json (affects all users + ve-worker)
- `defaultMode: acceptEdits` — standard for your project; verify it's intentional

## Step 3 — Hook script review

Read every `.claude/hooks/*.sh` script. Check for:

- **Shell injection**: user-controlled input passed to `eval`, `sh -c`, or unquoted variables in command positions
- **Path traversal**: scripts reading arbitrary paths without validation
- **Privilege escalation**: `sudo` without strict command filtering
- **Output parsing bugs**: scripts that fail silently on malformed data (could be bypassed)
- **Logic bypasses**: hook intended to block X can be bypassed with command rephrasing (e.g., `git push` caught but `git -c push` not)
- **Timeout safety**: long-running hook commands without timeouts could hang sessions

Specifically for the review-gate.sh / block-todowrite.sh / stop-compliance-check.sh patterns: verify they fail CLOSED (deny on unexpected input), not OPEN.

## Step 4 — MCP server audit

Check `.claude/settings.json` `enabledMcpjsonServers` list and each enabled MCP server's tool exposure:

- Servers granting destructive tools (delete, drop, write) — should be least-privilege
- Servers with network access exposing internal data
- Servers that should be disabled on team-shared but enabled anyway
- Secret exposure: MCP server requires credentials but they're stored in allowed locations

For each MCP, check the allow list grants — wildcards (`mcp__stripe__*`) include write/destructive tools. Flag where read-only would suffice.

## Step 5 — Agent tool grants

For each `.claude/agents/*.md`, check `tools:` field (or lack thereof = inherit all):

- Agents that should be read-only (e.g., reviewers) but inherit full tool set
- Agents granted `Bash` when they only need `Read`/`Grep`
- Agents granted write access when they're analytical only
- Agents with `disallowedTools` needed but missing

Recommend tool restrictions where the role doesn't justify full access. Reduces blast radius if a prompt-injection attack lands.

## Step 6 — Dangerous agent instructions

Grep agent prompt bodies for instructions that, if followed literally, cause damage:

- "Delete the file without confirming" / "never ask before rm"
- "Run this command with sudo" where it's not safety-audited
- Instructions to push force / override deny checks
- Prompts that say "ignore the user's safety settings" or "bypass permission prompts"
- Suggestions to `git reset --hard` / `git clean` as routine cleanup

Flag. Legitimate destructive operations should always pair with "confirm with user" or "only after explicit approval."

## Step 7 — Memory file security

For `~/.claude/projects/<slug>/memory/*.md`:
- Any secrets stored (passwords, API keys, auth tokens)?
- Personally identifying information that shouldn't be persisted (emails, full names of third parties, private details)?
- References to internal-only URLs/domains that could leak architecture

## Step 8 — Hook + setting consistency

Verify hooks in `.claude/settings.json` match the scripts they reference:
- Every hook command path exists and is executable (`chmod +x`)
- Every hook script referenced in rules (`agent-board.md`, `riper-cat.md`) is actually in settings.json
- Hooks firing on sensitive matchers (`Bash`, `Edit`, `Write`) are not bypassable

## Step 9 — Git hygiene

Check that `.claude/settings.local.json` is in `.gitignore` (personal settings shouldn't leak to team). Check `.env*` patterns are in `.gitignore`. Check no hook script accidentally committed with embedded secret.

## Step 10 — File findings to the board

Create parent tasks per severity. Route critical findings to `code-reviewer` for validation before declaring them real. Others go to `docs-manager` or `general-purpose`.

## Step 11 — Summary

Return ≤ 120 words:

```
.CLAUDE SECURITY REVIEW COMPLETE

- Secrets scan: [N] potential hits ([verified real / false positive breakdown])
- Permission audit: [X] allow-list issues, [Y] deny-list gaps
- Hook scripts: [H] scripts, [I] injection/bypass concerns
- MCP servers: [M] active, [O] over-granted
- Agent tool grants: [A] agents with broader tools than role needs
- Dangerous instructions: [D] prompts flagged
- Memory security: [MS] issues
- Git hygiene: [GH] issues

Critical: [C] | High: [H] | Medium: [M] | Low: [L]
Total: [T] findings
Board parent: <id>
Rotate-required secrets: [R]
```

## Anti-patterns to flag

- Secrets in agent prompts (ever)
- `Bash(*)` with an empty or missing deny list
- Hook scripts with `eval "$USER_INPUT"` or unquoted variables in commands
- `sudo` in hook scripts without filtering
- Agents that instruct destructive ops without "confirm with user"
- MCP server tool wildcards when read-only would suffice
- `defaultMode: bypassPermissions` in team-shared settings.json
- .env* NOT in .gitignore
- settings.local.json checked into git
- Private keys stored in .claude/

## Tools used

- Read, Glob, Grep (core audit)
- Bash (restricted): check file permissions on hook scripts, git status on sensitive files
- Board MCP
- Coordinate with `code-reviewer` for critical findings verification
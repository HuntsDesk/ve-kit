---
name: review-security
description: Security audit of the .claude/ configuration layer — secrets leaked in agent/skill bodies, overly broad permissions, deny list gaps, hook script shell injection, MCP server tool grants, dangerous agent instructions. Distinct from the built-in /security-review which audits code changes. Files every finding to the board (tasks for high/critical, a ledger comment for medium/low).
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
- `Edit(**)` — allows writing anywhere (Edit rules cover every file-editing tool: Edit, Write, NotebookEdit); flag high unless intentional. A `Write(**)` or `NotebookEdit(**)` entry is inert and only produces a startup warning — flag it for removal
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
- `defaultMode: bypassPermissions` or `auto` in team-shared `.claude/settings.json` or `.claude/settings.local.json` — flag HIGH as **dead/misleading config**: Claude Code ≥ 2.1.257 ignores both values from project files (bypass makes the session start in Manual — the opposite of the intent). The live surfaces for bypass are `~/.claude/settings.json` and the ve-worker's `--permission-mode bypassPermissions` CLI flag (correct: headless, in a container, non-root) — flag critical only if bypass reaches an INTERACTIVE session from the user file
- any `defaultMode` at all in team-shared settings.json — flag medium: it outranks each developer's `~/.claude/settings.json` for terminal sessions and blocks the `auto` starting mode (the reference project's standard since 2026-09-12); the project file should set none

## Step 3 — Hook script review

Read every `.claude/hooks/*.sh` script. Check for:

- **Shell injection**: user-controlled input passed to `eval`, `sh -c`, or unquoted variables in command positions
- **Path traversal**: scripts reading arbitrary paths without validation
- **Privilege escalation**: `sudo` without strict command filtering
- **Output parsing bugs**: scripts that fail silently on malformed data (could be bypassed)
- **Logic bypasses**: hook intended to block X can be bypassed with command rephrasing (e.g., `git push` caught but `git -c push` not)
- **Timeout safety**: long-running hook commands without timeouts could hang sessions

The roster, each hook's event and matcher, its escape hatch and its test suite are in [`.claude/hooks/README.md`](../../hooks/README.md) — read that, then `ls .claude/hooks` to confirm it is current. **The audit question is whether each hook's failure behaviour matches what it documents, and whether that choice was made rather than inherited.** The standing doctrine here is **fail OPEN**: on a missing python interpreter or unparseable hook input the hook exits 0 and allows, because a gate that hard-denies every edit when its interpreter is absent bricks the session. So an agent-facing gate that fails open is **not** a finding — a gate that fails open *without saying so at the branch that does it*, or one whose docs claim it denies, is. The doctrine is a default, not a prohibition: a hook MAY deliberately fail closed where the thing it guards is worth bricking the session over, and that is fine **provided it documents the choice**. Judge behaviour against documentation, in both directions; do not file a fail-closed hook as a finding merely for departing from the default. The real cost of the doctrine is worth naming in the report rather than re-litigating: a stripped container with no `python3` silently disables every gate in the one environment with no human watching, so check that the runtime actually carries the hooks' dependencies. Board `<YOUR_HOOK_DOCTRINE_TASK_ID>` tracks reconciling the doctrine itself; note deviations there rather than re-arguing it here. Note too that the edit-time gates only see the `Edit|Write|MultiEdit` tools — a Bash heredoc or `sed -i` rewrite bypasses them by construction, with the commit-time review gate as the backstop — so that bypass is a boundary of the control, not a finding.

`gitleaks-gate.sh` and the CI scanners are the same class of control, so check them together: a gate that cannot report a finding is indistinguishable from a clean scan. The Trivy filesystem and per-service image gates, their two-pass OS/library policy, and the `.trivyignore` files they consume are specified in your CI-validation rule, section "Cross-service validation gate" — read the policy there, do not restate it here.

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
- `defaultMode: bypassPermissions` reaching an interactive session from `~/.claude/settings.json` (in project files it is ignored since 2.1.257 — dead config, HIGH, not critical)
- .env* NOT in .gitignore
- settings.local.json checked into git
- Private keys stored in .claude/

## Tools used

- Read, Glob, Grep (core audit)
- Bash (restricted): check file permissions on hook scripts, git status on sensitive files
- Board MCP
- Coordinate with `code-reviewer` for critical findings verification
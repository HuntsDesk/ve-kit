# Anthropic Configuration Guide (Reference)

Canonical reference for writing `.claude/` agents, skills, and rules per Anthropic's official guidance. Sourced from Claude Code docs v2.1.112 and Claude API docs (Apr 2026).

Cite this file from `review-*` skills and `docs-manager` when enforcing conventions. If this doc goes stale, re-delegate research to the `claude-code-guide` agent.

---

## 1. Agent frontmatter (`.claude/agents/*.md`)

**Source**: https://code.claude.com/docs/en/agents.md#supported-frontmatter-fields

### Required

| Field | Notes |
|-------|-------|
| `name` | Unique, lowercase, hyphens. Max 64 chars. |
| `description` | When to delegate. Front-load trigger keywords. `description` + `when_to_use` combined ≤ 1,536 chars in context. |

### Optional (stable as of v2.1.112)

| Field | Notes |
|-------|-------|
| `model` | `opus`, `fable`, `sonnet`, `haiku`, `best`, `inherit` (default), or a pinned ID (`claude-opus-5-5`, `claude-fable-5-1`). **Prefer the alias.** `opus` resolves to the current Opus (`claude-opus-5-5` as of 2026-09-23; `claude-opus-5` from 2026-07-27) and `fable` to the current Fable (`claude-fable-5-1` since 2026-09-01), so alias-based agents inherit each new release for free; a version-pinned ID silently strands the agent on an old model. `inherit` takes the session's model; `best` lets Claude Code pick the strongest available. |
| `tools` | Comma/YAML list to restrict. Omit to inherit all. |
| `disallowedTools` | Denylist. Applied before `tools` allowlist. |
| `permissionMode` | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`. |
| `maxTurns` | Stops after N turns. |
| `skills` | List of skills preloaded into context at startup. Subagents don't inherit parent skills. |
| `mcpServers` | Inline or referenced MCP definitions. |
| `hooks` | `PreToolUse`, `PostToolUse`, `Stop` (becomes `SubagentStop`). Scoped to this agent. |
| `memory` | `user`, `project`, or `local`. Enables cross-session memory. Auto-enables Read/Write/Edit. |
| `background` | `true` to always run as background task. |
| `effort` | `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort when present. **When omitted the agent INHERITS the session's effort**, and a session's default is the *model's* default — `high` on most models but **`medium` on Opus 5.5** (code.claude.com/docs/en/model-config, verified 2026-09-23; a top-level `effortLevel` in user settings does not apply to Opus 5.5). Set it explicitly on **every** agent: **`high` by default**, `xhigh` only where the deliverable is a decision, diagnosis or gate verdict rather than a document, `max` only for the two domain-content authors. |
| `isolation` | `worktree` to run in isolated git worktree. |
| `color` | UI only: `red`/`blue`/`green`/`yellow`/`purple`/`orange`/`pink`/`cyan`. |
| `initialPrompt` | Auto-submitted as first user turn when agent runs as main. |

### Description format (canonical)

> `[role/expertise]. [what it does]. [when to invoke + triggers].`

Example: `"Code reviewer. Analyzes code changes for quality, security, and best practices. Use immediately after writing or modifying code, or when reviewing PRs."`

Front-load the trigger. Include 2+ `<example>` blocks showing Context → User → Assistant delegation pattern (see existing agent files for reference).

### Prompt body length

- Read-only (review, research): 200–400 words
- Execution (fix, implement): 300–600 words
- Coordination (project-coordinator): 400–800 words

**Subagents see only their own system prompt + assigned skills + basic environment.** No CLAUDE.md, no parent conversation, no project history. Prompts must be self-contained.

---

## 2. Skill frontmatter (`.claude/skills/*/SKILL.md`)

**Source**: https://code.claude.com/docs/en/skills.md#frontmatter-reference

### Fields (all optional, but `description` strongly recommended)

| Field | Notes |
|-------|-------|
| `name` | Defaults to directory name. Lowercase, hyphens, max 64 chars. |
| `description` | When/how Claude should use it. Combined with `when_to_use` ≤ 1,536 chars. |
| `when_to_use` | Extra trigger context. |
| `argument-hint` | Autocomplete hint, e.g., `[issue-number]`. |
| `disable-model-invocation` | `true` = only you invoke. For commands with side effects. |
| `user-invocable` | `false` = Claude-only (hidden from `/` menu). For background knowledge. |
| `allowed-tools` | Space-separated or YAML list. Pre-approves tools. |
| `model` | Skill-specific model override. |
| `effort` | `low`/`medium`/`high`/`xhigh`/`max`. Per-skill override. |
| `context` | Set to `fork` to run in isolated subagent context. |
| `agent` | Subagent type if `context: fork` (e.g., `Explore`, `Plan`, `general-purpose`). |
| `hooks` | Scoped to skill lifecycle. |
| `paths` | Glob patterns. Loads skill only when working with matching files. |
| `shell` | `bash` (default) or `powershell`. |

### Invocation matrix

| Flags | User invokes | Claude invokes | Use case |
|-------|---|---|---|
| (default) | Yes | Yes | Reference knowledge Claude applies and user may invoke |
| `disable-model-invocation: true` | Yes | No | Side-effect workflows (`/commit`, `/deploy`) |
| `user-invocable: false` | No | Yes | Background knowledge not meant as a command |

### Size and lifecycle

- Keep `SKILL.md` under **500 lines**. Move detail to supporting files in the same directory.
- When invoked, SKILL.md content enters the conversation as one message and **stays for the session**. Skills don't reload on later turns.
- After `/compact`, first 5k tokens of each invoked skill re-attach (up to 25k total). Re-invoke to refresh if needed.

### Progressive disclosure

```markdown
---
name: deep-research
description: Research $ARGUMENTS thoroughly
---

Short summary of steps.

## Additional resources
For complete API details, see [reference.md](reference.md).
For usage examples, see [examples.md](examples.md).
```

### Dynamic context injection

- `!\`command\`` inline or ```` ```! ```` block → executes before Claude sees the skill; output is substituted in.
- `$ARGUMENTS`, `$ARGUMENTS[N]`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` — standard substitutions.

---

## 3. Model assignment rubric (Opus 5.5 / Fable 5.1 / Sonnet 5 / Haiku 4.5)

**Source**: https://code.claude.com/docs/en/model-config (alias resolution + per-model effort levels, read 2026-09-23) + https://platform.claude.com/docs/en/about-claude/models/overview.md


| Model | Strengths | Recommended for |
|-------|-----------|-----------------|
| **Opus 5.5** | Current Opus (`opus` alias). Full effort ladder `low`–`max`; **model default effort is `medium`**, so every agent in this fleet states its effort. Thinking cannot be turned off. | **The default — every agent**, effort-tiered (members: review-checklist.md). Separately, the **ve-worker batch runner defaults to `opus`**
| **Sonnet 5** | Near-Opus quality on coding/agentic at Sonnet cost. 1M ctx, full effort ladder. | Reserved — speed-critical simple tasks |
| **Haiku 4.5** | Fastest with near-frontier intelligence. 200k ctx. | Read-only research, file discovery, grep patterns |

### Project-specific guidance (user on max plan — bias upward when ambiguous)

The **authoritative per-agent tier membership** lives in [review-checklist.md → Model + effort rubric](review-checklist.md) — do NOT re-inline the per-agent lists here (they drifted before). Role-level summary; every row is `model: opus`:

| Agent role | Effort |
|------------|--------|
| Correctness-critical offline domain-content authoring (content-writer, assessment-writer) | `max` (unvalidated — the A/B in review-checklist.md governs it) |
| **Decision/diagnosis/gate-verdict** deliverables where under-thinking costs more than overthinking — money/auth, schema + data integrity, outage-class infra, deploy, cross-system AI, the review and test gates (code-reviewer, test-runner), plus prod flag toggles — flag-manager, and ad conversion/PII upload routing — paid-ads-specialist (members: review-checklist.md tier rows) | `xhigh` |
| **Long-prose** deliverables — audits, docs, copy, content, every product-domain specialist, and processor (members: review-checklist.md tier rows) | `high` (the default and the floor) |
| Read-only exploration (future `Explore`-type agents) | `haiku` model |

**Rule of thumb (rewritten 2026-09-23)**: **Opus is the default for every agent; effort follows the shape of the output** — `high` for documents, `xhigh` for decisions, diagnoses and gate verdicts, `max` only for the two domain-content authors. **Every agent states `effort:` explicitly**, because an omitted line inherits the launching session and Opus 5.5's own default is `medium`. **Cost and capacity are not valid reasons to lower a model or an effort** without a measured quality check; a hard quota wall goes through the manifest's recorded `fallback`, never through `preferred`. **Use the alias, never a version-pinned ID** — aliases are what made the Opus 5, Fable 5.1 and Opus 5.5 upgrades zero-edit events.

---

## 4. When to write an agent vs. a skill vs. a rule

**Agent** (`.claude/agents/*.md`):
- Has its own system prompt, invoked via Task tool delegation
- Produces output from a clean context (no parent conversation)
- Good for: parallel work, domain specialization, background tasks
- Example: `code-reviewer`, `database-specialist`

**Skill** (`.claude/skills/*/SKILL.md`):
- Injected into the current conversation as a single message
- Stays loaded for the session
- Good for: workflows, checklists, commands the user invokes with `/name`
- Example: `/plan`, `/review`, `/review-agents`

**Rule** (`.claude/rules/*.md`):
- Referenced from CLAUDE.md, always in context for every session
- Good for: invariants that must always apply (database, deployment, RIPER)
- Example: `code-quality.md`, `git-workflow.md`, `riper-cat.md`

**Heuristic**: If it needs its own context → agent. If it's a command or workflow → skill. If it's an always-on constraint → rule.

---

## 5. Shared/referenced files convention

**Anthropic**: no mandatory location. Teams organize by preference.

**convention** (from the reference project, 2026-04):
- `.claude/skills/_shared/` — shared checklists, reference docs, templates. Underscore prefix keeps them out of `/` autocomplete (they're not user-invocable skills).
- Cross-reference with markdown links: `[checklist.md](../_shared/review-checklist.md)`.
- Supporting files live in the same skill directory (progressive disclosure).

---

## 6. New in 2026 Claude Code (v2.1.112)

- **`effort: xhigh`** — effort level between `high` and `max`; the docs describe it as "deeper reasoning at higher token spend" and make it the default only on Opus 4.7, so the reference fleet reserves `xhigh` for decision/diagnosis/gate-verdict deliverables (members in review-checklist.md's tier rows; derive the count with `agent-model-tier.py status`, never quote one).
- **Claude Opus 5.5** (2026-09) — `model: opus` / `claude-opus-5-5`; needs Claude Code ≥ 2.1.280. Model default effort is `medium`, so every agent in this fleet states its effort. Opus 5 (`claude-opus-5`, adopted 2026-07-27) is its predecessor under the same alias. See model rubric §3.
- **Claude Fable 5.1** (5.0 introduced 2026-06-09; 5.1 released 2026-09-01) — `model: fable` / `claude-fable-5-1`.
- **`/ultrareview`** — parallel multi-agent code review (Mar 2026).
- **`/less-permission-prompts`** — scan transcripts for read-only tools, propose allowlist (Feb 2026).
- **Worktree `sparsePaths`** — better isolation for `isolation: worktree` agents.
- **MCP elicitation** — MCP servers can request structured mid-task input.
- **No breaking changes** to agent/skill frontmatter from 2025 schema.

### Removed
- `/tag`, `/vim` (use `/config`)
- `/output-style` (use `/config`)

---

## 7. Prompt engineering for subagents

**Source**: https://code.claude.com/docs/en/how-claude-code-works.md

> "Think of delegating to a capable colleague. Give context and direction, then trust Claude to figure out the details."

- Brief task statement + focused instructions, not verbose walkthroughs
- Let the agent choose execution order
- Remember: subagents see only their system prompt — be self-contained
- Include 2+ `<example>` blocks in agent `description` showing when to invoke

---

## 8. Official citations

- Agents: https://code.claude.com/docs/en/agents.md
- Skills: https://code.claude.com/docs/en/skills.md
- Models: https://platform.claude.com/docs/en/about-claude/models/overview.md
- Changelog: https://code.claude.com/docs/en/changelog.md
- How Claude Code works: https://code.claude.com/docs/en/how-claude-code-works.md
- Memory (CLAUDE.md): https://code.claude.com/docs/en/memory.md

Document version: April 2026 (Claude Code v2.1.112, Claude API docs Jan 2026).
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
| `model` | `opus`, `sonnet`, `haiku`, pinned ID (`claude-opus-4-7`), or `inherit` (default). |
| `tools` | Comma/YAML list to restrict. Omit to inherit all. |
| `disallowedTools` | Denylist. Applied before `tools` allowlist. |
| `permissionMode` | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`. |
| `maxTurns` | Stops after N turns. |
| `skills` | List of skills preloaded into context at startup. Subagents don't inherit parent skills. |
| `mcpServers` | Inline or referenced MCP definitions. |
| `hooks` | `PreToolUse`, `PostToolUse`, `Stop` (becomes `SubagentStop`). Scoped to this agent. |
| `memory` | `user`, `project`, or `local`. Enables cross-session memory. Auto-enables Read/Write/Edit. |
| `background` | `true` to always run as background task. |
| `effort` | `low`, `medium`, `high`, `xhigh` (Opus 4.7), `max`. Overrides session effort. |
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

## 3. Model assignment rubric (Opus 4.7 / Sonnet 4.6 / Haiku 4.5)

**Source**: https://platform.claude.com/docs/en/about-claude/models/overview.md (Apr 2026)

| Model | Strengths | Cost (input/output per MTok) | Recommended for |
|-------|-----------|------------------------------|-----------------|
| **Opus 4.7** | Most capable. Step-change over 4.6 in agentic coding + complex reasoning. 1M ctx. `xhigh` effort available. | $5 / $25 | Complex coordinators, security review, architectural decisions, multi-step reasoning |
| **Sonnet 4.6** | Best speed/intelligence combo. 1M ctx. | $3 / $15 | Code review, domain specialists, interactive work, consolidation |
| **Haiku 4.5** | Fastest with near-frontier intelligence. 200k ctx. | $1 / $5 | Read-only research, file discovery, grep patterns |

### project-specific guidance (user on max plan — bias upward when ambiguous)

| Agent role | Recommended model |
|------------|-------------------|
| Orchestrators (project-coordinator, docs-manager) | `opus` |
| Security / critical review (code-reviewer, auth-specialist, subscription-specialist) | `opus` |
| Complex domain (chat-specialist, case-law-specialist, outline-iq-specialist, essay-coach-specialist, issue-spotter-specialist, intelligence-specialist, study-plan-specialist) | `opus` |
| Infra with real blast radius (database-specialist, deployment, gcp-infra, ai-infrastructure) | `opus` |
| UI & code review (ui-specialist) | `opus` |
| Routine specialists (blog-specialist, marketing-specialist, mobile-specialist, courses-specialist, community-specialist, dashboard-specialist, outline-manager, nextgen-*, n8n-*, cloud-run-specialist) | `sonnet` |
| Output consolidation (processor, test-runner) | `sonnet` |
| Read-only exploration (none currently — candidate for future `Explore`-type agents) | `haiku` |

**Rule of thumb**: If the agent makes non-trivial judgements that affect production, pick Opus. If it's transforming output or following a checklist, Sonnet is usually enough.

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
- Example: `database.md`, `deployment.md`, `riper-cat.md`

**Heuristic**: If it needs its own context → agent. If it's a command or workflow → skill. If it's an always-on constraint → rule.

---

## 5. Shared/referenced files convention

**Anthropic**: no mandatory location. Teams organize by preference.

**project convention** (established 2026-04):
- `.claude/skills/_shared/` — shared checklists, reference docs, templates. Underscore prefix keeps them out of `/` autocomplete (they're not user-invocable skills).
- Cross-reference with markdown links: `[checklist.md](../_shared/review-checklist.md)`.
- Supporting files live in the same skill directory (progressive disclosure).

---

## 6. New in 2026 Claude Code (v2.1.112)

- **`effort: xhigh`** — new Opus 4.7 effort level between `high` and `max`.
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
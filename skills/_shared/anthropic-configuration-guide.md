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
| `model` | `fable`, `opus`, `sonnet`, `haiku`, a pinned ID (`claude-opus-5`, `claude-fable-5`), or `inherit` (default). **Prefer the alias.** `opus` resolves to the current Opus — `claude-opus-5` since 2026-07-27 — so alias-based agents inherit each new release for free; a version-pinned ID silently strands the agent on an old model. |
| `tools` | Comma/YAML list to restrict. Omit to inherit all. |
| `disallowedTools` | Denylist. Applied before `tools` allowlist. |
| `permissionMode` | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`. |
| `maxTurns` | Stops after N turns. |
| `skills` | List of skills preloaded into context at startup. Subagents don't inherit parent skills. |
| `mcpServers` | Inline or referenced MCP definitions. |
| `hooks` | `PreToolUse`, `PostToolUse`, `Stop` (becomes `SubagentStop`). Scoped to this agent. |
| `memory` | `user`, `project`, or `local`. Enables cross-session memory. Auto-enables Read/Write/Edit. |
| `background` | `true` to always run as background task. |
| `effort` | `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort. Default when omitted is `medium`. Set explicitly (`xhigh`/`max`) on high-stakes agents; `xhigh` is Anthropic's recommended starting point for coding/agentic work on Opus 5. |
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

## 3. Model assignment rubric (Opus 5 / Fable 5 / Sonnet 5 / Haiku 4.5)

**Source**: https://platform.claude.com/docs/en/about-claude/models/overview.md + https://www.anthropic.com/news/claude-opus-5 (Jul 2026)

> **Claude Opus 5 (2026-07-27):** `model: opus` now resolves to **`claude-opus-5`** — same $5/$25 pricing as Opus 4.8, so this was a free capability upgrade. Because agents use the **alias** `opus` rather than a version-pinned ID, the whole Opus fleet picked it up with **zero frontmatter edits**. The Fable roster shrank **13 → 2** the same day: Anthropic puts Opus 5 within **0.5% of Fable 5's peak CursorBench 3.2 score at half the cost**, its cyber classifiers "intervene around 85% less often" than Fable's (which matters because Fable refuses benign security work), and it is Anthropic's "most aligned model to date." Fable 5 stays only where its remaining edge in general intelligence *is* the deliverable — the two domain-content authors.

| Model | Strengths | Cost (input/output per MTok) | Recommended for |
|-------|-----------|------------------------------|-----------------|
| **Opus 5** | State-of-the-art coding + long-horizon agentic work; more than doubles Opus 4.8 on Frontier-Bench v0.1 and lands within 0.5% of Fable 5 on CursorBench 3.2. High precision *and* recall on code review / bug-finding. Most aligned Claude model to date. 1M ctx, full effort ladder. `low`/`medium` unusually strong. | $5 / $25 | Everything except the two domain-content authors — high-stakes + complex domains (xhigh), routine specialists (medium default), ve-worker batch runner |
| **Fable 5** | Still the strongest on general intelligence and the most demanding open-ended reasoning. 1M ctx, full effort ladder. Capacity capped at 50% of Max limits; cyber classifiers refuse benign security work; requires 30-day data retention (no ZDR). | $10 / $50 | The two domain-content authors only (`effort: max`) — correctness-critical domain-content authoring. See review-checklist.md. |
| **Sonnet 5** | Near-Opus quality on coding/agentic at Sonnet cost. 1M ctx, full effort ladder. | $3 / $15 | Reserved — speed-critical simple tasks |
| **Haiku 4.5** | Fastest with near-frontier intelligence. 200k ctx. | $1 / $5 | Read-only research, file discovery, grep patterns |

### Project-specific guidance (user on max plan — bias upward when ambiguous)

The **authoritative per-agent tier membership** lives in [review-checklist.md → Model + effort rubric](review-checklist.md) — do NOT re-inline the per-agent lists here (they drifted before). Role-level summary of the two-model split:

| Agent role | Model + effort |
|------------|----------------|
| Correctness-critical offline domain-content authoring (content-writer, assessment-writer) | `fable` + `effort: max` |
| High-stakes + remaining complex domains — security/money, orchestration, deepest cross-system AI domains, highest blast-radius infra, public claims, plus corpus/grading/assessment/doc-analysis/planning/memory-bank/institutional/legacy-product/docs-manager/automation-architect/ai-infrastructure/deployment/ui (24 agents — see review-checklist.md) | `opus` + `effort: xhigh` |
| Routine domain specialists + consolidation (blog/mobile/courses/community/dashboard/study/flag-manager/outline-manager/n8n-*/cloud-run, processor, test-runner) + ve-worker | `opus` (effort omitted = medium) |
| Read-only exploration (future `Explore`-type agents) | `haiku` |

**Rule of thumb**: Opus 5 is the default for everything; Fable is a scarce resource (50% of plan limits, plus cyber-classifier refusals on security work) reserved for the one case where its general-intelligence edge *is* the deliverable — domain-content authoring, where a subtle mis-stated rule is costly and hard to detect. **Every high-stakes agent needs an explicit `effort:` line** (omitting it silently runs at `medium`). **Use the `opus` alias, never a version-pinned ID** — the alias is what made the Opus 5 upgrade a zero-edit event. Unattended batch work (ve-worker) never runs on Fable.

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

**convention** (from the reference project, 2026-04):
- `.claude/skills/_shared/` — shared checklists, reference docs, templates. Underscore prefix keeps them out of `/` autocomplete (they're not user-invocable skills).
- Cross-reference with markdown links: `[checklist.md](../_shared/review-checklist.md)`.
- Supporting files live in the same skill directory (progressive disclosure).

---

## 6. New in 2026 Claude Code (v2.1.112)

- **`effort: xhigh`** — effort level between `high` and `max`; Anthropic's recommended default for coding and agentic work on Opus 5.
- **Claude Opus 5** (adopted here 2026-07-27) — `model: opus` / `claude-opus-5`. State-of-the-art coding + long-horizon agentic work at unchanged Opus pricing ($5/$25); most aligned Claude model to date. Runs **37 of 39** agents. See model rubric §3.
- **Claude Fable 5** (introduced 2026-06-09, made permanent 2026-07-18 at 50% of Max plan limits) — `model: fable` / `claude-fable-5`. Retains the edge on general intelligence, but capped capacity + cyber-classifier refusals on security work narrowed its roster to **the two domain-content authors** on 2026-07-27. See model rubric §3.
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
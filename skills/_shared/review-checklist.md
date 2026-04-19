# Review Checklist (Shared)

Used by all `review-*` skills. Codifies Anthropic best practices + project conventions into an actionable checklist. For deep reference and citations, see [anthropic-configuration-guide.md](anthropic-configuration-guide.md).

---

## Core principles

1. **Search before creating** — never create a duplicate (v2, -new) file. Update existing.
2. **Anthropic is authoritative** — where conventions differ from project practice, flag the drift.
3. **Findings go to the board** — every finding becomes a task, not a conversation note.
4. **Severity mapping**:
   - **critical** → broken behavior, security, data loss risk
   - **high** → stale references, wrong model tier for critical agent, failing trigger keywords
   - **medium** → description clarity, missing examples, redundancy
   - **low** → style, minor polish

---

## Frontmatter schema (validate on every artifact)

### Agents (`.claude/agents/*.md`)

**Must have**:
- `name` — unique, lowercase, hyphens, max 64 chars, matches filename
- `description` — includes trigger keywords + 2+ `<example>` blocks
- `model` — explicit (`opus`/`sonnet`/`haiku`), not missing

**Check also**:
- `color` present for visual distinction
- `memory: project` for agents that should accumulate insights
- `tools` restriction makes sense for role (read-only agents should restrict)
- `effort` set to `xhigh` for Opus 4.7 agents doing the hardest reasoning (optional)

### Skills (`.claude/skills/*/SKILL.md`)

**Must have**:
- `description` — specific, explains when to invoke
- `name` matches directory (or omitted, defaults to directory name)

**Check also**:
- `disable-model-invocation: true` for commands with side effects
- `user-invocable: false` for Claude-only background knowledge
- `allowed-tools` listed for skills that use specific tools
- `paths` glob scoping for skills tied to specific directories

### Rules (`.claude/rules/*.md`)

Rules don't have frontmatter — they're plain markdown referenced from CLAUDE.md.

**Check**:
- Referenced from CLAUDE.md (orphaned rules are dead)
- Size reasonable (< 300 lines — split if growing)
- No contradictions with other rules or CLAUDE.md

---

## Model + effort rubric (apply to every agent)

If you're on the Max Claude plan. Token cost is NOT the constraint — throughput and quality are. New strategy (2026-04): default Opus 4.7 with `effort: medium`, elevate to `xhigh` for complex/nuanced work, reserve Sonnet/Haiku for edge cases.

| Tier | Frontmatter | Use for |
|------|-------------|---------|
| **Opus 4.7 + effort: xhigh** | `model: opus`, `effort: xhigh` | Orchestrators (project-coordinator, docs-manager). Security-critical (code-reviewer, auth-specialist, subscription-specialist). Complex AI systems (chat-specialist, case-law-specialist, outline-iq-specialist, essay-coach-specialist, issue-spotter-specialist, intelligence-specialist, study-plan-specialist). Blast-radius infra (database-specialist, deployment, gcp-infra, ai-infrastructure). UI judgement (ui-specialist). Architectural decisions. |
| **Opus 4.7 + effort: medium** *(default)* | `model: opus` (effort omitted — medium is the default) | Routine specialists where details still matter but scope is narrow: domain agents (blog-specialist, marketing-specialist, mobile-specialist, courses-specialist, community-specialist, dashboard-specialist, outline-manager, nextgen-*, n8n-*, cloud-run-specialist). Consolidation (processor, test-runner). |
| **Sonnet 4.6** | `model: sonnet` | Reserved — speed-critical simple tasks where Opus overhead is unjustified. Rarely applicable on a max plan. |
| **Haiku 4.5** | `model: haiku` | Read-only exploration, fast file discovery (e.g., future `Explore`-style agents). |

Flag these as **findings**:
- Haiku/Sonnet on any agent making non-trivial judgement → upgrade to Opus medium (or xhigh if complex)
- Opus without `effort: xhigh` on orchestrators, security, or complex AI work → promote to xhigh
- `effort: xhigh` on routine specialists → demote to medium (wasted ceiling)
- Missing `model` field → add explicit `model: opus`
- Missing `effort` on a complex-tier agent → add explicit `effort: xhigh`

---

## Description format (agents)

**Canonical pattern**: `[role]. [what it does]. [when to invoke + triggers].`

**Required structure for agents**:
```yaml
description: Short role statement. What it does. When to use it.

  Examples:
  - <example>
    Context: [Scenario]
    user: "[User request]"
    assistant: "I'll use [agent-name] to [action]."
    <commentary>[Why this agent fits]</commentary>
  </example>
```

**Flag if**:
- Fewer than 2 `<example>` blocks
- No `<commentary>` explaining why the agent fits
- Generic description (e.g., "Helps with database stuff") — not actionable
- Triggers absent or vague

---

## Content freshness checks

For every artifact, verify:

1. **Referenced files exist** — use Glob on every path mentioned
2. **Code examples valid** — use Grep to find current patterns
3. **No deprecated references** — Supabase Edge Functions, retired services, old table names, removed features
4. **Service references match reality** — cross-check with `services/` directory + Docker Compose
5. **Domain names correct** — <your-domain> variants, MIG host names, DB names
6. **Model IDs current** — `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5` (or use short aliases: `opus`, `sonnet`, `haiku`)

---

## Redundancy + merge/split criteria

### Merge candidates (flag if ≥ 2 true):
- Description overlap > 80% semantic similarity
- Trigger keywords overlap > 50%
- Same domain (e.g., two auth-related agents)
- Called in sequence most of the time

### Split candidates (flag if ≥ 2 true):
- Description contains "and" connecting unrelated domains
- Trigger keywords cluster into 2+ disjoint groups
- Prompt body > 1000 words and spans multiple concerns
- Agent invoked for mutually exclusive reasons

Recommendation format:
- **Merge**: `merge [agent-a] + [agent-b] → [new-name]`, with rationale
- **Split**: `split [agent] into [part-a] + [part-b]`, with boundary

---

## Cross-reference integrity

For rules, docs, agents, skills:
- Every markdown link resolves (file exists at relative path)
- Every referenced `$AGENT_NAME` / `$SKILL_NAME` exists
- Every mentioned command (`Enter C -push`, `/review`) is still valid
- Every external URL reachable (HTTP 200 or redirect)

---

## Size and shape

| Artifact | Target | Hard limit |
|----------|--------|------------|
| Agent prompt body | 200–800 words | 1500 words |
| SKILL.md | < 300 lines | 500 lines |
| Rule | < 200 lines | 300 lines |
| CLAUDE.md | < 150 lines | 200 lines |
| MEMORY.md | < 150 lines | 200 lines (truncated after) |
| Doc file | < 500 lines | 800 lines |

**Flag** any artifact exceeding target. Progressive-disclose (move reference material to supporting files) if exceeding hard limit.

---

## Output format (what review-* skills produce)

After reviewing, every skill must:

1. **Create a parent Vibe Board task** per severity tier found:
   - `[Review] [Artifact type] — Critical findings`
   - `[Review] [Artifact type] — High findings`
   - etc.
2. **Create a subtask** per finding with:
   - File path
   - Specific issue
   - Recommended fix
3. **Return a lean summary** to the main agent:
   - N artifacts reviewed
   - X findings total, broken down by severity
   - Board parent task IDs
4. **Never dump raw findings into the conversation** — they get lost on compaction.

---

## Anthropic compliance checklist

Quick binary checks any review should apply:

- [ ] Frontmatter uses documented fields only (no invented keys)
- [ ] `description` < 1,536 chars combined with `when_to_use`
- [ ] Model field explicit or justified as `inherit`
- [ ] Skill body < 500 lines (else progressive-disclose)
- [ ] Agent prompt self-contained (doesn't assume CLAUDE.md is loaded)
- [ ] Subagent prompt delegates like a "capable colleague" (brief + trusting)
- [ ] No deprecated Claude Code commands referenced (`/tag`, `/vim`, `/output-style`)
- [ ] No deprecated model IDs (Opus 4.5, Sonnet 4.5, Haiku 4.3 pinned IDs)
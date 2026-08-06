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
- `effort` set to `xhigh`/`max` for the hardest-reasoning agents. **Required (not optional) on every high-stakes agent** (orchestration / security / complex domain / blast-radius / correctness-critical authoring) — set `xhigh` (or `max` for the two domain-content authors) explicitly. Routine specialists may omit `effort` (defaults to `medium`, which is the intended default — and `medium` is unusually strong on Opus 5). See Model + effort rubric.

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

On the Max Claude plan, token cost is NOT a direct dollar constraint, but **Fable 5 capacity IS** (Fable is included in Max plans at only **50% of plan limits**). Tiering stays **two-model**, but the split moved sharply toward Opus with the **Claude Opus 5 release (2026-07-27)**: `model: opus` now resolves to **Claude Opus 5** (`claude-opus-5`, 1M ctx, $5/$25) and carries all but two agents; `model: fable` (Claude Fable 5, `claude-fable-5`, $10/$50) is reserved for the two domain-content authors.

> **`model:` values are ALIASES, not pinned IDs — this is load-bearing.** `model: opus` resolves to whatever Claude Code currently maps `opus` to, which is now `claude-opus-5`. That is why the Opus-tier fleet picked up Opus 5 with **zero frontmatter edits** on a model release. Keep using the alias; do NOT pin `claude-opus-4-8` (or any dated ID) in agent frontmatter — pinning is what turns a free upgrade into a 37-file migration.

**Why the Fable roster shrank 13 → 2 (2026-07-27):** (1) Anthropic puts Opus 5 **within 0.5% of Fable 5's peak score on CursorBench 3.2 at half the cost** (Anthropic measures that at `max` effort; the moved agents run `xhigh`, so expect near-parity rather than exactly that figure), and it "more than doubles Opus 4.8" on Frontier-Bench v0.1 — the code/infra/architecture correctness that 11 of the 13 agents actually do is Opus 5's strongest axis. (2) **Fable's cyber classifiers refuse benign security work**; Opus 5's "intervene around 85% less often" — decisive for code-reviewer / auth-specialist / gcp-infra / mig-specialist, whose job is security-adjacent by definition. (3) Opus 5 is Anthropic's "most aligned model to date," adhering to the Constitution better than Opus 4.8, Sonnet 5, *or* Fable 5 — relevant on money, auth, and public-claims surfaces. (4) Capacity: every Fable seat draws on the capped 50%-of-limits pool, so the roster is reserved for where depth genuinely decides the outcome. Fable 5 remains stronger on general intelligence — which is exactly the domain-content authors' deliverable, and why they stay.

**Effort ladder:** `low < medium < high < xhigh < max` (applies on both models). When `effort` is omitted the agent runs at the Claude Code default (`medium`). High-stakes agents set an explicit `effort:` line; routine specialists may omit it. Two Opus 5 notes: `low`/`medium` are **unusually strong** on Opus 5, so the omitted-effort routine tier got materially better for free; and `max` "can improve performance on demanding tasks but may show diminishing returns and is prone to overthinking" — NOT a blanket upgrade over `xhigh`; reserve it for the two domain-content authors.

| Tier | Frontmatter | Use for |
|------|-------------|---------|
| **Fable + max** | `model: fable`, `effort: max` | **Correctness-critical domain-content authoring & evaluation that is latency-insensitive** (design / batch / interactive authoring, NOT in a user's request path), where a subtle domain error (a mis-stated rule, a distractor that is quietly also correct) is costly and hard to detect. Members: **content-writer, assessment-writer**. The agent's job IS the domain reasoning — Fable's depth is the whole deliverable here. Production bulk generation runs on a separate non-Claude pipeline, so the Claude agent's role is design/eval, where overthinking risk is low. Do NOT promote request-path graders (grading, product-line grading via product-line-specialist) to max — they're latency-sensitive; keep them at xhigh. |
| **Opus 5 + xhigh** | `model: opus`, `effort: xhigh` | **24 members** — everything high-stakes plus the remaining complex domains. Security/money (**code-reviewer, auth-specialist, subscription-specialist**), orchestration (**project-coordinator**), deepest cross-system AI domains (**chat-specialist, intelligence-specialist, product-line-specialist**), highest blast-radius infra with production-outage history (**database-specialist, gcp-infra, mig-specialist**), public-claims/compliance (**marketing-specialist**) — these eleven moved off Fable on 2026-07-27, keeping `effort: xhigh`. Joining the tier they were already alongside: ai-infrastructure, automation-architect, corpus-specialist, deployment, docs-manager, grading-specialist, assessment-specialist, institutional-specialist, legacy-product-specialist, memory-bank-specialist, doc-analysis-specialist, planning-specialist, ui-specialist. xhigh is for **breadth / blast-radius / request-path reasoning** — distinct from max's **depth-of-correctness** rationale, and Anthropic's recommended default for coding + agentic work on Opus 5. |
| **Opus 5 medium** *(default)* | `model: opus` (effort omitted — medium is the default) | Routine specialists where details still matter but scope is narrow: domain agents (blog-specialist, mobile-specialist, courses-specialist, community-specialist, dashboard-specialist, practice-specialist, flag-manager, outline-manager, n8n-*, cloud-run-specialist). Consolidation (processor, test-runner). Plus the **ve-worker batch runner — deliberately Opus**, never Fable: unattended batch volume would burn the capped Fable pool. |
| **Sonnet 5** | `model: sonnet` | Reserved — speed-critical simple tasks where Opus overhead is unjustified. Rarely applicable on a max plan. |
| **Haiku 4.5** | `model: haiku` | Read-only exploration, fast file discovery (e.g., future `Explore`-style agents). |

Flag these as **findings**:
- Haiku/Sonnet on any agent making non-trivial judgement → upgrade to Opus medium (or xhigh if complex)
- An agent on `model: fable` that is NOT one of the **two** domain-content authors → demote to `model: opus` (capacity discipline), keeping its `effort:` line
- A **version-pinned model ID** in agent frontmatter (`claude-opus-4-8`, `claude-opus-5`, …) instead of the `opus` alias → replace with the alias. Pinning forfeits the automatic pickup of the next Opus release and creates a fleet-wide migration where there should be none
- A max-tier or xhigh-tier agent missing its explicit `effort:` line → add one (it would silently default to `medium`)
- `effort: xhigh`/`max` on a routine specialist → demote to medium (wasted ceiling)
- `effort: max` on a request-path or routine agent → demote to xhigh/medium (overthinking risk, no latency budget)
- A correctness-critical offline content-authoring agent NOT at `model: fable` + `effort: max` → promote
- Missing `model` field → add explicit `model: opus` (or `fable` if roster member)
- Missing `effort` on a high-stakes agent → add explicit `effort: xhigh` (or `max` for the two domain-content authors)
- The ve-worker or any unattended batch runner on `model: fable` → revert to Opus (capacity discipline)

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
6. **Model IDs current** — `claude-opus-5` (`opus` — 37 of 39 agents, tiered by effort), `claude-fable-5` (`fable` — the two domain-content authors only), `claude-sonnet-5`, `claude-haiku-4-5`. Flag any doc still claiming `opus` means Opus 4.8, still listing a 12/13-agent Fable roster, or still claiming Fable was "pulled"/"retired".

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
- [ ] No deprecated/retired model IDs, and no *version-pinned IDs* where an alias belongs. NOTE: two agent tiers since the 2026-07-27 Opus 5 release — `fable` (the **two** domain-content authors only) + `opus` (the other 37, effort-tiered); `claude-opus-5` and `claude-fable-5` are both current
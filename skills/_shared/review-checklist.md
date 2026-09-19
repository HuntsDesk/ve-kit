# Review Checklist (Shared)

Used by all `review-*` skills. Codifies Anthropic best practices + project conventions into an actionable checklist. For deep reference and citations, see [anthropic-configuration-guide.md](anthropic-configuration-guide.md).

---

## Core principles

1. **Search before creating** — never create a duplicate (v2, -new) file. Update existing.
2. **Anthropic is authoritative** — where conventions differ from project practice, flag the drift.
3. **Findings go to the board** — never a conversation note. **High/critical findings become tasks; medium/low findings are ledgered** as one comment on the severity parent (severity-gated since 2026-09-04; a ledgered line with live harm is filed as high at filing time, not left to the ledger).
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
- `model` — explicit (`fable`/`opus`/`sonnet`/`haiku`), not missing, and an **alias** rather than a dated ID. Must agree with `.claude/agent-model-tiers.json` (the kit ships `agent-model-tiers.template.json`) — verify with `agent-model-tier.py check`, not by eye

**Check also**:
- `color` present for visual distinction
- `memory: project` for agents that should accumulate insights
- `tools` restriction makes sense for role (read-only agents should restrict)
- `effort` stated explicitly on every Fable agent: `high` by default, `xhigh` only for decision/diagnosis deliverables, `max` only for the two domain-content authors. Only `processor` omits `effort`, which makes it **inherit the launching session's effort** — not a fixed `medium`. See Model + effort rubric.

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

Rules are markdown referenced from CLAUDE.md. They support ONE optional frontmatter key: `paths`, a YAML list of globs (`**`, `*`, and `{a,b}` all work). A rule with `paths` loads only when a matching file is read or edited. A rule WITHOUT `paths` loads unconditionally into every session and counts against startup context in full.

```yaml
---
paths:
  - "services/**"
  - "**/*.sql"
---
```

**Check**:
- Referenced from CLAUDE.md (orphaned rules are dead)
- **Domain-bound rules SHOULD be path-scoped; behavioural rules stay unconditional.** A rule that only applies while touching a specific surface (database, deployment, feature flags, UI components, a product's marketing claims) belongs behind `paths`. A rule about how to work at all — process gates, review discipline, git coordination — must stay unconditional, because the file that would trigger it is exactly the file you're about to get wrong.
  - **The dividing line is the TRIGGER, not the rule's pedigree** (a reference-project decision). A rule may call itself the sibling of an unconditional rule and still belong behind `paths` — a rule about code semantics (a value computed, displayed, never consumed) and its propagation sibling (carry a fix to every logical twin) are the worked example: both were correctly path-scoped to code files, because their traps are about code, column and prompt semantics, so every one of them fires *on a file edit* and the glob is what loads them at that moment. Their close relative, a rule about query discipline (never trust an empty result from a filter you have not validated), stays unconditional because its subject is **queries** — a database CLI, a log filter, a cloud CLI — which touch no file, so a `paths:` block would unload it exactly when it is needed. **Do not "reconcile" the two by reading a sibling relationship as implying identical scoping**; that inference is what this note exists to answer. A scoped rule still owes a pointer from an unconditional one wherever its subject can be reached without editing a file (e.g. a prod-state mutation applied by hand).
- Every glob resolves to real paths (check with `ls`/Glob before shipping one). A typo'd glob silently disables the rule.
- Prefer a few broad globs over many narrow ones — narrow globs rot as files move.
- Size reasonable (< 300 lines — split if growing)
- No contradictions with other rules or CLAUDE.md

---

## Model + effort rubric (apply to every agent)

**Founder directive, 2026-09-05 (reference project) — quality first; capacity is not a constraint.** Paraphrased: *"quota is rarely the binding constraint; the product is complex and intertwined, so use the right agent for each job rather than trading a wrong answer for capacity."* Every previous argument for keeping the Fable roster small was a capacity argument, and all of them are retired below. **Never keep an agent on Opus for cost or capacity reasons.**

### THE RULE — the roster is DERIVED from this, not the reverse

**Default to Fable 5.1** (`model: fable`) for any agent meeting **any one** of:

- **(a) writes code or config into a shared / intertwined domain** — anything another surface reads or another window edits
- **(b) produces claims or content that ship to users or to prod** — domain content, marketing copy, DB rows, prod-state mutation
- **(c) does long-horizon agentic or cross-domain research / orchestration**
- **(d) is a review gate** — anything whose verdict decides whether *code* proceeds to commit or deploy. Deliberately narrow: recording someone else's findings is not a gate, which is what leaves `processor` outside the rule.

**Opus 5 keeps only agents that TRANSCRIBE rather than AUTHOR or DECIDE**: no product or config writes, no prod-state mutation, no user-facing claim, no gate verdict, and a written procedure that fully determines the output. **Exactly one agent qualifies today — `processor`** (writes board rows only; no Write/Edit/Bash/WebFetch; its severity map is written down in this file).

**Sonnet 5** stays reserved. **Haiku 4.5** stays the read-only-exploration tier. Neither changed on 2026-09-05.

Why the rule is shaped this way: the benchmark deltas are widest on **long-horizon agentic and cross-domain** work, which is exactly where the reference project's defects come from. The 2026-08 audit found that *every* main-introduced defect sat in an undelegated specialist domain (`.claude/rules/riper-cat.md` MODE 4), and the 2026-09-05 assessment/signal-processing episode was a confident cross-domain false mechanism from an Opus/xhigh specialist.

### Benchmarks of record

Source: <https://www.anthropic.com/claude-fable-and-mythos-5-1>, read 2026-09-05. Fable 5.1 (`claude-fable-5-1`) vs Opus 5 (`claude-opus-5`):

| Benchmark | Fable 5.1 | Opus 5 |
|---|---|---|
| Terminal-Bench-Science 0.1 (agentic research) | **52.6** | 29.0 |
| Terminal-Bench 4.0 (agentic coding) | **55.8** | 52.3 |
| CursorBench 3.2.0 (agentic coding) | **73.4** | 70.0 |
| GDPval-AA v2 (knowledge work) | **1853** | 1824 |
| OSWorld 2.0 — strict / partial (computer use) | **41.7 / 77.9** | 39.6 / 75.4 |
| Humanity's Last Exam — no tools / with tools | **60.9 / 65.0** | 56.6 / 63.6 |
| AutomationBench (business workflows) | **31.4** | 26.9 |

Pricing: Fable 5.1 $10/$50 per MTok, cache reads $0.25/MTok; Opus 5 $5/$25, 1M context. Fable and Mythos 5.1 are the same underlying model with different safeguards. **Do not cite `42.0` as Opus 5's Terminal-Bench 4.0 score — that is Fable 5's column**, and the two get conflated by summarizers (it happened once while writing this section).

### Retired rationales — do NOT re-derive these

| Retired claim | Retired | Why it is dead |
|---|---|---|
| "Fable capacity is capped at 50% of Max plan limits, so every seat has to earn itself" | **2026-09-05** | Founder directive above. This was the **only** remaining reason the roster was 3 agents. With it withdrawn the roster follows THE RULE. |
| "Opus 5 is within 0.5% of Fable's peak CursorBench score" | 2026-09-01 | True of Fable 5, not Fable 5.1. Live gaps are in the table above. |
| "Fable's cyber classifiers refuse benign security work" | 2026-09-01 | Fable 5.1 intervenes ~60% less often per session in Claude Code; vulnerability-finding is permitted. |
| "project-coordinator is too high-volume to put on Fable" | **2026-09-05** | Volume was a capacity argument. It is an orchestrator (rule **c**) and now runs Fable/xhigh. The 2026-09-03 measurement (board `<YOUR_MEASUREMENT_TASK_ID>`) already favoured it on the hardest bucket. |

**Still open, NOT retired**: at `xhigh`/`max`, Fable 5.1 may draft a long deliverable inside its thinking and then write it again (~2× output tokens). That is now a **cost** note only, and cost does not gate model choice here — but it remains a reason to *measure* rather than assume `max` beats `xhigh` on long deliverables.

> **`model:` values are ALIASES, not pinned IDs — this is load-bearing.** `fable` → `claude-fable-5-1`, `opus` → `claude-opus-5`. The Opus fleet picked up Opus 5 with **zero frontmatter edits** because it used the alias. Never pin a dated ID; pinning is what turns a free upgrade into a fleet-wide migration.

### THE EFFORT RULE (amended 2026-09-05, same directive)

**Effort ladder:** `low < medium < high < xhigh < max` (both models). On Fable 5.1:

- **`high` is the DEFAULT for every Fable agent.** Anthropic's guidance is to start at `high` and move up only on measured gain. This is *not* a downgrade from `opus` + `xhigh`: Fable 5.1's lower effort levels already exceed prior models at `xhigh`.
- **`xhigh` ONLY where the deliverable is a DECISION or DIAGNOSIS rather than a DOCUMENT, and under-thinking is the costlier failure.** Money/auth, schema and data integrity, outage-class infra, deploy, and the cross-system AI domains where a wrong root cause sends real work down the wrong path. Members are listed in the tier rows below; the only stated count is the **Preferred roster total** line beneath them (the one count with a ground-truth check, `scripts/agent-model-tier.py status`). The test is the SHAPE OF THE OUTPUT, not the importance of the domain — marketing-specialist and institutional-specialist matter enormously and still write *documents*, so they sit at `high`.
- **`max` only on the two domain-content authors**, and **still unvalidated on Fable 5.1** — see the OPEN note below.

**Two cautions, and the mechanism behind both.** At `xhigh`/`max` Fable 5.1 may draft a long deliverable inside its thinking and then write it again — roughly **2× output tokens** for no measured gain. Long-prose deliverables (a code review, an audit, a doc, a marketing page, a question set) are exactly the shape that triggers this, which is why prose agents stay at `high`. Separately, `max` "can improve performance on demanding tasks but may show diminishing returns and is prone to overthinking" — it is **not** a blanket upgrade over `xhigh`.

> **OPEN — `effort: max` on the two domain-content authors is unvalidated on Fable 5.1. Do not change it; do not defend it either.** Settle it by A/B-ing `high` and `xhigh` against `max` on one real batch and comparing accept rate — not by reasoning from the ladder. Until that batch runs, `max` stays. The same A/B governs whether outline-manager should be promoted.

**An omitted `effort:` INHERITS THE LAUNCHING SESSION'S effort — it does NOT pin the agent to `medium`.** Claude Code's default is `high` on both models, so an omitted line runs at `high` in practice but would follow a session *down* if someone set it lower. It is inheritance, not a floor. Since 2026-09-05 **every Fable agent states its effort explicitly**; `processor` is the only agent that inherits.


| Tier | Frontmatter | Members | Use for |
|------|-------------|---------|---------|
| **Fable 5.1 + `max`** | `model: fable`, `effort: max` | content-writer, assessment-writer | **Correctness-critical domain-content authoring & evaluation that is latency-insensitive** (design / batch / interactive authoring, NOT in a user's request path), where a subtle domain error — a mis-stated rule, a distractor that is also correct — is costly and hard to detect. The agent's job IS the domain reasoning. Do NOT promote request-path graders (grading, product-line grading) to `max`; they are latency-sensitive, keep them at `xhigh`. |
| **Fable 5.1 + `xhigh`** | `model: fable`, `effort: xhigh` | auth-specialist, subscription-specialist, database-specialist, gcp-infra, mig-specialist, deployment, intelligence-specialist, chat-specialist, product-line-specialist, project-coordinator, assessment-specialist, grading-specialist, doc-analysis-specialist, ai-infrastructure, **flag-manager** (added the same day; the owner deferred to the rubric: "do what you think is best" — its deliverable is a prod flag toggle, not a document), **an ad-tracking specialist** (a routing decision in the money/PII band, not copy) | **Decision/diagnosis deliverables where under-thinking costs more than overthinking.** Money/auth, schema + data integrity, outage-class infra, deploy, and the cross-system AI domains where a wrong root cause sends real work down the wrong path. These are the agents whose output is a *judgement*; request-path graders belong here, not at `max`. |
| **Fable 5.1 + `high`** *(the default)* | `model: fable`, `effort: high` | everything else on Fable: **code-reviewer**, **agent-manager** (added 2026-09-07; deliberately never `xhigh` — it is a bookkeeper against this rubric, and must stay cheap enough to run *while quota is exhausted*), docs-manager, marketing-specialist, ui-specialist, institutional-specialist, legacy-product-specialist, memory-bank-specialist, planning-specialist, corpus-specialist, automation-architect, every product-domain specialist, test-runner, n8n-manager, outline-manager, **video-specialist** (added 2026-09-17; its deliverable is a composition and a rendered file — a document, not a decision — and the marketing-specialist review of public on-screen copy does not raise this agent's own effort) | **Long-prose deliverables** — reviews, audits, docs, copy, content. Exactly the shape that triggers the ~2× draft-twice behaviour at higher effort, so they stay at the recommended default. **code-reviewer sits here** (`high` reaffirmed 2026-09-05 after a same-day reversal to `xhigh`): a review IS a long prose deliverable, and the standing "do not raise without measuring" caution applies to it more than to any other agent. **outline-manager is a standing `max` candidate** (it authors domain outlines that ship to users — rule **b**), held pending the A/B above. |
| **Opus 5 · session effort** *(default `high`)* | `model: opus` (effort omitted) | processor | The transcribe-not-author carve-out. **Be honest about it: this is the one placement not fully derived from THE RULE.** Its severity gate ("live harm is never ledgered" — `.claude/rules/agent-board.md`) is a real judgement, and mis-filing a harm finding as a ledger line decides whether it gets scheduled at all. It stays on Opus only while that gate holds; the first time it misfires, processor moves to Fable and this tier empties. |
| **Sonnet 5** | `model: sonnet` | 0 | Reserved — speed-critical simple tasks. Rarely applicable. |
| **Haiku 4.5** | `model: haiku` | 0 | Read-only exploration, fast file discovery. |

**The roster follows from THE RULE — derive it from your own agent files; do not quote a count, it rots.**


> **The ve-worker batch runner's model is a PER-PROJECT call and is not governed by this table** (it is set on the worker's compose services). The reference project defaulted it to `opus`; paraphrased: *"an unattended batch should never stall on a model whose quota can run out mid-run, so default it to the one that is always available."* It is a **fixed default outside the preferred/fallback switch**, not a fallback entry: `scripts/agent-model-tier.py` only rewrites `.claude/agents/*.md` and never touches that compose file, so `apply preferred` will not return it to the fleet default when the fleet is restored to `preferred`. Changing it back is a separate, deliberate decision, and the compose file is where it is recorded. A review-agents finding that flags the worker on `opus` — in either fleet mode — is wrong.
>
> Lineage from the reference project, illustrative only — do not act on it: `opus` 2026-07-27 → 2026-09-05; then `fable` 2026-09-05 → 2026-09-19 (board `<YOUR_DECISION_TASK_ID>`), on the reading that it writes product code across the whole repo unattended (rules **a** and **c**) and that unattended long-horizon work is where Fable 5.1's lead is largest. On 2026-09-07 the owner was asked again during a weekly-quota fallback and chose to leave it on the fleet default, pausing batches rather than running them degraded. 2026-09-19 supersedes both, so a batch never draws on an exhausted Fable quota. Effort: `claude-go` and `claude-triage` pass none and inherit the CLI default (`high`); `claude-worker` keeps `--effort xhigh`, which is what it ran at during its first Opus stint — the only argument for `high` was Fable 5.1's ~2× draft-twice output tax, which has no Opus counterpart (the same reasoning as the code-reviewer / test-runner fallback exceptions).

Flag these as **findings**:
- An agent meeting any clause of THE RULE that is NOT on `model: fable` → promote, citing the clause it meets
- An agent on `model: opus` that authors, mutates prod, ships a user-facing claim, or issues a gate verdict → promote to `fable` (the Opus tier is transcription-only)
- Any argument for keeping an agent on Opus that reduces to **cost or capacity** → reject; that reasoning was retired 2026-09-05
- Haiku/Sonnet on any agent making non-trivial judgement → upgrade
- A **version-pinned model ID** in agent frontmatter (`claude-opus-5`, `claude-fable-5-1`, …) instead of the `opus`/`fable` alias → replace with the alias
- An `xhigh`/`max`-tier agent missing its explicit `effort:` line → add one. It does **not** fall back to `medium`; it inherits whatever the launching session runs at, so its ceiling is set by someone else's `/model` setting
- `effort: xhigh`/`max` on an agent whose deliverable is a **document** rather than a decision → demote to `high` (the ~2× draft-twice tax, no measured gain)
- `effort: high` on an agent whose deliverable is a **decision or diagnosis** in money/auth/schema/infra/deploy/cross-system-AI → promote to `xhigh`
- `effort: max` on a request-path agent → demote to `xhigh` (overthinking risk, no latency budget)
- A correctness-critical **offline** domain-content authoring agent not at `effort: max` → evaluate for promotion (currently the two domain-content authors; outline-manager is the standing candidate)
- Any doc still stating the 3-agent Fable roster, the 50%-capacity cap as a live constraint, "Opus is within 0.5% on CursorBench", or `42.0` as Opus 5's Terminal-Bench score → stale, fix it

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
6. **Model IDs current** — `claude-fable-5-1` (`fable` — the default, tiered by effort), `claude-opus-5` (`opus` — processor only), `claude-sonnet-5`, `claude-haiku-4-5`. Flag any doc still claiming `opus` means Opus 4.8, still naming `claude-fable-5` as current, still listing a 2/3/12/13-agent Fable roster, still treating Fable capacity as a live constraint, or still claiming Fable was "pulled"/"retired".

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
2. **Create a subtask** per **high/critical** finding (medium/low: one ledger comment on the severity parent, one line per finding with the same three fields; a line showing live harm is filed as high instead) with:
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
- [ ] No deprecated/retired model IDs, and no *version-pinned IDs* where an alias belongs. NOTE: `fable` is the DEFAULT (effort-tiered); `opus` carries only transcribe-not-author agents. Run `agent-model-tier.py status` (ships in the kit) before flagging a live `model:` value — a declared fallback is not drift. `claude-fable-5-1` and `claude-opus-5` are both current
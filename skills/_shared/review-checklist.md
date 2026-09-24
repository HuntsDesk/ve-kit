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
- `model` — explicit (`opus`/`fable`/`sonnet`/`haiku`; `opus` for every agent since 2026-09-23), not missing, and an **alias** rather than a dated ID. Must agree with `.claude/agent-model-tiers.json` (the kit ships `agent-model-tiers.template.json`) — verify with `agent-model-tier.py check`, not by eye

**Check also**:
- `color` present for visual distinction
- `memory: project` for agents that should accumulate insights
- `tools` restriction makes sense for role (read-only agents should restrict)
- `effort` stated explicitly on **every** agent: `high` by default, `xhigh` only for decision/diagnosis/gate-verdict deliverables, `max` only for the two domain-content authors. No agent omits it: an omitted line inherits the launching session, and Opus 5.5's model default is `medium`. See Model + effort rubric.

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


### THE RULE — the roster is DERIVED from this, not the reverse

**Every agent runs `model: opus`.** An agent may sit on a cheaper model only if it meets **none** of these, and today none qualifies:

- **(a) writes code or config into a shared / intertwined domain** — anything another surface reads or another window edits
- **(b) produces claims or content that ship to users or to prod** — domain content, marketing copy, DB rows, prod-state mutation
- **(c) does long-horizon agentic or cross-domain research / orchestration**
- **(d) is a review gate** — anything whose verdict decides whether *code* proceeds to commit or deploy


Why the clauses still matter: they are why nothing sits below the default. The 2026-08 audit found that *every* main-introduced defect sat in an undelegated specialist domain (`.claude/rules/riper-cat.md` MODE 4) — that is where the reference project's defects come from, and it is exactly the work (a)–(d) describe.

> **`model:` values are ALIASES, not pinned IDs — this is load-bearing.** `opus` → `claude-opus-5-5` (verified 2026-09-23 against code.claude.com/docs/en/model-config; Opus 5.5 needs Claude Code ≥ 2.1.280), `fable` → `claude-fable-5-1`. The fleet picked up Opus 5.5 with **zero frontmatter edits** because it used the alias — the same free upgrade Opus 5 and Fable 5.1 were. Never pin a dated ID; pinning is what turns a free upgrade into a fleet-wide migration.

### THE EFFORT RULE (re-stated for Opus 2026-09-23)

**Effort ladder:** `low < medium < high < xhigh < max` — all five supported on Opus 5.5 (verified 2026-09-23: `claude --help` on CLI 2.1.281, and the model-config docs' per-model table).

- **Every agent states `effort:` explicitly. None inherits.** Opus 5.5's *model default is `medium`* — the docs' "reduces token usage for cost-sensitive work that can trade off some intelligence" level — and a top-level `effortLevel` in user settings does not apply to it. An omitted line therefore follows a default Opus 5.5 session down to `medium`. That is why `processor`, the one agent that used to inherit, now states `high`.
- **`high` is the floor and the default** — for every agent whose deliverable is a DOCUMENT: reviews-as-prose, audits, docs, copy, content, product-domain work.
- **`xhigh` where the deliverable is a DECISION, DIAGNOSIS or GATE VERDICT and under-thinking is the costlier failure.** Money/auth, schema and data integrity, outage-class infra, deploy, the cross-system AI domains where a wrong root cause sends real work down the wrong path, prod flag toggles, and the two gates (code-reviewer, test-runner — a verdict is a decision, clause **d**). Members are listed in the tier rows below; derive the count from your own agent files with `agent-model-tier.py status` (the kit ships it at its root), never quote one. The test is the SHAPE OF THE OUTPUT, not the importance of the domain — marketing-specialist and institutional-specialist matter enormously and still write *documents*, so they sit at `high`.
- **`max` only on the two domain-content authors**, and **still unvalidated** — see the OPEN note below. The docs: `max` "can improve performance on demanding tasks but may show diminishing returns and is prone to overthinking. Test before adopting broadly." It is **not** a blanket upgrade over `xhigh`.


> **OPEN — `effort: max` on the two domain-content authors is unvalidated. Do not change it; do not defend it either.** Settle it by A/B-ing `high` and `xhigh` against `max` on one real batch and comparing accept rate — not by reasoning from the ladder. Until that batch runs, `max` stays. The same A/B governs whether outline-manager should be promoted.

| Tier | Frontmatter | Members | Use for |
|------|-------------|---------|---------|
| **Opus + `max`** | `model: opus`, `effort: max` | content-writer, assessment-writer | **Correctness-critical domain-content authoring & evaluation that is latency-insensitive** (design / batch / interactive authoring, NOT in a user's request path), where a subtle domain error — a mis-stated rule, a distractor that is also correct — is costly and hard to detect. The agent's job IS the domain reasoning. Do NOT promote request-path graders (grading, product-line grading) to `max`; they are latency-sensitive, keep them at `xhigh`. |
| **Opus + `xhigh`** | `model: opus`, `effort: xhigh` | auth-specialist, subscription-specialist, database-specialist, gcp-infra, mig-specialist, deployment, intelligence-specialist, chat-specialist, product-line-specialist, project-coordinator, assessment-specialist, grading-specialist, doc-analysis-specialist, ai-infrastructure, **code-reviewer** and **test-runner**, **flag-manager** (its deliverable is a prod flag toggle, not a document), **an ad-tracking specialist** (a routing decision in the money/PII band, not copy) | **Decision/diagnosis/verdict deliverables where under-thinking costs more than overthinking.** Money/auth, schema + data integrity, outage-class infra, deploy, and the cross-system AI domains where a wrong root cause sends real work down the wrong path. These are the agents whose output is a *judgement*; request-path graders belong here, not at `max`. |
| **Opus + `high`** *(the default)* | `model: opus`, `effort: high` | everything else: **agent-manager** (added 2026-09-07; deliberately never `xhigh` — it is a bookkeeper against this rubric, and must stay cheap enough to run *while quota is exhausted*), **processor** (the former transcribe-not-author carve-out; states `high` explicitly since 2026-09-23 so it cannot inherit Opus 5.5's `medium`), docs-manager, marketing-specialist, ui-specialist, institutional-specialist, legacy-product-specialist, memory-bank-specialist, planning-specialist, corpus-specialist, automation-architect, every product-domain specialist, n8n-manager, outline-manager, **video-specialist** (added 2026-09-17; its deliverable is a composition and a rendered file — a document, not a decision — and the marketing-specialist review of public on-screen copy does not raise this agent's own effort) | **Long-prose deliverables** — audits, docs, copy, content. **outline-manager is a standing `max` candidate** (it authors domain outlines that ship to users — rule **b**), held pending the A/B above. |
| **Sonnet 5** | `model: sonnet` | 0 | Reserved — speed-critical simple tasks. Rarely applicable. |
| **Haiku 4.5** | `model: haiku` | 0 | Read-only exploration, fast file discovery. |

**The roster follows from THE RULE — derive it from your own agent files; do not quote a count, it rots.**






Flag these as **findings**:
- An agent not on `model: opus` while `mode` reads `preferred` → fix, citing THE RULE (on a `fallback` mode, compare against the manifest's `fallback` column instead)
- Any argument for moving an agent to a weaker model or lower effort that reduces to **cost or capacity** → reject: never downgrade a model or an effort for cost or capacity without a measured quality check. A recorded quota wall is the one exception, and it goes through the manifest's `fallback`, never through `preferred`
- Haiku/Sonnet on any agent making non-trivial judgement → upgrade
- A **version-pinned model ID** in agent frontmatter (`claude-opus-5-5`, `claude-fable-5-1`, …) instead of the `opus`/`fable` alias → replace with the alias
- Any agent missing its explicit `effort:` line → add one. It inherits the launching session, which on Opus 5.5 defaults to `medium`
- `effort: xhigh`/`max` on an agent whose deliverable is a **document** rather than a decision → demote to `high` (no measured gain)
- `effort: high` on an agent whose deliverable is a **decision, diagnosis or gate verdict** in money/auth/schema/infra/deploy/cross-system-AI → promote to `xhigh`
- `effort: max` on a request-path agent → demote to `xhigh` (overthinking risk, no latency budget)
- A correctness-critical **offline** domain-content authoring agent not at `effort: max` → evaluate for promotion (currently the two domain-content authors; outline-manager is the standing candidate)

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
6. **Model IDs current** — `claude-opus-5-5` (`opus` — the default, tiered by effort), `claude-fable-5-1` (`fable` — no agent by preference; the recorded quota fallback only), `claude-sonnet-5`, `claude-haiku-4-5`. Flag any doc still claiming `opus` means Opus 5 or 4.8.

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
- [ ] No deprecated/retired model IDs, and no *version-pinned IDs* where an alias belongs. NOTE: `opus` is the DEFAULT (effort-tiered); `fable` appears only as a recorded quota fallback. Run `agent-model-tier.py status` (ships in the kit) before flagging a live `model:` value — a declared fallback is not drift. `claude-opus-5-5` and `claude-fable-5-1` are both current
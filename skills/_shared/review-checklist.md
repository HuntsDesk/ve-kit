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
- `description` — short: when to delegate + trigger keywords + **at most 2 one-line examples**. Detail belongs in the prompt body. Every agent description loads at session start, and Claude Code warns at startup once descriptions pass 15k tokens combined (code.claude.com/docs/en/sub-agents)
- `model` — explicit (`opus`/`fable`/`sonnet`/`haiku`; `opus` for every agent since 2026-09-23), not missing, and an **alias** rather than a dated ID. Must agree with `.claude/agent-model-tiers.json` (the kit ships `agent-model-tiers.template.json`) — verify with `agent-model-tier.py check`, not by eye

**Check also**:
- `color` present for visual distinction
- `memory: project` for agents that should accumulate insights
- `tools` restriction makes sense for role (read-only agents should restrict)
- `effort` stated explicitly on **every** agent: `medium` by default, `high` for decision/diagnosis/gate-verdict deliverables and offline domain-content authoring, and nothing above `high` without a recorded eval delta. No agent omits it: an omitted line inherits the launching session rather than the level the rubric chose. See Model + effort rubric.

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

### THE EFFORT RULE (rebaselined 2026-10-10)

**Effort ladder:** `low < medium < high < xhigh < max` — all five supported on Opus 5.5 (verified 2026-09-23: `claude --help` on CLI 2.1.281, and the model-config docs' per-model table).

**Read the per-model guidance, not the generic level table.** Anthropic's effort docs describe each level generically, then give per-model recommendations, and the per-model text overrides the generic table (platform.claude.com: `prompting-claude-opus-5-5#calibrate-effort`; `effort#recommended-effort-levels-for-claude-opus-5-5`). For Opus 5.5 it says: the default is `medium`; at `medium` it matches or exceeds Opus 5 at `high` on coding and knowledge work; at a given level it thinks *more* per turn than Opus 5, most of all at `xhigh`/`max`; reserve `xhigh`/`max` for a **measured** gain. Levels tuned for an older model do not carry over to a new one.

- **Every agent states `effort:` explicitly, so no agent FILE inherits.** A teammate spawn still does. See the next bullet. Opus 5.5's *model default is `medium`*, and a top-level `effortLevel` in user settings does not apply to it. An omitted line therefore follows whatever the launching session runs at, not the level this rubric chose for the agent.
- **A named spawn ignores frontmatter `effort:`, so spawn any agent whose effort matters WITHOUT `name:`.** An agent's effort "matters" when its frontmatter effort differs from the calling session's. That covers every `high` agent spawned from a `medium` window, and every `medium` agent spawned from a `high` or `xhigh` window. **Preconditions**, all from the agent-teams docs (code.claude.com/docs/en/agent-teams, fetched 2026-09-29): the rule applies only in an **interactive** session with agent teams enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). A `-p` or Agent SDK session never spawns teammates, and there "a subagent that Claude names runs as an ordinary subagent". A **fork**, or a call that passes `isolation`, is never a teammate either. When the preconditions hold, passing `name:` makes the agent a teammate (`taskKind: in_process_teammate`), and a teammate runs at the LEAD's effort. The docs say "Teammates inherit the lead's effort level", and `effort` is not among the definition parts applied to a teammate. Claude may also name a subagent on its own, so leave `name:` off on purpose. In a `medium` window every named spawn runs at `medium`, the `high` agents included. Spawn it unnamed and address it by its agentId for SendMessage. Verify a runtime effort claim with `echo $CLAUDE_EFFORT` inside the agent, never with `check`: `check` reads disk, and disk stays correct while the spawn runs at the wrong effort.
- **`medium` is the default** — Opus 5.5's own default, which its per-model guidance puts at or above Opus 5 at `high`. It covers every agent whose deliverable is a DOCUMENT: reviews-as-prose, audits, docs, copy, content, product-domain work, bookkeeping.
- **`high` where the deliverable is a DECISION, DIAGNOSIS or GATE VERDICT and under-thinking is the costlier failure.** Money/auth, schema and data integrity, outage-class infra, deploy, the cross-system AI domains where a wrong root cause sends real work down the wrong path, prod flag toggles, orchestration, and the two gates (code-reviewer, test-runner — a verdict is a decision, clause **d**). Also **offline domain-content authoring**, where a subtle domain error ships to users: the domain-content authors. Members are listed in the tier rows below; derive the count from your own agent files with `agent-model-tier.py status` (the kit ships it at its root), never quote one. The test is the SHAPE OF THE OUTPUT, not the importance of the domain — marketing-specialist and institutional-specialist matter enormously and still write *documents*, so they sit at `medium`.
- **Nothing above `high` without a recorded eval delta.** `xhigh` and `max` need an A/B on real tasks showing a gain over `high`, recorded in the manifest's `effort_policy` and here. Reasoning from the ladder is not evidence: the docs call `max` "prone to overthinking", and Opus 5.5 already thinks more per turn at those levels than Opus 5 did.


> **PARKED — the effort A/B (board `<YOUR_EFFORT_AB_TASK_ID>`).** The only route above `high`. For the domain-content authors: run `high` against `xhigh` (and `max`) on one real batch and compare accept rate; the same A/B decides whether any `medium` agent belongs at `high`. Until it runs and records a delta, nothing sits above `high`. Spawn every arm unnamed or run it headless (`-p`). A named arm is a teammate that runs at the lead's effort, so it would measure nothing.

| Tier | Frontmatter | Members | Use for |
|------|-------------|---------|---------|
| **Opus + `xhigh` / `max`** | — | 0 | Only with a recorded eval delta over `high` (PARKED A/B above). Never a request-path agent: no latency budget for the extra thinking. |
| **Opus + `high`** | `model: opus`, `effort: high` | auth-specialist, subscription-specialist, database-specialist, gcp-infra, mig-specialist, deployment, intelligence-specialist, chat-specialist, product-line-specialist, project-coordinator, assessment-specialist, grading-specialist, doc-analysis-specialist, ai-infrastructure, **code-reviewer** and **test-runner** (the gates), **flag-manager** (its deliverable is a prod flag toggle, not a document), **an ad-tracking specialist** (a routing decision in the money/PII band, not copy), **the domain-content authors** (their content ships to users — rule **b**) | **Decision/diagnosis/verdict deliverables where under-thinking costs more than overthinking.** Also **Correctness-critical domain-content authoring & evaluation that is latency-insensitive** (design / batch / interactive authoring, NOT in a user's request path), where a subtle domain error — a mis-stated rule, a distractor that is also correct — is costly and hard to detect. The agent's job IS the domain reasoning. Request-path graders (grading, product-line grading) sit here too, and never go above `high` (no latency budget). |
| **Opus + `medium`** *(the default)* | `model: opus`, `effort: medium` | everything else: **agent-manager** (a bookkeeper against this rubric), **processor** (transcribes findings to the board), docs-manager, marketing-specialist, ui-specialist, institutional-specialist, memory-bank-specialist, planning-specialist, corpus-specialist, automation-architect, every product-domain specialist, n8n-manager, n8n-automator, **video-specialist** (its deliverable is a composition and a rendered file — a document, not a decision) | **Document-shaped deliverables** — audits, docs, copy, content, product-domain work. Opus 5.5's own default. |
| **Sonnet 5.5** | `model: sonnet` | 0 | Reserved — speed-critical simple tasks. Rarely applicable. |
| **Haiku 5.5** | `model: haiku` | 0 | Read-only exploration, fast file discovery. |

**The roster follows from THE RULE — derive it from your own agent files; do not quote a count, it rots.**






Flag these as **findings**:
- An agent not on `model: opus` while `mode` reads `preferred` → fix, citing THE RULE (on a `fallback` mode, compare against the manifest's `fallback` column instead)
- Any argument for moving an agent to a weaker model or lower effort that reduces to **cost or capacity** → reject: never downgrade a model or an effort for cost or capacity without a measured quality check. A recorded model outage is the one exception, and it goes through the manifest's `fallback`, never through `preferred`; an Opus quota wall is not one, because Fable draws from the same weekly. A change grounded in the model's own per-model effort guidance (2026-10-10) is a quality argument, not a cost one
- Haiku/Sonnet on any agent making non-trivial judgement → upgrade
- A **version-pinned model ID** in agent frontmatter (`claude-opus-5-5`, `claude-fable-5-1`, …) instead of the `opus`/`fable` alias → replace with the alias
- Any agent missing its explicit `effort:` line → add one. It inherits the launching session, which on Opus 5.5 defaults to `medium`
- `effort: xhigh`/`max` on any agent without a recorded eval delta → demote to `high`
- `effort: high` on an agent whose deliverable is a **document** and which is not an offline domain-content author → demote to `medium`
- `effort: medium` on an agent whose deliverable is a **decision, diagnosis or gate verdict** in money/auth/schema/infra/deploy/cross-system-AI, or on an offline domain-content author → promote to `high`
- A proposal to raise any agent above `high` → require the recorded A/B delta (arms spawned unnamed or headless); an argument from the ladder or from the domain's importance is not one

---

## Description format (agents)

**Canonical pattern**: `[role]. [what it does]. [when to invoke + triggers].`

**Required structure for agents** — the description is a routing signal, not documentation. The sub-agents docs (code.claude.com/docs/en/sub-agents) say to keep it to when to delegate plus triggers and put detail in the body; every description loads at session start, and Claude Code warns at startup once they pass 15k tokens combined.
```yaml
description: |
  Short role statement. What it does. When to delegate to it.

  Trigger keywords: a, b, c.

  Examples:
  - "[User request]" -> [what the agent does and why it fits, one line].
```

**Flag if**:
- More than 2 examples, or a multi-line `<example>`/`<commentary>` block (legacy shape: convert to one-liners, moving any load-bearing detail into the body)
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
6. **Model IDs current** — `claude-opus-5-5` (`opus` — the default, tiered by effort), `claude-fable-5-1` (`fable` — no agent by preference; the recorded Opus-outage fallback only), Sonnet 5.5 (`sonnet`), Haiku 5.5 (`haiku`) — cite these two by alias. Flag any doc still claiming `opus` means Opus 5 or 4.8, or naming Sonnet 5 / Haiku 4.5 as current.

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
- [ ] Agent prompt doesn't restate CLAUDE.md or unscoped rules: subagents load both (except the built-in Explore/Plan; `omitClaudeMd: true` opts an agent out — then it must be self-contained). Path-scoped rules load only on a matching file, so an agent that depends on one names it (code.claude.com/docs/en/sub-agents)
- [ ] Subagent prompt delegates like a "capable colleague" (brief + trusting)
- [ ] No deprecated Claude Code commands referenced (`/tag`, `/vim`, `/output-style`)
- [ ] No deprecated/retired model IDs, and no *version-pinned IDs* where an alias belongs. NOTE: `opus` is the DEFAULT (effort-tiered); `fable` appears only as a recorded outage fallback (for when the default model is unavailable, never a quota escape). Run `agent-model-tier.py status` (ships in the kit) before flagging a live `model:` value — a declared fallback is not drift. `claude-opus-5-5` and `claude-fable-5-1` are both current
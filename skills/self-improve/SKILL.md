---
name: self-improve
description: Mine recent Vibe Board review findings + worker batch outcomes for RECURRING patterns, then propose preventive guardrails — LESSONS.md rules (applied), agent-definition hardening (proposed), and flagged CLAUDE.md / rules proposals (human approval only). The feedback loop that turns "what reviewers keep catching" into "encoded so it stops happening." Run manually or after every ~5 worker batches.
disable-model-invocation: true
user-invocable: true
---

# Self-Improve — learn from review findings, encode guardrails

This skill closes the agent-fleet feedback loop: it reads what code-reviewers and batch retrospectives have been **catching**, finds the **recurring** root causes, and encodes them as guardrails so the same class of mistake stops recurring.

**Owner**: `project-coordinator` agent (the self-improvement domain + the consumer that runs it). Pairs with `docs-manager` for any agent/skill/rule edits (that's docs-manager's lifecycle domain — this skill *proposes*, docs-manager *applies* the config-layer ones).

## How this differs from the `review-*` family (do NOT duplicate)

| | `review-*` (docs-manager) | `/self-improve` (this skill) |
|---|---|---|
| Question | "Is the config well-formed + current?" | "What keeps going wrong, and how do we prevent it?" |
| Input | The `.claude/` artifacts themselves | Board **review findings** + **batch outcomes** + LESSONS.md |
| Output | Structural fixes (frontmatter, stale refs, model IDs) | New **preventive rules** (LESSONS.md, agent hardening, flagged proposals) |
| Trigger | Model upgrade, quarterly, pre-initiative | After ~5 batches, a finding cluster, or a notable incident |

If a finding is "the config is structurally stale" → that's a `review-*` job; route it there. This skill is for **behavioral** patterns (recurring bugs, repeated reviewer catches, repeated skips).

## When to invoke

- After every ~5 worker batches (the auto-claude worker's CLOSING step may call this on a counter).
- When you notice a **cluster** of related review findings across recent sessions.
- After a notable incident whose root cause would recur without a guardrail.
- Periodically (monthly) as a fleet-health pass.

## The one rule that governs everything here

**A one-off is NOT a rule.** Only encode a guardrail when the pattern recurred across **≥2 distinct batches/sessions/findings**. A single incident gets a shared-memory note (cross-dev) or a board task, not a permanent rule. Over-encoding turns LESSONS.md + agent prompts into noise that gets skimmed and ignored. Be ruthless: the bar is "recurring root cause," not "something went wrong once."

---

## Step 1 — Create the run parent

On the current board project (default: Agent Infrastructure `<YOUR_PROJECT_ID>`), create a parent task:

```
[self-improve] Pattern analysis <date>
  status: in_progress, priority: medium
  description: Mined review findings + batch outcomes over <window>; proposing guardrails.
```

Capture the parent ID for all proposals to reference.

## Step 2 — Gather inputs (don't analyze yet)

1. **Review findings** — query the board activity log for review output over the window (last ~5 batches or ~14 days):
   - `board_get_activity` filtered to `action: "commented"` by `code-reviewer` / `test-runner` / review-mode agents.
   - Tasks created from reviews (critical/high subtasks under review parents). Look for the severity-tier parents the `/review` + `processor` flow creates.
2. **Worker batch outcomes**:
   - Skipped tasks: `board_get_tasks` filtered for `metadata.skipped_by_worker: true` (or the NocoDB skipped view if built — `<YOUR_VIEW_ID>`). A task class that's *repeatedly* skipped is a signal (missing capability, unclear spec, or a guard that's too aggressive).
   - Batch handoff notes (`board_get_handoff` / recent `session_ended` activity) — reviewer findings + "issues found during reviews" + deviations flagged.
3. **Existing guardrails (to DEDUPE against)**:
   - `docker/ve-worker/LESSONS.md` — every section. Don't re-propose an existing rule.
   - `board_search_shared_memories(recency_days=30)` — a pattern may already be a cross-dev memory.
   - `.claude/rules/*.md` — a pattern may already be a rule (then the issue is *enforcement*, not a missing rule).

## Step 3 — Cluster + identify patterns

Group the gathered findings by root cause, not by symptom. For each candidate pattern, record:
- **Evidence**: the ≥2 distinct findings/batches it appeared in (cite task IDs / commit SHAs / file:line). If you can only find 1, it's NOT a pattern — drop it (or note as a watch-item).
- **Root cause**: the underlying thing, not the surface bug. ("Reviewer caught N missing savepoints" → root cause = "psycopg3 fallible-SQL pattern not internalized," which is *already* LESSONS rule #1 → so the issue is enforcement/visibility, not a new rule.)
- **Which layer should own the guardrail** (see Step 4 tiers).
- **Whether it's already covered** (LESSONS / rule / memory). If covered-but-recurring → the proposal is about *enforcement* (e.g., a pre-commit check, a louder prompt line), not a duplicate rule.

## Step 4 — Propose guardrails (3 tiers by blast radius)

### Tier A — LESSONS.md rules (APPLY directly)
The worker's own institutional-memory file. Low blast radius (only the autonomous worker reads it), so this skill MAY apply Tier-A directly:
- Append to the correct existing section (`Safety Rules` / `Quality Patterns` / `Content/Domain Rules` / `Cross-Service Breakage Prevention` / `Definition of Done`). Match the terse, imperative style.
- Cite the evidence inline ("caught in batches X, Y").
- One commit: `chore(self-improve): append N lessons from <window> review-pattern analysis`.
- DEDUPE first — if a near-identical rule exists, strengthen the wording instead of adding a duplicate.

### Tier B — Agent-definition hardening (PROPOSE; apply only if trivial+unambiguous)
When a recurring finding maps to a specialist's domain, OR a worker batch changed code that makes an agent definition stale (the agent-staleness sub-mode — see below):
- File a board task assigned to `docs-manager` (skill/agent lifecycle owner) describing the exact edit: which agent, which section, what to add/correct, the evidence.
- If the edit is trivial + unambiguous (e.g., a one-line "always check X" in a specialist's checklist that exactly mirrors a confirmed recurring miss), you may apply it directly + note it for docs-manager review. When in doubt, propose.

### Tier C — CLAUDE.md / `.claude/rules/*.md` (PROPOSE ONLY — never auto-apply)
Core instructions are too consequential to auto-modify (this is a hard rule — see `<YOUR_TASK_ID>` item 5 + the documentation rule):
- File a board task (priority by severity) with the exact proposed change + evidence + rationale, assigned to `docs-manager`, flagged **needs founder/owner approval**.
- NEVER edit CLAUDE.md or a rule file directly from this skill.

## Step 5 — Agent-staleness sub-mode (subsumes `<YOUR_TASK_ID>` item 2)

Independently of review findings: if the analysis window includes batches that changed code in a specialist's domain, check whether that agent's definition now references an outdated pattern (a renamed table/column, a deprecated path, a changed convention). For each stale reference found → Tier B proposal. This catches drift that no reviewer flagged because the agent file wasn't in the diff.

## Step 6 — Report

Post to the run parent:
- **Patterns found** (with evidence) vs **watch-items** (single occurrences, not yet rules).
- **Applied**: Tier-A LESSONS.md diff (commit SHA) + any trivial Tier-B edits.
- **Proposed**: Tier-B / Tier-C board task IDs (with approval flags).
- **Already-covered-but-recurring**: enforcement gaps (e.g., "rule exists but no CI check") — these are often the highest-value findings.

Return a lean summary to the main agent (don't dump the full analysis). If nothing recurred (a healthy window with only one-offs), say so — "no new patterns; N watch-items logged" is a valid, good outcome. Do NOT manufacture rules to look productive.

## Anti-patterns (things this skill must NOT do)

- Encode one-offs as permanent rules (the cardinal sin — see Step 2's governing rule).
- Auto-modify CLAUDE.md or `.claude/rules/*.md` (Tier C is propose-only).
- Duplicate an existing LESSONS rule / shared-memory / rule instead of strengthening it.
- Re-do a `review-*` structural audit (route stale-config findings there).
- Run on a window with no review data and invent patterns from nothing.

## Relationship to the broader self-improvement system

- **LESSONS.md loop** (`<YOUR_TASK_ID>` Phase 1, DONE): the worker reads LESSONS.md at startup + appends single-batch lessons at close. This skill is the **cross-batch** layer — it finds patterns spanning *multiple* batches that no single batch would notice, and it can harden the config layers a worker won't touch.
- **`review-*` family** (docs-manager): structural config hygiene — complementary, not overlapping.
- **Shared memory** (`board_save_shared_memory`): real-time cross-dev facts — a watch-item (single occurrence) often belongs here rather than as a rule.
- **Cadence automation** (`<YOUR_TASK_ID>`, future): wire a batch-counter so the worker invokes this every 5 batches, and/or a scheduled monthly run. Tier-C auto-proposal-with-approval is the aspirational Phase 3 — already structurally supported here (Tier C files approval-flagged tasks).

---
name: review-all
description: Orchestrator that runs the full review-* family (agents, skills, rules, docs, memory) and aggregates findings under a single board parent task. Produces a prioritized remediation roadmap. Use for full system audits.
disable-model-invocation: true
user-invocable: true
---

# Full Review Orchestrator

Runs the complete `review-*` family in sequence and aggregates findings. Use for comprehensive system audits (e.g., post-model-upgrade, quarterly health check, pre-major-initiative sanity check).

Child skills:
1. `/review-agents` — `.claude/agents/*.md`
2. `/review-skills` — `.claude/skills/*/SKILL.md`
3. `/review-rules` — `CLAUDE.md` + `.claude/rules/*.md`
4. `/review-docs` — `docs/**/*.md`
5. `/review-memory` — `~/.claude/projects/<slug>/memory/*.md`
6. `/review-board` — Vibe Board state (Firestore via `mcp__agent-board__*`)
7. `/review-security` — `.claude/` configuration security posture

Cites [../_shared/review-checklist.md](../_shared/review-checklist.md) and [../_shared/anthropic-configuration-guide.md](../_shared/anthropic-configuration-guide.md).

**Owner**: `docs-manager` agent.

## When to invoke

- After a Claude model upgrade (e.g., Opus 4.6 → 4.7)
- After major infrastructure migrations (e.g., Supabase → MIG)
- Quarterly (every ~3 months)
- Before a major initiative where the `.claude/` config needs to be trusted

## Output contract

A single aggregate report posted to the board + a lean summary to the main agent.

---

## Step 1 — Create audit parent

On the current board project (or create a new "System Audit YYYY-MM-DD" project), create a parent task:

```
[review-all] System Audit <date>
  status: in_progress
  priority: high
  description: Orchestrated run of review-agents, review-skills, review-rules, review-docs, review-memory.
```

Capture the parent task ID for all child skills to reference.

## Step 2 — Run child skills in sequence

Run in this order (sequential — rules first so deprecated-reference findings surface once centrally, not N times across child reviews):

1. `/review-rules` — core instructions are the foundation
2. `/review-agents` — agents are the most consequential artifacts
3. `/review-skills` — skills reference agents and rules
4. `/review-docs` — docs may reference agents, skills, rules
5. `/review-memory` — memory may reference anything
6. `/review-board` — Vibe Board hygiene, independent of config layer
7. `/review-security` — runs last so it sees all flagged references and can cross-check for secrets in files flagged for other reasons

For each child, pass the parent task ID so subtasks roll up under it.

## Step 3 — Aggregate findings

After all child skills finish, query the board for subtasks rolling up to the audit parent. Group by:
- Severity (critical / high / medium / low)
- Domain (agents / skills / rules / docs / memory)
- Theme (model tier, staleness, frontmatter, cross-reference, duplication, gap)

## Step 4 — Cross-cutting findings

Look for patterns that only emerge when viewing all findings together:
- Model rubric drift across multiple agents (most are on Opus; should audit globally)
- Deprecated-reference cluster (same retired service mentioned in multiple places)
- Rule-hook misalignment that shows up in both rules and agent behavior
- Naming inconsistencies across agents/skills (e.g., `nextgen-*` vs `next-gen-*`)
- Documentation index drift showing up in `review-docs`, but the underlying cause is missed updates during agent rewrites

Promote cross-cutting patterns to **critical** priority even if individual findings were lower severity.

## Step 5 — Remediation roadmap

Under the audit parent, create ordered child tasks representing the suggested fix order. Priority:

1. **Critical** — broken behavior, security, production risk
2. **High** — wrong model tier on critical-path agents, stale references that cause wrong behavior
3. **Cross-cutting patterns** elevated here
4. **Medium** — clarity, redundancy, style
5. **Low** — polish

Include blast-radius annotation: how many other artifacts reference this one?

## Step 6 — Summary

Return to main agent (≤ 150 words):

```
SYSTEM AUDIT COMPLETE — <date>

Scope:
- [N_a] agents, [N_s] skills, [N_r] rules, [N_d] docs, [N_m] memory files reviewed

Findings (total: [T]):
- Critical: [C]
- High: [H]
- Medium: [M]
- Low: [L]

Cross-cutting themes:
- [theme 1]: [count]
- [theme 2]: [count]

Model rubric drift: [X] agents flagged for reassignment
Deprecated references: [Y] occurrences across [Z] files

Board parent task: <id>
Next recommended action: [specific first fix]
```

## Anti-patterns for the orchestrator itself

- Do NOT dump all child-skill findings into the conversation (they live on the board)
- Do NOT run children in parallel — some depend on others' outputs
- Do NOT skip creating the aggregate parent — individual child findings without a roll-up are lost
- Do NOT elevate every finding to critical — discipline the tiers

## Tools used

- Skill tool (to invoke each child skill)
- Board MCP (create_task, update_task, log_activity, get_tasks)
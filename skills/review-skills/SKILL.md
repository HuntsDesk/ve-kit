---
name: review-skills
description: Review all skill definitions in .claude/skills/ for frontmatter correctness, progressive-disclosure hygiene, trigger clarity, merge/split candidates, and gap analysis. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Skill Review Protocol

Comprehensive review of every `.claude/skills/*/SKILL.md` file. Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md) and [../_shared/anthropic-configuration-guide.md](../_shared/anthropic-configuration-guide.md).

**Owner**: `docs-manager` agent.

## When to invoke

- After adding multiple new skills in quick succession
- Quarterly audit
- After Claude Code version bumps that change skill frontmatter capabilities
- When the `/` autocomplete menu gets cluttered or confusing

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Inventory

List every `.claude/skills/*/SKILL.md` file (excluding `_shared/`). For each:
- Parse frontmatter: `name`, `description`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `paths`, `model`, `effort`, `context`, `agent`
- Count body lines
- List supporting files in the skill directory
- Extract referenced files / commands / agents from the body

## Step 2 — Frontmatter validation

For each skill, check against `review-checklist.md` §"Skills":

| Issue | Severity |
|-------|----------|
| `name` mismatches directory | critical |
| `description` missing | high |
| `description` generic or vague | medium |
| `disable-model-invocation` / `user-invocable` combination nonsensical | high |
| `allowed-tools` uses tool names that don't exist | high |
| `paths` glob invalid syntax | high |
| Uses invented frontmatter keys | high |
| `description` + `when_to_use` combined > 1,536 chars | high |

## Step 3 — Invocation semantics

For each skill, decide whether the flag combination matches intent:

| Pattern | Intent | Flag combo |
|---------|--------|-----------|
| User-triggered command with side effects | `/commit`, `/deploy` | `disable-model-invocation: true`, `user-invocable: true` |
| Reference knowledge Claude applies | `/common-tasks`, `/troubleshooting` | (defaults) |
| Background knowledge, not user-invocable | Internal guides | `user-invocable: false` |
| Workflow Claude runs, user may also invoke | `/plan`, `/review` | `user-invocable: true`, model-invocable |

Flag mismatches.

## Step 4 — Progressive disclosure check

For each skill:
- Measure SKILL.md line count
- Identify supporting files in the same directory
- Flag SKILL.md > 300 lines as a candidate for progressive-disclose (split reference material to sibling files, link from SKILL.md)
- Flag SKILL.md > 500 lines as **required** to split (hard limit per Anthropic guidance)

## Step 5 — Trigger clarity

For each skill:
- Does the `description` tell the user when to reach for this vs. a similar skill?
- Are there obvious naming collisions (e.g., two skills with "review" in the trigger)?
- Does the skill's intent match its `name` (don't hide `/commit` under a name like `persist`)?

Flag ambiguous triggers.

## Step 6 — Redundancy / overlap

Across the roster, look for:
- Skills with overlapping scope (e.g., `review` + `review-pr`)
- Skills that do the same thing with different flags
- Skills that could be merged into a single parameterized skill

## Step 7 — Content freshness

For each skill:
1. Glob every file path mentioned in the body — flag missing
2. Grep for any referenced command (`Enter C -push`, `/plan`) — confirm still valid
3. Check for deprecated Claude Code commands (`/tag`, `/vim`, `/output-style`)
4. Check for references to retired infrastructure (Supabase Edge Functions, old MIG templates)
5. Verify any shell command examples actually work (spot-check 2-3 per skill)

## Step 8 — Gap analysis

Look for recurring manual operations that should be skills:
- Commands you run frequently (>5x/month) without a skill
- Multi-step workflows the user types out by hand
- Troubleshooting recipes not yet codified
- Repeated delegation patterns that could be a `/review-*`-style skill

Flag as "Create skill for [pattern]".

## Step 9 — Orchestrator coverage

Check that orchestrator skills like `/review` and `/review-all` reference all relevant sub-skills. If a new review-* skill was added, verify `/review-all` picks it up.

## Step 10 — File findings to the board

Create parent tasks per severity + subtasks per finding on project `<YOUR_AUDIT_PROJECT_ID>` (or current). Assigned agent: `docs-manager` for most; `code-reviewer` for skills with structural issues.

## Step 11 — Summary

Return ≤ 100 words:

```
SKILL REVIEW COMPLETE
- [N] skills reviewed (excluding _shared)
- [C/H/M/L] findings per severity → board parent tasks
- [G] gap candidates
- [MS] merge/split recommendations
```

## Anti-patterns to flag

- SKILL.md > 500 lines (must progressive-disclose)
- `disable-model-invocation: true` + `user-invocable: false` (unreachable)
- `description` that just restates the `name`
- Skills with identical trigger keywords
- Shell commands that reference retired services
- `allowed-tools` that includes `*` (grant specific tools)

## Tools used

- Read, Glob, Grep
- Board MCP (create_task, update_task, log_activity)
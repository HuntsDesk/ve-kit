---
name: review-rules
description: Review the core instruction layer — CLAUDE.md, .claude/rules/*.md, and RIPER/CAT mode definitions — for size, staleness, cross-reference integrity, alignment with active hooks, and redundancy. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Rules & Core Instructions Review Protocol

Reviews the always-loaded instruction layer that governs every Claude Code session in this repo. Scope:
- `CLAUDE.md` (project root)
- `.claude/rules/*.md`
- `.claude/settings.json` hooks config (only to verify rule-hook alignment)

Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md) and [../_shared/anthropic-configuration-guide.md](../_shared/anthropic-configuration-guide.md).

**Owner**: `docs-manager` agent.

## When to invoke

- CLAUDE.md approaching 150 lines (lean limit) or > 200 lines
- After significant process changes (new hooks, new RIPER modes, new deployment patterns)
- Quarterly audit
- When new team members or agents repeatedly make mistakes the rules should prevent

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Inventory

- Read `CLAUDE.md`. Record line count, section list, referenced rules/skills/docs/agents.
- Read every `.claude/rules/*.md`. Record line count, topic, referenced files.
- Read `.claude/settings.json` hooks block. Record which hooks exist and what they enforce.

## Step 2 — Size discipline

| Artifact | Target | Hard limit |
|----------|--------|------------|
| CLAUDE.md | < 150 lines | 200 lines |
| Individual rule | < 200 lines | 300 lines |

Flag bloat. Recommend:
- CLAUDE.md bloat → push detail into a new rule or existing rule
- Rule bloat → split by sub-topic or move deep reference to a skill / doc

## Step 3 — Staleness

For each rule and for CLAUDE.md, check:
- Deprecated infrastructure references (Supabase Edge Functions, old table names, retired services)
- Domain names and URLs still current (<your-domain> variants, MIG host IDs, LB IP `<YOUR_LB_IP>`)
- Model IDs match current Anthropic lineup (Opus 4.7, Sonnet 4.6, Haiku 4.5)
- Command references valid (`Enter C -push-dev`, `Enter C -push`, `Enter C -all`)
- Stripe API version current (`2025-08-27.basil` per CLAUDE.md)
- Referenced docs exist (every `[link](path)` resolves)
- Referenced agents exist in `.claude/agents/`
- Referenced skills exist in `.claude/skills/`

## Step 4 — Cross-reference integrity

- Every `[text](relative/path.md)` in CLAUDE.md and rules → file exists (Glob)
- Every rule file → referenced from CLAUDE.md at least once (orphans are dead weight)
- Every rule topic → has an invocation pattern documented

## Step 5 — Rule-hook alignment

Match the written rules against the behavior enforced by `.claude/settings.json`:
- Does `agent-board.md` describe hooks that actually exist?
- Does `riper-cat.md` describe auto-transitions that the Stop hook actually enforces?
- Does CLAUDE.md reference hooks that are live?
- Are there hooks in settings.json that no rule explains to humans?

Flag misalignments.

## Step 6 — RIPER-CAT accuracy

Specifically for `riper-cat.md`:
- All 8 modes (R/I/P/E/RE/C/AI/T) described and mapped to the Enter signal
- Auto-transitions described match `/plan` and `/review` skill behavior
- COMMIT flags (`-commit`, `-push`, `-push-dev`, `-all`, `-return`) match `rules/deployment.md`
- Agent assignment rules cross-check with `/plan` skill + `.claude/agents/` roster

## Step 7 — Redundancy

For the ruleset as a whole:
- Content duplicated across rules (flag for consolidation)
- Content duplicated between CLAUDE.md and a rule (rule wins — pull from CLAUDE.md)
- Two rules that should be merged (near-duplicate scope)
- One rule that should be split (two unrelated topics joined)

## Step 8 — Missing rules

Scan recent memory (MEMORY.md), recent commits, and recent incident logs for recurring patterns not yet codified as rules. Candidates:
- Ops patterns that caused repeat incidents
- Coding rules recently learned the hard way
- Deployment patterns not yet documented

Flag as "Codify pattern [X] as a rule".

## Step 9 — File findings to the board

Create parent tasks per severity + subtasks on project `<YOUR_AUDIT_PROJECT_ID>`. Assigned agent: `docs-manager`.

## Step 10 — Summary

Return ≤ 100 words:

```
RULES REVIEW COMPLETE
- CLAUDE.md: [N] lines (target <150)
- [X] rule files reviewed
- [C/H/M/L] findings per severity → board parent tasks
- [MR] missing-rule candidates
- [RA] redundancy/alignment issues
```

## Anti-patterns to flag

- CLAUDE.md growing past 200 lines (must reduce)
- Rules that contradict each other
- Rule behavior described in CLAUDE.md but not enforced by hooks (drift risk)
- Dead links in CLAUDE.md or rules
- References to retired model IDs or deprecated commands
- Rules that have never been referenced (orphans)

## Tools used

- Read, Glob, Grep
- Optionally: read `.claude/settings.json` to verify hook alignment
- Board MCP (create_task, update_task, log_activity)
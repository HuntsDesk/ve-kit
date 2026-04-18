---
name: review-agents
description: Review all specialist agent definitions in .claude/agents/ for accuracy, currency, and Anthropic best-practice compliance. Flags stale references, wrong model assignments, missing examples, merge/split candidates, and gap-analysis coverage. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Agent Review Protocol

Comprehensive review of every `.claude/agents/*.md` file. Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md) and [../_shared/anthropic-configuration-guide.md](../_shared/anthropic-configuration-guide.md).

**Owner**: `docs-manager` agent.

## When to invoke

- Periodic audit (quarterly or after major infrastructure changes)
- After model upgrades (e.g., Opus 4.6 → 4.7)
- When new services, features, or domains land without a specialist
- Before a big delegation-heavy initiative where agent accuracy matters

## Output contract

This skill produces **only board tasks**. It does not write findings into the conversation. Main-agent output = a lean summary pointing to the Vibe Board parent task.

---

## Step 1 — Inventory

Read every file matching `.claude/agents/*.md`. Extract:
- `name`, `description`, `model`, `color`, `memory`, `tools` (if present)
- Trigger keywords from description
- File/path references (via regex for `.md`, `src/`, `services/`, `docs/`)
- Service references (cross-check with `services/` directory)
- Table references (cross-check with Postgres schema)
- Code snippets (language fence blocks)
- `<example>` block count

Record in a structured list. Don't dump it to the user.

## Step 2 — Frontmatter validation

Apply the schema from `review-checklist.md` §"Agents". For each agent, flag:

| Issue | Severity |
|-------|----------|
| Missing `name` or mismatched with filename | critical |
| Missing `description` | critical |
| Missing `model` (defaulting to `inherit` without justification) | high |
| `description` uses undocumented frontmatter conventions | medium |
| No `<example>` blocks or only 1 | medium |
| No `<commentary>` in examples | low |
| `description` + `when_to_use` combined > 1,536 chars | high |
| Uses invented (non-Anthropic) keys | high |

## Step 3 — Description quality

Check each `description` against the canonical pattern:
`[role]. [what it does]. [when to invoke + triggers].`

Flag:
- Generic phrasing ("helps with database stuff")
- No trigger keywords
- Vague "when to use" that doesn't distinguish from peer agents
- Missing examples showing delegation pattern

## Step 4 — Model assignment review

For each agent, check the model tier against the rubric in `review-checklist.md` §"Model assignment".

**Priority**: flag Opus assignments on routine-content work first (highest cost savings). Flag Sonnet or Haiku on critical-review work second (highest correctness risk).

Known high-value reassignment candidates (verify during review):
- Routine-content specialists currently on Opus → likely Sonnet
- Orchestrators currently on Sonnet or below → likely Opus
- `inherit` on any critical-path agent → pin explicitly

User is on max Claude plan — bias upward on ambiguous cases.

## Step 5 — Content freshness

For each agent, verify:

1. **Referenced file paths** — Glob every path mentioned in the body; flag missing.
2. **Code examples** — Grep for the pattern in the current codebase; flag dead references.
3. **Service references** — cross-check `services/` directory; flag retired services (e.g., Supabase Edge Functions — archived 2026-02-24).
4. **Table references** — cross-check with current Postgres schema via pg MCP or SSH psql.
5. **Domain/URL references** — Confirm `ai.<your-domain>`, `<your-domain>`, etc. still current.
6. **Command references** — Confirm `Enter C -push`, `/plan`, `/review` etc. still work.

## Step 6 — Merge / split analysis

For the roster as a whole:

**Merge candidates** — pairs of agents where:
- Description overlap > 80% semantic similarity
- Trigger keywords overlap > 50%
- Same domain boundary

**Split candidates** — single agents where:
- Description uses "and" to join unrelated domains
- Trigger keywords cluster into 2+ disjoint groups
- Prompt body spans multiple distinct concerns

For each recommendation, include rationale and proposed new structure.

## Step 7 — Gap analysis

Find new ground without a specialist:

1. List services in `services/` — does each have a specialist (directly or under a broader agent)?
2. List top-level directories in `src/features/` — does each map to a specialist?
3. List Cloud Run services — covered?
4. List MIG services — covered?
5. List newly added systems in recent CLAUDE.md commits — covered?

Flag gaps as "Create new agent for [feature/service]".

## Step 8 — README consistency

Check `.claude/agents/README.md`:
- Agent count matches actual file count (excluding archived)
- Every agent in the roster has a row in the appropriate tier table
- Trigger keywords in README match the agent's description
- Archived agents section accurate

## Step 9 — File findings to the board

**MANDATORY**: every finding becomes a board task. Nothing lives only in conversation.

1. Create **parent tasks** per severity tier on the current project (or `Opus 4.7 System Audit/Review` project, id `<YOUR_AUDIT_PROJECT_ID>`):
   - `[review-agents] Critical findings`
   - `[review-agents] High findings`
   - `[review-agents] Medium findings`
   - `[review-agents] Low findings`
2. For each finding, create a **subtask** under the matching parent with:
   - `title`: `[agent-name]: [short issue]`
   - `description`: file path + specific issue + recommended fix
   - `assigned_agent`: typically `docs-manager` (it owns agent files)
   - `priority`: matches severity tier
3. Log the summary via `board_log_activity` on the parent tasks.

## Step 10 — Summary

Return to the main agent (keep ≤ 100 words):

```
AGENT REVIEW COMPLETE
- [N] agents reviewed (excluding [X] archived)
- [C] critical findings → board parent <id>
- [H] high findings → board parent <id>
- [M] medium findings → board parent <id>
- [L] low findings → board parent <id>
- [G] gap candidates → board <id>
- [MS] merge/split recommendations → board <id>

All findings in Vibe Board project [project_id]. Review checklist: ../_shared/review-checklist.md.
```

## Anti-patterns to flag proactively

- Agent descriptions that start with "Use this agent when..." without concrete trigger keywords
- Model field missing or implicit `inherit` on a critical-path agent
- Code examples that reference dead or renamed services
- Two agents with near-identical trigger keyword sets
- Agent prompt body > 1500 words
- Missing `<example>` blocks in description
- References to deprecated Claude Code commands (`/tag`, `/vim`, `/output-style`)
- References to removed infrastructure (Supabase Edge Functions, old MIG versions)

## Tools used

- Read — agent file contents
- Glob — file/path existence
- Grep — code pattern freshness
- Bash (restricted) — `ls` on service directories, psql via SSH for schema checks
- Board MCP — `board_create_task`, `board_update_task`, `board_log_activity`
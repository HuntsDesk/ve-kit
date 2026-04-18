---
name: review-board
description: Review the Vibe Board (Firebase Firestore) for stale tasks, orphans, duplicates, done-but-unmarked work, abandoned projects, session handoff quality, and referential integrity. Creates remediation board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Vibe Board Review Protocol

Audits the Vibe Board state itself — the meta layer where all other work is tracked. Uses `mcp__agent-board__*` tools to query live Firestore data.

Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md).

**Owner**: `docs-manager` agent (once registered) or `general-purpose` fallback.

## When to invoke

- Board feels cluttered or noisy in the UI
- Tasks piling up with unclear ownership
- Multiple "stale session" banners in a row
- Before a major initiative (clean board = clear signal)
- Quarterly hygiene pass

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Inventory

Query the board for state across all active projects:

- `board_get_projects(status: "active")` — every active project
- For each project: `board_get_tasks(project_id, include_done: false)` — current open tasks
- Collect: task count per status, per priority, per assigned_agent, per project

## Step 2 — Stale in-progress tasks

Flag tasks where:
- `status = in_progress` AND `started_at` > 7 days ago
- `status = in_progress` AND last activity log entry > 3 days ago
- `status = in_progress` AND session that claimed them ended without marking done

**Severity**:
- critical → production-blocking tasks stale > 7 days
- high → any task stale > 14 days
- medium → stale 7-14 days with recent activity
- low → stale < 7 days, low-priority

Fix recommendation: either `status: done` with completion comment, `status: blocked` with reason, or `status: todo` to surrender ownership.

## Step 3 — Orphaned tasks (no assigned_agent)

Flag tasks where `assigned_agent` is null or empty.

**Per agent-board.md rule**: every task MUST have an `assigned_agent` set during PLAN. Orphans indicate process drift.

Severity: medium (or high if `priority: critical`).

## Step 4 — Duplicate detection

For each project, compare task titles pairwise:
- Exact title match (usually a mistake from session drift)
- >80% semantic similarity (e.g., "Fix login bug" + "Repair auth sign-in issue")
- Same file referenced in description across 2+ open tasks

Recommend merge (keep the older, close the newer with a comment linking).

## Step 5 — Done-but-not-marked

Cross-reference activity log with task status:
- Task with activity entries describing completion but status still `todo` / `in_progress`
- Task referenced in recent commit (via commit hash in activity) but status not `done`
- Subtasks all done but parent still `in_progress`

Fix: update status, optionally add a short completion comment.

## Step 6 — Abandoned projects

Flag projects where:
- No session started in > 30 days
- All tasks done but project status still `active` (should be `completed` or `archived`)
- 0 tasks, 0 recent activity (project created and never used)

Recommend archive via `board_update_project(status: "archived")` (if tool supports) or documented abandonment comment.

## Step 7 — Session handoff quality

For recent sessions (last 20 per project):
- `handoff_notes` null or < 20 words → low-quality handoff
- `progress_summary` missing → handoff failed
- `context_artifacts` empty when session had commits / file modifications → incomplete
- Sessions marked `abandoned` with no reason → process smell

**Per agent-board.md**: "A session without handoff notes is a session whose context is lost forever."

## Step 8 — Task description clarity

Flag tasks where:
- `description` < 20 words
- `description` missing file path / function name / concrete reference
- Title is vague ("Fix the thing", "Update stuff")
- No recommended fix if task is a finding from an audit

## Step 9 — Referential integrity

Cross-check:
- `depends_on` arrays reference task IDs that exist
- `parent_task_id` references existing parent
- Parent tasks aren't themselves children (no cycles)
- Subtasks under a done parent — should subtasks also be closed?

Broken references are usually from task deletions that didn't cascade. Flag and recommend fix.

## Step 10 — Priority drift

Flag:
- `critical` tasks with `status: todo` and no activity for > 3 days
- `high` priority tasks older than any `critical` task (inverted queue)
- All tasks in a project at `medium` (priority tier not discriminated)
- `critical` tasks outnumbering `high` (critical inflation)

## Step 11 — File findings to the board

Create parent tasks per severity on the current audit project (or active project):
- `[review-board] Critical findings`
- `[review-board] High findings`
- etc.

For each finding, create a subtask with:
- Task ID reference (not just title) so the fix can be applied directly
- Severity-matched `priority`
- `assigned_agent`: typically `general-purpose` (board ops don't have a dedicated specialist)
- `parent_task_id` pointing to the severity parent

## Step 12 — Summary

Return ≤ 100 words:

```
BOARD REVIEW COMPLETE
- [P] active projects
- [T] open tasks across all projects
- Stale in-progress: [S]
- Orphans: [O]
- Duplicates: [D]
- Done-but-unmarked: [DU]
- Abandoned projects: [A]
- Handoff issues: [H]
- Referential integrity issues: [R]

Critical: [C] | High: [H] | Medium: [M] | Low: [L]
Board parent: <id>
```

## Anti-patterns to flag

- Sessions ending without `board_end_session` (abandoned)
- Tasks with `priority: critical` for > 7 days untouched
- Projects acting as junk drawers (>100 tasks with no structure)
- Tasks mentioning "I'll do X" without making a subtask (per agent-board rule: nothing exists unless it's on the board)
- Hundreds of `done` tasks visible in default queries (always filter `include_done: false`)
- Activity logs showing same debate repeated across multiple sessions (issue not captured as a task)

## Tools used

- `mcp__agent-board__board_get_projects`
- `mcp__agent-board__board_get_tasks`
- `mcp__agent-board__board_create_task`, `board_update_task`, `board_log_activity`
- `mcp__agent-board__board_get_handoff` (for session quality checks)
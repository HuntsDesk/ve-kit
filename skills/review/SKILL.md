---
name: review
description: Use when entering REVIEW mode or when the user says "Enter RE". Validates plans or implementations by invoking specialist sub-agents based on what changed. Detects whether this is a post-plan review or post-execute review automatically.
user-invocable: true
---

# REVIEW Mode Protocol

You are entering REVIEW mode. Determine which type of review is needed and follow the appropriate protocol.

## Detect Review Context

Check `board_get_tasks` for the active project:
- If tasks exist with `status: 'todo'` and `riper_mode: 'plan'` → **Post-PLAN Review**
- If tasks exist with `status: 'done'` and `riper_mode: 'execute'` → **Post-EXECUTE Review**
- If git diff shows uncommitted changes → **Post-EXECUTE Review**
- If unclear, ask the user: "Is this a plan review or an implementation review?"

---

## Post-PLAN Review

Validate the plan is complete and correct before execution begins.

### Checklist

1. **Query board tasks**: `board_get_tasks(project_id, status='todo')`
2. **For each task, verify**:
   - [ ] Has an `assigned_agent` set (FAIL if missing)
   - [ ] The assigned agent matches the task type (see `/plan` skill mapping)
   - [ ] Dependencies are correct — no circular deps, no missing prerequisites
   - [ ] Priority makes sense — blocking tasks are `critical` or `high`
   - [ ] Description has enough context for the agent to execute standalone
   - [ ] Description includes **acceptance criteria** (FAIL if missing — "build X" without "with Y behavior, Z config" is insufficient)
   - [ ] Acceptance criteria include any user-specified requirements (schedule, trigger method, notification rules, etc.)
3. **Check for gaps**:
   - [ ] Are there missing tasks? (e.g., plan mentions 5 steps but only 4 tasks exist)
   - [ ] Is there a `test-runner` task? (there should be one for integration testing)
   - [ ] Is there a `code-reviewer` task for post-implementation review?
4. **Fix issues**:
   - Missing agent → `board_update_task` to set `assigned_agent`
   - Wrong agent → `board_update_task` to correct it
   - Missing task → `board_create_task` to add it
   - Wrong dependency → `board_update_task` to fix `depends_on`

### Verdict

- **PASS**: All tasks have correct assignments, dependencies are valid, no gaps. Ready for EXECUTE.
- **NEEDS REVISION**: List specific issues. Do NOT proceed to EXECUTE until resolved.

---

## Post-EXECUTE Review

Validate the implementation by invoking specialist sub-agents AND verifying requirements compliance.

### Step 0: Requirements Traceability Check (MANDATORY — do this FIRST)

Before checking if the code works, check if it matches the plan:

1. **Pull the original plan**: Read the plan file (if one exists in `.claude/plans/`) or `board_get_tasks` with the project's planned tasks
2. **For each plan spec point, verify**:
   - [ ] The implementation matches the acceptance criteria on the board task (not just "it runs")
   - [ ] No spec points were silently dropped or changed
   - [ ] If the implementation deviates from the plan, it is flagged as a **PLAN DEVIATION** with explicit justification
3. **Flag deviations explicitly**:
   - If an agent built something different from the plan (e.g., polling instead of webhook, different schedule), mark it as `DEVIATION: [what was planned] → [what was built] — [reason]`
   - Deviations are not automatically failures — but they MUST be called out, never silently accepted
4. **Check acceptance criteria**:
   - Every board task should have acceptance criteria (added during PLAN). If missing, flag as a plan quality issue.
   - Compare the actual implementation against each acceptance criterion, not just "does it error?"

**If deviations are found**: Log each as a `board_log_activity` with `action: "deviation_flagged"` and ask the user whether to accept the deviation or revert to the original spec.

### Step 1: Determine What Changed

Check what was modified during EXECUTE:
- Run `git diff --stat` to see changed files
- Check `board_get_tasks` for tasks marked `done` in this session
- Categorize changes: code, UI, DB, Python services, config, docs

### Step 1.6: ast-grep cross-reference sweep (MANDATORY for structural changes)

Before invoking sub-agents, ask yourself: **have I ast-grep'd this change?** If not, decide whether to.

Run ast-grep (or, as a fallback, ripgrep with type filters) when this session:
- Removed or renamed a function, hook, component, type, or string-literal value (e.g., a `task_type` enum value)
- Removed or renamed a database column, table, or view
- Changed the shape of a shared interface or return type
- Deleted a file (orphaned imports?)
- Modified an enum/union of valid string values used in `switch` cases, `.eq()` filters, `match` checks, or type guards

**Why this is mandatory**: text `grep` misses structural references (multi-line calls, JSX attribute names, type unions, computed property keys). Sessions that skipped ast-grep have repeatedly shipped with stale references — e.g., filter dropdowns still listing deleted enum values, unmounted-but-imported components, types missing newly-added columns. This step exists because that's the most common "you missed stuff" pattern.

**Patterns to run** (adapt to the change):
- `ast-grep --pattern "'<deleted-value>'" --lang ts` (string literals)
- `ast-grep --pattern "$.task_type === $X" --lang tsx` (enum comparisons)
- `ast-grep --pattern "import { $$$ } from '$path'" --lang tsx` (imports of removed/renamed exports)
- `rg -n '<symbol-name>' src/ services/ docs/` (fallback catch-all)

**Output**: list any matches that look stale. File each as a board subtask under the active project (severity: medium for visible UX, low for dead code).

**Skip only when**: the change is purely additive (new file, new function, no enum/type changes, no deletions) — in which case write "ast-grep skipped: additive-only" in the review output for the audit trail.

### Step 1.5: Bidirectional parent/child reconciliation check (SAFETY NET)

**Since vibe-board 2.0.0**, both directions of parent/child reconciliation are surfaced by the MCP itself:

- **Parent→child**: `board_update_task(status="done")` REJECTS the call if the task has open children unless an explicit `on_open_children` directive is passed. No way to silently orphan.
- **Child→parent**: every child-close response includes `parent_now_empty: { id, title }` when the parent now has zero open siblings. Surfaces the parent-closure opportunity inline.

This step is now a **safety net** rather than primary enforcement. Sweep here for any case where:

1. A `parent_now_empty` advisory was returned during EXECUTE but ignored — agent closed a child without acting on the parent-closure recommendation.
2. The agent used `on_open_children: "leave_attached"` with a reason that looks like a bypass excuse (vague, "just close it", "TODO later", etc.) rather than a real reason (scope-shift, deferred-to-followup, archived-initiative).
3. The agent used `"close_all"` on a parent whose children weren't actually finished, just to make the guard happy.

For each, surface in the review verdict and ask the user whether to revisit. If you found NONE of these patterns, write "Parent/child reconciliation: clean per MCP enforcement" in the verdict for audit trail.

**Why kept as a step despite MCP enforcement**: the guard prevents silent orphans, but it can't prevent intent-fraud (correct API usage, wrong intent). Human eyes catch the soft failure modes.

### Step 2: Invoke Sub-Agents (PARALLEL where possible)

**Always invoke** (these are mandatory for every post-execute review):
- `code-reviewer` — Review all code changes for security, quality, patterns
- `test-runner` — Run type-check (`npm run type-check`) and any relevant tests

**Conditionally invoke** based on what changed:
- **UI files changed** (`.tsx` in `src/components/`, `src/pages/`, `src/features/`): → `ui-specialist`
- **DB changes** (migration files, RLS, schema): → `database-specialist`
- **Python service changes** (`services/` directory): → relevant service specialist
- **Auth changes** (Firebase, JWT, session): → `auth-specialist`
- **Stripe/billing changes**: → `subscription-specialist`
- **User-facing copy changed**: → `marketing-specialist`

**Invoke in parallel** when agents are independent:
```
PARALLEL: code-reviewer + test-runner + ui-specialist (independent)
SEQUENTIAL: database-specialist → service-specialist (if service depends on schema)
```

### Step 3: Process Findings

Route all sub-agent findings through the `processor` agent:
- Provide: `project_id`, `parent_task_id` (if applicable), raw findings
- Processor creates board tasks by severity tier
- Processor returns lean summary

### Step 4: Composite Verdict

- **PASS**: All sub-agents report no critical/high issues. Ready for COMMIT. **Create the review gate marker**: run `touch /tmp/ve-review-complete` so the commit hook allows the next `git commit`.
- **FAIL**: Critical or high issues found. List them with board task IDs. Return to EXECUTE to fix, then re-review. Do NOT create the review marker.

Output format:
```
REVIEW VERDICT: [PASS/FAIL]

Requirements traceability:
- [N] spec points checked, [N] matched, [N] deviations
- Deviations: [list any, or "none"]

Board reconciliation (Step 1.5):
- [N] tasks closed this session, [N] had parents checked
- Parents to close: [list IDs with one-line reason, or "none"]
- Parents to revise: [list IDs with one-line reason, or "none"]

Sub-agent results:
- code-reviewer: [PASS/FAIL] — [summary]
- test-runner: [PASS/FAIL] — [summary]
- ui-specialist: [PASS/FAIL or N/A] — [summary]
- [other agents]: [PASS/FAIL or N/A] — [summary]

[If DEVIATIONS]: Flagged deviations require user approval before COMMIT.
[If parent reconciliation flagged any IDs]: Resolve those before COMMIT (or confirm deferral with the user).
[If FAIL]: Issues logged to board under task [ID]. Fix and re-review.
[If PASS]: Ready for COMMIT (Enter C).
```

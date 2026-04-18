---
name: go
description: Full autonomous RIPER cycle in one command. Runs RESEARCH → PLAN → REVIEW → EXECUTE → REVIEW with auto-advance on REVIEW PASS. Stops only on REVIEW FAIL, user-required decisions, or safety guards.
user-invocable: true
---

# /go — Autonomous Full-Cycle Execution

Execute a complete RIPER cycle from a single command. The agent handles research, planning, review, execution, and validation — stopping only when human judgment is required.

## Usage

```
/go <task description>
```

**Examples:**
- `/go Fix the mobile padding on the pricing page`
- `/go Add a loading spinner to the essay submission button`
- `/go Add weekly study streak tracking to the dashboard`

## Safety Guards

These are hard stops that cannot be bypassed:

| Guard | Threshold | What happens |
|-------|-----------|-------------|
| **REVIEW FAIL** | Any critical/high finding | Stops, reports findings, waits for user direction |
| **Cumulative lines changed** | 500+ lines modified across all files | Stops, reports scope, waits for user to approve continuing |
| **Scope escalation** | During RESEARCH, task is clearly multi-day or architectural | Stops after RESEARCH, reports findings, asks user to confirm scope |
| **User input needed** | Implementation requires a decision only the user can make | Stops, asks the specific question, resumes after answer |
| **Commit** | Never auto-commits or auto-pushes | Reports completion, waits for `Enter C` |

## Execution Protocol

### Phase 1: RESEARCH
`[MODE: RESEARCH]`

1. Read all files relevant to the task description
2. Understand current state, patterns, dependencies
3. Log findings to the board via `board_log_activity`
4. **Scope check**: If the task is clearly larger than expected (3+ files, architectural decisions, multi-day), STOP and report:
   > "This task is larger than a /go cycle. It touches [X, Y, Z] and requires [architectural decision]. Recommend entering PLAN mode manually. Continue anyway?"
5. If scope is reasonable, auto-advance to PLAN

### Phase 2: PLAN
`[MODE: PLAN]`

1. Create board tasks with `assigned_agent` and acceptance criteria (per `/plan` skill protocol)
2. Include a `test-runner` task and `code-reviewer` task in the plan
3. Output the implementation checklist
4. Auto-advance to REVIEW (existing behavior)

### Phase 3: POST-PLAN REVIEW
`[MODE: REVIEW]`

1. Invoke `/review` skill (post-plan validation)
2. **If PASS**: Auto-advance to EXECUTE (no user approval needed)
3. **If NEEDS REVISION**: Fix the issues automatically if possible (missing agent, wrong dependency). If the fix requires user judgment, STOP and ask.

### Phase 4: EXECUTE
`[MODE: EXECUTE]`

1. Delegate each task to its `assigned_agent` per the plan
2. Track cumulative lines changed across all files
3. **Line guard**: If cumulative lines > 500, STOP:
   > "500-line safety cap reached ([N] lines across [M] files). Review changes so far before continuing?"
4. On completion, auto-advance to REVIEW (existing behavior)

### Phase 5: POST-EXECUTE REVIEW
`[MODE: REVIEW]`

1. Invoke `/review` skill (post-execute validation)
2. **If PASS**: Report completion summary. Wait for `Enter C`.
   > "/go complete. [summary of what was built]. All reviews passed. Ready for commit (Enter C)."
3. **If FAIL**: Report findings. Attempt auto-fix for low/medium issues. For critical issues, STOP and ask user.

## Task Queue Mode

When used with multiple tasks (future: task chaining from board queue):

```
/go --queue <project_id>
```

Pulls READY tasks from the board queue in priority order. After completing each task:
1. Run the full /go cycle above
2. Ping Discord with completion status
3. Pull next task
4. **Queue guards**: Stop after 15 tasks OR 4 hours OR 500 cumulative lines (whichever first)

## What /go Does NOT Do

- **Never pushes to main** — autonomous execution ONLY commits/pushes to `dev`. If on main, switch to dev first. This is a hard safety rule for both interactive and Docker worker modes.
- **Never commits or pushes without authorization** — in interactive mode, waits for explicit `Enter C`. In worker/Docker mode, auto-commits to dev only.
- **Never skips REVIEW gates** — both post-plan and post-execute reviews run every time
- **Never makes architectural decisions** — if the task requires choosing between approaches, it stops and asks
- **Never modifies scope** — if it discovers related issues, it logs them as separate board tasks but doesn't fix them in this cycle
- **Never runs without a board task** — creates one immediately at cycle start for tracking

## Relationship to RIPER Modes

`/go` is not a new mode — it's an orchestrator that drives through existing modes automatically. Each phase respects all existing mode rules. The only behavioral change is **auto-advance on REVIEW PASS**, which eliminates the need for explicit "Enter E" after a passing plan review.

When `/go` is active, the mode header still shows the current mode (e.g., `[MODE: RESEARCH]`). The `/go` context is noted in the board session.

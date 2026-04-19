# Vibe Board: Persistent Task Tracking for AI Coding Agents

A Firebase Firestore-backed MCP server that gives AI coding agents (Claude Code, etc.) persistent memory across sessions. Tasks, projects, and session handoffs survive when conversations end.

**The problem**: AI coding sessions are stateless. When a conversation ends, all context — what was planned, what was done, what's next — evaporates. Plans get lost, steps get skipped, and every new session starts from scratch.

**The solution**: A shared task board that lives outside any single conversation. Agents create tasks during planning, track progress during execution, and write handoff notes when sessions end. The next session picks up exactly where the last one left off.

---

## What You Get

- **14 MCP tools** for task/project/session management (see [full list below](#mcp-tool-reference))
- **Session handoff protocol** — relay race, not marathon
- **Activity log** — audit trail of every decision and change, queryable via `board_get_activity`
- **RIPER mode tracking** — optional workflow mode integration
- **Task project-reassignment + bulk operations** — move tasks between projects, consolidate projects, hard-delete with safety guards
- **Free tier** — Firebase Firestore free tier handles thousands of sessions

## Architecture

```
Claude Code / AI Agent
    |
    | (MCP stdio)
    v
ve-vibe-board (Node.js)
    |
    | (Firebase Admin SDK)
    v
Firestore (4 collections)
    - projects
    - tasks
    - sessions
    - activity_log
```

---

## Setup (15 minutes)

### Prerequisites

- Node.js 18+
- `gcloud` CLI authenticated
- A Google Cloud / Firebase project (or create one)

### Step 1: Create a Firebase Project

```bash
# Option A: Use an existing GCP project
# Option B: Create a new one at https://console.firebase.google.com

# Enable Firestore API
gcloud services enable firestore.googleapis.com --project=YOUR_PROJECT_ID

# Create Firestore database (Native mode, pick your region)
gcloud firestore databases create \
  --project=YOUR_PROJECT_ID \
  --location=us-central1 \
  --type=firestore-native
```

### Step 2: Create a Service Account

```bash
# Create service account
gcloud iam service-accounts create vibe-board \
  --project=YOUR_PROJECT_ID \
  --display-name="Vibe Board MCP"

# Grant Firestore access
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:vibe-board@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

# Download key (store securely, never commit to git)
gcloud iam service-accounts keys create ~/.config/gcloud/vibe-board-key.json \
  --iam-account=vibe-board@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### Step 3: Clone the Vibe Board MCP server

The server source lives in a standalone public repo. Cloning keeps you
on the latest version — new tools added upstream flow to you via `git pull`.

```bash
# From your project root (or wherever you want the server to live)
git clone https://github.com/HuntsDesk/ve-vibe-board.git
cd ve-vibe-board
```

That's it for this step. The next step builds it.

**Updating to new tool versions later**: when new board tools ship (e.g.,
bulk task operations, activity log queries, etc.), run:

```bash
cd ve-vibe-board
git pull
npm install   # if dependencies changed
npm run build
```

Then update your `.claude/settings.local.json` permissions list (see
Step 6 below) to allow the new tool names, and restart Claude Code so
it re-registers the MCP's tool schemas.

**Historical note**: earlier versions of this doc inlined the full server
source as copy-paste TypeScript. That's been replaced with a git-based
install so users automatically get new tools without doc-drift friction.
If you need to fork or extend the server, fork the public repo directly.

### Step 4: Build and Install

```bash
cd ve-vibe-board
npm install
npm run build
```

### Step 5: Create Firestore Composite Indexes

These are required for multi-field queries. Without them, `board_create_session` and `board_get_handoff` will fail.

```bash
# Index 1: Sessions — for handoff queries
gcloud firestore indexes composite create \
  --project=YOUR_PROJECT_ID \
  --collection-group=sessions \
  --field-config field-path=project_id,order=ascending \
  --field-config field-path=status,order=ascending \
  --field-config field-path=ended_at,order=descending

# Index 2: Tasks — for active task queries
gcloud firestore indexes composite create \
  --project=YOUR_PROJECT_ID \
  --collection-group=tasks \
  --field-config field-path=project_id,order=ascending \
  --field-config field-path=status,order=ascending
```

Wait 1-5 minutes for indexes to build. Check status at:
https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore/indexes

### Step 6: Configure Claude Code

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "vibe-board": {
      "command": "node",
      "args": ["ve-vibe-board/dist/index.js"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/ABSOLUTE/PATH/TO/vibe-board-key.json"
      }
    }
  }
}
```

Add tool permissions to `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__vibe-board__board_get_projects",
      "mcp__vibe-board__board_create_project",
      "mcp__vibe-board__board_update_project",
      "mcp__vibe-board__board_get_tasks",
      "mcp__vibe-board__board_get_task",
      "mcp__vibe-board__board_create_task",
      "mcp__vibe-board__board_update_task",
      "mcp__vibe-board__board_bulk_update_tasks",
      "mcp__vibe-board__board_delete_task",
      "mcp__vibe-board__board_create_session",
      "mcp__vibe-board__board_end_session",
      "mcp__vibe-board__board_get_handoff",
      "mcp__vibe-board__board_log_activity",
      "mcp__vibe-board__board_get_activity"
    ]
  },
  "enabledMcpjsonServers": ["vibe-board"]
}
```

### Step 7: Verify

Start a new Claude Code session and ask it to call `board_get_projects`. If it returns an empty array `[]`, you're live.

---

## MCP Tool Reference

All 14 tools. Implementations live in the cloned [`HuntsDesk/ve-vibe-board`](https://github.com/HuntsDesk/ve-vibe-board) source under `src/tools/` (projects.ts, tasks.ts, sessions.ts, activity.ts). The 5 **bolded** tools below are additions from the 2026-04 release — run `git pull && npm run build` in your cloned ve-vibe-board dir to pick them up.

### Projects

| Tool | Purpose |
|---|---|
| `board_get_projects` | List all projects with task count summaries |
| `board_create_project` | Create a new project |
| **`board_update_project`** | Update name/description/status/metadata. Enforces status transitions (active → completed/archived, etc.). Use `status: "archived"` to archive completed projects. |

### Tasks

| Tool | Purpose |
|---|---|
| `board_get_tasks` | List tasks for a project (filterable by status, priority, assignment) |
| **`board_get_task`** | Fetch a single task by ID with all fields + ISO timestamps |
| `board_create_task` | Create a task (supports parent_task_id for subtasks) |
| `board_update_task` | Update status/priority/assignment/RIPER mode. **Now supports `project_id` to move tasks between projects** — validates target project exists, warns if subtasks are orphaned in source. |
| **`board_bulk_update_tasks`** | Apply same update (project_id/status/priority/agent) to 1-100 tasks atomically. All-or-nothing: preflight fails if any task missing. Direct fit for consolidating small projects. |
| **`board_delete_task`** | Hard-delete a task + its activity_log entries. Default safety: `require_done=true` refuses if status != done. Optional `cascade_subtasks` cleans up children. Irreversible. |

### Sessions

| Tool | Purpose |
|---|---|
| `board_create_session` | Start a session; abandons stale sessions; returns last session's handoff |
| `board_end_session` | End session with progress summary + handoff notes for the next one |
| `board_get_handoff` | Fetch the most recent completed session's handoff mid-session |

### Activity

| Tool | Purpose |
|---|---|
| `board_log_activity` | Write an activity log entry (action types: created, updated, claimed, blocked, completed, commented, mode_changed, session_started, session_ended) |
| **`board_get_activity`** | Query the activity log. Filter by task_id / session_id / agent_name / action. Cursor-paginated, newest-first, default limit 50 / max 200. Returns `{entries, scanned, truncated}` so callers know if filters were too selective to fill the limit. |

---

## Agent Rules (add to CLAUDE.md or equivalent)

Copy this into your project's instructions file so every session follows the protocol:

```markdown
## Vibe Board

Persistent task tracking across sessions via Firebase Firestore MCP tools (`board_*`).
**Mandatory for every substantive session** (any session where you read, write, plan, debug, or deploy code).

### Use Board Tasks, NOT TodoWrite

TodoWrite is ephemeral — it dies when the session ends. Board tasks persist forever and enable cross-session handoff. When you would reach for TodoWrite to track multi-step work, use `board_create_task` instead.

**Nothing exists unless it's on the board.** If an action item, future phase, recommendation, or follow-up is mentioned in conversation or discovered in a document but has no board task, it WILL be forgotten. The board is the single source of truth for "what needs to be done." Conversation text, plan docs, and strategy docs are reference material — the board is the task list. When in doubt, create the task. A redundant board task costs nothing; a forgotten action item costs real work.

### Proactive Triggers

These are condition → action pairs. When the condition is true, take the action immediately.

| Condition | Action |
|-----------|--------|
| Session starts (substantive work) | `board_create_session` before any other work |
| Context compacted / continuation session | `board_create_session` IMMEDIATELY — compaction loses the active session ID |
| Multi-step task (3+ steps) | `board_create_task` for each step |
| Batch of items (fix 5 bugs, review 3 files) | Parent task + subtask per item via `board_create_task` |
| New work discovered during execution | `board_create_task` immediately |
| Significant decision or blocker | `board_log_activity` |
| Start working on a task | `board_update_task` → `in_progress` + set `assigned_agent` to your name |
| Finish a task | `board_update_task` → `done` |
| Review/audit produces findings | Parent task per severity tier + subtask per finding |
| Deploying a new service for the first time | `board_create_task` for: verify deployment, create CI/CD trigger, push to prod |
| Committing + pushing code | `board_log_activity` with commit hash; update related tasks |
| You read a doc/plan with unbuilt phases or pending items | `board_create_task` for each actionable item not already on the board |
| You mention a future action item in conversation | `board_create_task` immediately — conversation text is ephemeral, board tasks are permanent |
| A sub-agent reports a finding or recommendation | `board_create_task` if it requires future work (don't let it exist only in conversation) |
| User says "handoff" or signals session end | Create board tasks for ALL pending next steps, THEN `board_end_session` |
| Session ending OR context getting long | `board_end_session` with handoff notes |

**The test**: If this session died right now, could the next session reconstruct what you were doing from the board alone? If not, you haven't been proactive enough.

**The second test**: If a documented plan has unchecked items, unbuilt phases, or "pending" status markers — and there's no corresponding board task — that's a gap. Every actionable item in every plan doc should have a board task. Plans without board tasks get forgotten.

### Session Lifecycle

**Starting a session** (before any other work — **including after context compaction**):

**Context compaction destroys the active session ID.** If you're continuing from a compacted conversation, you MUST call `board_create_session` before doing anything else. This is the #1 failure mode — compaction preserves your behavioral patterns but loses board state.

1. Call `board_get_projects` to see all active projects
2. **Match work to the correct project** — read project names/descriptions and pick the best fit. Do NOT default to one project for everything. Use a general catch-all project only when no specific project fits.
3. Call `board_create_session` with the matched `project_id`
   - This auto-abandons any stale sessions and returns handoff context
   - Read the handoff carefully — it contains what the last session accomplished and what's next
4. Review active tasks via the handoff response or `board_get_tasks`

**During a session:**
- **PLAN mode**: Create all tasks on the board immediately with status `todo` and `riper_mode: "plan"`. This ensures the plan survives even if the session crashes before execution.
- **REVIEW mode**: Review the *task list on the board*, not just prose. Call `board_get_tasks`, then use `board_log_activity` with `task_id` and `action: "commented"` to attach review comments to specific tasks. ALL review output MUST go through the board — conversation text disappears when sessions end.
- **Review findings → board tasks**: When a review produces findings (FAILs, WARNs, issues, blockers), every finding must become a board task — not just an activity log comment. Create one parent task per severity tier (e.g., "Tier 1: BLOCKING items"), then subtasks for each finding using `parent_task_id`. Map priorities: BLOCKING/FAIL → `critical`, HIGH/WARN → `high`, LOW/INFO → `low`. Include enough context in each subtask's description to fix the issue without re-reading the review.
- **EXECUTE mode**: Move tasks to `in_progress` as work begins, then `done` when complete. `started_at` is set automatically on first move to `in_progress` — work duration = `completed_at - started_at`.
- **COMMIT mode**: Log the commit hash via `board_log_activity` on related tasks. When deploying a new service for the first time, create follow-up tasks: (1) verify deployment in browser, (2) create CI/CD trigger for auto-deploy, (3) push to production. These are predictable follow-ups — don't wait for the user to ask.
- **Tracking your own work**: The board isn't just for project plans — it tracks what YOU are doing right now. When you receive a batch of items (e.g., "fix these 5 issues", "review these 3 files"), create a **parent task** for the batch and **subtasks** for each item using `parent_task_id`. Move each subtask to `in_progress` -> `done` as you work. This creates a recoverable checkpoint: if the session dies mid-batch, the next agent sees exactly which items are done and which remain.
- **Sub-agent board delegation**: When spawning specialist sub-agents that produce detailed findings, instruct them to write results directly to the board. Include the `project_id` and parent task ID in the prompt. The sub-agent returns only a brief summary (e.g., "Found 8 issues, 3 critical. All logged to board under parent task X."). This keeps the main agent's context lean while preserving full detail on the board. Pattern: `"Write all findings to the Vibe Board (project: PROJECT_ID, parent task: TASK_ID). Return only a 1-sentence summary to me."`
- **All modes**: Log notable events via `board_log_activity`. Create additional tasks as new work is discovered — the board should always reflect the current state of work.

**Ending a session** (before the session ends or when the user signals they're done):
1. **Scan your tasks**: Check for any tasks still `in_progress` that you own — mark them `done` if complete, or add a `board_log_activity` comment explaining what remains.
2. **Create tasks for all next steps**: Every pending follow-up must exist as a board task BEFORE ending. Do not list future work only in handoff prose — if it's worth mentioning as a next step, it's worth tracking as a task.
3. Call `board_end_session` with progress_summary, handoff_notes (referencing task IDs, not just prose), and context_artifacts.

**This is the most critical step.** A session without handoff notes is a session whose context is lost forever.

**Proactive ending:** If you sense the conversation is getting long or you are approaching context limits, call `board_end_session` immediately — even a partial handoff is infinitely better than an abandoned session with no notes.

### Task Status Flow

backlog -> todo -> in_progress -> review -> done
                       |
                    blocked

### Priority Levels

- **critical**: Blocking other work, needs immediate attention
- **high**: Important, should be next
- **medium**: Standard priority (default)
- **low**: Nice to have, do when time allows
```

---

## RIPER Mode Integration (Optional)

RIPER is a structured workflow mode system. If you use it, tasks track which mode they're in:

| Mode | Purpose | Board Action |
|------|---------|-------------|
| **RESEARCH** | Observe and understand | Read tasks, log findings |
| **INNOVATE** | Brainstorm options | Log ideas as activity comments |
| **PLAN** | Create implementation spec | Create all tasks with `riper_mode: "plan"` |
| **EXECUTE** | Implement the plan | Move tasks through `in_progress` -> `done` |
| **REVIEW** | Validate output | Review task list, attach comments via `board_log_activity`, convert findings into subtasks by severity tier |
| **COMMIT** | Finalize and persist | Log commit hash via `board_log_activity`, create deployment follow-up tasks, end session with handoff notes |

The `riper_mode` field on tasks is optional. If you don't use RIPER, just ignore it — everything else works the same.

---

## Agent Organization (Optional)

If you use multiple specialist sub-agents, the Vibe Board enables a delegated hierarchy that prevents context bloat. Without this, every sub-agent dumps its full output back to the main agent — overwhelming it with raw data instead of letting it think strategically.

### The Problem: Star Topology

```
Main Agent (overloaded)
  /   |   |   |   \
sub  sub  sub  sub  sub   ← all output flows back to center
```

Every specialist returns full findings. The main agent spends 80% of its capacity processing raw output instead of coordinating.

### The Solution: Delegated Hierarchy

```
User (direction, decisions, approvals)
  |
Main Agent (routing, user communication)
  |
├── Project Coordinator (team lead - task lifecycle, delegation)
│     ├── Processor (raw output → board tasks → lean summaries)
│     └── Specialists (domain experts)
│
└── Direct specialists (simple single-domain tasks)
```

### Processor Agent

Create an agent whose only job is consolidation. When specialists produce detailed findings:

1. Route raw output to the processor
2. Processor categorizes by severity, creates board tasks (parent per tier, subtask per finding)
3. Processor returns a 1-sentence summary to the caller
4. Full details live on the board, not in anyone's context window

**Prompt pattern for the processor:**
```
You are the processor agent. Your job is to take raw specialist output and:
1. Create parent tasks on the Vibe Board per severity tier
2. Create subtasks for each individual finding with enough context to fix standalone
3. Return ONLY a brief summary (e.g., "Processed 12 findings: 3 critical, 5 high, 4 low. All on board.")
Never return the full raw findings — that defeats your purpose.
```

### Delegation Patterns

**Simple task (one specialist):**
```
Main Agent → Specialist → Result back to main agent
```

**Complex task (multiple specialists):**
```
Main Agent → Project Coordinator → creates board tasks
  → Specialists (parallel where possible)
  → Processor (findings → board tasks + lean summary)
  → Coordinator returns clean summary to main agent
```

**Review / Audit (bulk findings):**
```
Main Agent → Specialist(s) in parallel
  → Processor (findings → board subtasks by severity)
  → Lean summary back to main agent
```

This is entirely optional. If you only use one agent, the session lifecycle and board tools work fine on their own. The organizational layer matters when you're coordinating 3+ specialists and their output starts overwhelming the main agent's context.

---

## Tool Reference

| Tool | Purpose |
|------|---------|
| `board_get_projects` | List projects with task count summaries |
| `board_create_project` | Create a new project |
| `board_update_project` | Update project status (active / completed / archived), name, description, metadata |
| `board_get_tasks` | Get tasks (filterable by status, priority, assignment; includes `started_at`/`completed_at` for duration) |
| `board_create_task` | Create a task with title, description, priority, dependencies |
| `board_update_task` | Update status, priority, assignment, description, dependencies |
| `board_create_session` | Start session (auto-abandons stale ones, returns handoff) |
| `board_end_session` | End session with summary + handoff notes |
| `board_get_handoff` | Get previous session's handoff context |
| `board_log_activity` | Log decisions, comments, blockers, or arbitrary events |

---

## Viewing Your Board

Go to https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore to browse all collections, tasks, sessions, and activity logs in the Firebase Console UI.

---

## Cost

Firebase Firestore free tier: 50,000 reads, 20,000 writes, 1GB storage per day. This easily handles hundreds of agent sessions before you'd ever see a bill.

---

## License

MIT. Use it however you want.

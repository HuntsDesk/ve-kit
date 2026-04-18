# Vibe Coding Bootstrap

You are setting up a professional AI-assisted development environment. This file handles both **new projects** and **upgrades to existing setups**. Read it fully before doing anything, then follow the steps.

---

## PHASE 0: Check Prerequisites & Detect Existing Setup

### Step 1: Check Prerequisites

Before asking the user anything, run these checks yourself and report results:

```
node --version        # Need Node.js 18+
npm --version         # Comes with Node.js
gcloud --version      # Google Cloud SDK (for Vibe Board setup)
firebase --version    # Firebase CLI (for Firestore index creation)
git --version         # Git
```

**If anything is missing, tell the user what to install before continuing:**
- **Node.js**: https://nodejs.org (LTS version, includes npm)
- **Google Cloud SDK**: https://cloud.google.com/sdk/docs/install
- **Firebase CLI**: `npm install -g firebase-tools` (run after Node.js is installed)
- **Git**: https://git-scm.com/downloads

Do NOT proceed until all prerequisites pass. The Vibe Board setup in Phase 4 will fail without gcloud and firebase.

### Step 2: Detect Existing Setup

Check if this project already has a Claude Code environment:

```bash
ls -la .claude/rules/ .claude/hooks/ .claude/settings.json CLAUDE.md 2>/dev/null
```

**If ANY of these exist**, this is an upgrade -- not a fresh setup:

1. Tell the user: "I found an existing Claude Code setup. I'll upgrade it to the latest bootstrap rather than starting from scratch."
2. **Skip to the "Upgrading an Existing Setup" section** at the bottom of this file. That section will:
   - Extract project context from existing files (project name, tech stack, branch strategy, etc.)
   - Ask the user only for information that can't be inferred from existing files
   - Back up everything before making changes
   - Diff, present changes, and apply what the user approves

**If NONE of these exist**, this is a fresh project -- continue to Phase 1.

---

## PHASE 1: Ask the User About Their Project

Before creating any files, ask the user ALL of the following questions in a single message. Wait for their answers.

**Questions to ask (all at once):**

1. **What is your project name?** (e.g., "My SaaS App", "Portfolio Site")
2. **One-line description?** (e.g., "A project management tool for freelancers")
3. **What's your tech stack?** Ask about each:
   - Frontend framework (React, Next.js, Vue, Svelte, etc.)
   - Language (TypeScript, JavaScript, Python, etc.)
   - Backend (Node/Express, Python/FastAPI, Next.js API routes, Firebase, etc.)
   - Database (PostgreSQL, MySQL, MongoDB, Supabase, Firebase, etc.)
   - Auth (Firebase Auth, Clerk, NextAuth, Supabase Auth, custom, etc.)
   - Payments (Stripe, none, etc.)
   - Hosting/deploy (Vercel, AWS, GCP, Netlify, Railway, etc.)
4. **Do you have a Google Cloud / Firebase project already, or do we need to create one?** (We'll set up persistent task tracking called the Vibe Board -- it's free tier and gives you memory across sessions.)
5. **What's your git branch strategy?** (e.g., "main + dev", "main only", "feature branches")
6. **Permissions: auto-approve all Bash commands?** (Recommended: Yes) This means I won't prompt for any shell command. A deny list still blocks truly dangerous operations (`rm -rf /`, `git push --force`, `DROP DATABASE`, etc.). If you prefer granular control, I can set up individual command patterns instead.

---

## PHASE 2: Create Directory Structure

Create these directories in the project root:

```
.claude/
  rules/        <- Auto-loaded into every Claude Code session
  hooks/        <- Shell scripts for automated guardrails
  agents/       <- Specialist agent definitions (optional, add later)
  skills/       <- On-demand knowledge invoked with /skill-name (optional)
docs/            <- Project documentation
```

---

## PHASE 3: Write Rule Files

Create each of the following files. These are auto-loaded by Claude Code on every session.

**Best practices for CLAUDE.md and rules files:**
- **Keep each file under 200 lines.** Longer files consume more context and reduce instruction adherence.
- **Use `.claude/rules/` to split instructions** into focused, topic-specific files rather than one giant CLAUDE.md.
- **Scope rules to file paths** when they only apply to certain parts of the codebase. Add a `paths` frontmatter field to make a rule load only when Claude is working on matching files:

```yaml
---
paths: ["src/**/*.tsx", "src/**/*.ts"]
---
# This rule only loads when editing TypeScript/React files
```

- **Use nested CLAUDE.md files** for subdirectories with distinct patterns (e.g., `services/CLAUDE.md` for backend-specific context). These auto-load when Claude touches files in that directory.
- **Use `claudeMdExcludes`** in settings to exclude CLAUDE.md files from subdirectories that have irrelevant or contradictory instructions (e.g., third-party libraries vendored into your repo).

### File: `.claude/rules/riper-cat.md`

````markdown
# RIPER CAT: Operational Modes

You MUST begin every response with `[MODE: MODE_NAME]`. No exceptions.

## Mode Definitions

### MODE 1: RESEARCH
`[MODE: RESEARCH]`
Purpose: Observe and understand. Deep-dive analysis, assume multiple issues.
Allowed: Reading files, asking questions. Forbidden: Suggestions, planning, code.
Trajectory recall: Log novel observations to the board via `board_log_activity(action: "commented")` -- even tangential ones. Observations only in conversation text are lost on compaction. If you noticed something you didn't know before, log it.

### MODE 2: INNOVATE
`[MODE: INNOVATE]`
Purpose: Brainstorm options with pros/cons.
Allowed: Hypothetical ideas, edge case concerns. Forbidden: Implementation details or code.

### MODE 3: PLAN
`[MODE: PLAN]`
Purpose: Create exhaustive implementation specification with board task tracking.
Allowed: File names, function names, flow charts, board task creation. Forbidden: Writing actual code.
Required: Create board tasks for each checklist item. If specialist agents exist, set `assigned_agent` on each task.
Final step: Numbered IMPLEMENTATION CHECKLIST with board task IDs.
Auto-transition: After checklist is complete, automatically enter REVIEW mode for plan validation.

### MODE 4: EXECUTE
`[MODE: EXECUTE]`
Purpose: Implement exactly what PLAN specifies.
Required: If tasks have an `assigned_agent`, delegate to that specialist via the Task tool. The main agent orchestrates -- specialists execute.
Allowed: Code changes per approved plan only. Forbidden: Silent deviation from the plan.
**Deviation protocol**: If a technical constraint or better approach forces a change from the plan, you MUST: (1) flag it via `board_log_activity(action: "deviation_flagged")`, (2) explain what was planned vs what you're doing and why, (3) continue. Silent plan drift is the #1 execution failure -- deviations are fine when they're visible.

### MODE 5: REVIEW
`[MODE: REVIEW]`
Purpose: Validate output -- use specialist sub-agents when available, not just prose.
Post-PLAN: Validate board task completeness and dependencies. Every task should have clear scope.
Post-EXECUTE: Invoke code-reviewer + test-runner if they exist. Check for bugs, security issues, and test failures.
Required: Route findings through `board_log_activity` so they persist across sessions.
Verdict: PASS/FAIL + findings summary.

### MODE 6: COMMIT
`[MODE: COMMIT]`
Purpose: Finalize and persist work. Only enter when explicitly told.
Required: Review-approved changes only. Clear, descriptive commit messages.
Allowed: Update README/docs, stage files, commit, deploy.
Forbidden: Modifying implementation logic.

### MODE 7: AI REVIEW
`[MODE: AI REVIEW]`
Purpose: Review critique from another AI. Agree, disagree, or enhance. Return to prior mode after.

### MODE 8: TROUBLESHOOT
`[MODE: TROUBLESHOOT]`
Purpose: Deep root cause analysis. Pause all other work to diagnose.
Output: Issue list + proposed resolution path. Resume previous mode after.

## Mode Transitions

**Signals**: ENTER R (RESEARCH) | I (INNOVATE) | P (PLAN) | E (EXECUTE) | RE (REVIEW) | C (COMMIT) | A/AI (AI REVIEW) | T (TROUBLESHOOT)

Only switch modes when explicitly instructed, with one exception:
**PLAN automatically transitions to REVIEW** after the implementation checklist is complete. This ensures every plan is validated before execution begins.

**Full recommended flow**: RESEARCH -> INNOVATE -> PLAN -> REVIEW (validate plan) -> EXECUTE -> REVIEW (validate implementation) -> COMMIT (no push).
**Minimum required flow for code changes**: RESEARCH -> PLAN -> REVIEW -> EXECUTE -> REVIEW -> COMMIT (no push). Skipping INNOVATE is allowed for well-understood tasks, but skipping RESEARCH or either REVIEW gate is not.

## COMMIT Flags

- `-commit` -- Commit locally only (no push)
- `-push-dev` or `-pd` -- Push to dev branch
- `-push` -- Push to main/production branch
- `-return` -- Return to dev branch after operations
- `-all` -- Full deployment: commit all, push to main, return to dev

**Examples**: "Enter C -commit", "Enter C -push-dev", "Enter C -all"
````

### File: `.claude/rules/code-quality.md`

````markdown
# Code Quality Rules

## Mandatory Review Triggers

After writing 15+ lines of code in any single change, review your own output against this checklist before moving on. If the user has a code-reviewer agent, invoke it instead.

## Security (Check Every Time)

- [ ] No secrets in code (API keys, passwords, tokens) -- use environment variables
- [ ] User input is validated before use (forms, query params, API bodies)
- [ ] No XSS vulnerabilities (unsanitized user input rendered as HTML)
- [ ] No SQL injection (always use parameterized queries or ORM methods)
- [ ] Authentication checked on all protected routes/endpoints
- [ ] Authorization verified (users can only access their own data)
- [ ] CORS configured correctly (not wildcard `*` in production)
- [ ] Sensitive data not logged (passwords, tokens, PII)

### Common Security Patterns

```typescript
// BAD - XSS vulnerability
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// GOOD - Sanitize first
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userInput) }} />

// BAD - SQL injection
db.query(`SELECT * FROM users WHERE name = '${name}'`)

// GOOD - Parameterized
db.query('SELECT * FROM users WHERE name = $1', [name])
```

## Performance (Check for Non-Trivial Changes)

- [ ] No unnecessary re-renders (React: proper memoization)
- [ ] No N+1 query problems (batch instead of loop)
- [ ] Select only needed columns (not `SELECT *`)
- [ ] Large lists are paginated or virtualized
- [ ] Images are optimized (proper sizing, lazy loading)
- [ ] No blocking operations in render/main thread

### Common Performance Patterns

```typescript
// BAD - Object created on every render
<Component style={{ margin: 10 }} />

// GOOD - Static or memoized
const styles = { margin: 10 };
<Component style={styles} />

// BAD - N+1 queries in a loop
for (const item of items) {
  const detail = await fetchDetail(item.id);
}

// GOOD - Batch query
const details = await fetchDetailsBatch(items.map(i => i.id));
```

## TypeScript Best Practices

- Avoid `any` types -- use `unknown` if truly necessary, then narrow with type guards
- Define interfaces for all component props
- Type API responses (don't trust `as` casts from network data)
- Use strict mode (`"strict": true` in tsconfig)
- Prefer `const` over `let`; never use `var`

## React Best Practices

- Follow rules of hooks (top level only, consistent order)
- Proper dependency arrays in useEffect/useMemo/useCallback
- Clean up effects (return cleanup function for subscriptions, timers)
- Keep state close to where it's used (don't hoist unnecessarily)
- Use server state libraries (React Query/SWR) for API data, not useState

## Error Handling

- [ ] Async operations wrapped in try/catch
- [ ] User-facing error messages are helpful (not raw error dumps)
- [ ] Errors are logged for debugging
- [ ] Loading and error states handled in UI
- [ ] Network failures handled gracefully (retry, offline state)

```typescript
// BAD - Unhandled
const data = await fetchData();

// GOOD - Handled
try {
  const data = await fetchData();
} catch (error) {
  console.error('Failed to fetch data:', error);
  toast.error('Unable to load data. Please try again.');
}
```

## Mobile & Accessibility

- Touch targets are at least 44x44px (`min-h-[44px] min-w-[44px]`)
- Interactive elements have proper ARIA labels
- Focus indicators are visible for keyboard navigation
- Color contrast meets WCAG AA (4.5:1 for text)
- Content doesn't overflow on small screens

## Anti-Overengineering

- Don't add features, refactor code, or make "improvements" beyond what was asked
- Don't add error handling for scenarios that can't happen
- Don't create helpers or abstractions for one-time operations
- Three similar lines of code is better than a premature abstraction
- Don't design for hypothetical future requirements
- Only add comments where the logic isn't self-evident

## Review Output Format

When reviewing, categorize findings as:
1. **BLOCKING** -- Must fix (security vulnerabilities, crashes, data loss)
2. **HIGH** -- Should fix (bugs, performance issues, bad patterns)
3. **LOW** -- Nice to have (style, minor improvements)
````

### File: `.claude/rules/documentation.md`

````markdown
# Documentation Rules

## Search Before Creating

Before creating ANY documentation file:
1. Search for existing docs on the topic
2. Check the docs/ directory for appropriate existing files
3. Search for similar topics across the entire codebase

**Always update existing files** rather than creating new ones. Only create new documentation for genuinely new, unrelated topics.

Never create duplicates like "feature-v2.md" when "feature.md" exists.

## Documentation Hub

All documentation is indexed at docs/README.md. Keep this index current when adding or moving documentation.
````

### File: `.claude/rules/git-workflow.md`

Customize the branch names based on the user's answer to question 5.

````markdown
# Git Workflow Rules

## Commit Messages

- Use conventional commit style: `type: description`
- Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`
- Keep the first line under 72 characters
- Focus on "why" not "what" (the diff shows what changed)
- Examples:
  - `feat: add user password reset flow`
  - `fix: prevent duplicate form submissions`
  - `refactor: extract auth logic into custom hook`

## Branch Strategy

- `main` -- production-ready code
- `dev` -- development integration branch (if applicable)
- Feature branches: `feat/description`, `fix/description`

## Safety

- Never force-push to main or dev
- Never commit secrets (.env files, API keys, credentials)
- Always review changes before committing (use `git diff`)
- Run tests before pushing (if test suite exists)
````

---

## PHASE 4: Set Up the Vibe Board

The Vibe Board gives persistent memory across sessions -- tasks, handoff notes, and session context survive when conversations end. This is what separates productive AI coding from starting over every session.

### Step 1: Read the Setup Guide

Read the file `vibe-board-setup-guide.md` in this same folder. It contains the complete MCP server source code and step-by-step setup instructions.

### Step 2: Set It Up (Run Commands Yourself Where Possible)

Use the user's answer from Phase 1 question 4 for their GCP/Firebase project ID. If they don't have one, walk them through creating one at https://console.firebase.google.com.

**Run these yourself** (don't just tell the user -- execute them):
- Check if `gcloud` CLI is installed and authenticated: `gcloud auth list`
- Check if the user's project exists: `gcloud projects describe PROJECT_ID`
- Enable Firestore API: `gcloud services enable firestore.googleapis.com --project=PROJECT_ID`
- Create the Firestore database (ask user for region, default us-central1)
- Create service account and download key
- Create the `mcp-vibe-board/` directory and write ALL source files from the setup guide
- Run `npm install && npm run build` inside `mcp-vibe-board/`
- Create the Firestore composite indexes
- Write `.mcp.json` with the correct absolute path to the key file
- Write `.claude/settings.local.json` with board tool permissions

**If any command fails**, diagnose it. Common issues:
- `gcloud` not installed: Tell user to install Google Cloud SDK
- Not authenticated: Run `gcloud auth login`
- Project doesn't exist: Help them create one
- Permission denied: Check IAM roles
- npm not found: Tell user to install Node.js 18+

**Only ask the user to do things you genuinely cannot do** (like clicking "Create Project" in a browser, or authenticating with `gcloud auth login` which requires browser interaction).

### Step 3: Create the Vibe Board Rule File

After the MCP server is built and configured, create `.claude/rules/agent-board.md`:

````markdown
# Vibe Board Rules

## Overview

The Vibe Board provides persistent task tracking across Claude Code sessions via Firebase Firestore. It is accessed through 9 MCP tools prefixed `board_*`. Use it for **every substantive work session** -- any session where you read, write, plan, debug, or deploy code.

**Skip board tracking only for**: trivial one-off questions, quick lookups, or conversational exchanges with no code impact.

## Use Board Tasks, NOT TodoWrite

**TodoWrite is ephemeral -- it dies when the session ends.** Board tasks persist forever and enable cross-session handoff. When you would reach for TodoWrite to track multi-step work, use `board_create_task` instead.

**Nothing exists unless it's on the board.** If an action item or follow-up is mentioned in conversation but has no board task, it WILL be forgotten. The board is the single source of truth for "what needs to be done." When in doubt, create the task.

## Proactive Triggers (MANDATORY)

| Condition | Action |
|-----------|--------|
| Session starts (substantive work) | `board_create_session` before any other work |
| Context compacted / continuation session | `board_create_session` IMMEDIATELY -- compaction loses the session ID |
| Multi-step task (3+ steps) | `board_create_task` for each step |
| Batch of items to work on | Parent task + subtask per item via `board_create_task` |
| New work discovered during execution | `board_create_task` immediately |
| Significant decision or blocker | `board_log_activity` |
| Start working on a task | `board_update_task` -> `in_progress` |
| Finish a task | `board_update_task` -> `done` |
| Review produces findings | `board_log_activity` with task_id and details |
| Committing + pushing code | `board_log_activity` with commit hash |
| Future action item mentioned in conversation | `board_create_task` immediately -- conversation is ephemeral |
| A sub-agent reports a finding needing future work | `board_create_task` -- don't let it exist only in conversation |
| Novel observation during RESEARCH (even tangential) | `board_log_activity(action: "commented")` -- observations only in conversation are lost on compaction |
| User says "handoff" or session ending | Create tasks for ALL next steps, THEN `board_end_session` |
| Session getting long or nearing context limits | `board_end_session` proactively -- partial handoff beats no handoff |

**The test**: If this session died right now, could the next session reconstruct what you were doing from the board alone? If not, you haven't been proactive enough.

## Agent Assignment During Planning

When creating board tasks during PLAN mode and specialist agents exist, EVERY task MUST have an `assigned_agent`. This is how sub-agents get used -- they're assigned during planning and delegated to during execution.

| Task Type | Suggested Agent |
|-----------|----------------|
| DB schema, migration, queries | `database-specialist` |
| React component, page, styling | `ui-specialist` |
| Security review, code quality | `code-reviewer` |
| Tests, type-check, validation | `test-runner` |
| CI/CD, deployment | `deployment` |
| Auth flow, sessions, JWT | `auth-specialist` |
| Payments, billing, subscriptions | `subscription-specialist` |

**During EXECUTE**: Delegate each task to its `assigned_agent` -- the main agent orchestrates, specialists execute.

## Session Lifecycle

### Starting a Session
1. Call `board_get_projects` to see active projects
2. **Match work to the correct project** -- don't dump everything into one project
3. Call `board_create_session` with the relevant `project_id`
   - This auto-abandons stale sessions and returns handoff context
   - Read the handoff carefully -- it tells you what the last session accomplished
4. Review active tasks via the handoff response or `board_get_tasks`

### During a Session

**RESEARCH mode -- log observations (trajectory recall):**
- Any novel observation -- even tangential to the current task -- should be logged via `board_log_activity(action: "commented")` with details describing what you found
- Don't filter for relevance; filter for novelty. If you noticed something you didn't know before, log it
- This creates a "trajectory buffer" that survives compaction. The next session can see what you noticed even if you didn't act on it
- Without this, observations that don't become tasks are lost forever when context compacts

**PLAN mode -- create tasks early:**
- When an implementation checklist is defined, create all tasks on the board immediately with status `todo`
- This ensures the full plan survives even if the session crashes before execution

**EXECUTE mode -- track progress:**
- Move tasks to `in_progress` as work begins, then `done` when complete
- `started_at` is set automatically when a task first moves to `in_progress`
- Create additional tasks as new work is discovered

**REVIEW mode -- route findings to the board:**
- When reviewing, attach findings to tasks via `board_log_activity` with `task_id`
- Do NOT review only in conversation text -- conversation disappears, board persists
- If review produces action items, create board tasks for them

**All modes:**
- Log notable events (`board_log_activity`) for decisions, blockers, or context future sessions need

### Ending a Session
1. Mark completed tasks as `done`; add `board_log_activity` comments to in-progress tasks explaining what remains
2. Create board tasks for ALL pending next steps -- every follow-up must be a task
3. Call `board_end_session` with:
   - `progress_summary`: What was accomplished (1-3 sentences)
   - `handoff_notes`: Reference task IDs for next steps
   - `context_artifacts`: Files modified, decisions made, blockers

**A session without handoff notes is a session whose context is lost forever.**

**Proactive ending:** If you sense the conversation is getting long, call `board_end_session` immediately -- even a partial handoff is infinitely better than an abandoned session.

## Task Status Flow

```
backlog -> todo -> in_progress -> review -> done
                       |
                    blocked
```

## Priority Levels

- **critical**: Blocking other work
- **high**: Important, should be next
- **medium**: Standard priority (default)
- **low**: Nice to have

## Board Hygiene

**Manual (every session):** At session start, scan open tasks for anything obviously stale or irrelevant and close it. This is a quick sanity check, not a deep audit.

**Automated (recommended):** Schedule a daily board audit using whatever scheduler you have (cron, n8n, GitHub Actions, Cloud Scheduler, etc.). This keeps your board accurate — not just small.

The daily audit should check for:
1. **Duplicates** -- tasks describing the same work, often created across separate sessions
2. **Stale tasks** -- `todo` or `backlog` items with no recent activity that are no longer relevant
3. **Orphaned in-progress** -- tasks stuck in `in_progress` with no session activity (crashed session, forgot to close)
4. **Completed but not marked** -- work that was done but the task status never got updated
5. **Digest** -- post a summary of what was cleaned and what's still active (Discord, Slack, email, etc.)

- **When**: Daily, before your work day starts (e.g., 5:30 AM local time)
- **Keep the manual check too**: The session-start scan catches anything the daily job missed

## Query Best Practices

- **Mid-session checks**: Always filter -- `board_get_tasks(project_id, status='in_progress')` or `status='todo'`
- **Never pass `include_done: true`** unless specifically auditing completed work
- **Full audit only**: Omit status filter only when reviewing the complete task landscape

## Tool Reference

| Tool | When to Use |
|------|-------------|
| `board_get_projects` | Start of session, find project IDs |
| `board_create_project` | New major initiative |
| `board_get_tasks` | Check current task state (always filter by status) |
| `board_create_task` | Breaking work into trackable units |
| `board_update_task` | Status changes, priority changes, agent assignment |
| `board_create_session` | **Always** at session start |
| `board_end_session` | **Always** before session ends |
| `board_get_handoff` | Check previous session context mid-session |
| `board_log_activity` | Decisions, blockers, review findings, notable events |
````

### Step 4: Verify the Board Works

Start a new Claude Code session (or restart the current one so MCP tools load) and call `board_get_projects`. If it returns an empty array `[]`, the board is live.

Then create the user's first project:
- Call `board_create_project` with the project name from Phase 1
- Save the returned project ID -- it goes in the CLAUDE.md and the agent-board.md rule file

---

## PHASE 5: Set Up Hooks

Hooks are shell scripts that Claude Code runs automatically in response to events. They enforce discipline without requiring you to remember to do things manually. Create these four hook scripts:

### File: `.claude/hooks/block-todowrite.sh`

This prevents the agent from using the ephemeral TodoWrite tool (which dies when the session ends) and redirects it to use persistent board tasks instead.

```bash
#!/bin/bash
# Block TodoWrite -- use board_create_task instead
# Hook event: PreToolUse, matcher: tool_name = TodoWrite

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [ "$TOOL_NAME" = "TodoWrite" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"TodoWrite is disabled. Use board_create_task instead -- board tasks persist across sessions while TodoWrite dies with this session. Call board_get_projects to find the right project, or create a new one with board_create_project."}}'
  exit 0
fi

exit 0
```

### File: `.claude/hooks/session-handoff.sh`

This reminds the agent to create a board session at startup (and urgently after context compaction).

```bash
#!/bin/bash
# Inject board context reminder on session start
# Hook event: SessionStart (all sources: startup, resume, compact)

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('source','startup'))" 2>/dev/null)

if [ "$SOURCE" = "compact" ]; then
  cat << 'REMINDER'
CRITICAL -- CONTEXT WAS COMPACTED. Your board session ID is LOST.
You MUST call board_create_session IMMEDIATELY before doing ANY other work.
Then call board_get_tasks to see what you were working on.
Do NOT proceed with any other actions until the board session is re-established.
REMINDER
else
  cat << 'REMINDER'
BOARD REMINDER: Call board_create_session at the start of any substantive work session.
Read the handoff notes -- they contain what the last session accomplished and what's next.
Track all work on the Vibe Board. Use board_create_task, NOT TodoWrite.
REMINDER
fi

exit 0
```

### File: `.claude/hooks/post-compact-recovery.sh`

A second safety net for context compaction (the #1 failure mode for board continuity).

```bash
#!/bin/bash
# Post-compaction board recovery
# Hook event: PostCompact

cat << 'RECOVERY'
CONTEXT COMPACTED -- BOARD SESSION LOST.
Your previous board session ID no longer exists in context.
IMMEDIATELY call board_create_session before any other work.
This is the #1 failure mode across all sessions -- do not skip this step.
RECOVERY

exit 0
```

### File: `.claude/hooks/review-gate.sh`

This intercepts `git commit` commands and blocks them unless REVIEW mode was completed. The agent must confirm reviews happened and ask the user to approve the commit. This is the enforcement mechanism for the "no commit without review" rule.

```bash
#!/bin/bash
# Review gate -- block git commit unless REVIEW was done
# Hook event: PreToolUse, matcher: Bash
# Only fires on git commit commands, passes through everything else

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Only intercept git commit commands
if echo "$COMMAND" | grep -qE '^\s*git\s+commit'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"REVIEW GATE -- You cannot commit without completing REVIEW mode first. Before committing:\n1. Did you run REVIEW after PLAN? (validate task assignments, dependencies, completeness)\n2. Did you run REVIEW after EXECUTE? (invoke code-reviewer + test-runner + relevant specialists)\n3. Are all review findings logged to the board?\n\nIf BOTH reviews are done and findings are on the board, tell the user the review gate fired and ask them to approve the commit. Do NOT bypass this by rephrasing the command."}}'
  exit 0
fi

exit 0
```

### File: `.claude/hooks/stop-compliance-check.sh`

This runs when the agent tries to stop, ensuring it hasn't forgotten to create a board session, log tasks, or write handoff notes.

```bash
#!/bin/bash
# Compliance check before agent stops
# Hook event: Stop

INPUT=$(cat)

# Check if stop_hook_active is true to prevent infinite loops
ACTIVE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null)

if [ "$ACTIVE" = "True" ]; then
  exit 0
fi

# Inject a compliance reminder -- the agent will self-check
cat << 'CHECK'
STOP COMPLIANCE CHECK -- Before finishing, verify:
1. Did you call board_create_session at the start? If not, do it now.
2. Did you create board tasks for all work done? If not, create them now.
3. If you wrote 15+ lines of code, did you invoke code-reviewer (if it exists)? If not, do it now.
4. Did you invoke test-runner before declaring complete (if it exists)? If not, do it now.
5. Are there pending next steps? Create board tasks for them now.
6. Call board_end_session with handoff notes before finishing.
If ALL items are satisfied, you may stop. If ANY are not, address them first.
CHECK

echo '{"decision":"block","reason":"Compliance check: verify board tasks and handoff before stopping."}'
exit 0
```

**Make all hook scripts executable:**
```bash
chmod +x .claude/hooks/*.sh
```

---

## PHASE 6: Set Up Permissions & Safety Guardrails

Create `.claude/settings.json` with hooks configuration AND permissions based on the user's answer to question 6. This file is checked into git so it applies to everyone on the project.

### Why `Bash(*)` instead of individual command patterns

The old approach listed 50+ individual patterns (`Bash(ls *)`, `Bash(echo *)`, `Bash(git *)`, etc.). This caused constant permission prompts for compound shell commands -- pipes, `&&` chains, subshells `$(...)`, and `for` loops all failed to match simple prefix patterns. The `Bash(*)` catch-all with a deny list is simpler, eliminates false prompts, and is just as safe because **deny rules always take precedence over allow rules**.

**If Yes** (recommended):
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-handoff.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "TodoWrite",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-todowrite.sh",
            "timeout": 5000
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/review-gate.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-compact-recovery.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop-compliance-check.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Bash(*)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf ~*)",
      "Bash(rm -rf .)",
      "Bash(git push --force*)",
      "Bash(git push * --force*)",
      "Bash(git reset --hard*)",
      "Bash(git clean -fd*)",
      "Bash(git branch -D main*)",
      "Bash(git branch -D dev*)",
      "Bash(dropdb *)",
      "Bash(*DROP DATABASE*)",
      "Bash(*DROP SCHEMA*)",
      "Bash(*TRUNCATE*CASCADE*)",
      "Bash(gh repo delete*)"
    ]
  }
}
```

**If No** (granular control): Use `"defaultMode": "default"`, `"allow": []`, `"deny": []` (still include the hooks section -- those are separate from permissions). The user will be prompted for every Bash command and can approve them individually, which auto-adds patterns to the allow list over time.

**After creating, explain:**
- **Hooks**: These run automatically. You'll never need to think about them -- they enforce board discipline and safety checks behind the scenes.
- **`Bash(*)`**: Auto-approves all shell commands. This is safe because the deny list blocks the truly dangerous operations, and deny rules always override allow rules.
- **deny list**: Blocks destructive commands even if they match `Bash(*)`. Add platform-specific dangers as needed (e.g., `"Bash(gcloud projects delete*)"`, `"Bash(aws * delete-*)"`)
- You can always edit `.claude/settings.json` later to adjust

**Common deny list additions** (add based on your platform):

| Platform | Commands to deny |
|----------|-----------------|
| Cloud (GCP) | `gcloud projects delete*`, `gcloud compute instances delete*` |
| Cloud (AWS) | `aws * delete-*`, `aws s3 rb *` |
| Kubernetes | `kubectl delete namespace*` |
| Docker | `docker system prune -a*` |

**Common non-Bash allow entries** (add to the allow list based on your stack):

| Type | Pattern | Purpose |
|------|---------|---------|
| MCP tools | `mcp__<server>__*` | Auto-approve all tools from an MCP server |
| File reads | `Read(/Users/yourname/**)` | Auto-approve reads in your home directory |
| Web access | `WebFetch(*)` | Auto-approve web fetches |
| Search | `WebSearch` | Auto-approve web searches |

---

## PHASE 7: Write CLAUDE.md

Create `CLAUDE.md` in the project root using the user's answers from Phase 1. Fill in all the bracketed sections:

````markdown
# CLAUDE.md

This file provides core instructions for Claude Code working in this repository.
Modular rules are in `.claude/rules/` (auto-loaded every session).
Hook scripts in `.claude/hooks/` enforce board discipline and safety checks automatically.

## Project Identity

**[PROJECT NAME]** -- [ONE-LINE DESCRIPTION]

## Tech Stack

- **Frontend**: [FRONTEND FRAMEWORK + LANGUAGE]
- **Backend**: [BACKEND FRAMEWORK]
- **Database**: [DATABASE]
- **Auth**: [AUTH PROVIDER]
- **Payments**: [PAYMENT PROVIDER or "None"]
- **Infrastructure**: [HOSTING/DEPLOY TARGET]

## Core Constraints

<!-- Fill these in based on the user's tech stack. Examples below. -->
<!-- Delete examples that don't apply and add project-specific ones. -->

- Always use TypeScript strict mode
- Never expose API keys in frontend code
- All database queries must use parameterized queries or ORM methods
- Test before committing

## Vibe Board

Persistent task tracking across sessions via Firebase Firestore MCP tools (`board_*`).
**Mandatory for every substantive session** -- see `.claude/rules/agent-board.md`.

**Use `board_create_task` instead of TodoWrite.** TodoWrite is blocked by hooks --
board tasks persist forever and enable cross-session continuity.

Active project: "[PROJECT NAME]" (`[PROJECT_ID from Phase 4 Step 4]`)

## Hooks (Automated Guardrails)

Five hooks enforce discipline automatically (configured in `.claude/settings.json`):
- **SessionStart**: Reminds agent to create board session; critical alert after compaction
- **PreToolUse (TodoWrite)**: Blocks TodoWrite, redirects to board_create_task
- **PreToolUse (Bash)**: Review gate -- blocks `git commit` unless REVIEW mode was completed
- **PostCompact**: Forces board session re-establishment after context compaction
- **Stop**: Compliance check before finishing (board tasks, handoff notes, code review)

## Compaction Preservation

When compacting context, always preserve in the summary:
- Current RIPER mode and phase of work (e.g., "executing step 3 of 5")
- List of all files modified in this session
- Current git branch and whether there are uncommitted changes
- Any failing tests or build errors and their current status
- Active board project ID and session ID
- Test or build commands that were run and their pass/fail results

## Key Architectural Patterns

<!-- Ask the user if they have established patterns, or leave this section -->
<!-- for them to fill in as the project evolves. Examples: -->

<!-- - **Routing**: File-based routing with Next.js App Router -->
<!-- - **State**: React Query for server state, Zustand for client state -->
<!-- - **API**: RESTful endpoints under /api/ -->

## Documentation

**Hub**: [docs/README.md](docs/README.md)
````

---

## PHASE 8: Create docs/README.md

````markdown
# Documentation Index

## Project Docs

<!-- Add links to documentation as the project grows -->

## Rules Reference

- [RIPER Modes](.claude/rules/riper-cat.md) -- Workflow mode system
- [Code Quality](.claude/rules/code-quality.md) -- Review checklist
- [Git Workflow](.claude/rules/git-workflow.md) -- Commit and branch conventions
- [Documentation](.claude/rules/documentation.md) -- Doc management rules
- [Vibe Board](.claude/rules/agent-board.md) -- Persistent task tracking protocol

## Hooks Reference

- [Session Handoff](.claude/hooks/session-handoff.sh) -- Board session reminder on startup
- [Block TodoWrite](.claude/hooks/block-todowrite.sh) -- Redirects to persistent board tasks
- [Post-Compact Recovery](.claude/hooks/post-compact-recovery.sh) -- Board recovery after compaction
- [Review Gate](.claude/hooks/review-gate.sh) -- Blocks git commit unless REVIEW was completed
- [Stop Compliance](.claude/hooks/stop-compliance-check.sh) -- Pre-stop verification
````

---

## PHASE 9: Install Code Intelligence Plugins

Code intelligence plugins give Claude automatic type error detection after every file edit and precise code navigation (jump to definition, find references). They connect Claude to Language Server Protocol (LSP) servers -- the same technology that powers VS Code's intellisense.

**Why this matters:** Without these plugins, Claude must run `tsc --noEmit` or a linter manually to catch type errors. With them, errors surface immediately after each edit and get fixed in the same turn.

### Step 1: Detect Project Languages

Scan the project to determine which languages are used:

```bash
# Check for TypeScript/JavaScript
ls tsconfig.json package.json 2>/dev/null

# Check for Python
ls requirements.txt pyproject.toml setup.py Pipfile 2>/dev/null
find . -name "*.py" -maxdepth 3 | head -5

# Check for Go
ls go.mod 2>/dev/null

# Check for Rust
ls Cargo.toml 2>/dev/null

# Check for other languages as needed
```

### Step 2: Install Relevant Plugins

Based on what you find, tell the user which plugins to install. The user must run these commands in a **terminal** (not inside Claude Code's VSCode extension):

| Language | Install Command | Binary Required |
|----------|----------------|-----------------|
| TypeScript/JavaScript | `claude plugin install typescript-lsp@claude-plugins-official` | `typescript-language-server` |
| Python | `claude plugin install pyright-lsp@claude-plugins-official` | `pyright-langserver` |
| Go | `claude plugin install gopls-lsp@claude-plugins-official` | `gopls` |
| Rust | `claude plugin install rust-analyzer-lsp@claude-plugins-official` | `rust-analyzer` |
| C/C++ | `claude plugin install clangd-lsp@claude-plugins-official` | `clangd` |
| Java | `claude plugin install jdtls-lsp@claude-plugins-official` | `jdtls` |
| Swift | `claude plugin install swift-lsp@claude-plugins-official` | `sourcekit-lsp` |
| PHP | `claude plugin install php-lsp@claude-plugins-official` | `intelephense` |
| Kotlin | `claude plugin install kotlin-lsp@claude-plugins-official` | `kotlin-language-server` |
| Lua | `claude plugin install lua-lsp@claude-plugins-official` | `lua-language-server` |
| C# | `claude plugin install csharp-lsp@claude-plugins-official` | `csharp-ls` |

**Only suggest plugins for languages actually present in the project.** Don't install all of them.

### Step 3: Verify Binary Availability

The plugins require the language server binary to be installed on the user's system. Check if they're available:

```bash
# For TypeScript
which typescript-language-server || echo "Install with: npm install -g typescript-language-server typescript"

# For Python
which pyright-langserver || echo "Install with: npm install -g pyright"
```

If binaries are missing, tell the user how to install them. After installing, the user should run `/reload-plugins` inside Claude Code (or restart the session).

### What This Enables

Once installed, Claude gains two capabilities:
- **Automatic diagnostics**: After every file edit, the language server reports type errors, missing imports, and syntax issues. Claude sees and fixes these in the same turn without needing to run a compiler.
- **Code navigation**: Jump to definitions, find references, get type info -- more precise than grep-based search.

Reference: https://code.claude.com/docs/en/discover-plugins#code-intelligence

---

## PHASE 10: Install Starter Skills

Skills are on-demand knowledge files invoked with `/skill-name`. They live in `.claude/skills/<skill-name>/SKILL.md` and are NOT auto-loaded — they activate only when explicitly called. This keeps context lean while giving you structured protocols on demand.

**When to use skills vs rules:**
- **Rules** (`.claude/rules/`): Auto-loaded every session. For constraints, patterns, and always-on behavior.
- **Skills** (`.claude/skills/`): On-demand. For complex workflows, step-by-step protocols, or specialized knowledge that would bloat context if always loaded.

### Step 1: Create the Skills Directory

```bash
mkdir -p .claude/skills/_shared
```

The `_shared/` subdirectory holds reference material cited by multiple skills (schema guides, checklists). Individual skills live in their own subdirectories.

### Step 2: Install the Starter Set

These four skills wire the RIPER-CAT workflow from Phase 3 into structured protocols + give you an on-demand way to re-run this bootstrap:

| Skill | Purpose | Triggered by |
|-------|---------|--------------|
| `bootstrap` | Runs THIS bootstrap protocol interactively (fresh setup or upgrade) | `/bootstrap` |
| `plan` | Structured PLAN mode with board task creation and agent assignment | `/plan` or "Enter P" |
| `review` | REVIEW mode with sub-agent invocation (auto-detects post-plan vs post-execute) | `/review` or "Enter RE" |
| `go` | Full RIPER cycle in one command (RESEARCH → PLAN → REVIEW → EXECUTE → REVIEW) | `/go <task>` |

**If you copied this bootstrap from a distribution package**, ready-made versions of these skills are in the accompanying `skills/` directory alongside this file. Copy them into `.claude/skills/` (paths assume you're running commands from your project root and the distribution package lives at `<project-root>/docs/ve-kit/`; adjust the source path if you placed the package elsewhere):

```bash
# Paths assume: CWD = project root, package = docs/ve-kit/
PKG=docs/ve-kit
cp -r "$PKG/skills/bootstrap" .claude/skills/
cp -r "$PKG/skills/plan"      .claude/skills/
cp -r "$PKG/skills/review"    .claude/skills/
cp -r "$PKG/skills/go"        .claude/skills/
cp -r "$PKG/skills/_shared"   .claude/skills/
```

Otherwise create them yourself following the format below.

### Step 3: Skill File Format

Every skill is a directory containing `SKILL.md` with YAML frontmatter:

````markdown
---
name: plan
description: Use when entering PLAN mode or when the user says "Enter P". Creates structured implementation plans with Vibe Board tasks and specialist agent assignments for each checklist item.
user-invocable: true
disable-model-invocation: false
---

# PLAN Mode Protocol

## Step 1: Research & Design
Analyze the task and create an implementation specification...

## Step 2: Create Board Tasks
For EACH item in your checklist, call `board_create_task` with...
````

**Frontmatter fields that matter:**
- `name` — matches the directory name; invoked as `/name`
- `description` — specific, trigger-oriented. Claude reads this to decide when the skill applies.
- `user-invocable: true` — user can type `/name` to trigger
- `disable-model-invocation: true` — skill only runs when user types `/name` (not auto-invoked by Claude). Set this on audit skills to prevent accidental runs.

### Step 4: Install the `/review-*` Audit Family (Recommended)

As the `.claude/` tree grows, you'll accumulate drift: stale agent descriptions, oversized docs, deprecated patterns. A dedicated family of review skills — each scoped to one artifact type — makes periodic audits routine:

| Skill | Audits |
|-------|--------|
| `/review-agents` | `.claude/agents/*.md` frontmatter, staleness, model tier |
| `/review-skills` | `.claude/skills/*/SKILL.md` frontmatter, progressive-disclose, trigger clarity |
| `/review-rules` | `CLAUDE.md` + `.claude/rules/*.md` (size, cross-refs, rule-hook alignment) |
| `/review-docs` | `docs/**/*.md` (broken links, staleness, index currency) |
| `/review-memory` | per-project memory dir (index currency, type correctness) |
| `/review-board` | Vibe Board itself (stale in-progress, orphans, abandoned projects) |
| `/review-security` | `.claude/` config security (secrets, permissions, hook fail-closed, agent tool grants) |
| `/review-all` | orchestrator that runs all review-* skills sequentially |

Each review skill sets `disable-model-invocation: true` + `user-invocable: true` (audits run on-demand, never auto-invoked). **Findings write to the Vibe Board as severity-tiered subtasks — never as prose.** Run quarterly or after major upgrades.

If the distribution package includes these skills under `skills/review-*`, copy them the same way:

```bash
PKG=docs/ve-kit
for s in review-agents review-skills review-rules review-docs review-memory review-board review-security review-all; do
  cp -r "$PKG/skills/$s" .claude/skills/
done
```

### Step 5: Verify Skills Are Loaded

Start a fresh Claude Code session. Type `/` — you should see the installed skills in the autocomplete. Typing `/plan` should invoke the plan skill. If skills don't appear, check:

1. The skill directory structure (`skills/<name>/SKILL.md` — the filename must be exactly `SKILL.md`)
2. The frontmatter is valid YAML (no tab characters, colons followed by space)
3. `user-invocable: true` is set in frontmatter

### What This Enables

Once installed:
- `/plan` creates every checklist item as a board task with an `assigned_agent` — no forgotten steps
- `/review` invokes code-reviewer + test-runner automatically after EXECUTE — no skipped review gates
- `/go` runs the full RIPER cycle hands-off for well-scoped tasks — one command, auto-advance on REVIEW PASS
- `/review-all` runs a full configuration audit and files findings to the board — quarterly hygiene without manual scanning

---

## PHASE 11: Self-Verify Everything

Run these checks yourself. Do NOT just tell the user to verify -- actually do each check and report results.

### File Structure Check
1. List `.claude/rules/` -- confirm these files exist:
   - `riper-cat.md`
   - `code-quality.md`
   - `documentation.md`
   - `git-workflow.md`
   - `agent-board.md`
2. List `.claude/hooks/` -- confirm these files exist and are executable:
   - `block-todowrite.sh`
   - `session-handoff.sh`
   - `post-compact-recovery.sh`
   - `review-gate.sh`
   - `stop-compliance-check.sh`
3. Confirm `CLAUDE.md` exists in the project root and contains the user's project name (not placeholder brackets)
4. Confirm `docs/README.md` exists
5. Confirm `.claude/settings.json` exists with both hooks and permissions configured
6. Confirm `.mcp.json` exists and points to the built MCP server
7. Confirm `.claude/settings.local.json` exists with board tool permissions

### Vibe Board Check
8. If you have access to the `board_get_projects` tool, call it. Confirm:
   - It returns successfully (connection works)
   - The user's project exists in the list
   - Report the project ID to the user so they can reference it later

### Build Check
9. Check that `mcp-vibe-board/dist/index.js` exists (the MCP server was built)
10. If it doesn't exist, run `cd mcp-vibe-board && npm run build`

### Hook Check
11. Test that hook scripts run without errors:
    ```bash
    echo '{"source":"startup"}' | .claude/hooks/session-handoff.sh
    echo '{"tool_name":"TodoWrite"}' | .claude/hooks/block-todowrite.sh
    echo '{}' | .claude/hooks/post-compact-recovery.sh
    echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | .claude/hooks/review-gate.sh
    echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | .claude/hooks/review-gate.sh
    echo '{"stop_hook_active":true}' | .claude/hooks/stop-compliance-check.sh
    ```

### Git Check
12. Check if `.gitignore` includes entries for:
    - Service account key files (e.g., `vibe-board-key.json`) -- if stored inside the project
    - `mcp-vibe-board/node_modules/` and `mcp-vibe-board/dist/`
    - If missing, add appropriate entries to `.gitignore`

### Skills Check (if Phase 10 ran)
13. List `.claude/skills/` -- confirm starter skills installed (if Phase 10 was completed):
    - `bootstrap/SKILL.md`
    - `plan/SKILL.md`
    - `review/SKILL.md`
    - `go/SKILL.md`
    - Optionally: `review-*/SKILL.md` audit family
14. For each `SKILL.md`, confirm frontmatter is valid YAML with `name`, `description`, and `user-invocable: true`.

### Report Results
Report a pass/fail summary. If anything failed, fix it before moving on.

### Teach the User
After everything passes, tell the user:

**Your setup is complete. Here's how to use it:**

- Say **"Enter R"** to start researching any topic (I won't jump to code)
- Say **"Enter I"** to brainstorm approaches with pros/cons
- Say **"Enter P"** to plan a feature (I'll create a checklist and board tasks before coding)
- Say **"Enter E"** to execute an approved plan
- Say **"Enter RE"** to review what was built
- Say **"Enter C -commit"** to commit completed work
- Say **"Enter C -push"** to commit and push to main

**Every session, I will automatically:**
- Start a Vibe Board session (so nothing gets lost)
- Track all tasks persistently (survives when this conversation ends)
- Hand off context to the next session when we're done
- Block myself from using ephemeral task tracking (TodoWrite -> board tasks)
- Block git commits until REVIEW mode is completed (catches bugs before they're committed)
- Run a compliance check before finishing (did I track everything? write handoff notes?)

**The `.claude/rules/` folder auto-loads into every session -- you never need to paste instructions again.**
**The `.claude/hooks/` folder enforces discipline automatically -- no willpower required.**

---

## REFERENCE: When to Use What

Two decision frameworks for choosing the right Claude Code feature.

### Configuration: CLAUDE.md vs Hooks vs MCP

| Feature | Used when... | Examples |
|---------|-------------|----------|
| **CLAUDE.md** | Project-related context and instructions to prevent repeating instructions | "use pnpm, not npm", "Run tests with pytest", "Follow PEP8" |
| **Hooks** | Deterministic automation that must always run at specific lifecycle events | Auto-format on save, run tests after edits, send notifications on completion |
| **MCP** | Access to external tools, databases, and APIs through a standardized protocol | Query database, fetch from GitHub, send Slack messages, access Google Drive |

**Rule of thumb**: If it's *context/instructions* → CLAUDE.md or rules. If it *must happen every time automatically* → Hook. If it *talks to an external system* → MCP.

### Parallelism: Parallel Claude vs Subagents vs Agent Teams

| Feature | Used when... | Examples |
|---------|-------------|----------|
| **Parallel Claude** | Working on multiple unrelated tasks at once, each in its own terminal and worktree | Fix a bug in one worktree while building a feature in another |
| **Subagents** | Delegating focused subtasks from the main session with isolated context | Spawn a reviewer or researcher that returns a summary |
| **Agent Teams** | Splitting a large task into independent workstreams that coordinate | Multi-service refactor where each agent owns a slice and syncs progress |

**Rule of thumb**: If tasks are *unrelated* → Parallel Claude. If they're *focused subtasks of the current work* → Subagents. If they're *coordinated parts of one big task* → Agent Teams.

---

## REFERENCE: Parallel Claude (for later)

Run multiple Claude Code instances simultaneously for truly independent work:

```bash
# Option 1: Separate terminals, same repo (file conflict risk)
# Terminal 1: claude  (working on frontend)
# Terminal 2: claude  (working on backend)

# Option 2: Git worktrees (recommended -- no file conflicts)
claude --worktree  # Creates an isolated working directory from the same repo
```

**Git worktrees** create isolated directories that share the same `.git` history. Each Claude instance operates on a different worktree, so there's no risk of two agents editing the same file.

**When to use**:
- Fixing a bug while building an unrelated feature
- Running long test suites in one terminal while coding in another
- Working on frontend and backend simultaneously when changes are independent

**When NOT to use** (use subagents or agent teams instead):
- Tasks that need to share context or coordinate
- Tasks where one depends on the output of another
- Simple research or code review (subagents are lighter weight)

---

## REFERENCE: Agent Architecture (for later)

Once the user is comfortable with RIPER and the basics, they can add specialist agents. Agents live in `.claude/agents/` as markdown files:

````markdown
---
name: my-specialist
description: Use this agent when working on [domain] features
model: sonnet
memory: project
---

# My Specialist Agent

You are an expert in [domain]. Your responsibilities include:
- [specific task 1]
- [specific task 2]

## Key files in the project
- `src/features/my-domain/` -- main feature code

## Patterns to follow
- [pattern 1]
- [pattern 2]
````

**Agent frontmatter options:**

| Field | Purpose | Example |
|-------|---------|---------|
| `name` | Agent identifier (required) | `code-reviewer` |
| `description` | When to use this agent (required) | `Use for security and quality review` |
| `model` | Which Claude model to use | `sonnet`, `opus`, `haiku` |
| `memory` | Persistent memory scope — agent remembers across sessions | `project` (recommended), `user`, or `local` |
| `initialPrompt` | Auto-submitted first prompt before the task begins | `"Run git diff to see what changed."` |
| `effort` | Thinking intensity (low/medium/high/xhigh/max) | `high` for complex analysis; `xhigh` for orchestrators, security review, blast-radius infra (Opus 4.7+ only) |
| `disallowedTools` | Deny-list tools for this agent (defense-in-depth for review/consolidation agents) | `[Write, Edit, NotebookEdit]` for read-only reviewers |
| `maxTurns` | Cap on back-and-forth turns | `10` (use sparingly — can cut agents off mid-work) |
| `isolation` | Run in isolated worktree | `worktree` (prevents file conflicts with main session) |

**Recommendations:**
- **Always add `memory: project`** — agents learn and remember patterns across sessions at zero cost
- **Add `initialPrompt` selectively** — only for agents with a universal first step (e.g., code-reviewer always checks git diff, test-runner always runs type-check)
- **Avoid `effort: low` and `maxTurns`** unless you have a specific agent that's consistently over-thinking simple tasks. Most agents benefit from full thinking power, especially in complex codebases.

**Recommended starter agents** (create these when the user needs them):

| Agent | Purpose | When to Create |
|-------|---------|----------------|
| **code-reviewer** | Security, quality, patterns | When codebase has 10+ files |
| **test-runner** | Run tests, validate changes | When test suite exists |
| **database-specialist** | Schema, migrations, queries | When using a database |
| **ui-specialist** | Component design, accessibility | When building UI |
| **deployment** | CI/CD, hosting, deploys | When deploying to production |
| **auth-specialist** | Auth flows, sessions, security | When implementing authentication |
| **subscription-specialist** | Payments, billing, webhooks | When using Stripe or similar |

The main agent can invoke these via the Task tool. When agents exist, PLAN mode should assign tasks to them (`assigned_agent` field), and EXECUTE mode should delegate to them.

**Mandatory invocation rules** (add to CLAUDE.md as agents are created):

| Condition | Required Agent |
|-----------|---------------|
| After writing 15+ lines of code | `code-reviewer` |
| Before declaring task complete | `test-runner` |
| Any database schema change | `database-specialist` |
| Any UI component modification | `ui-specialist` |
| Deploying to any environment | `deployment` |

**Delegated hierarchy** (for mature projects with many agents):
```
User (direction, decisions, approvals)
  |
Main Agent (routing, prioritization, user communication)
  |
Specialists (domain experts who do the actual work)
```

The main agent's context should contain summaries, not raw specialist output. Instruct specialists to write detailed findings to the Vibe Board and return only lean summaries.

**Growth agents** (add as the project matures):

| Agent | Purpose | When to Create |
|-------|---------|----------------|
| **automation-architect** | Audit what's automated, identify gaps, choose the right tool for new recurring tasks | When you have 5+ automated processes (CI/CD triggers, cron jobs, workflows, scheduled tasks) |
| **project-coordinator** | Decompose complex multi-domain tasks, delegate to specialists, drive execution | When tasks regularly span 3+ specialist domains |
| **docs-manager** | Maintain documentation, audit for staleness, keep indexes current | When docs/ has 10+ files and documentation drift becomes a problem |

The automation-architect doesn't build automations -- it surveys the landscape and delegates to the right builder (deployment agent for CI/CD, n8n agents for workflows, etc.). Create it when you find yourself manually tracking "what runs on a schedule" or asking "should this be a cron job or a workflow?"

---

## REFERENCE: Optional Companion MCPs

The Vibe Board MCP (Phase 4) is the only required MCP server. Several optional companions extend Claude Code's reach into other systems — install them only if your project needs them:

### Google Workspace (ve-gws)

**[HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws)** — **VE Google Workspace MCP**. Gmail, Drive, Docs, Calendar, Sheets, Slides, Forms, Tasks, Chat, Contacts, Apps Script. Python fork of [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) with 28 additional authoring tools (deeper Slides editing, markdown-to-Docs, smart chips, Sheets data validation, recursive folder copy, revision history).

When to install it:
- You need Claude to read/write Gmail, create Drive files, edit Docs, or manage Calendar from inside Claude Code
- You're building workflows that cross the coding context into Google Workspace (e.g., drafting emails from code, exporting reports to Sheets)

Setup is standard MCP configuration — the `ve-gws` repo README covers OAuth, service account setup, and the `.mcp.json` entry. Pair it with the broader ve-* framework: this bootstrap + Vibe Board + optional `ve-worker` Docker agent.

### Other companions

Community MCP servers exist for Stripe, Slack, GitHub (beyond the CLI), n8n, Listmonk, Firebase, and many other services. Install only what your project actually uses — each MCP adds startup time and tool-selection complexity for Claude.

---

## REFERENCE: Team Playbooks (advanced, for later)

Agent teams coordinate multiple independent Claude Code sessions working in parallel. This is useful for complex tasks crossing 3+ domains. Teams need the experimental feature flag enabled:

Add to your existing `.claude/settings.json` (merge with the hooks + permissions config from Phase 6):
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Common team patterns:
- **Full Feature Ship**: Backend + Frontend + QA working in parallel
- **Security Audit**: Auth reviewer + Data reviewer + Code reviewer in parallel
- **Incident Response**: Infra investigator + Service investigator + Fix & Deploy

Each team has a lead (project-coordinator) who creates board tasks and delegates. Findings route through the Vibe Board -- specialists write detailed results there and return lean summaries to the lead.

Save this for when the project is complex enough to benefit from it.

---

## Upgrading an Existing Setup

When a user says **"upgrade @bootstrap.md"** (or points you at this file and asks to upgrade), follow this protocol. Do NOT run the normal Phase 1-10 setup flow -- this section is specifically for existing projects.

### Step 1: Extract Project Context

Before diffing anything, read the user's existing files to learn about their project. This replaces the Phase 1 questionnaire for upgrade users.

**Auto-detect from existing files:**

| Info needed | Where to find it |
|-------------|-----------------|
| Project name | `CLAUDE.md` → "Project Identity" section |
| Tech stack | `CLAUDE.md` → "Tech Stack" section, or `package.json`, `requirements.txt`, `go.mod`, etc. |
| Branch strategy | `.claude/rules/git-workflow.md`, or check `git branch -a` |
| Permission preferences | `.claude/settings.json` → `permissions.allow` / `permissions.deny` |
| GCP/Firebase project | `.mcp.json` → service account path, or `CLAUDE.md` → project IDs |
| Vibe Board status | Check if `.mcp.json` exists and references a `mcp-vibe-board` server |
| Agents | Check if `.claude/agents/` has any `.md` files |

**Ask only for what's missing.** If `CLAUDE.md` doesn't exist or is missing sections, ask the user those specific Phase 1 questions. Don't re-ask things you already know.

### Step 2: Identify Bootstrap-Managed Files

Scan the project for these files. Not all will exist -- that's fine, missing files are gaps to fill.

**Rules** (`.claude/rules/`):
- `riper-cat.md` — RIPER operational modes
- `code-quality.md` — Review checklist and security patterns
- `documentation.md` — Doc management rules
- `git-workflow.md` — Commit and branch conventions
- `agent-board.md` — Vibe Board protocol

**Hooks** (`.claude/hooks/`):
- `block-todowrite.sh` — Redirects TodoWrite to board tasks
- `session-handoff.sh` — Board session reminder on startup/compaction
- `post-compact-recovery.sh` — Board recovery after context compaction
- `review-gate.sh` — Blocks git commit unless REVIEW was completed
- `stop-compliance-check.sh` — Compliance check before agent stops

**Config**:
- `.claude/settings.json` — Hooks configuration + permissions (allow/deny lists)
- `CLAUDE.md` — Project root instructions

**Optional** (only if the user has set these up):
- `.claude/agents/*.md` — Specialist agent definitions
- `.claude/skills/*/SKILL.md` — On-demand skill files
- `.mcp.json` — MCP server configuration (Vibe Board)
- `docs/README.md` — Documentation index

### Step 3: Back Up Everything

Before making ANY changes, create backups of every file that exists:

```bash
# Back up each file with .backup extension
for file in \
  .claude/rules/riper-cat.md \
  .claude/rules/code-quality.md \
  .claude/rules/documentation.md \
  .claude/rules/git-workflow.md \
  .claude/rules/agent-board.md \
  .claude/hooks/block-todowrite.sh \
  .claude/hooks/session-handoff.sh \
  .claude/hooks/post-compact-recovery.sh \
  .claude/hooks/review-gate.sh \
  .claude/hooks/stop-compliance-check.sh \
  .claude/settings.json \
  CLAUDE.md \
  docs/README.md; do
  [ -f "$file" ] && cp "$file" "${file}.backup"
done
```

Also back up any agent files:
```bash
for file in .claude/agents/*.md; do
  [ -f "$file" ] && cp "$file" "${file}.backup"
done
```

**Tell the user**: "I've backed up all existing files with `.backup` extensions. You can restore any file by removing the `.backup` suffix."

### Step 4: Diff and Present Changes

For each bootstrap-managed file, compare what exists against the current bootstrap template. Categorize every difference into one of three buckets:

| Bucket | Meaning | Example |
|--------|---------|---------|
| **New** | File or section doesn't exist yet | Missing `post-compact-recovery.sh` hook |
| **Updated** | Bootstrap template has changed from what's installed | RIPER modes gained TROUBLESHOOT mode |
| **Custom** | User has project-specific content not in the bootstrap | Extra allow-list entries, custom CLAUDE.md sections |

**Present a summary to the user** showing all differences grouped by file. For each difference, explain:
- What changed and why it matters
- Whether it's additive (new content) or a modification (changed content)

**Ask the user which changes to apply.** Offer these as a checklist -- the user can accept all, or pick and choose. Example:

> **Upgrade summary — 7 changes found:**
>
> `.claude/rules/riper-cat.md`:
> 1. Add TROUBLESHOOT mode (MODE 8) — deep root cause analysis mode
> 2. Add auto-transition rule: PLAN → REVIEW after checklist complete
>
> `.claude/settings.json`:
> 3. Add 23 new auto-allow entries (shell keywords, text processing, process management)
> 4. Add `rm *` to allow list (protected by existing deny rules)
>
> `.claude/hooks/` (missing):
> 5. Create `post-compact-recovery.sh` — prevents lost board sessions after compaction
>
> `.claude/agents/*.md` (if agents exist):
> 6. Add `memory: project` to all agents — persistent cross-session learning
> 7. Add `initialPrompt` to code-reviewer and test-runner
>
> **Which changes do you want to apply?** (all / pick by number / skip)

### Step 5: Apply Approved Changes

Apply only what the user approved. For each change:

1. **New files**: Create them from the bootstrap templates, substituting any project-specific values (project name, branch names, project IDs) from the existing `CLAUDE.md` or by asking the user
2. **Updated content**: Merge bootstrap changes into existing files, preserving project-specific customizations (custom CLAUDE.md sections, extra allow-list entries, project-specific rules)
3. **Permission changes**: Merge new allow/deny entries into the existing list -- never remove entries the user added

**Critical rule**: Never delete or overwrite project-specific content. If a user added custom sections to `CLAUDE.md`, extra allow-list entries, or project-specific rules, those MUST be preserved. The upgrade only adds/updates bootstrap-managed content.

### Step 6: Verify and Clean Up

After applying changes:

1. Run the same verification checks from Phase 11 (file existence, hook executability, board connectivity)
2. Report what was changed and what was preserved
3. Tell the user: "Backup files (`.backup`) are still in place. Once you've verified everything works, you can remove them with: `find .claude -name '*.backup' -delete && rm -f CLAUDE.md.backup docs/README.md.backup`"

### Handling Edge Cases

- **No existing setup found**: Fall back to the full Phase 1-10 setup flow. Tell the user: "This looks like a fresh project. I'll run the full setup instead of an upgrade."
- **Vibe Board not set up**: Offer to run Phase 4 (Vibe Board setup) as part of the upgrade
- **Agents exist but have no `memory` field**: Add `memory: project` to all agent frontmatter (universally beneficial, no downside)
- **Context running low mid-upgrade**: Prioritize applying changes already approved. If you can't finish, create a board task listing remaining unapplied changes so the next session can continue
- **User wants to undo**: Tell them to restore from `.backup` files: `for f in $(find . -name '*.backup'); do mv "$f" "${f%.backup}"; done`

---

## Changelog

### 2026-03-28 — Review Gate Hook + Trajectory Recall + Stop Hook Alignment

**Context**: Analysis of [Chroma Context-1 research](https://www.trychroma.com/research/context-1) identified one actionable gap (trajectory recall). Separately, review enforcement was purely instructional — nothing prevented skipping REVIEW before COMMIT. Reviews are where bugs get caught; they need to be enforced, not suggested.

**Changes**:

1. **Review gate hook** (`review-gate.sh`, NEW)
   - PreToolUse hook with Bash matcher that intercepts `git commit` commands
   - Blocks the commit and asks the agent to confirm both REVIEW gates were completed (post-PLAN and post-EXECUTE)
   - Agent must tell the user the review gate fired and get approval — cannot bypass by rephrasing the command
   - Passes through all non-commit Bash commands with zero overhead
   - Wired in `.claude/settings.json` as a second PreToolUse entry (alongside TodoWrite blocker)

2. **Full recommended flow documented** (`riper-cat.md` template, Mode Transitions)
   - Added: `RESEARCH → INNOVATE → PLAN → REVIEW → EXECUTE → REVIEW → COMMIT`
   - Clarified: R and I can be skipped for well-understood tasks; neither REVIEW gate can be skipped

3. **RESEARCH mode — trajectory recall** (`riper-cat.md` template)
   - Added instruction: log novel observations to the board via `board_log_activity(action: "commented")`, even tangential ones
   - Rationale: conversation text is ephemeral; observations not on the board are lost on compaction. The board's activity log now serves as a "trajectory buffer"

4. **Proactive triggers — observation logging** (`agent-board.md` template, triggers table)
   - Added trigger: `Novel observation during RESEARCH (even tangential)` → `board_log_activity(action: "commented")`

5. **RESEARCH mode — session guidance** (`agent-board.md` template, "During a Session" section)
   - Added new `RESEARCH mode — log observations (trajectory recall)` subsection before PLAN mode guidance

6. **Stop compliance hook — test-runner step** (`stop-compliance-check.sh` template)
   - Added step 4: `Did you invoke test-runner before declaring complete (if it exists)?`
   - Now 6 compliance checks (was 5), matching the full production hook

7. **CLAUDE.md template — five hooks** (was four)
   - Updated hooks section to list all five hooks including the review gate

8. **Upgrade section — review-gate.sh** added to bootstrap-managed files list and backup script

### 2026-03-19 — Permissions Overhaul: `Bash(*)` + Deny List

**Context**: The original Bootstrap shipped with 50+ individual `Bash(command *)` allow patterns. This caused constant permission prompts for compound shell commands — pipes (`|`), chains (`&&`), subshells (`$(...)`), and `for` loops all failed to match simple prefix patterns. Every new compound command triggered a prompt, disrupting flow.

**Changes**:

1. **Replaced granular allow list with `Bash(*)`** (`.claude/settings.json` template)
   - Single catch-all `"Bash(*)"` in the allow list replaces 50+ individual patterns
   - Deny list blocks destructive operations: `rm -rf /`, `git push --force`, `DROP DATABASE`, `gh repo delete`, etc.
   - Deny rules always take precedence over allow rules — `Bash(*)` never overrides a deny entry
   - Zero false permission prompts for legitimate compound commands

2. **Added `defaultMode: "acceptEdits"`** (`.claude/settings.json` template)
   - File edits auto-approved alongside bash commands
   - Combined with `Bash(*)`, this eliminates virtually all permission interruptions during normal development

3. **Added explanation section** ("Why `Bash(*)` instead of individual command patterns")
   - Documents the rationale for future upgraders who see the catch-all and wonder if it's safe
   - Explains that deny rules are the safety mechanism, not the allow list

4. **Added platform-specific deny list guidance**
   - Table of recommended deny entries per cloud platform (GCP, AWS, Kubernetes, Docker)
   - Table of common non-Bash allow entries (MCP tools, file reads, web access)

### 2026-03-19 — Hook System + Board Enforcement

**Context**: Agents frequently forgot to create board sessions, use board tasks instead of TodoWrite, or write handoff notes before stopping. This caused cross-session context loss — the #1 productivity killer.

**Changes**:

1. **Four hook scripts** (`.claude/hooks/`)
   - `block-todowrite.sh` (PreToolUse) — denies TodoWrite tool calls, redirects to `board_create_task`
   - `session-handoff.sh` (SessionStart) — injects board reminder on startup; CRITICAL alert when `source=compact` (dual-layer compaction defense)
   - `post-compact-recovery.sh` (PostCompact) — second safety net forcing board session re-establishment after compaction
   - `stop-compliance-check.sh` (Stop) — blocks agent from stopping until board tasks, code review, and handoff notes are verified

2. **Hooks wired in `.claude/settings.json`**
   - All four hooks configured with `$CLAUDE_PROJECT_DIR` relative paths and 5000ms timeouts
   - Hooks are deterministic enforcement — the agent cannot bypass them regardless of instruction drift

3. **Dual compaction defense**
   - `SessionStart` detects `source: "compact"` and fires CRITICAL alert
   - `PostCompact` fires independently as a redundant safety net
   - Both force `board_create_session` before any other work — the #1 failure mode is now covered by two independent hooks

### 2026-03-16 — Initial Bootstrap Release

- RIPER CAT operational modes (8 modes with transition signals)
- Vibe Board MCP server (9 tools, Firestore-backed)
- Agent board rules (proactive triggers, session lifecycle, task tracking)
- Code quality rules (security, performance, TypeScript, React checklists)
- Git workflow rules (conventional commits, branch strategy)
- Documentation rules (search before creating, hub index)
- Phase 4: Complete Vibe Board setup guide with Firestore indexes
- Phase 9: Code intelligence plugin installation
- Phase 10: Install starter skills (`plan`, `review`, `go`, `review-*` audit family)
- Phase 11: Self-verification checklist
- Upgrade path for existing setups (backup, diff, selective apply)

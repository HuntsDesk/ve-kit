# VE Worker: Autonomous Coding with Claude Code + Docker

A system for running Claude Code autonomously in Docker containers, processing tasks from a persistent board, with quality gates, cross-model review, and human-in-the-loop oversight.

## What It Does

You give it a project and a batch size. It:
1. Creates a git branch for the batch
2. Reads accumulated lessons from previous batches (self-improvement loop)
3. Scans the task board for READY tasks in that project
4. Verifies each task isn't already implemented before coding
5. Picks the highest priority task, researches, makes changes, type-checks, commits
6. Every 3 tasks: commits first, then invokes a code-reviewer sub-agent
7. At batch end: audits docs/agents for staleness, appends new lessons, ends board session
8. You review the diffs with specialist agents + cross-model review, fix findings, merge

## Architecture

```
You (direction + decisions)
  │
  ├── Monitor Claude (interactive session)
  │     ├── Starts/stops Docker workers
  │     ├── Monitors via docker logs + git log + board
  │     ├── Reviews diffs with specialist sub-agents
  │     ├── Runs cross-model adversarial review (Codex/GPT)
  │     ├── Fixes HIGH/CRITICAL findings
  │     └── Merges approved batches to dev
  │
  └── VE Worker (Docker container, autonomous)
        ├── Reads CLAUDE.md + LESSONS.md for context + rules
        ├── Connects to task board via MCP
        ├── Picks tasks, researches, verifies, codes, commits
        ├── Runs type-check before every commit
        ├── Invokes code-reviewer every 3 tasks
        ├── Appends lessons learned at close
        └── Stops at batch limit, logs handoff notes
```

## Prerequisites

- **Claude Code CLI** — `npm install -g @anthropic-ai/claude-code`
- **Docker Desktop** — Running locally
- **Claude subscription** (Pro/Max/Team) — For the OAuth token (no API billing)
- **A task board** — Accessible via MCP (we use Firebase Firestore)
- **A codebase with CLAUDE.md** — The worker reads this to understand your project
- **Optional: OpenAI Codex CLI** — For cross-model adversarial reviews

## Quick Start

### 1. Get auth token
```bash
claude setup-token
# Creates a long-lived token from your Claude subscription (valid 1 year)
```

### 2. Configure
```bash
cd docker/ve-worker
cp .env-example .env
# Paste your CLAUDE_CODE_OAUTH_TOKEN into .env
```

### 3. Build
```bash
docker compose build
```

### 4. Run a batch
```bash
TASK_PROMPT="You are an autonomous worker agent. QUALITY OVER SPEED.
FOCUS: Only work on tasks from project '[Your Project]'.
Create branch ve-worker/batch-[slug]-\$(date +%Y%m%d-%H%M%S).
Board session, type-check before commits, code-reviewer every 3 tasks.
ONE COMMIT PER TASK. Guards: 10 tasks, 4 hours, 500 lines." \
BATCH_SIZE=10 docker compose run --rm -d claude-worker
```

### 5. Monitor
```bash
docker logs -f <container_id>
# Or use an interactive Claude session as the monitor
```

### 6. Review + merge
```bash
git diff --stat dev..ve-worker/batch-*  # see what changed
git checkout dev
git merge ve-worker/batch-* --no-edit
git push origin dev
git branch -d ve-worker/batch-*
```

## Worktree Isolation

The Docker container uses git worktrees to prevent the worker from interfering with your local working directory. Here's how it works:

1. Your repo is mounted at `/repo` (read-write, for git objects)
2. The entrypoint script runs `git worktree add` to create an isolated copy at `/workspace`
3. The worker operates entirely in `/workspace` — your host branch, staged files, and uncommitted changes are untouched
4. On exit, the worktree is cleaned up automatically

**Why this matters:** Without worktree isolation, the Docker worker and your local session fight over the same git working directory. When the worker runs `git checkout`, it changes files on your host too. We learned this the hard way when a worker switched branches mid-session and erased in-progress edits.

## Dockerfile

```dockerfile
FROM node:22-slim

RUN apt-get update && apt-get install -y \
    git curl openssh-client \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Non-root user required for --permission-mode bypassPermissions
RUN useradd -m -s /bin/bash claude
RUN su claude -c 'git config --global user.email "claude-agent@yourcompany.com"' \
    && su claude -c 'git config --global user.name "Claude Agent"' \
    && su claude -c 'git config --global credential.helper "!gh auth git-credential"'

# Entrypoint creates a worktree for isolation
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
```

### Entrypoint Script

The entrypoint script (`entrypoint.sh`) handles worktree lifecycle:

```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="/repo"
WORK_DIR="/workspace"
BRANCH_NAME="ve-worker/batch-$(date +%Y%m%d-%H%M%S)"

rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR"

git config --global --add safe.directory "$REPO_DIR"
git config --global --add safe.directory "$WORK_DIR"

cd "$REPO_DIR"
git worktree add -b "$BRANCH_NAME" "$WORK_DIR" dev

cleanup() {
  cd "$REPO_DIR" 2>/dev/null || true
  git worktree remove "$WORK_DIR" --force 2>/dev/null || true
}
trap cleanup EXIT

cd "$WORK_DIR"
exec claude "$@"
```

## Worker Prompt Template

```
You are an autonomous worker agent. QUALITY OVER SPEED — take your time, get it right.

SETUP:
1. Create a board session immediately.
2. You are already on a ve-worker/* branch in a git worktree. Do NOT create a new branch or run git checkout.
3. Read CLAUDE.md to understand the codebase.
4. Read LESSONS.md — accumulated lessons from all previous batches. Follow every rule.

SAFETY:
- NEVER push to main. Work on your branch only.
- Do NOT add frontend events without verifying the backend handler exists.
- Cross-layer changes require BOTH sides implemented.
- Do NOT remove existing fields/features unless the task explicitly requires it.
- [Your language-specific safety rules here]

WORKFLOW — for each task:
1. Pull the next READY task from the board (highest priority first).
2. Verify task is still todo/backlog (not claimed by someone else).
3. Update task status to in_progress.
4. VERIFY: Check if already implemented (grep for key functions). If done, mark done, move on.
5. RESEARCH: Read relevant files, understand context.
6. EXECUTE: Make changes. Do NOT exceed task scope — log discovered issues as new tasks.
7. Run type-check — fix before committing.
8. Commit with clear message. ONE COMMIT PER TASK.
9. Update task status to done with activity log.

REVIEW GATE — after every 3 completed tasks:
1. Run type-check (must pass).
2. COMMIT ALL WORK FIRST (preserves work if reviewer exhausts budget).
3. Invoke code-reviewer agent on recent changes.
4. If critical/high issues found, fix in a new commit.
5. Log review results to the board.

SKIPPING:
If a task is blocked, needs user input, or requires architectural changes
spanning multiple services — SKIP it. Tag with metadata skipped_by_worker:true
and log why. Move to the next one.

GUARDS — stop when ANY of these hit:
- Task count reaches batch limit.
- Cumulative lines changed exceeds 500.
- 4 hours elapsed.
- No more READY tasks.

CLOSING (mandatory):
1. Final type-check — fix any errors.
2. Doc/agent audit: check if relevant docs or agent definitions need updating.
3. Self-improvement: append any new patterns the reviewer caught to LESSONS.md.
4. Open a PR to dev (if gh CLI available).
5. End board session with handoff notes.
6. Exit cleanly.
```

## Self-Improvement Loop (LESSONS.md)

Create `docker/ve-worker/LESSONS.md`. The worker reads it at startup and appends at closing.

Over time it accumulates:
- Safety rules from code reviews
- Quality patterns (touch targets, error handling, etc.)
- Domain-specific rules
- Process fixes (commit before review, etc.)

Every future batch benefits from every past batch's mistakes. This replaces manual rule additions with an automated feedback loop.

## Cross-Model Review (Codex Integration)

Install the Codex plugin for Claude Code:
```bash
claude plugins marketplace add openai/codex-plugin-cc
claude plugins install codex@openai-codex
npm install -g @openai/codex
```

Commands:
- `/codex:review` — standard code review from GPT
- `/codex:adversarial-review` — paranoid security review (auth bypass, XSS, race conditions)
- `/codex:rescue` — delegate investigation to Codex

**Use adversarial review before every production push.** Different model family catches blind spots the primary model misses. In practice, Codex found real auth bypass and XSS vulnerabilities that Claude's code-reviewer missed.

## Safety Guards

| Guard | Purpose | Default |
|-------|---------|---------|
| `--max-budget-usd` | Cost cap per batch | $50 |
| `--disallowedTools` | Blocks push to main, force push | Always on |
| `--permission-mode bypassPermissions` | No interactive prompts | Required for headless |
| `--strict-mcp-config` | Only specified MCP servers | Prevents host-path leaks |
| Batch size | Max tasks per run | 7-10 |
| Line cap | Max cumulative lines changed | 500 |
| Time cap | Max runtime | 4 hours |
| Branch isolation | Never commits to main/dev directly | Feature branches |
| Worktree isolation | Worker can't modify host working directory | Entrypoint creates worktree |
| COMMIT BEFORE REVIEW | Preserves work if reviewer exhausts budget | Learned the hard way |

## Definition of Done

Never claim "done" without ALL of these:
1. Code written and type-check passes
2. Deployed to target environment (build triggered and SUCCEEDED)
3. Visually verified (screenshot or manual check)
4. Access tested — correct users CAN access, unauthorized CANNOT
5. Board task updated with evidence

## Lessons Learned (from 16+ batches)

### What works well
- One commit per task (easy to review/revert)
- Verify-before-coding (prevents re-implementing ~30% of tasks)
- Code-reviewer every 3 tasks (catches issues before they compound)
- Cross-model review before production (different blind spots)
- Self-improvement loop (LESSONS.md accumulates institutional knowledge)
- Parallel batches on different projects (no conflicts)

### What to watch for
- Cross-layer changes (frontend + backend) — worker tends to do only one side
- Database safety patterns get violated even when explicitly stated in the prompt
- Workers can exhaust budget during sub-agent review calls — COMMIT FIRST
- Nested React Router layout patterns cause rendering errors
- "Pre-existing" is not a valid excuse — fix it or board-task it

### Recommended workflow
1. Keep a monitor Claude session open
2. Monitor starts batches, watches progress, reviews diffs
3. Worker does the coding
4. Monitor does the quality gate (3 reviewers + Codex) and merge
5. You review results periodically or check notifications

## Scaling

- **Single developer**: 2-3 parallel workers + monitor session
- **Machine must stay awake** (or use a cloud VM)
- **Subscription rate limits apply** — 3 parallel workers is practical on Max plan
- **Context compaction**: Long batches (10+ tasks) may hit context limits. Board session survives compaction. Reduce batch size if workers lose work.

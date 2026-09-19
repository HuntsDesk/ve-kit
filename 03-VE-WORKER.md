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
docker compose build --build-arg CLI_REFRESH=$(date +%s)
```

Always pass `CLI_REFRESH` — without it Docker's layer cache serves whatever CLI version was current the first time the image was built. Build **one shared image tag** for every service (`image: ve-worker:latest` in each compose service). Services that build their own tags from the same Dockerfile drift apart silently: same file, different build dates, CLI versions months apart, no error on either side.

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

# python3 is NOT optional, and nothing in this image fails loudly without it.
# Every hook in .claude/hooks parses its hook JSON with python3 and exits 0 --
# "fail open" -- when no interpreter is found, and `claude -p` still LOADS those
# hooks (only --bare skips them). On an image without python3 the worker's
# commits therefore pass every gate unexamined and the Stop check never fires,
# in the one environment with no human watching. Re-derive the dependency with
# `grep -l python .claude/hooks/*.sh` rather than trusting this comment.
RUN apt-get update && apt-get install -y \
    git curl openssh-client python3 \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# gitleaks -- the binary the staged-diff secret gate shells out to. Without it
# that gate warns and ALLOWS the commit, so the worker's only pre-commit secret
# scan is silently absent. PIN it to the version your host runs so container and
# host agree on rules and on .gitleaks.toml semantics; bump the two together,
# never float to "latest".
#
# The tarball is verified against the release's own checksums file BEFORE it is
# unpacked: a truncated download or a tampered asset must fail the BUILD, not
# ship a silently broken scanner into the unattended environment. `set -eux`
# plus `sha256sum -c` is what makes any mismatch abort the layer.
ARG GITLEAKS_VERSION=8.30.1
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) GL_ARCH=x64 ;; \
      arm64) GL_ARCH=arm64 ;; \
      *) echo "unsupported arch for gitleaks: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    GL_TAR="gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz"; \
    GL_BASE="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"; \
    cd /tmp; \
    curl -fsSL -o "$GL_TAR" "${GL_BASE}/${GL_TAR}"; \
    curl -fsSL -o gitleaks_checksums.txt "${GL_BASE}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"; \
    grep " ${GL_TAR}\$" gitleaks_checksums.txt > gitleaks_expected.txt; \
    test -s gitleaks_expected.txt; \
    sha256sum -c gitleaks_expected.txt; \
    tar -xzf "$GL_TAR" -C /usr/local/bin gitleaks; \
    rm -f "$GL_TAR" gitleaks_checksums.txt gitleaks_expected.txt; \
    chmod +x /usr/local/bin/gitleaks; \
    gitleaks version

# Claude Code CLI -- TRACKS LATEST. Deliberately not the `stable` dist-tag,
# which lags. `@latest` ALONE IS NOT ENOUGH, and that is the whole point of the
# CLI_REFRESH ARG: an unpinned install line is still frozen by Docker's LAYER
# CACHE at whatever was current the first time this layer built. Two services
# built from this identical Dockerfile on different days will silently run CLI
# versions months apart, with no error on either side. Bump this ARG (or pass
# `--build-arg CLI_REFRESH=$(date +%s)`) to rebuild ONLY from here down; the
# apt and gitleaks layers above stay cached.
#
# Belt and braces: entrypoint.sh re-checks the installed version at container
# start and refuses to run a stale CLI, so a forgotten refresh is loud at the
# only moment it matters rather than silent forever.
ARG CLI_REFRESH=1
RUN npm install -g @anthropic-ai/claude-code@latest \
    && claude --version

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

# --- CLI staleness check ----------------------------------------------------
# The image installs @latest, but Docker's layer cache freezes that at first
# build. A stale CLI in an UNATTENDED batch is the worst case: nobody sees a
# banner. THREE outcomes, kept distinct on purpose -- a probe failure is NOT a
# staleness verdict, and an unreachable registry must never render the same as
# an up-to-date CLI:
#   behind        -> print the exact rebuild command and EXIT NON-ZERO
#   up to date    -> one quiet line, continue
#   check failed  -> WARN that the check did not run, name which half failed,
#                    and continue (a registry hiccup must not kill a batch)
# Runs BEFORE any worktree is created. VE_SKIP_CLI_VERSION_CHECK=1 skips it.
if [ "${VE_SKIP_CLI_VERSION_CHECK:-0}" = "1" ]; then
  echo "=== CLI version check SKIPPED (VE_SKIP_CLI_VERSION_CHECK=1) ==="
else
  INSTALLED_CLI="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  # `npm view` inherits a 300 s fetch timeout with retries, so an unreachable
  # registry would stall EVERY container start for minutes. Bound it hard: the
  # kill leaves LATEST_CLI empty, which lands in the WARN branch -- never in the
  # FATAL branch, because FATAL requires two parsed versions.
  LATEST_CLI="$(timeout 20 npm view @anthropic-ai/claude-code version \
                  --fetch-timeout=10000 --fetch-retries=1 2>/dev/null \
                | tr -d '[:space:]' || true)"

  if [ -z "$INSTALLED_CLI" ] || [ -z "$LATEST_CLI" ]; then
    echo "WARNING: CLI version CHECK DID NOT RUN — this is NOT a claim that the CLI is current." >&2
    [ -z "$INSTALLED_CLI" ] && echo "         could not read the INSTALLED version." >&2
    [ -z "$LATEST_CLI" ]    && echo "         could not reach the NPM REGISTRY — probe failure, not staleness." >&2
  elif [ "$INSTALLED_CLI" = "$LATEST_CLI" ]; then
    echo "=== Claude CLI $INSTALLED_CLI (latest) ==="
  elif [ "$(printf '%s\n%s\n' "$INSTALLED_CLI" "$LATEST_CLI" | sort -V | head -1)" != "$INSTALLED_CLI" ]; then
    # Installed sorts HIGHER than the registry's `latest`. Plain string
    # inequality would have called this "STALE" and killed the batch; it is the
    # opposite problem and not a problem at all (a dist-tag rollback, or an
    # @next build). Version-aware compare via `sort -V`, so 2.1.9 < 2.1.278.
    echo "NOTE: Claude CLI $INSTALLED_CLI is NEWER than the registry's latest ($LATEST_CLI) — continuing."
  else
    echo "FATAL: Claude CLI in this image is STALE — installed $INSTALLED_CLI, latest $LATEST_CLI." >&2
    echo "       The image's npm layer is cached; @latest alone will not refresh it." >&2
    echo "       Rebuild with: docker compose build --build-arg CLI_REFRESH=\$(date +%s)" >&2
    exit 1
  fi
fi

rm -rf "$WORK_DIR" 2>/dev/null || true
mkdir -p "$WORK_DIR"

# Fail fast if the git host auth is unusable — otherwise the batch runs to
# completion and dies at the final push/PR step. Host keychain tokens do not
# reach the container; pass a token through the environment.
if ! gh api user --silent 2>/dev/null; then
  echo "FATAL: no usable GitHub token in container. Set GH_TOKEN in your .env." >&2
  exit 1
fi

git config --global --add safe.directory "$REPO_DIR"
git config --global --add safe.directory "$WORK_DIR"

cd "$REPO_DIR"

# Prune registrations left by prior containers: each container registers
# /workspace in the host repo's .git, the dir dies with the container, and the
# stale entry blocks the next `git worktree add`. Branch refs survive pruning,
# so unpushed batch work stays recoverable.
git worktree prune

git worktree add -b "$BRANCH_NAME" "$WORK_DIR" dev

cleanup() {
  cd "$REPO_DIR" 2>/dev/null || true
  git worktree remove "$WORK_DIR" --force 2>/dev/null || true
}
trap cleanup EXIT

cd "$WORK_DIR"
exec claude "$@"
```

> ⚠️ `exec` REPLACES this shell, so the `trap cleanup EXIT` above never fires once Claude starts. That is why `git worktree prune` at the top is the real cleanup: it reclaims the dead registrations the previous container left behind. Keep both — the trap still covers the failure paths before `exec`.

## Model choice

**The worker's model is a per-project call, and it is deliberately NOT governed by your agent-fleet manifest.** `agent-model-tier.py` only ever rewrites `.claude/agents/*.md`; it cannot see a compose file. So whatever you set here, a later `apply preferred` / `apply fallback` will not move it — and will not move it *back*. Record the decision in a comment at the compose file, because nothing else will.

Two considerations that pull in opposite directions, both real:

- **The rubric's rule** (see `skills/_shared/review-checklist.md`) puts an unattended agent that writes code across a shared repo on your highest-capability tier. The worker is exactly that shape.
- **Availability beats the benchmark for unattended work.** A model with a capacity cap can exhaust its quota mid-batch, and an unattended batch has nobody to notice. A project that runs batches overnight may rationally default the worker to whichever model is always available, even when a benchmark favours the other.

Pass the **alias** (`opus`, `fable`), never a dated ID like `claude-opus-5`. The alias picks up each release for free; a pinned ID silently strands the worker on an old model — which is the failure mode this line exists to prevent.

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

### The guards only run if the IMAGE can run them

`claude -p` **loads your project's hooks** (only `--bare` skips them), so the review gate, the secret gate and the Stop compliance check are registered inside the container too. They are also the hooks most likely to be inert there: each one parses its hook JSON with `python3` and exits 0 — fail-open — when no interpreter is found, and the secret gate warns-and-allows when its binary is missing. Neither absence breaks the build or produces any error. It just turns every gate off, silently, in the one environment with no human watching.

Measured before and after adding `python3` + `gitleaks` to an image that had neither, running the suites **in-container**:

| Suite | Image without them | With them | Host |
|---|---|---|---|
| the review-gate suite | 9 passed / **15 failed** | 24 / 0 | 24 / 0 |
| the Stop-compliance suite | 14 passed / **25 failed** | 39 / 0 | 39 / 0 |

Verify after any base-image change, in this order — the second command is the one that matters, because a `command -v` hit proves the binary exists, not that the gates pass:

```bash
docker compose build --build-arg CLI_REFRESH=$(date +%s) claude-worker
docker run --rm --entrypoint sh ve-worker:latest -c 'command -v python3 gitleaks'
docker run --rm -v "$PWD:/repo:ro" --entrypoint bash ve-worker:latest \
  -c 'cd /repo && for t in .claude/hooks/test-*.sh; do bash "$t" || exit 1; done'
```

Re-derive the dependency list from the hooks themselves (`grep -l python .claude/hooks/*.sh`) rather than from this page. `jq`, for instance, is **not** needed by the hooks in this kit — check before adding it.

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

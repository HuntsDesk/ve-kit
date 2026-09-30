# VE Worker: Autonomous Coding with Claude Code + Docker

A system for running Claude Code autonomously in Docker containers, processing tasks from a persistent board, with quality gates, cross-model review, and human-in-the-loop oversight.

## What It Does

You give it a project and a batch size. It:
1. Clones your repository from the git host into the container and creates a branch for the batch
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
# Set GH_TOKEN (fine-grained, this one repo: contents + pull requests) and
# REPO_URL=https://<git-host>/<owner>/<repo>.git — the container CLONES this; your checkout is not mounted
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
git fetch origin                                   # the batch branch exists on the git host only
git diff --stat origin/dev...origin/ve-worker/batch-<timestamp>   # see what changed
git checkout dev
git merge origin/ve-worker/batch-<timestamp> --no-edit            # or merge the PR
git push origin dev
git push origin --delete ve-worker/batch-<timestamp>
```

Without the `git fetch`, `git log dev..ve-worker/*` prints nothing — and that empty result means "not fetched", not "no commits".

## Host Isolation

**Your checkout is not mounted into the container.** The entrypoint `git clone`s `REPO_URL` over https, authenticating with `GH_TOKEN`, into `/workspace` — a directory in the container's own filesystem — and cuts the batch branch from `origin/<base branch>`.

Earlier versions of this kit mounted the host repo **read-write** at `/repo` and ran `git worktree add` against it. That kept the worker off your checked-out files, and nothing more: a `bypassPermissions` agent could read the checkout's gitignored files (`.env*`, MCP config with secrets) and write files your **host** later executes — `.git/hooks/*` (a linked worktree reads hooks from the shared `.git`), `.claude/hooks/*.sh`, `.claude/settings.json`, the compose file itself. If you adopted that version, remove the `/repo` volume and replace your entrypoint with the one below.

What is mounted, and how:

| Host path | Target | Mode |
|---|---|---|
| `mcp-config.json` | `/etc/claude/mcp-config.json` | `:ro` |
| the board MCP server's built directory | `/mcp/agent-board` | `:ro` |
| one board service-account key file | `/etc/claude/agent-board-key.json` | `:ro` |

What follows mechanically, and what does not:

- A clone carries **tracked content only**, so gitignored files in your checkout never enter `/workspace`. `.git/hooks` is not cloned. Your tracked `.claude/hooks` are — the worker runs with them, in its own copy.
- The container is given no path to any host file outside those three read-only binds. That is a container boundary with a container boundary's limits: a runtime escape bug, a mounted Docker socket or `--privileged` defeats it. The entrypoint refuses to start if `/repo` exists, if `/proc/self/mountinfo` shows any writable bind or volume, if a bind is writable by `[ -w ]` or by a real write probe, or if a bind-mounted directory contains `.git`.
- **Residual channels, none of them closed by this:** the git-host token can push any branch its scope allows, including your default branch unless the host enforces branch protection; the board key can write to the board, which later sessions read as instructions; the network is open, so anything the container holds can be sent out and anything can be fetched in; and you merge the worker's PR — review changes to `.claude/hooks/`, `.claude/settings.json`, the worker's own compose file and CI config as carefully as application code, because merging is how its code reaches your machine now.
- A read-only bind of some *other* host directory that holds secrets and contains no `.git` is indistinguishable, from inside, from the legitimate board-MCP bind. Keep the volume list at three.

What the shared `.git` used to give you for free, and no longer does:

1. **Commits survived the container.** Now nothing in `/workspace` does. The entrypoint installs a `post-commit` hook in the clone that pushes every commit made on a `ve-worker/*` branch and declines any other branch. This is durability against a batch dying at the spend cap, not a control — the worker can delete it. `cherry-pick`, `rebase` and `merge` do not fire `post-commit`; the closing push covers them.
2. **The batch branch appeared in your local `git branch`.** Now it exists on the git host until you `git fetch origin`.
3. **The worker saw local-only commits on your base branch.** Now it sees what is pushed. That is deliberate — branching from a local branch published every unpushed commit on it via the worker's branch and put them in its PR diff — but push first if the worker needs them.
4. **LESSONS.md appended after the final push still reached you.** Now the lessons commit must come *before* the final push (the prompt template orders it that way).
5. **A service that commits without opening a PR kept its work.** If you run a single-task or interactive service from the same entrypoint, its commits now survive only because the hook publishes a `ve-worker/go-*` branch that no PR points at. List them (`git branch -r --list 'origin/ve-worker/go-*'`), merge what you want, delete the rest (`git push origin --delete <branch>`). Give a read-mostly service such as triage `VE_AUTO_PUSH=off` so it cannot publish a branch as a side effect.

**Why clone from the git host instead of mounting the checkout read-only?** A `:ro` mount still lets the container read `.env`. Mounting only `.git` read-only still exposes every local-only branch, stash and reflog object. Measure your own clone time before deciding it is too slow: on a repo with ~210 MB of pack, a full clone with checkout took ~14 s, against a dependency install measured in minutes.

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
    git curl python3 \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# gitleaks -- the binary the pre-commit secret gate shells out to. Without it
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

# Entrypoint clones the repo into the container (the host checkout is not mounted)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER claude
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
```

### Entrypoint Script

The entrypoint script (`entrypoint.sh`) checks the container's mounts, clones the repository and starts Claude:

```bash
#!/bin/bash
set -euo pipefail

WORK_DIR="/workspace"
BASE_BRANCH="${BASE_BRANCH:-dev}"
# One entrypoint usually serves several compose services (batch worker, single
# task, triage). Name the branch after the service so a stray remote branch is
# recognisable; keep every prefix under ve-worker/ so the auto-push hook's guard
# covers it, and keep the word `main` out of it (the deny list would match it).
case "${VE_BRANCH_KIND:-batch}" in
  batch|go|triage) BRANCH_NAME="ve-worker/${VE_BRANCH_KIND:-batch}-$(date +%Y%m%d-%H%M%S)" ;;
  *) echo "FATAL: VE_BRANCH_KIND must be batch, go or triage." >&2; exit 1 ;;
esac

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
# Runs BEFORE anything is cloned. VE_SKIP_CLI_VERSION_CHECK=1 skips it.
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

# NOT `rm -rf "$WORK_DIR"`: in a fresh container it is already empty, and if it
# is not, something is mounted there — wiping it would delete the mounted files.
mkdir -p "$WORK_DIR"

# --- Host isolation: fail CLOSED, before the token is used --------------------
# The host checkout must not be reachable: not writable (the host later RUNS
# .git/hooks, .claude/hooks and the compose file) and not readable (gitignored
# .env* sit in it). `:ro` on a checkout is NOT enough — it still hands over .env.
if [ -e /repo ]; then
  echo "FATAL: /repo exists — the host checkout is mounted. Remove that volume (read-only included)." >&2
  exit 1
fi
is_writable() {   # either test saying "writable" counts; each can be blind alone
  local t="$1" probe
  [ -e "$t" ] || return 1
  [ -w "$t" ] && return 0
  if [ -d "$t" ]; then
    probe="$t/.ve-write-probe.$$"
    if ( : > "$probe" ) 2>/dev/null; then command rm -f -- "$probe"; return 0; fi
  else
    if ( : >> "$t" ) 2>/dev/null; then return 0; fi   # opens for append, writes nothing
  fi
  return 1
}
# A "bind" = a mountinfo row whose root (field 4) is not "/", on a real
# filesystem, other than the three files Docker binds into /etc. A named volume
# renders the same way and is refused too: a writable volume shared between
# batches is a channel from one batch into the next.
MI_AWK='{ fs=""; for (i=7; i<=NF; i++) if ($i == "-") { fs=$(i+1); break } }
        fs ~ /^(proc|sysfs|tmpfs|devpts|mqueue|cgroup|cgroup2|devtmpfs|overlay)$/ { next }
        $4 == "/" { next }
        $5 ~ /^\/etc\/(resolv\.conf|hostname|hosts)$/ { next }'
RW_BINDS="$(awk "$MI_AWK"' $6 ~ /(^|,)rw(,|$)/ { print $4 " -> " $5 }' /proc/self/mountinfo || true)"
if [ -n "$RW_BINDS" ]; then
  echo "FATAL: a WRITABLE bind mount or volume is attached:" >&2; echo "$RW_BINDS" | sed 's/^/         /' >&2
  exit 1
fi
for bind in /mcp/agent-board /etc/claude/mcp-config.json /etc/claude/agent-board-key.json \
            $(awk "$MI_AWK"' { print $5 }' /proc/self/mountinfo || true); do
  [ -e "$bind" ] || continue
  if is_writable "$bind"; then
    echo "FATAL: $bind is writable from inside the container — mount host paths ':ro'." >&2; exit 1
  fi
  if [ -d "$bind" ] && [ -e "$bind/.git" ]; then
    echo "FATAL: $bind is a bind-mounted git checkout — the host repo must not be mounted at all." >&2; exit 1
  fi
done

# Fail fast if the git host auth is unusable — otherwise the batch runs to
# completion and dies at the final push/PR step. Host keychain tokens do not
# reach the container; pass a token through the environment. stderr is shown,
# not discarded: "bad credentials" and "network unreachable" need different fixes.
if ! GH_ERR="$(gh api user --silent 2>&1)"; then
  echo "FATAL: no usable GitHub token in container (set GH_TOKEN in your .env): ${GH_ERR:-<no output>}" >&2
  exit 1
fi

# REPO_URL is what gets cloned. https only: ssh needs keys this container must
# not hold, and a path or file:// URL only works if a host directory is mounted.
# Embedded credentials are refused, not used — git would store them in .git/config.
# Whitespace or a CR is REFUSED, not trimmed: it is what a .env saved with CRLF
# line endings produces, and a trailing CR passes the https glob and then dies
# inside `git clone` with an error that names neither the CR nor the .env file.
# The value is not echoed — at this point it may still hold a password.
for ws_var in REPO_URL BASE_BRANCH; do
  case "${!ws_var:-}" in
    *[[:space:]]*)
      echo "FATAL: $ws_var contains whitespace or a carriage return (CRLF .env?). Fix the line; not trimming it." >&2
      exit 1 ;;
  esac
done
case "${REPO_URL:-}" in
  https://?*/?*) ;;
  *) echo "FATAL: set REPO_URL to the repo's plain https:// URL." >&2; exit 1 ;;
esac
REPO_AUTHORITY="${REPO_URL#https://}"; REPO_AUTHORITY="${REPO_AUTHORITY%%/*}"
case "$REPO_AUTHORITY" in
  *@*) echo "FATAL: REPO_URL carries embedded credentials — remove them; auth is GH_TOKEN." >&2; exit 1 ;;
esac

# Clone from the GIT HOST, and branch from origin/$BASE_BRANCH — not from a host
# checkout, whose local branch may hold commits nobody has pushed.
git clone --branch "$BASE_BRANCH" "$REPO_URL" "$WORK_DIR"
cd "$WORK_DIR"
git switch -c "$BRANCH_NAME"

# Durability, NOT a control: nothing in /workspace outlives the container, so
# push each commit as it is made. The branch guard keeps the hook from ever
# pushing a commit made on another branch. The worker can delete this hook —
# or REWRITE it, which is why no deny list bounds a push (see Safety Guards).
# Set VE_AUTO_PUSH=off on a service that is not meant to commit (triage); leave
# it on for one that commits but opens no PR, or its work dies with the container.
if [ "${VE_AUTO_PUSH:-on}" != "off" ]; then
cat > .git/hooks/post-commit <<'HOOK'
#!/bin/bash
branch="$(git symbolic-ref --quiet --short HEAD || true)"
case "$branch" in
  ve-worker/*)
    if ! out="$(git push --quiet -u origin "HEAD:refs/heads/$branch" 2>&1)"; then
      echo "[auto-push] WARNING: push FAILED — this commit exists only in the container:" >&2
      echo "$out" | sed 's/^/[auto-push]   /' >&2
    fi ;;
  *) echo "[auto-push] skipped: HEAD is '${branch:-detached}', not a ve-worker/* branch." >&2 ;;
esac
exit 0
HOOK
chmod +x .git/hooks/post-commit
fi

# Install dependencies if a commit gate needs them. Capture the output instead
# of piping it to `tail -1`: on failure the installer's LAST line is only a
# pointer to a log file inside a container that is about to exit with nobody
# watching. No `--prefer-offline` — the container starts with an empty cache and
# a cache volume is refused above, so there is nothing to prefer.
if [ -f package-lock.json ]; then
  DEP_LOG="$(mktemp /tmp/npm-ci.XXXXXX)"
  if npm ci --no-audit --no-fund >"$DEP_LOG" 2>&1; then
    tail -1 "$DEP_LOG"
  else
    DEP_RC=$?
    echo "FATAL: npm ci failed (exit $DEP_RC) — last 40 lines:" >&2
    tail -40 "$DEP_LOG" | sed 's/^/         /' >&2
    exit "$DEP_RC"
  fi
fi

exec claude "$@"
```

> There is no cleanup step and none is needed: no worktree is registered in any host repo, and `/workspace` goes away with the container. The flip side is the point of the `post-commit` hook above — **a commit that was never pushed is gone too.**
>
> The mount checks were observed against a running container on Docker Desktop for macOS (a bind of `/Users/<u>/a/b` renders mountinfo field 4 as `/<u>/a/b`, filesystem type `fakeowner`, with the real `ro`/`rw` in field 6). Other runtimes were not checked. Run the negative controls yourself after adopting this — add a scratch directory as a writable volume and confirm the entrypoint refuses — because an assertion that never fires looks exactly like one that passes.

## Model choice

**Run the worker on the fleet's default model — `opus` in this kit — and pass `--effort` explicitly on every service.** An unattended batch that writes code across a shared repo is the shape the rubric (`skills/_shared/review-checklist.md`) puts on the default model. Opus has a usage limit like any model: a batch that hits a quota wall mid-run with nobody watching simply stops, so size batches to your plan, and if you configure a per-model fallback for the agent fleet, decide separately whether the worker should follow it. If your plan makes a different model the one you are least likely to exhaust, running the worker there is a legitimate per-project call — make it deliberately and write down why.

**State the effort; do not inherit it.** A `claude -p` service that passes no `--effort` runs at the *model's* default, and on Opus 5.5 that is `medium` ([model configuration](https://code.claude.com/docs/en/model-config)) — the level the docs describe as trading some intelligence for lower token use. A batch worker that writes and commits code is a decision-shaped deliverable, so pass `--effort xhigh` (or at least `high`) on it, and pass one on the triage and single-task services too rather than leaving them to the default.

**The worker's model sits OUTSIDE your agent-fleet switch.** `agent-model-tier.py` only ever rewrites `.claude/agents/*.md`; it cannot see a compose file. So a later `apply preferred` / `apply fallback` will not move the worker, and will not move it *back*. Record the decision twice: a comment at the compose file, and an entry in the manifest's `excluded` block naming the file and why — the block exists so a fallback sweep reads as deliberately leaving it alone rather than having missed it.

Pass the **alias** (`opus`), never a dated ID like `claude-opus-5-5`. The alias picks up each release for free; a pinned ID silently strands the worker on an old model — which is the failure mode this line exists to prevent.

## Worker Prompt Template

```
You are an autonomous worker agent. QUALITY OVER SPEED — take your time, get it right.

SETUP:
1. Create a board session immediately.
2. You are already on a ve-worker/* branch, in a clone of the repo that exists ONLY inside this container. Do NOT create a new branch or run git checkout. A commit that is not pushed when you exit is lost; a post-commit hook pushes each commit for you — if it prints an [auto-push] WARNING, run git push -u origin HEAD before anything else. Never amend or rebase: the commit is already pushed.
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
3. Self-improvement: append any new patterns the reviewer caught to LESSONS.md and commit — BEFORE the final push; a commit made after it never leaves the container.
4. git push origin HEAD, then open a PR to dev (if gh CLI available). Confirm with git status -sb that the branch is not ahead of origin.
5. End board session with handoff notes.
6. Exit cleanly.
```

## Self-Improvement Loop (LESSONS.md)

Create `docker/ve-worker/LESSONS.md` and commit it. The worker reads it from its clone at startup and appends at closing; the additions reach you through the batch's PR, like every other change — there is no side channel from the container to your checkout.

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

**Read the "Enforced by" column before you rely on any row.** Only the first group is mechanical — a CLI flag, or something the entrypoint did before the model started. Mechanical is not the same as unbypassable: the spend cap and the MCP lock hold whatever the model does, while `--disallowedTools` matches command text and holds only for the spellings it lists, the host-isolation row holds because of what the container is given, not because of anything the model is told, and the branch-isolation row describes where the worker *starts*, not where it is able to go. Everything in the second group is a line of text in the worker's prompt: the worker is *instructed* to stop, and a worker that loses the thread, miscounts, or reasons its way around the instruction will not stop. Both kinds are useful; conflating them is how you end up believing a runaway batch has four independent brakes when it has one.

| Guard | Purpose | Default | Enforced by |
|-------|---------|---------|-------------|
| `--max-budget-usd` | Cost cap per batch | $50 (`$MAX_BUDGET`) | **CLI flag** |
| Credential scoping | **The real control.** The worker runs `bypassPermissions` and reads unvetted text, so what the container *holds* is the boundary. Give it a fine-grained, single-repo git-host token (contents + pull requests, nothing else) through the environment, one board service-account key file mounted `:ro`, and nothing more. Never mount `~/.ssh`, your cloud CLI's config directory, `~/.config/gh` **or your checkout** — `:ro` stops the agent editing a credential or a file, not reading and using it | Nothing is mounted unless your compose file mounts it | **Yours to enforce** — the entrypoint template only checks that `GH_TOKEN` works, not how broad it is. A token scoped by repository can still push to your default branch; only server-side branch protection stops that |
| `--disallowedTools` | **A speed bump, not a boundary.** Put the same list on *every* service that runs `bypassPermissions`, not only the batch worker. Deny the usual spellings: `Bash(git push*main*)`, `Bash(git push*--force*)`, `Bash(git push* -f*)`, `Bash(git push* +*)`, `Bash(git checkout main)`, `Bash(git checkout main *)`, `Bash(git switch main)`, `Bash(git switch main *)`, the refspec-less pushes as exact rules (`Bash(git push)`, `Bash(git push origin)`, `Bash(git push -u origin)` — on a checked-out default branch these push it with its name nowhere in the command text, so have the worker always push `origin HEAD`), `Bash(git merge *main*)`, `Bash(git reset --hard*)`, `Bash(gh pr merge*)` — and a `Bash(git -* push*main*)`-style twin for each git rule, because a rule written `git push …` does not match `git -C <dir> push …` or `git -c k=v push …`. Rules match the command *text*: `bash -c '…'`, `/usr/bin/git`, a quoted subcommand, a script file, `curl` against the host's REST API, or **a git hook** all walk past the list. The hook is the quiet one: `.git/hooks/` in the clone belongs to the worker (the entrypoint installs `post-commit` there), so a rewritten hook turns a *permitted* `git commit` into any push — the rule sees `git commit`, never what the hook runs. What bounds a push is the token's scope and host-side branch protection, not this list | Always on | **CLI flag** — for the spellings listed, and only those. Re-test after every edit: an inert deny rule looks exactly like a working one |
| `--strict-mcp-config` + `--mcp-config` | Only the servers in the mounted read-only config | Prevents host-path leaks | **CLI flag** |
| Host isolation | The host checkout is not mounted. `/workspace` is a clone made inside the container; the three host paths that are mounted are `:ro`. The container has no path by which to write a host file or read the checkout's gitignored files. Still open: the token's push rights, the board key, the network, and your merge of its PR | No `/repo` volume; `git clone "$REPO_URL" /workspace` | **Compose file** (what is mounted) + **entrypoint** assertions that fail closed on `/repo`, any writable bind or volume, or a bind-mounted checkout. Decided before the model starts, so it does not depend on the model's behaviour — but it is a container boundary, no stronger than the runtime. Does not detect a read-only bind of a secrets directory that has no `.git` |
| Branch isolation | The worker starts on its own branch, cut from `origin/<base>`, so its commits land there by default. Staying there is prompt + the deny list's usual spellings of a checkout of, or push to, `main` | Feature branch per batch | **Entrypoint** for the starting branch; **prompt** + `--disallowedTools` for staying on it |
| Batch size | Max tasks per run | 7-10 (`$BATCH_SIZE`) | Worker **prompt** — the value is interpolated into the prompt text, not passed to a runner |
| Line cap | Max cumulative lines changed | 500 | Worker **prompt** |
| Time cap | Max runtime | 4 hours | Worker **prompt** — nothing kills the container at 4h |
| Type-check before each commit | Catch breakage before it lands | — | Worker **prompt**, unless you add the worker-only commit gate described under [Make the type-check a gate](#make-the-type-check-a-gate-not-an-instruction) — the kit ships that pattern, not a hook |
| Code-reviewer every 3 tasks | Periodic quality gate | Every 3 | Worker **prompt** |
| COMMIT BEFORE REVIEW | Preserves work if reviewer exhausts budget | Learned the hard way | Worker **prompt** |
| `--permission-mode bypassPermissions` | No interactive prompts | Required for headless | **CLI flag** — listed for completeness; it *removes* a control rather than adding one, which is why the two flags above it matter |

**The spend cap is the real backstop.** If every prompt-level guard is ignored, `--max-budget-usd` still ends the batch, and `--disallowedTools` still stops the usual spellings of a push to `main`. Only credential scoping and host-side branch protection keep a determined agent off it. Size that budget as though the line, time and task caps were not there — because under a model that has lost the plot, they aren't.

### Make the type-check a gate, not an instruction

"Run type-check — fix before committing" in the prompt is instruction-following in the one environment with no human watching: nothing observes whether the worker ran it, and nothing stops the commit if it did not. The fix is a `PreToolUse` Bash hook that runs your type-check at commit time and DENIES the commit with the compiler output, so the worker fixes it and retries. The kit ships the **pattern**, not a hook, because the moving parts — which command, which surfaces, how the command reports each one — are yours. The properties that make it trustworthy, each worth a case in its suite:

- **Inert outside the worker.** The first executable statement checks an environment marker your worker's compose file sets (say `VE_WORKER=1`) plus a kill switch (`VE_WORKER_TYPECHECK_GATE=off`), drains stdin and exits. An interactive window pays one process spawn; a multi-minute type-check on every commit in a shared tree would be hostile. The kill switch lives in the compose environment, where a human sets it — hooks get the harness environment, not the agent's shell, so the worker cannot reach it.
- **Fails CLOSED inside the worker.** No interpreter, no package manager, a timeout, an unreadable log or a crashed verdict builder all deny. This inverts the fail-open doctrine the other hooks follow, deliberately and only here: there is no developer to brick, and a green commit from a gate that never ran is exactly the silent failure an unattended environment cannot afford. Write the deviation into your hooks README.
- **A skip is not a pass — require positive evidence.** A multi-surface type-check script that skips a surface with no `node_modules` and still exits 0 will report green for code it never looked at. Map each committed path to the surface it belongs to, and require a verdict line per touched surface (for example `PASS [<surface>]` / `FAIL [<surface>]`) in the output. No line for a touched surface means it did not run: deny, and say which `npm install` fixes it. Pin those two literals in the suite against your script, so a wording change reddens the tests instead of silently opening the gate.
- **Find what the commit really contains.** A PreToolUse hook runs BEFORE the command, so the index alone under-reports: `git add X && git commit`, `git add -A`, `git commit -a/-am`, `git commit <pathspec>`, `-i`/`-o` and `--amend` all take content at execution time. Parse the add segments; resolve the dirty set (`git status --porcelain -uall` — without `-uall` a brand-new directory collapses to one line and its files vanish) for broad adds; and when the index and the add segments name no type-checked file, fall back to the dirty set anyway. That fallback can only add work, never remove it: its cost is an occasional extra type-check, where the miss is an unchecked commit.
- **Keep the commit regex byte-identical to your other commit gates** and assert their agreement across several command forms.
- **Cover the whole commit-creating family, not just the token `commit`.** `cherry-pick`, `revert`, `merge`, `pull`, `rebase` and `am` all create commits without that token, so a gate keyed on it misses every one of them. Share one classifier across your commit gates, byte-identical and pinned by a test, that sorts each git segment into three kinds. `run` creates a commit from content that is not in the index. `continue` covers `--continue` and `--skip`, which commit the index. `control` covers the forms that create no commit: `-n`, `--no-commit`, `--squash`, `--ff-only`, `--abort` and `--quit`. The gates can then legitimately differ: a secret scan should cover every verb, while a review gate may exempt merge, pull and rebase as routine sync of already-reviewed commits. Pin that relationship in the suite as agreement where you intend it and a **named** difference where you don't. For this gate, the result of a pick, merge or rebase does not exist yet at PreToolUse, so do not pretend to type-check it. Deny when the new commit could change what the checker sees: the pick touches a checked surface, or both merge sides changed one since the merge base. Then name the route the gate CAN check, which is the `--no-commit` form followed by a separate `git commit`.
- **Deny text with exits the agent can take.** Show the errors head-first with every omission counted in-band and the full log's path, never just the tail. Tell the worker to check `git status` for its OWN stray files before anything else, and give it a way out when the failure is not its code — log a board task naming the surface and the first error, mark its task skipped, and end the batch. An unattended agent with no modelled exit loops until the time cap. Forbid the three bad exits by name: disabling the gate, committing around it, and adding an entry to a type-check suppression list.
- **Test it with a fake package manager**, never the real type-check: put a stub `npm` first on `PATH` that records it was called, prints a canned transcript and exits a canned code. The "was it called" sentinel is what makes "the inert path costs nothing" and "a docs-only commit pays nothing" mean something — empty hook output alone cannot tell "did not run" from "ran and passed". Drive the hook with the command TEXT against a throwaway repo's index; the suite never needs a real `git commit` from the agent's shell (the review gate cannot tell a temp-repo commit from a real one).

### The guards only run if the IMAGE can run them

`claude -p` **loads your project's hooks** (only `--bare` skips them), so the review gate, the secret gate and the Stop compliance check are registered inside the container too. They are also the hooks most likely to be inert there: each one parses its hook JSON with `python3` and exits 0 — fail-open — when no interpreter is found, and the secret gate warns-and-allows when its binary is missing. Neither absence breaks the build or produces any error. It just turns every gate off, silently, in the one environment with no human watching.

The effect is measurable, and it is large. Running the hook suites **in-container** on an image that had neither binary, then again after adding both, the review-gate suite went from 9 passed / **15 failed** to 24 passed / 0 failed — the same result the host produces. The Stop-compliance suite (an earlier 39-assertion revision of the `test-stop-hook.sh` this kit now ships) moved 14 passed / 25 failed → 39 / 0 on the same images. Expect that shape from any gate suite you run in a stripped image: most of it fails, and none of the failures look like a missing dependency.

Which suites you actually have depends on which hooks you installed. This kit ships a suite for every hook it ships — the review gate, the secret gate (`test-gitleaks-gate.sh`, which prints `SKIP:` and asserts nothing when gitleaks is missing), the two edit-time gates, the three telemetry hooks, and since 2026-09-21 the Stop check (`test-stop-hook.sh`), the todo block and the two board reminders — but `ls .claude/hooks/test-*.sh` is the list, not this paragraph. The loop below runs whatever is there.

Verify after any base-image change, in this order — the second command is the one that matters, because a `command -v` hit proves the binary exists, not that the gates pass:

```bash
docker compose build --build-arg CLI_REFRESH=$(date +%s) claude-worker
docker run --rm --entrypoint sh ve-worker:latest -c 'command -v python3 gitleaks'
docker run --rm -v "$PWD:/repo:ro" --entrypoint bash ve-worker:latest \
  -c 'cd /repo && for t in .claude/hooks/test-*.sh; do bash "$t" || exit 1; done'
```

That last command does mount your checkout, read-only, into a container that runs **only those test scripts** — the entrypoint is overridden and no agent starts. It is a manual check you run; the worker services never get that volume.

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

# Run Claude Code for hours without babysitting it.

### VE Harness (`ve-kit`) — the Vibe Entrepreneurs harness for Claude Code

[![gates](https://github.com/HuntsDesk/ve-kit/actions/workflows/gates.yml/badge.svg)](https://github.com/HuntsDesk/ve-kit/actions/workflows/gates.yml)

VE Harness is the layer you bolt around Claude Code so a long session stops being a conversation and starts being a process: it plans, delegates to specialists you define, reviews itself, and gets its `git commit` denied until it has. It keeps the work on a hosted board, so when a window dies, gets compacted, or you just close it, the next one picks up where the last one left off — and it gives your team's agents a shared memory, so what one of them learns tonight the others can find tomorrow.

> **Gates, not guidelines. The session ends; the work doesn't.**

Mental model: **board → gate → commit → handoff → resume.**

---

## What a day with it looks like

You kick off a task and walk away. The model doesn't ask you for permission every ninety seconds, because the harness already approved everything it's supposed to be able to do and drew a hard line around everything it isn't. A start-of-session hook puts the board protocol back in front of it before the first move, so opening a board session is the first thing it does rather than something you have to ask for — and the work is documented from the start.

It plans. Once you've built specialists for the parts of your codebase that deserve one, it hands them the pieces they own — and when a specialist disagrees with what it just wrote, it concedes and fixes it more often than you'd expect. When it tries to end a turn in which it changed something and the board hasn't heard about it, a stop hook blocks it once and hands back a checklist: did you actually review this, did you leave anything half-done, is the board current. When it tries to commit without a review, the commit is denied.

You come back. If that window is gone, you open a new one and it reads the handoff and continues. If someone else on your team learned something in their window ten minutes ago, your agent can find it on its next search — the board's shared memory is live, not a file you have to remember to pull.

That's why you can run several windows at once. You kick one off and it churns — and because the windows share one working tree and one branch, there's a rule in the box for how they're meant to share it.

---

## Memory, in three layers

Claude Code forgets at three different speeds, so the harness remembers at three. The second one is the part most setups don't have.

| Layer | Outlives | What it holds | What keeps it honest |
|---|---|---|---|
| **The board** | the session, a compaction, the machine | Tasks, sessions, handoff notes, and an activity log of decisions and deviations | The server refuses a close that would orphan subtasks; a stop hook hands back the handoff checklist when a turn changed something and nothing reached the board |
| **Shared memory** | the developer | The rules and gotchas any teammate's agent recorded — "X caused Y; do Z instead", with the files and commits that prove it | It lives in the same hosted store: saved in one window, findable from every other window's next search. No commit, no pull, no "did you see my message" |
| **Auto-memory** | the conversation | Claude Code's own per-project memory | `/review-memory` audits it for stale, duplicated and mis-filed entries, and files what it finds as board tasks |

That middle row is the one that changes how a team works. Your repo already syncs your *code*. It does not sync what your agents *learned* while writing it — the endpoint that lies, the migration that has to go first, the fix that looked right and wasn't. With shared memory, the second developer's agent can look up in the morning what the first one's found out at 11pm. (It is searched, not pushed: an agent finds a memory when it looks for one, and the tool descriptions tell it to look at session start.)

## Without / With

| | Without a harness | With VE Harness |
|---|---|---|
| **Session ends** | Context is gone; next session starts cold | Handoff notes on the board; next window resumes |
| **Compaction hits** | Task state silently drops out | Board state re-injected automatically |
| **Review** | A habit you skip under pressure | `git commit` denied until a review ran |
| **Permissions** | Approve-this-approve-that, all day | Pre-approved inside the fence, denied outside it |
| **Secrets** | Caught in code review, or not at all | Scanned before the commit lands — staged, or staged by the commit command itself |
| **Declarative files** | Stale copies silently revert shipped fixes | Edit denied until you explicitly override it |
| **Team knowledge** | Travels by pull request, or by Slack | Agents share what they learn in real time |
| **Overnight** | Queue sits idle until you're back | Container worker runs it under a spend cap, opens a PR |
| **Your process** | Lives in your head | Lives in rules, hooks, and modes |

---

## What ships

| Piece | Count | What it gives you |
|---|---|---|
| **Hooks** | 11 | 6 deny (review, first-edit facts, protected files, secrets, stop-compliance, ephemeral todos); 2 re-inject board state after a restart or compaction; 3 record gate telemetry |
| **Hook test suites** | 11 | One per hook. CI runs them on Ubuntu and macOS on every push, and fails if a hook ever ships without one |
| **`doctor.sh`** | 1 | Tells you whether the gates in *your* project are installed, registered and able to fire — because a gate that fails open looks identical to a gate that never ran |
| **Rule templates** | 6 | RIPER-CAT process, code quality, documentation, git workflow, board protocol, multi-window coordination (the last is opt-out, for one checkout shared by concurrent sessions) |
| **Skills** | 15 | `/bootstrap`, `/go`, `/plan`, `/review`, `/close`, `/build-agents`, the eight `/review-*` audits, `/self-improve` — plus a shared reference folder they all cite |
| **Agent files** | 0 | Deliberate. `/build-agents` surveys your repo and proposes the few specialists it actually deserves, then interviews you and writes them. A template, a reviewer-discipline block and a recommended roster (7 starter + 3 growth) are the manual path |
| **Vibe Board MCP tools** | 21 | Projects, tasks, sessions, handoffs, activity, gate telemetry, and real-time shared memory (save / search / delete) |
| **VE Worker** | 1 container | Pulls board tasks, works in a clone made inside its container, opens a PR |
| **Setup** | ~15–20 min, ~6 questions | One interactive protocol, run once per project |

---

## Install

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash
# then open Claude Code and paste the prompt from .ve-kit/PROMPT.txt
```

Open `.ve-kit/PROMPT.txt` as a file rather than copying it off your terminal — terminals add color codes.

Then budget **15–20 minutes and about six questions.** It isn't a package install; it's an interview. Claude asks about your project and your stack, then writes the rules, hooks and permissions into your repo while you watch. You can stop after the foundation layer and add the board or the worker later.

<details>
<summary><strong>Two other ways in</strong> (zero local files, or an existing checkout)</summary>

**Paste-a-prompt** — open Claude Code anywhere and paste this in full:

> Fetch `https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/01-BOOTSTRAP.md` and set up this project following the protocol. I want Layer 1 (foundation) + Layer 2 (Vibe Board). Walk me through Phase 0 prerequisites first, then ask the Phase 1 project questions. Once you have my answers, execute all phases end to end. Self-verify at the end and report pass/fail.

**`/bootstrap`** — if VE Harness is already in the repo, type `/bootstrap`. The skill finds the protocol and runs it, in fresh-setup or upgrade mode.

**→ [Full Get Started guide](./00-GET-STARTED.md)** — phase-by-phase walkthrough, pinning to a commit, upgrade mode, first-run troubleshooting, adding the worker, env-var customization.

**After bootstrap, each developer runs [`05-DEVELOPER-SETUP.md`](./05-DEVELOPER-SETUP.md) once.** Auto mode and the classifier's environment live in `~/.claude/settings.json`, which no repo can carry — the kit ships a template and a merge script for that half.
</details>

---

## What you're doing → start here

| You want to | Go to |
|---|---|
| Set up a project from scratch | [`00-GET-STARTED.md`](./00-GET-STARTED.md) → [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) |
| Understand the gates before you trust them | [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) § hooks, and the fold below |
| Check the gates actually fire in your project | `bash doctor.sh` — [`doctor.sh`](./doctor.sh) |
| Add persistent memory and handoffs | [`02-VIBE-BOARD.md`](./02-VIBE-BOARD.md) |
| Let it work overnight | [`03-VE-WORKER.md`](./03-VE-WORKER.md) |
| Build specialists for your own codebase | `/build-agents` — [`skills/build-agents/`](./skills/build-agents/) |
| Get your own machine configured | [`05-DEVELOPER-SETUP.md`](./05-DEVELOPER-SETUP.md) |
| Set model + effort per agent, with an optional quota fallback | [`agent-model-tier.py`](./agent-model-tier.py) + [`agent-model-tiers.template.json`](./agent-model-tiers.template.json) |
| Drop in just the slash commands | [`skills/`](./skills/) |
| Reach Gmail / Drive / Docs / Calendar | [`04-GOOGLE-WORKSPACE-MCP.md`](./04-GOOGLE-WORKSPACE-MCP.md) |
| See what changed, and what we got wrong | [`CHANGELOG.md`](./CHANGELOG.md) |

---

## The three things it actually buys you

### 1. It runs longer

The limiting factor on a long Claude Code session isn't the model. It's that everything the session knew evaporates when the window closes, and you spend the first ten minutes of the next one re-explaining yourself.

- **You never have to ask for a board session.** A start-of-session hook injects the board protocol before the first move, and the agent opens its own session from there. Plans, decisions, deviations and blockers land on tasks while the work happens, so the record exists before you need it. (The hook reminds; the agent acts. It is reliable, not mechanical.)
- **Handoff gets one hard stop.** When a turn changed something — an edit, a commit, a command outside the repo, a hand-off to an agent that can write — and nothing has reached the board since, a stop hook blocks the first attempt to end it and hands back the checklist — progress summary, handoff notes that reference task IDs, the files it touched — so ending without one takes a deliberate second attempt. A turn that only answered a question stops freely. A new window reads that handoff and continues the thread.
- **Compaction stops being a cliff.** Two hooks re-inject board state after a restart or a compaction — the single most common way a session loses the plot.
- **Parent/child tasks can't quietly orphan.** Closing a task with open children is refused until you say what happens to them, and closing the last child tells you the parent is now empty. This exists because agents kept closing parents and silently orphaning five to nine real subtasks that then rotted for weeks — a documented rule didn't stop it, so the data layer refuses.
- **Your team's agents are in sync in real time.** Shared memory is a board tool, not a file you have to remember to commit — one developer's agent learns a gotcha, and the next tool call in someone else's window can find it.

### 2. It runs safely

Not "safely" as in sandboxed. Safely as in: the moves that cost you a bad afternoon are the ones the harness makes hard.

- **`git commit` is denied until a review ran** — and the review marker is per-session, so one window's review can't authorize another window's commit. That detail matters the moment you run more than one.
- **Secrets are scanned before the commit lands.** A secret that is staged, or in a file the commit command itself stages (`git add … && git commit`, `commit -a`, `commit <pathspec>`), denies the commit, and the finding is listed without ever printing the secret's value. That second half was missing until 2026-09-20: a pre-execution hook sees a clean index on a one-call add-and-commit, so the most common way to commit was never scanned. The suite was green the whole time. (No gitleaks installed? It warns and lets you through — see Known limits.)
- **The first edit of each code file is denied once,** and asks for its importers, its callers, the surface the change affects, and your instruction quoted verbatim before it lets the retry through. It exists because three agents hit the same trap in one session while actively citing the rule that was supposed to prevent it. A rule that says "look first" gets cited and bypassed; a hook that asks for the importer list gets the agent to actually look.
- **Protected declarative files require an explicit diff-then-override.** Allowlists, ignore files, linter and tsconfig files, `.claude/settings*.json`, and the hook scripts themselves — so an agent can't quietly edit the check instead of the code. Three stale-copy reverts happened in four days; two of them were invisible to CI, because reverting a suppression list makes the build *more* permissive and a green build looks identical either way.
- **The permission model is a fence, not a doorbell.** You pre-approve the whole space the agent is supposed to work in and deny the rest, which is exactly why it can churn for an hour without pinging you — and why you can have several windows churning at once. `/close` winds a window down cleanly when you're done with it.
- **Several windows on one checkout have a rule for sharing it.** Most harnesses make *one* session safe; the moment you open a second against the same working tree, git stops warning you about anything. The multi-window rule is the doctrine for that — commit by explicit path, commit only what's safe to deploy because any window's push carries it, one window per domain, merge rather than cherry-pick, and diff any file you didn't deliberately edit before committing it. It's a rule, not a gate: four clauses have a mechanism behind them (the per-session review marker, the protected-files gate, the secret gate that scans a one-call add-and-commit, the `ask` rule on pushes to `main`), and the rule says plainly which of the rest are conventions the agents follow because it's loaded. Skip it if you only ever run one window.

### 3. Best practices, without the pain of applying them

Everyone knows you should plan before you code, review before you commit, and write down why. Nobody does it consistently at 11pm. The harness does it whether or not you're in the mood.

- **RIPER-CAT** — a mode system (RESEARCH → INNOVATE → PLAN → REVIEW → EXECUTE → REVIEW → COMMIT, plus AI REVIEW and TROUBLESHOOT) with auto-transitions written into the rule, so the process usually advances without you typing the next step. Plans bind to board tasks; each task names the specialist that owns it.
- **Specialists that disagree with the generalist.** When the model does the work and then checks it against what the domain owner says, it concedes surprisingly often. That's the whole value of the roster — not more prompts, but a second opinion that's harder to talk past.
- **A deviation protocol.** If the implementation has to diverge from the plan, it says so on the record instead of silently substituting a different approach. Silent plan drift is the failure mode this was written for.
- **A stop hook that hands back the checklist.** The hook reads the session transcript to decide whether to ask: did this turn change anything, and has the board heard about it since? If it did and the board hasn't, the first stop is blocked and the agent is made to check its own work against the list. A tool call that was denied before it ran doesn't count as a change, and the same stop is never blocked twice. The hook doesn't check the answers — it makes sure the question gets asked.
- **Config that audits itself.** The `/review-*` family checks your agents, skills, rules, docs, memory, board and `.claude/` security, and files findings as board tasks rather than prose you'll scroll past.
- **`/self-improve` won't codify a one-off.** Gate telemetry feeds it, and a pattern needs to recur before it's allowed to become a rule. That guardrail is the point: a harness that learns from every single incident becomes unusable within a month.

<details>
<summary><strong>What the maintainers run</strong> (not what's in the box)</summary>

On a large production codebase, this harness drives **40+ specialist agents**, each owning a domain — payments, auth, database, infrastructure, each product surface — with its own trigger keywords and its own memory. The generalist plans and integrates; the specialists do the work in their own context and hand back a summary.

None of those agent files ship here, and they shouldn't: they're worth something precisely because they're about *that* codebase. What ships is the template, the reviewer-discipline block, and a starting roster to grow from.
</details>

---

## Reference

<details>
<summary><strong>Architecture — three layers, adopt as many as you want</strong></summary>

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: VE WORKER (optional autonomy)                     │
│  Docker worker that processes board tasks headlessly        │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: VIBE BOARD (persistent memory)                    │
│  Firestore-backed MCP server for cross-session continuity   │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: BOOTSTRAP (project foundation)                    │
│  CLAUDE.md, rules, hooks, permissions, skills, agents       │
└─────────────────────────────────────────────────────────────┘
```

- **Just Layer 1** — a disciplined single-session setup with process gates
- **1 + 2** — adds persistent tasks so sessions hand off cleanly
- **1 + 2 + 3** — adds autonomous runs against your task queue

The board works without the worker. The hooks work without the board.
</details>

<details>
<summary><strong>File manifest</strong></summary>

| File / Dir | Layer | Covers |
|---|---|---|
| [`00-GET-STARTED.md`](./00-GET-STARTED.md) | — | Onboarding: three paths, phase walkthrough, troubleshooting, upgrade mode |
| [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) | 1 | Fresh-project setup: `CLAUDE.md`, `.claude/rules/`, `.claude/hooks/`, permissions + deny list, skills library, agent template, RIPER-CAT |
| [`02-VIBE-BOARD.md`](./02-VIBE-BOARD.md) | 2 | Firestore-backed MCP server for persistent tasks, sessions and shared memory. 21 tools. |
| [`03-VE-WORKER.md`](./03-VE-WORKER.md) | 3 | Docker coding agent: reads board tasks, runs under guards, commits to a branch and opens a PR |
| [`04-GOOGLE-WORKSPACE-MCP.md`](./04-GOOGLE-WORKSPACE-MCP.md) | Companion | When and how to add Gmail / Docs / Slides / Sheets / Drive / Calendar |
| [`05-DEVELOPER-SETUP.md`](./05-DEVELOPER-SETUP.md) + [`user-settings.template.json`](./user-settings.template.json) + [`merge-user-settings.py`](./merge-user-settings.py) | Per-developer | The half of the config a repo can't carry — auto mode, `autoMode.environment`, per-model effort |
| [`agent-model-tier.py`](./agent-model-tier.py) + [`agent-model-tiers.template.json`](./agent-model-tiers.template.json) | Fleet | Preferred/fallback model + effort per agent, applied mechanically |
| [`doctor.sh`](./doctor.sh) + [`extract-hooks.py`](./extract-hooks.py) + [`.github/workflows/gates.yml`](./.github/workflows/gates.yml) | Verify | `doctor.sh` checks a bootstrapped project: every hook present, executable and registered, which Python the hooks will use, whether gitleaks is there, then runs every `test-*.sh`. One `KEY=ok\|WARN\|FAIL\|SKIPPED` line per check; `SKIPPED` means "could not run", never a pass. `extract-hooks.py` writes the hook templates out of `01-BOOTSTRAP.md`. The workflow runs both on Ubuntu and macOS on every push. `doctor.sh --self-check` is the maintainer check that doctor's hook roster matches what the bootstrap ships, and that every hook's suite ships with it. |
| [`init.sh`](./init.sh) | — | One-command installer |
| [`skills/`](./skills/) | Skills | Drop-in `.claude/skills/` files, pre-sanitized |
| [`CHANGELOG.md`](./CHANGELOG.md) | — | What changed, and where we corrected ourselves |

The hooks and their test suites live as templates inside `01-BOOTSTRAP.md` and are written out by the bootstrap protocol rather than shipped as loose files.
</details>

<details>
<summary><strong>Skills, grouped by job</strong></summary>

Drop these into `.claude/skills/`. They're already sanitized — project-specific board IDs and domains are placeholders like `<YOUR_AUDIT_PROJECT_ID>` and `<your-domain>`.

**Get set up and get work done**
- [`skills/bootstrap/`](./skills/bootstrap/) — `/bootstrap` runs the setup protocol interactively (fresh or upgrade)
- [`skills/go/`](./skills/go/) — `/go <task>` runs a full RIPER cycle in one command
- [`skills/plan/`](./skills/plan/) — `/plan` structured planning with board tasks + agent assignment
- [`skills/review/`](./skills/review/) — `/review` invokes sub-agents; auto-detects post-plan vs post-execute
- [`skills/close/`](./skills/close/) — `/close` winds a window down without losing anything: stashes its own edits by explicit path, returns its in-progress tasks, ends the session with a handoff, files what needs a person
- [`skills/build-agents/`](./skills/build-agents/) — `/build-agents` finds the specialists your codebase actually deserves: surveys churn and fix density, proposes a small evidence-backed set (and says "none yet" when that is the honest answer), interviews you for the invariants a generalist gets wrong, writes the agent files, registers them in the roster and the tier manifest, and verifies they loaded

**Keep the config honest**
- [`skills/review-agents/`](./skills/review-agents/) — audit `.claude/agents/*.md`
- [`skills/review-skills/`](./skills/review-skills/) — audit `.claude/skills/*/SKILL.md`
- [`skills/review-rules/`](./skills/review-rules/) — audit `CLAUDE.md` + `.claude/rules/*.md`
- [`skills/review-docs/`](./skills/review-docs/) — audit `docs/**/*.md`
- [`skills/review-memory/`](./skills/review-memory/) — audit the per-project auto-memory directory
- [`skills/review-board/`](./skills/review-board/) — audit board state (stale tasks, orphans, abandoned projects)
- [`skills/review-security/`](./skills/review-security/) — audit `.claude/` config security (secrets, permissions, hook behavior)
- [`skills/review-all/`](./skills/review-all/) — runs every `review-*` in sequence

**Get better over time**
- [`skills/self-improve/`](./skills/self-improve/) — mines review findings and worker-batch outcomes for *recurring* patterns and encodes preventive guardrails. Governing rule: a one-off is never a rule.

**Shared reference, cited by the review skills**
- [`skills/_shared/anthropic-configuration-guide.md`](./skills/_shared/anthropic-configuration-guide.md) — frontmatter / model / skill schema reference, with citations to the official docs
- [`skills/_shared/review-checklist.md`](./skills/_shared/review-checklist.md) — the checklist every `review-*` skill cites

Every review skill writes findings as severity-tiered board subtasks, never as prose. Swap `<YOUR_AUDIT_PROJECT_ID>` for your own project ID after you drop them in.
</details>

<details>
<summary><strong>Hook by hook</strong> (11 total)</summary>

**Six that deny**

| Hook | Fires on | What it refuses |
|---|---|---|
| `review-gate` | `git commit` | A commit with no review marker for this session. Markers are per-session, so another window's review doesn't count. |
| `fact-gate` | First `Edit`/`Write` of each code file, once per file per session (docs, tests and `.claude/` are exempt) | The first attempt — it asks for the file's importers, callers, affected surface and your instruction verbatim, then lets the retry through. It interrupts so you look; it doesn't grade your answer. |
| `protected-files-gate` | `Edit`/`Write` on protected declarative paths | Edits to allowlists, ignore files, linter/tsconfig files, `.claude/settings*.json` and the hook scripts until this session has diffed against HEAD and set an override marker. |
| `gitleaks-gate` (recommended) | `git commit` | A commit with a secret finding in the staged diff **or in a file the command itself stages** (`git add … && git commit`, `commit -a`, `commit <pathspec>`). Lists every finding, never prints the value. Scans the files the commit will contain, never the whole tree; when it cannot tell which files those are (a loop, any `$(…)` or backtick, `xargs`, `bash -c`), it widens to everything modified, and when a file-writing step it recognises (a redirection, `touch`/`cp`/`tee`/`curl` and similar) precedes the staging, it warns `NOT SCANNED`, because the content is not on disk when the hook runs. It cannot see a shell alias, a script that runs git, or a commit made outside Bash. Warns and allows if gitleaks isn't installed. |
| `stop-compliance-check` | End of turn | Stopping after a change with nothing written to the board since. It reads the session transcript for an edit, a commit/push/merge, a command on your out-of-repo list, an MCP tool you have listed as a write (that list ships empty, so MCP writes are invisible until you fill it), or a hand-off to an agent that can write — skipping any call that was denied or failed before it ran — then blocks the stop once and hands the checklist back. It fails open, and it is still a nudge: the agent answers the checklist itself and the hook checks none of the answers. |
| `block-todowrite` | Ephemeral todo tools | Ephemeral task lists, which die with the session. Board tasks don't. |

**Two that re-inject**

Session start and post-compaction hooks push board state back into context — the fix for the single most common way a long session loses the plot.

**Three that record**

Gate telemetry: which gate fired, on what, how often. It's what `/self-improve` reads, and it's why a guardrail proposal can point at recurrence instead of at a hunch.

Eleven hook test suites ship, one per hook — the Stop check, the todo block and the two board reminders got theirs on 2026-09-21. `ls .claude/hooks/test-*.sh` is the honest list, and `bash doctor.sh` runs them all. CI runs the same eleven on Ubuntu and macOS on every push, and its roster check fails if a hook ships without a suite. A green badge means every hook made the right decision on synthetic input on clean machines. It does not mean an agent acts on a reminder or answers the stop checklist honestly — three of these hooks are nudges, and no suite can test the reader. The secret-gate suite asserts nothing without gitleaks installed — `doctor.sh` reports that as `SKIPPED`, never `ok`. It matters more than it sounds: a gate that silently stops evaluating looks exactly like a gate that's passing.
</details>

<details>
<summary><strong>VE Worker guards</strong></summary>

The container agent pulls board tasks and runs them unattended. Know which of its limits are mechanical and which are instructions:

**Mechanically enforced**
- **Host isolation** (compose + entrypoint) — your checkout is not mounted; the entrypoint clones the repo from the git host into the container and refuses to start if the checkout, or any writable volume, is mounted. Still open: the token's push rights, the board key, the network, and your merge of its PR
- **$50 per batch** spend cap (`--max-budget-usd`) — the real backstop on a runaway batch
- **`--disallowedTools`** blocking the usual spellings of a push to `main`, force pushes, and checkout/merge of `main` — a text-matching speed bump (it cannot see `bash -c`, absolute paths, scripts, the REST API, or a rewritten git hook in the worker's own clone), on every bypass-mode service
- **Credential scoping — the real control:** the worker gets a fine-grained, single-repo GitHub token through the environment and one read-only key file; never a mount of `~/.ssh`, a cloud CLI config directory or `~/.config/gh`. A repo-scoped token can still push to your default branch unless the host enforces branch protection
- **A locked MCP config** — only the servers you listed

**Instructed in the worker's prompt, not enforced by a hook**
- Batch size (7–10 tasks), a **500-line** cumulative cap and a **4-hour** cap
- **code-reviewer every 3 tasks**, committing before each review so work survives a reviewer that exhausts the budget
- Type-checking before each commit
- **Opening a PR** on the batch branch for you to read in the morning (needs the `gh` CLI in the container)

**Built into the image and entrypoint**
- **gitleaks, checksum-verified** at image build — so the secret gate has its scanner inside the container
- **A CLI staleness check** at startup that tells "you're behind" apart from "the lookup failed"

It runs on your existing Claude plan via `CLAUDE_CODE_OAUTH_TOKEN`, so an unattended overnight batch doesn't push you onto per-token API billing.

A prompt instruction is advice and a flag is a gate. We'd rather you knew which was which before you left it running overnight.
</details>

<details>
<summary><strong>Fleet model tiers</strong></summary>

[`agent-model-tier.py`](./agent-model-tier.py) + [`agent-model-tiers.template.json`](./agent-model-tiers.template.json) record a **preferred** and a **fallback** model + effort pair per agent, once, and apply them mechanically. The template puts every agent on `opus` with an **explicit** effort — an omitted `effort:` inherits the session, and Opus 5.5 defaults to `medium` — and ships the fallback identical to `preferred`, so it does nothing until you give it a cheaper model:

- `status` — what the fleet is running now
- `check` — fails loudly when a file has drifted from the manifest
- `apply fallback` — if you configured one, switch the whole fleet to the recorded fallback when you hit a weekly quota wall
- `apply preferred [--tier N]` — switch back, exactly, because `preferred` was never overwritten; restore tier by tier if only part of your budget is back

Recording both pairs up front is the point. A blanket rewrite under quota pressure is easy; getting back to where you were afterwards is not.
</details>

<details>
<summary><strong>Per-developer setup</strong></summary>

Some Claude Code configuration lives in `~/.claude/settings.json` and can't travel in a repo — auto mode, the classifier's `autoMode.environment`, per-model effort. The kit ships a placeholder template and a merge script so each developer runs one command instead of hand-editing JSON.

→ [`05-DEVELOPER-SETUP.md`](./05-DEVELOPER-SETUP.md), [`user-settings.template.json`](./user-settings.template.json), [`merge-user-settings.py`](./merge-user-settings.py)
</details>

<details>
<summary><strong>Companion: VE Google Workspace MCP</strong></summary>

**[HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws)** — a Python fork of [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) reaching Gmail, Drive, Docs, Calendar, Sheets, Slides, Forms, Tasks, Chat, Contacts and Apps Script, with 28 authoring-focused tools added on top — so you can write to Workspace, not just read from it.

Install it after the base bootstrap is running. **→ [Full companion guide](./04-GOOGLE-WORKSPACE-MCP.md)**
</details>

---

## Known limits

These are design decisions. Each one is a trade we made on purpose, and we'd rather you know the reasoning than discover the edge.

**The hooks fail open.** Every hook in this kit exits 0 when its dependencies are missing or its input is malformed. A harness that wedges your editor because Python moved is a harness you delete by Wednesday, so we chose availability. The consequence is real and you should hold it in your head: **these gates are enforced discipline, not a security boundary.** They make the wrong move take deliberate effort. They do not make it impossible, and nothing here can promise your repo is safe from an agent — or from you.

**The permission fence guards against accidents, not adversaries.** The deny list stops the commands you'd regret — it does not enumerate every spelling of them, and an agent that wants to route around a pattern can. The `ask` rule on pushes to `main` is documented by Claude Code to prompt in every mode, but we have measured a session hosted inside an IDE extension where it did not prompt at all — prompt delivery there depends on the host. Test it in the environment you actually use (`git push no-such-remote main` is a harmless probe), and if `main` is production, put a real boundary on the server side as well.

**Setup is an interview, not an install.** Fifteen to twenty minutes and roughly six questions. It writes rules, hooks and permissions into your repo and touches your `~/.claude/settings.json`; we'd rather you watched that happen than had it done to you.

**Zero agent files are in the box.** A specialist is worth something because it owns a real domain of *your* codebase, so the kit ships the thing that builds them (`/build-agents`) rather than a catalogue. For the manual path you get a template, a reviewer-discipline block and a recommended starting roster of ten. A catalogue of pre-written agents would look more generous and be worth less.

**The board needs Firebase.** Persistent, real-time, cross-machine state has to live somewhere, and Firestore's free tier covers normal use. If you won't run a cloud dependency, take Layer 1 alone — the hooks and modes work without the board, you just lose continuity between sessions.

**Claude Code needs a paid plan.** Your existing Pro/Max subscription, or API billing. The CLI is a free download; using it isn't. VE Harness adds no model cost of its own, and the worker runs on the same subscription. You do not need a separate Anthropic API key, any other provider key, or a paid observability tool.

**The [CHANGELOG](./CHANGELOG.md) retracts our own advice.** This kit once recommended running on bypass-permissions plus a deny list, and has described its own hooks as fail-closed when they were not. When we're wrong, the correction goes in the log next to the original claim rather than quietly replacing it. Read the retractions — they're the most useful part.

---

## Built on / Credits

VE Harness borrows freely and says so.

- **RIPER-CAT** extends **RIPER-5**, created by Cursor Community Forum user **robotlovehuman** (March 2025) — [original post](https://forum.cursor.com/t/i-created-an-amazing-mode-called-riper-5-mode-fixes-claude-3-7-drastically/65516). The five modes (RESEARCH, INNOVATE, PLAN, EXECUTE, REVIEW) are theirs. We added COMMIT, AI REVIEW and TROUBLESHOOT, auto-transitions between modes, binding to board tasks, per-mode delegation, a deviation protocol, and hook enforcement.
- **[affaan-m/ECC](https://github.com/affaan-m/ECC)** (MIT) — the fact-gate and protected-files-gate patterns, the reviewer-discipline block, and the Delegation Completion Contract.
- **[zunoworks/gateguard](https://github.com/zunoworks/gateguard)** (MIT) — the GateGuard fact-forcing pattern our `fact-gate` is rewritten from.
- **[taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)** — upstream of the ve-gws companion, with feature ideas ported from **[blakesplay/apollo](https://github.com/blakesplay/apollo)**, itself based on **[piotr-agier/google-drive-mcp](https://github.com/piotr-agier/google-drive-mcp)**.
- **[openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)** — the optional cross-model review step in the worker.
- **[gitleaks](https://github.com/gitleaks/gitleaks)** — the secret scanner behind the pre-commit gate.
- **Anthropic's Claude Code documentation** — cited inline throughout [`skills/_shared/anthropic-configuration-guide.md`](./skills/_shared/anthropic-configuration-guide.md).

---

## Who's behind it

Built and maintained by the people behind **[Vibe Entrepreneurs](https://vibeentrepreneurs.com)**, out of a large production codebase where the alternative to a harness was losing an afternoon a week to re-explaining context and re-reviewing work that had already been reviewed.

> **Part of [Vibe Entrepreneurs](https://vibeentrepreneurs.com)** — a community for anyone shipping real work with AI: solo builders, product-minded devs, agency folks, side-project makers. You don't need to run VE Harness to join. Come say hi: **[vibeentrepreneurs.com](https://vibeentrepreneurs.com)**.

If you build on this and hit something interesting, the lessons that drove changes land in [`CHANGELOG.md`](./CHANGELOG.md).

---

## License

MIT — see [`LICENSE`](./LICENSE).

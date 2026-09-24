# Changelog — Vibe Coding Framework

Snapshot-level changelog. Covers what's new in this share package since prior distributions. Version-stamped by date, not semver — this is a pattern library, not a package.

Entries below are **dated records of what was said at the time**, not a description of the current kit. Where an earlier entry turned out to be wrong, it is left in place with a `(corrected …)` annotation and the correction is written out in the Corrections section immediately below. Rewriting the original would hide that this kit's own docs were, for a while, confidently wrong about it.

---

## 2026-09-23 — Opus is the default for every agent; the Stop check knows `/close`; ingest cannot be wedged by one row

**Model rubric: `opus` for every agent, with an explicit effort.** `skills/_shared/review-checklist.md` and `anthropic-configuration-guide.md` are re-synced: the reference fleet now runs every agent on `model: opus` (the alias, which resolves to `claude-opus-5-5` from Claude Code 2.1.280) and tiers by **effort** instead of by model — `high` for document-shaped work, `xhigh` where the deliverable is a decision, diagnosis or gate verdict (the review gate and the test runner included), `max` only for domain-content authors and still unvalidated. This supersedes the 2026-09-05 entry below, which made Fable 5.1 the default. The reason on record is a direct re-tier decision, not a benchmark; no benchmark figures are claimed. **Every agent states `effort:`**, because Opus 5.5 defaults to `medium` ([model configuration](https://code.claude.com/docs/en/model-config)) and an omitted line inherits the launching session. The hand-maintained files follow: the agent template and frontmatter table in `01-BOOTSTRAP.md`, `agent-model-tiers.template.json` (every entry `opus` with a stated effort; the fallback column ships identical to `preferred`, so `apply fallback` does nothing until you configure a cheaper model), the README's fleet section, `05-DEVELOPER-SETUP.md` and `user-settings.template.json` (a `claude-opus-5-5` effort entry — a top-level `effortLevel` in the user file does not apply to Opus 5.5), and `03-VE-WORKER.md` § Model choice (default the worker to `opus`, pass `--effort` on every service, and record it in the manifest's `excluded` block because the tier script never touches a compose file).

**The Stop check's text knows `/close`.** Its first checklist item used to tell every blocked window to call `board_create_session` — which auto-abandons every active session on the project, i.e. every *other* window's, the one call the close protocol forbids. A window running `/close` (typed, `Skill(close)`, or a `board_log_activity` with `metadata.protocol: "close"`, after the last `board_create_session`) now gets close-protocol text: log the close state, do not create a session, no review/test demands. Any code change after the marker switches back to the normal text. The normal text's item 1 now creates a session only when the window has none and is not closing. The block/allow verdict is unchanged. `test-stop-hook.sh` 91 → **109**, with two new mutations stated.

**Telemetry ingest: one bad row can no longer wedge it.** The package's ingest script now size-checks each row, quarantines an un-ingestable one whole to `.claude/telemetry/gate-events.deadletter.jsonl` (never truncated), advances the watermark over the longest *handled* prefix, tells transient failures from poison (an isolation pass, a positive-control probe, string error codes), brakes on a poison *rate*, dedupes dead-letter appends on a rotation rescan, and records `.claude/telemetry/.ingest-state.json` with a status derived from row states rather than a counter. `QUARANTINE_DECIDED=` and `QUARANTINED=` are separate log lines, so a failed append never reads as a success; `INGEST=partial` is a new status. `test-telemetry-ingest.sh` 9 → **30** cases, the write path driven through a fake `firebase-admin` (`VE_INGEST_ADMIN_MODULE`), seven mutation controls. New test-only env vars: `VE_INGEST_MAX_DOC_BYTES`, `VE_INGEST_WALL_MS`, `VE_INGEST_POISON_BRAKE_ABS` / `_FRACTION` / `_MIN_RUN`. **Needs ve-vibe-board 2.2.1 or later** (published; the kit's CI now pins it); against an older clone the write-path cases fail rather than skip.

**The commit gates see every commit-creating command.** `review-gate.sh` and `gitleaks-gate.sh` keyed on the word `commit`, so `cherry-pick`, `revert`, `merge`, `pull`, `rebase` and `am` created commits neither saw. The secret gate now scans what each would ADD (INCOMING), warning instead of denying when every incoming commit is already on a remote; the review gate adds cherry-pick, revert and `am` and exempts merge, pull and rebase by design as routine sync. One shell-aware classifier, byte-identical in both hooks, decides which segment is which, so a commit message that mentions a pick is not one. `test-review-gate.sh` 24 → **71**, `test-gitleaks-gate.sh` 175 → **249**; the hooks README template gains a "What the commit gates see" table.

**The worker type-check gate, as a pattern.** `03-VE-WORKER.md` gains "Make the type-check a gate, not an instruction": a worker-only `PreToolUse` hook, inert outside the container, that fails CLOSED inside it, demands a per-surface verdict line as positive evidence (a skip is not a pass), resolves what a commit really contains at PreToolUse time, and gives the agent a sanctioned way out. The kit ships the properties, not a hook, because the command and the surface map are project-specific. The hooks README template gains the matching doctrine note — when failing closed is right — and a testing rule: a commit gate's suite never needs a real `git commit` from the agent's shell.

---

## 2026-09-21 — the Stop check is now a transcript analyser, and every hook ships a suite

**`stop-compliance-check.sh` is replaced, not tweaked.** The template this kit shipped was an unconditional reminder: it blocked the first stop of *every* turn — a one-line answer included — and inspected nothing. The new one reads the session transcript and blocks only when the session **executed a change** (an edit tool; `git commit`/`push`/`merge` or `gh pr merge` at command position; a command on a short, user-editable out-of-repo list — database clients, `kubectl`, `terraform apply`, `curl -X POST` by default; a delegation to a sub-agent that can write) **and nothing has been written to the board since**. Board writes are matched by tool-name suffix, so the MCP server can be called anything. A board write *before* the change excuses nothing; board reads never count. **Adopters: re-extract the hook, then edit the list at the top of it for what your project can reach.**

**A tool call that never ran is not a change.** The analyser pairs each `tool_use` with its `tool_result` and skips any call whose result has `is_error: true` — a permission denial, a hook's deny, a rejected prompt, a failed `Edit` — unless it is a Bash result starting `Exit code <n>`, which means the command ran and failed (`git commit -m x && npm test` exits 1 with the commit made). An errored board write resets nothing. This was a live false positive in the reference project: a headless session whose only action was a `git push` that permissions refused was handed the "you EXECUTED changes" checklist, because the scan matched the command text and never looked at what became of the call. Deny text is arbitrary — every hook writes its own — so "ran anyway" is the side that is enumerated and everything unrecognised reads as "did not run"; if a future Claude Code words a failed command differently, the cost is a missed nudge, never a false block.

**What it still is: a nudge.** It decides whether to ask. The agent answers the checklist itself and the hook checks none of the answers — the checklist text now says so in as many words. It blocks at most once per stop attempt (`stop_hook_active`), fails open (no Python, unparseable input, no session id, no transcript), never prints or records a command or a path (the telemetry row a block appends carries only `why: edit|bash|mcp|agent`), and does not see a sub-agent's transcript, a change older than the last 32 MB, or a git write that is not at command position. The accepted costs are pinned in the suite so that changing one is a decision: a heredoc body line beginning `git commit` reads as a command; `bash -c "git commit"`, `for … do git commit`, `if …; then git push; fi`, `env … git commit`, `nohup git push &`, `xargs git commit` and `$(which git) commit` are not seen (measured in the reference project against the older match-anywhere regex over 24,835 real Bash commands: 63 judged differently, none an executed git write).

**Two fixes from the review of this port, same day.** *Result pairing is by transcript order.* The first cut kept errored results in a table keyed by `tool_use_id`, and ids repeat — a resumed session replays records — so one errored twin could silence a completed call that shared its id: a false *negative*, the dangerous direction for this hook. A result now belongs to the nearest preceding call with its id that has no result yet, and is consumed once. *MCP write tools can be listed.* The checklist has always named changes made through an MCP server while the detector could not see one. `MCP_WRITE_TOOLS` (one regex per server, matched from the start of the tool name; `why: mcp`) closes that — **and ships empty**, because what `create_` means on a server nobody has read is a guess. Until you list a server's write tools, they are invisible to this hook, and the hook header says so.

**Four new suites; all eleven hooks now ship one.** `test-stop-hook.sh` (91 assertions), `test-block-todowrite.sh` (14), `test-session-handoff.sh` (13), `test-post-compact-recovery.sh` (9). Each was checked by mutation against a copy of its hook, and each Stop mutation is stated so it can be repeated — Stop (91 passing before each): a result never marks its call as not-run → 11 fail; `if why:` → `if False:` → 49; `COMMAND_POSITION +` dropped from the verb regex → 9; the board reset (`why = []`) → `pass` → 8; the read-only marker always ignored → 2; the id-keyed result table restored → 3; `kind = "mcp"` → `None` → 3. (The first draft of this entry quoted five kill-counts without saying what was mutated; a reviewer could reproduce two of them. The counts above were re-measured after the two review fixes below.) Todo block: comparison never true → 2; session handoff: compact branch off → 1, stash filter broken → 1; post-compact: instruction line deleted → 2. `post-compact-recovery.sh` has no branch, so its suite pins a contract rather than a decision, and says so; the case that earns its place is "identical output with nothing but `cat` on PATH" — the day that hook grows a Python dependency it starts failing open into silence at exactly the moment the board session id is lost. `doctor.sh`'s roster gained a fourth column, each hook's suite, and `--self-check` now fails when a hook's suite is not among those the bootstrap ships; CI plants that defect and requires the red. `extract-hooks.py` floor: `MIN_SUITES` 7 → 11.

What the badge means now: every hook made the right decision on synthetic input, on a clean Ubuntu and a clean macOS runner. What it still cannot mean: that an agent acts on a reminder or answers the checklist honestly.

---

## 2026-09-21 — a sixth rule template: multi-window coordination

The kit already shipped the *mechanisms* that make several concurrent Claude Code windows survivable on one checkout — a review marker keyed to the session id, so one window's review can't authorize another's commit; a protected-files gate on declarative paths; a secret gate that scans what a one-call `git add … && git commit` stages; `/close`; real-time shared memory — and none of the *doctrine* that tells those windows how to share one working tree and one branch. `01-BOOTSTRAP.md` Phase 3 now carries `.claude/rules/multi-window-coordination.md` alongside the other five templates.

Seven sections: don't leave uncommitted WIP (explicit paths, never `git add -A`, stash what isn't done, check the branch, never amend on a shared branch); a push carries everything committed, so commit = publish and only deploy-safe units get committed, with the three ways to stay safe (feature-flag, migration-first, hold it back) in preference order; one window per domain; worktree isolation as the escalation; coordinate through the board, including a pre-promotion check for what the other windows have in flight; merge rather than cherry-pick; and — the section with the least prior art anywhere — diff any file you didn't deliberately edit before committing it, because a stale copy in your tree or index silently *un-does* work another window already shipped, and on a **declarative** file (an allowlist, an ignore file, a suppression list, a CI config) the revert makes the build *more* permissive, so a green run looks identical either way.

**It says which clauses are enforced and which are not.** A table at the top of the template splits them: four clauses name the hook, skill or settings rule standing behind them (with the caveat that the `ask` rule on pushes to `main` prompts reliably in a terminal session but depends on the host inside an IDE extension); one-window-per-domain, the deploy-safety judgment, merge-not-cherry-pick and the pre-push board check are labelled plainly as conventions that no hook can see. This kit has described its own advice as mechanism before, and the correction is in this log; the fix is to say so in the rule itself rather than in a changelog nobody re-reads.

**Opt-out, not opt-in, and no new question.** Phase 1 question 5 (branch strategy) now also asks whether you'll run more than one window on the checkout; the count stays at about six. The rule is written unless you say you won't. It is deliberately **unconditional** — no `paths:` block — for the reason Phase 3 already gives: its subject is git coordination, which no file edit triggers, so a glob would unload it exactly when it matters. Branch names are `<integration-branch>` / `<production-branch>` placeholders filled from your answer.

Still in the reference project and still not ported: rules on query discipline, code tracing, silent degradation, fix propagation and task-closure validation, plus a fail-closed type-check gate for the worker and the file-based half of shared memory.

---

## 2026-09-21 — VE Worker: the host checkout is no longer mounted

The entrypoint now clones `REPO_URL` over https into a container-local `/workspace` and fails closed if `/repo`, any writable bind or volume, or a bind-mounted git checkout is present. Earlier versions mounted the repo read-write, which let the agent read gitignored files and write files the host later executes (`.git/hooks`, `.claude/hooks`, the compose file). A read-only mount was considered and rejected: the container could still read your `.env`. **Adopters: remove the `/repo` volume, set `REPO_URL`, replace `entrypoint.sh`, rebuild.** The batch is cut from the remote integration branch, not your local one — push first if the worker needs local-only commits — and the batch branch exists only on the git host until you fetch it. A post-commit hook pushes each commit on the batch branch, because nothing in the container survives it. One entrypoint serves every compose service: `VE_BRANCH_KIND` names the branch (`ve-worker/batch-*`, `go-*`, `triage-*`); a service that commits without opening a PR publishes a branch you must delete yourself, and read-mostly services get `VE_AUTO_PUSH=off`. `REPO_URL` and `BASE_BRANCH` containing whitespace or a CR are refused, not trimmed. A failed dependency install now prints its output instead of npm's one-line log pointer. What this does not close: the token can still push to your default branch, the board key can write to the board, the network is open, and you still run the worker's code when you merge its PR — review hook, settings and compose changes in a worker PR as carefully as application code.

---

## 2026-09-20 — `doctor.sh`, a hook extractor, and CI that runs the suites

Every hook here fails open, so "my commits go through" was never evidence the gates work. `doctor.sh` is: per-hook present / executable / registered-under-the-right-event, the interpreter the hooks will actually pick, gitleaks as a WARN, then every `test-*.sh`, one `KEY=ok|WARN(..)|FAIL(..)|SKIPPED(..)` line each, exit 1 on any FAIL (`--strict` also fails WARN/SKIPPED). `SKIPPED` means "could not run" and is never reported as a pass. `extract-hooks.py` materialises the `### File:` hook templates from `01-BOOTSTRAP.md` and refuses loudly on an unterminated fence or a short count. `.github/workflows/gates.yml` extracts, registers and runs everything on ubuntu-latest and macos-latest (gitleaks pinned by sha256, both actions pinned by commit SHA, the Vibe Board package pinned by commit), and proves in CI that doctor goes red for a deleted hook, a non-executable hook, a removed registration, a registered-but-missing optional hook, a hidden Python, a hung suite (reported as a timed-out FAIL, not as "could not run"), and a hook added to or removed from `01-BOOTSTRAP.md` without updating doctor's own roster (`doctor.sh --self-check`). New suite: `test-gitleaks-gate.sh` — seven of the eleven hooks now ship a suite; `stop-compliance-check`, `block-todowrite`, `session-handoff` and `post-compact-recovery` still do not. The README badge reports those seven suites on clean machines, nothing more. *(superseded 2026-09-21 — all eleven now ship one; see the entry above)*

### New skill — `/build-agents`

The kit shipped a frontmatter template, a recommended roster and a reviewer-discipline block, and zero agent files — so "define your specialists" was left as an exercise, and the common failure was either skipping it or cloning someone else's forty-agent roster onto a repo that deserved three. `/build-agents` closes that: it surveys layout, 90-day churn and fix density, proposes a deliberately small set of candidates each justified by paths owned, repeated repair, a contract that spans files and a piece of vocabulary a generalist gets wrong, asks which to create, interviews you per accepted candidate, writes the file, registers it in `.claude/agents/README.md` and the tier manifest, and verifies it actually registered. The sizing rule is a ceiling rather than a quota (`ceil(qualifying_areas / 2)`, at most three per run) and "none yet, here is what would change my mind" is an explicit valid outcome. Two traps are encoded because both are invisible: a multi-line `description` without a YAML block scalar silently de-registers the agent — the file sits on disk looking fine and is not invocable — and on a repo already running this harness, agent-written memory and telemetry routinely outrank every product surface by churn, so they are excluded from the read before it is interpreted. `01-BOOTSTRAP.md` § Agent Architecture now points at the skill as the recommended path and keeps the manual template as the fallback.

### VE Worker — credential scoping is the control; the deny list is a speed bump

`03-VE-WORKER.md` Safety Guards: `--disallowedTools` is now described as what it is — a text-matching speed bump, not a boundary. The row lists the patterns to ship (including a `git -* …` twin per rule, because `git -C <dir> push` walks past a rule written `git push …`), says to put the list on every bypass-mode service rather than only the batch worker, and names the forms it cannot see (`bash -c`, absolute paths, scripts, the REST API). A new **Credential scoping** row states the real control: a fine-grained single-repo token via the environment plus one read-only key file, and never a mount of `~/.ssh`, a cloud CLI config directory or `~/.config/gh`. It also says plainly that a repo-scoped token can still push to the default branch unless the host enforces branch protection. This came from auditing our own worker, which mounted all three of those directories into bypass-mode containers and used none of them. The same pass removed four more overclaims from that page: the Worktree Isolation and Branch Isolation guards no longer say the worker *can't* touch the host repo or *never* commits elsewhere — they say what the entrypoint sets up and what is left to the prompt and the deny list; the Safety Guards intro now distinguishes "mechanical" from "unbypassable"; the `--disallowedTools` row gained exact rules for refspec-less pushes (`git push`, `git push origin`, `git push -u origin` — on a checked-out default branch these reach production with the branch name nowhere in the command text) and tells you to have the worker always push `origin HEAD`; and `openssh-client` is dropped from the Dockerfile template, because the template authenticates over https with a token. Every spelling the page lists as covered is one we ran through the real CLI and saw denied.

### Shared memory is now in the rules, not just in the server

The README gained a "Memory, in three layers" section (the board, real-time shared memory, Claude Code's auto-memory). Writing it surfaced a gap: the `agent-board.md` rule template never mentioned shared memory at all, so in a freshly bootstrapped project nothing but the MCP tool descriptions told an agent when to save or search. The template now carries a **Shared Memory** section: search at session start and before debugging a confusing failure; save a rule with its reason and its evidence; never save secrets or session state; correct a wrong memory rather than deleting it. Memory is searched, not pushed — an agent finds what a teammate's agent learned when it looks.

---

## 2026-09-20 — README rewritten; display name is now VE Harness

The README was rebuilt so a reader can tell what this is in ten seconds. It now opens with what the kit is for ("Run Claude Code for hours without babysitting it"), a short walk through a day with it, a Without / With table, a counts table, and a "what you're doing → start here" table; everything reference-grade (architecture, file manifest, skills by job, hook by hook, worker guards, fleet tiers, per-developer setup, the ve-gws companion) is folded below. A **Known limits** section states the trade-offs as decisions with reasons — the hooks fail open, setup is a ~15–20 minute interview, the board needs Firebase, Claude Code needs a paid plan — and a **Built on / Credits** section names what was borrowed and from whom, including the origin of RIPER.

**Display name: VE Harness.** The repo slug, the install URL and every path stay `ve-kit`.

**Cost footprint corrected.** The previous README listed the Claude Code CLI as "free" and a Claude subscription as optional. The CLI is a free download; using it needs a paid plan (an existing Pro/Max subscription, or API billing). The kit adds no model cost of its own.

**Real-time shared memory is now documented.** The board server has shipped `board_save_shared_memory` / `board_search_shared_memories` / `board_delete_shared_memory` for some time with one clause of documentation. They now have their own section in `02-VIBE-BOARD.md` and a place in the README: one developer's agent records a gotcha, and the next search from anyone else's window finds it.

---

## Corrections — 2026-09-20

An inventory of the whole package against the code and templates it describes found two claims that had been repeated across multiple files and were simply wrong. Both are corrected everywhere; this section is the record that we got them wrong first.

**1. The hooks were described as failing CLOSED. They fail OPEN, and always have in this kit.** *(corrected 2026-09-21 — see #6: one hook's no-interpreter branch did not)*

The 2026-04 snapshot announced "Hooks fail CLOSED on JSON parse errors" as a hardening win, and the `/review-security` row in the README, in `01-BOOTSTRAP.md` and in that snapshot's skill table went on describing the audit as checking "fail-closed behavior" long after the change had been reverted. It was reverted for a good reason, recorded in the hook source itself: a gate that hard-denies when it cannot parse its own input locks the agent out of all work, which is worse than a gate that occasionally misses. Every hook in this kit therefore exits 0 — allow — when `python3` is absent or stdin is unparseable, and says so in a comment at the branch that does it.

What `/review-security` actually audits is **whether each hook's failure behaviour matches what it documents**, and whether that choice is stated rather than accidental. The fail-open default has a real cost, which `03-VE-WORKER.md` spells out: in a container with no `python3`, every gate silently turns itself off in the one environment with no human watching. That is a tradeoff the kit takes deliberately, not a property it gets to claim it doesn't have.

**2. The Vibe Board was described as having 10 tools, and elsewhere 14. The server registers 21.**

Three different counts were live at once: "10 tools" in the README's package table, "14 MCP tools" in `02-VIBE-BOARD.md` and in the board server's own README, and a correct "16 most agents use, 21 registered" in the `02-VIBE-BOARD.md` tool reference. Twenty-one is right, and it is now the number every file carries. The five that no count had ever included are the three shared-memory tools (`board_save_shared_memory`, `board_search_shared_memories`, `board_delete_shared_memory`) and the two activity-log deletes — the shared-memory ones had shipped in the server without ever being documented in the kit, and now have their own section in the tool reference.

Two smaller things went with it. The board doc said Firestore held **4 collections**; it holds six (`shared_memories` and `gate_events` were added and the diagram was not). And the free-tier line read "50,000 reads, 20,000 writes, 1GB storage per day" — the reads and writes are daily, the 1 GB is a standing total.

**3. The worker's "safety guards" were listed without saying which are enforced. Most are not.**

`03-VE-WORKER.md`'s Safety Guards table put a CLI flag, a thing the entrypoint does, and a sentence in the worker's prompt in one undifferentiated list, so all eleven read as mechanisms. Only five are: `--max-budget-usd` (default $50), `--disallowedTools` (blocks push to main, force push, `checkout main`, `merge main`), `--strict-mcp-config` with its mounted read-only config, and the branch + git worktree the entrypoint creates before the model starts. **Batch size, the 500-line cumulative cap, the 4-hour cap, the code-reviewer pass every 3 tasks and the type-check before each commit are all lines of text in the prompt.** The worker is instructed to stop; nothing stops it. Nothing kills the container at four hours, and `$BATCH_SIZE` is interpolated into the prompt string rather than passed to a runner that counts. The table now carries an **Enforced by** column, and the guidance is to size the spend cap as though the other caps were absent — because under a model that has lost the thread, they are.

This correction was itself a correction. The first draft of this Corrections section fixed the type-check claim and, in the same sentence, *promoted* the line cap, the time cap and the reviewer cadence to "enforced by the entrypoint" — inventing a new false claim inside the section written to retract false claims. It was caught in review. Worth recording, because it is the failure mode this whole section exists to document: the fix for a wrong mechanism claim is to go read the mechanism, not to reshuffle which item in the sentence carries the confidence.

**Also corrected in this pass**, each a smaller instance of the same failure — a number or a mechanism written once and never re-derived:

- **"Full Node.js source inlined"** (README, `00-GET-STARTED.md`): the board server is **cloned** from [`HuntsDesk/ve-vibe-board`](https://github.com/HuntsDesk/ve-vibe-board) and built. `02-VIBE-BOARD.md` is a setup guide and tool reference, not a source listing.
- **"type-check per commit"** as a quality gate (README, `00-GET-STARTED.md`): in this kit that is an instruction in the **worker's prompt**, not a hook. The worker is told to type-check and fix errors before committing; nothing stops it if it doesn't. See the next correction for what *is* mechanically enforced — the first draft of this line got that wrong too.
- **Hook and skill counts** (`00-GET-STARTED.md` Phase 5 / Phase 10): the kit ships **11** hooks, six of them with their own test suite *(corrected later the same day: seven — the secret-gate suite now ships)*, not the five that row listed. Phase 10 installs four workflow skills plus the eight `/review-*` skills; `close` and `self-improve` also ship and were never mentioned there.
- **`01-BOOTSTRAP.md` is ~4,000 lines**, not the "1500+" `00-GET-STARTED.md` claimed.
- **The skill-copy blocks hardcoded `PKG=docs/ve-kit`**, which is the subtree layout. `init.sh` stages the package at `.ve-kit/`, so the most common install path did not match the commands. Both blocks now locate the package.
- **The agent template carried `model: sonnet`**, which the kit's own rubric reserves for "speed-critical simple tasks, rarely applicable". It now shows `model: fable` + `effort: high`, and the frontmatter table says plainly that `model:` takes an **alias** and never a dated ID.
- **`03-VE-WORKER.md` quoted a `39 passed / 0 failed` result for a Stop-compliance hook suite that this kit does not ship**, presented in a table beside one that it does. The measurement was real; implying the reader has the suite was not.
- **The README pointed readers at a `LESSONS.md`** that lives in a private repo and has never been part of the package. It now points at this file.
- **RIPER-CAT had no origin credit anywhere**, in a package whose central process rule is an extension of someone else's published work. RIPER-CAT extends **RIPER-5**, created by Cursor Community Forum user **robotlovehuman** in March 2025 ([forum thread](https://forum.cursor.com/t/i-created-an-amazing-mode-called-riper-5-mode-fixes-claude-3-7-drastically/65516)). The credit now appears in the README, on the `riper-cat.md` template in `01-BOOTSTRAP.md`, and in a new README **Credits** section that also consolidates the ECC, GateGuard, gitleaks, `taylorwilsdon`, `apollo`, `piotr-agier` and `codex-plugin-cc` attributions that were previously only inline.

The common shape in all of it: a count or a mechanism is written down once, the thing it describes changes, and nothing re-derives it. Where a number could be derived instead of quoted, these docs now tell you how — `grep` the bootstrap for the hook templates, call `tools/list` against your own board build — and say to trust that over the page.

**4. The secret gate never scanned `git add <paths> && git commit`.**

`gitleaks-gate.sh` exited early when the index was clean. A PreToolUse hook runs before the command does, so for a one-call add-and-commit (and for `git commit -a` and `git commit <pathspec>`) the index is always clean at that moment. The most common way to commit was never scanned, and the kit published earlier on 2026-09-20 shipped with that hole. The gate's 19-assertion suite was green throughout, because it checked that the gate *fires* on the compound form against an already-staged index, not that it *scans* what the command is about to stage. Fixed: the gate now also resolves and scans the working-tree files the command will stage; the suite has 175 assertions, including mutation controls that remove the new scan and confirm the clean-index cases fail. The first fix for this, written the same day, claimed that anything it could not resolve would widen the scan. It did not: `git stage`, `{ git add x; }`, `then git add x`, `command git add x` and a backslash-newline continuation each scanned nothing — 20 of the 43 shapes we then probed. Code review caught it before release. The gate now resolves, widens, or warns `NOT SCANNED` for every shape in a table the suite pins, and every shape has a control so that widening cannot quietly become always-deny. Content that is not on disk when the hook fires (a file the same command creates, `git apply --index`, a stash pop) cannot be scanned before the commit, and the gate now warns about it — for the file-writing constructs it recognises (redirections, `touch`/`cp`/`mv`/`tee`/`curl`/`tar` and similar, `sed -i`), not for a build script it cannot see into. A third pass closed two more silent allows found in a second review: a command substitution inside a `-m`/`-F`/`--author` value could stage a file unseen (any substitution now widens the scan; only `$((…))` arithmetic and the quoted-heredoc commit-message idiom are exempt), and a file created by the same command was only flagged `NOT SCANNED` when named literally, not through a glob. Still out of reach, by design: a shell alias or function wrapping git, a script that runs git internally, symlinks and submodules, and commits made outside Bash. The review gate had received the same fix months earlier and the secret gate never got the sibling change — a fix applied in one place is a fix in one place. **If you installed the hook before this release, re-extract it.**

**5. "`ask` rules prompt in every mode" is true only where the host can show a prompt.**

The permission notes said an `ask` rule on `git push*main*` "forces a prompt in every mode." Measured on Claude Code 2.1.278: in a terminal session the push reaches the permission prompt in both `default` and `auto`, as documented. In a session hosted inside an IDE extension through the Agent SDK, the same command simply ran — no prompt, from the main thread or from a subagent — while `deny` rules in the same settings file still fired. The documentation says an SDK host receives `ask` decisions through a callback and does not say what happens when the host supplies none. The pattern also cannot match `git -C <dir> push … main`. `01-BOOTSTRAP.md` Phase 6 and the README's Known limits now say so, with a harmless probe (`git push no-such-remote main`) to test your own environment.

**6. (2026-09-21) The old Stop hook did not fail open, and its "blocks the stop once" was never tested.**

Correction #1 above says the hooks fail open "and always have in this kit." One did not. The `stop-compliance-check.sh` template shipped until 2026-09-21 carried the comment `No working Python — fail open`, and on that branch set `ACTIVE="False"` and fell through to the block. Measured against the old template with nothing but `cat` on PATH and `stop_hook_active: true` on stdin: it still printed `{"decision":"block",…}`. Without an interpreter it could not read `stop_hook_active` at all, so it blocked the retry too — the opposite of failing open, and the one state in which "blocks at most once" was false. Separately, it wrote the checklist as plain text and then a JSON object to the same stdout, which does not parse as one JSON object (also measured); the reference project had already moved everything inside `reason` for that reason. What Claude Code did with the mixed output was **not** measured, so the README's "blocks the first attempt to end the turn" and its "handoff gets one hard stop" described that template's intent, not an observed behaviour — the hook had no suite. The replacement emits one JSON object, exits 0 with no output when there is no interpreter, and has a suite that asserts both. The README also said the hook "doesn't inspect anything itself"; that was true of the old template and is no longer — it now reads the transcript to decide whether to ask, and still verifies none of the answers.

---

## 2026-09 snapshot

### Nothing truncates any more — and one of the two removals needed CHUNKING, not deletion

Both hooks that summarised a list now emit all of it. `gitleaks-gate.sh` lists **every** finding in its deny, grouped by file, instead of ten plus "... and N more" — the agent reading that deny is the one who has to fix them all, so showing a subset just buys a second failed commit. Values are still never rendered; paths, line numbers and rule ids only.

`bash-edit-telemetry.sh` records **every** changed path, and the interesting part is that the `cap = 50` could not simply be deleted. If you mirror telemetry into a document store (this kit's is Firestore, 1 MiB per document) and the ingest path has no per-row size guard, one oversized row throws, the offset watermark never advances, and every later run re-reads and re-fails the same line — ingest dead permanently and silently. So a large set is **split across rows** with `part` / `parts` carrying the same total `n`; nothing is lost and no row is oversized. Readers are unaffected (an `array-contains` match on `paths` still finds a path in whichever part holds it; content-derived doc ids keep the parts distinct). **Read `n` as the total, never `len(paths)`, and count CALLS by `part == 1`** — counting raw rows turns one Bash call into N edits and inflates exactly the number `/self-improve` compares against gate denies. The `truncated` field is gone.

The suite gained four assertions and now carries **three** mutation controls, because the obvious chunking test is vacuous: at the production budget 60 realistic paths fit one row, so an assertion written against them passes even with the chunk loop replaced by `chunks = [changed]`. A test-only `VE_BASH_EDIT_CHUNK_BUDGET` makes the boundary reachable; the three controls prove each assertion discriminates (disable the diff, collapse the chunk loop, reintroduce a `[:50]` slice).

### New hook: `instructions-loaded-telemetry.sh` — which rules actually loaded, and why

Rule files are usually the most-edited instruction artifacts in a project and the least observable: nothing records whether a rule was in context when a session made a decision. This hook fires on `InstructionsLoaded`, once per file loaded, and writes one row per `CLAUDE.md` / rule file with the load reason (`session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`), the file that TRIGGERED it, and the rule's own `paths:` globs. It never denies and — uniquely among the hooks here — **prints nothing at all**, because stdout at instruction-load time injects text into context at the worst possible moment.

It answers two questions that were previously settled by argument: *do my path-scoped rules actually scope* (a scoped rule should be absent from an unrelated session and load on the first matching file, with `trigger` naming it), and *is rule length causing misses*. Two findings not obvious from the payload: the glob match is on the PATH, so it fires for a path that does not exist on disk, and a subdirectory's own `CLAUDE.md` arrives as `nested_traversal`, a different reason from `path_glob_match`. Ships with a suite in which **every negative case sits beside a positive control** — a kill switch and a broken hook both produce zero rows — including the no-interpreter fail-open branch. Registered in the settings template; `INSTRUCTIONS_TELEMETRY=off` disables it alone.

> The payload schema is documented nowhere public. The fields were read off an installed CLI and confirmed by running it: treat them as a claim about the version you measured, not a contract.

### A fail-open gate reports "clean" identically whether it passed or never ran

New doctrine in the hooks README template and in `03-VE-WORKER.md`, from a measured failure. `claude -p` **loads** a project's hooks (only `--bare` skips them), and every hook in this kit parses its JSON with `python3` and exits 0 when no interpreter is found. A worker image built on `node:22-slim` has no `python3` and no `gitleaks` — so every gate was registered, invoked, and inert, on every unattended commit, with no error, no warning and not even a telemetry row (the telemetry needs the interpreter too). Running the hook suites *in-container* on the pre-fix image, better than a third of the assertions failed in each — against a clean run of the same suites on the host. Adding the two dependencies made the container match the host exactly.

"Fails open" is therefore a property of the ENVIRONMENT, not just of the code. Run the suites wherever the hooks actually execute — container, CI image, a new machine — before trusting a green commit from it. A `command -v python3` hit is weaker evidence: it proves the binary exists, not that the gates pass.

### VE Worker: checksum-verified tooling, a CLI that really tracks latest, and a stated model policy

`03-VE-WORKER.md`'s Dockerfile and entrypoint were several fixes behind. Now:

- **`python3` + `gitleaks` in the image**, for the reason above. `gitleaks` is pinned to the version the host runs (so container and host agree on rules and allowlist semantics) and its tarball is **verified against the release's own checksums file before it is unpacked** — a truncated download or a tampered asset fails the BUILD rather than shipping a silently broken scanner into the unattended environment.
- **`@latest` behind a `CLI_REFRESH` cache-bust ARG.** An unpinned `npm install -g` line is still frozen by Docker's layer cache at whatever was current when the layer first built; two services built from the identical Dockerfile on different days ran CLI versions months apart, with no error either way. Build one shared image tag for every service, and always pass `--build-arg CLI_REFRESH=$(date +%s)`.
- **An entrypoint staleness check** that refuses to start on a CLI older than the registry and prints the exact rebuild command. Three outcomes kept deliberately distinct: behind → exit non-zero; current → one quiet line; **lookup failed → WARN that the check did not run**, naming which half failed. A probe failure is never a staleness verdict, and the compare is `sort -V`, so `2.1.9 < 2.1.278` and a newer-than-registry build is a note, not a failure. The whole thing is bounded at 20 s so an unreachable registry cannot stall every container start.
- **`git worktree prune` at startup**, because `exec claude` replaces the shell and the `trap cleanup EXIT` never fires — the previous container's dead `/workspace` registration is what blocks the next `git worktree add`.
- **A "Model choice" section.** The worker's model is a per-project call and is deliberately **not** governed by the agent-fleet manifest: `agent-model-tier.py` only rewrites `.claude/agents/*.md` and cannot see a compose file, so a later `apply preferred` will not move it, and will not move it back. The two pulls are stated plainly — the rubric's rule points an unattended repo-wide code writer at the top tier, while availability beats the benchmark for unattended work, since a capacity-capped model can exhaust its quota mid-batch with nobody watching. Pass the alias, never a dated model ID.

### Rule hygiene: an emphasis budget, a trigger test for `paths`, and a native task type

Three changes to how the kit tells you to write the always-loaded layer.

- **Spend emphasis like a budget.** `MANDATORY`, bold and ALL-CAPS work by contrast, so each extra one devalues the rest; a file where a dozen things are MANDATORY has said nothing about which to obey when they conflict. Count them (`grep -c MANDATORY`) and keep the total enumerable from memory. Cutting emphasis is not cutting a rule: remove the shouting, keep every prohibition, renumber nothing.
- **The dividing line for `paths:` is the TRIGGER, not the subject matter or the rule's pedigree.** Scope a rule when the thing it governs is reached *by editing a file*. Keep it unconditional when its subject touches none — rules about querying (log filters, trusting an empty SQL result), process gates and git coordination have no triggering path, so a `paths:` block would unload them exactly when they matter. A rule can be the close sibling of an unconditional one and still belong behind `paths`; do not reconcile the pair into identical scoping. The new telemetry hook above is how you verify the scoping instead of assuming it.
- **Task type is a native field, not a title prefix.** `board_create_task` takes `task_type` (`story` / `design` / `task` / `bug` / `chore` / `investigation`) plus `story_id` / `design_id`, and `board_get_tasks` filters on it. The old `[STORY]`-style prefix convention is retired to a read-side note: recognise it in an old task, never write a new one. A prefix is text-search only, invisible to the filter, and drifts the moment a title is edited. The board rule template also **dropped its copy of the MCP tool table** — the server ships a description per tool, so a second copy in an always-loaded rule burns context every session and is wrong the moment a tool changes.

### Reviewer discipline: state whether any tests were weakened

A fifth rule for the `code-reviewer` prompt body. A green suite proves nothing if the diff moved the bar, so any diff touching a test, a fixture or a suppression list must end with `tests touched: none weakened` or the list of what was — explicitly, because silence reads as "checked" and usually means "not looked at". Weakening is enumerated concretely (deleted assertions, loosened matchers, a new `skip` / `.only`, a mock that now returns the asserted value, a re-recorded snapshot, entries added to a type-check allowlist or a scanner ignore file). Each is legitimate sometimes and silent always: CI cannot tell "the test was wrong" from "the code was wrong and the test lost the argument", and a suppression entry matching nothing fails OPEN and passes exactly like a correct one. A test loosened in the same commit as the behaviour it covers is a HIGH until explained.

### Tool-independent edit telemetry + automatic cross-developer ingest (two hooks)

`bash-edit-telemetry.sh` closes the measurement hole the two edit-time gates left open: they see only the edit TOOLS, and in auto mode most edits go through Bash (heredocs, `sed -i`, redirects), so gate telemetry undercounted by construction. The hook runs on `PreToolUse` and `PostToolUse` for `Bash`, diffs `git status` around the call, and logs the files it changed as a `bash-edit` event. It never denies. `telemetry-ingest.sh` then mirrors each machine's telemetry file into the Vibe Board's `gate_events` collection on `SessionStart` and `Stop`, detached and watermarked, so `/self-improve` reads every developer's gates from one place instead of one machine's file. Both ship with test suites (the bash-edit suite carries mutation controls, the ingest suite a cross-language document-id parity check — re-derive the assertion counts from the scripts rather than quoting them here) and are registered in the settings template. The kit copy of the ingest hook looks for the package under `vibe-board/` and `ve-vibe-board/`.

### Vibe Board MCP 2.2.0 — `gate_events`

Two tools (`board_query_gate_events`, `board_ingest_gate_events`), the `scripts/ingest-gate-events.mjs` push script the hook above spawns, and 7 composite indexes for the collection, shipped as `firestore.indexes.json` so one `firebase deploy --only firestore:indexes` creates every index the package needs. `02-VIBE-BOARD.md` Step 5 and the tool reference are updated. Per machine after pulling: `npm install && npm run build`.

### New skill: `/close` — wind a window down without losing anything

For anyone running several Claude Code windows against one working tree, the failure this closes is mundane and expensive: a window is shut with edits still in the tree, an `in_progress` board task nobody else can claim, and a decision the user still owes it, all gone with the tab. `/close` is the opposite of resuming. It re-orients in three commands, inventories what *this* session owns from its own transcript (not from `git status`, which shows every window's work), stashes only those files by explicit path with `-u`, returns every held task to `todo` with a comment on where it stands, ends the board session with a handoff that cites task ids and the stash name, and files anything only a person can do. It never commits — an idle window cannot judge deploy-safety — and it ends with a fixed report block and stops.

The human-facing step needs a place to write. The reference project uses a dedicated table behind its admin UI, which the kit omits; **`02-VIBE-BOARD.md` § Human tasks on the same board** shows the zero-infrastructure alternative: a human-only project in the same Firestore instance, `assigned_agent` as the person, `vibe_task_ids` / `human_task_ids` linked both ways in `metadata`. The rules of the step — file only what a person must do, apply your own recommendation first, re-verify the ask before filing, link both directions — are the same whichever board you use.

### Kit skills no longer cite rules the kit does not ship

Four skills pointed at three rule files (a multi-window coordination rule, a deployment rule, a database rule) that exist in the reference project and nowhere in this kit, so a reader following the pointer found nothing. The COMMIT-flags reference now names `riper-cat.md` § COMMIT Flags (which the kit ships), the path-scoped-rule examples name shipped rules, and the two remaining pointers were reworded. Behind it, the maintainer's publish now fails on any such reference (the shipped set is derived from `01-BOOTSTRAP.md`, never hand-listed) and on any sanitizer rule that stopped matching, which is how these went unnoticed.

### Edit-time gates lifted from ECC: `fact-gate.sh` and `protected-files-gate.sh`

Two new PreToolUse hooks on the `Edit|Write|MultiEdit` matcher, both lifted from [`affaan-m/ECC`](https://github.com/affaan-m/ECC) (MIT, Affaan Mustafa) and rewritten to this kit's hook conventions — python probe, fail-open on any parse failure, per-session state keyed by the session id Claude Code passes in the hook input, JSON deny output.

**`fact-gate.sh`** denies the FIRST edit of each code file in a session, once, and demands four facts before the retry: the file's importers and callers, the surface the change affects, every other reader of any shared table or column it touches, and the user's instruction quoted verbatim. The retry on the same path is allowed silently, so the cost is one round-trip per file, not per edit. A `Write` to a path that does not exist yet gets a "search before creating" variant instead. `docs/`, `.claude/`, `workbench/`, tests, fixtures and non-code extensions are exempt; `FACT_GATE=off` is the kill switch. Origin: the GateGuard pattern (`zunoworks/gateguard`, vendored in ECC as `scripts/hooks/gateguard-fact-force.js`).

**Why a rule alone was known-insufficient.** The reference project already carried three rules saying this — follow the value to its terminal consumer, name the importers before you call a fix done, scope a remediation by concept and never by directory — and one of them says outright that a rule alone does not hold, having watched three agents fall into the same trap *while actively citing the rule that governs it*. A hook does not work by asking "are you sure?", which a model always answers yes. It works by refusing to proceed until concrete facts have been produced, and the act of looking is what creates the awareness the self-check never did.

**`protected-files-gate.sh`** denies edits to the declarative files where a stale copy silently reverts someone else's shipped work and nothing goes red: `*.allowlist`, `.trivyignore`, `.gitleaksignore`, `.gitleaks.toml`, the feature-flag desired-state file, the automation registry, the live URL map, n8n backups, `.claude/settings*.json`, `.claude/hooks/*.sh`, and the lint/format/type configs (eslint, prettier, biome, ruff, markdownlint, stylelint, pyright, `tsconfig*.json`). The deny message is three steps: fix the code, not the gate; run `git diff HEAD -- <file>` first; then `touch /tmp/ve-protected-override.$CLAUDE_CODE_SESSION_ID` in a SEPARATE call and retry. The marker is consumed on use and that one path stays authorized for the rest of the session. `PROTECTED_FILES_GATE=off` is the kill switch. Origin: ECC's `scripts/hooks/config-protection.js`, which hard-blocks linter configs — widened here to the whole declarative set and given an explicit override, because a hard block on a file you sometimes legitimately need to shrink just gets switched off.

**Gate telemetry.** Every deny from the four commit- and edit-time gates — `review-gate.sh`, `gitleaks-gate.sh`, `fact-gate.sh`, `protected-files-gate.sh`, but not `block-todowrite.sh`, which denies without telemetry — plus a consumed protected-files override, an override marker that could not be consumed, and the review gate consuming its own marker, appends one JSON line to `.claude/telemetry/gate-events.jsonl`: `ts`, `session_id`, `hook`, `event`, plus per-hook fields such as the path and the tool. The file is gitignored and therefore per machine; `VE_GATE_TELEMETRY=<path>` redirects it, which is how the suites capture events, and `VE_GATE_TELEMETRY=off` disables it. The consumer is `/self-improve` Step 2, where a path that trips the fact gate across two or more sessions, or a protected file overridden across two or more, is a candidate recurring pattern. This is ECC's observation sensor without its instinct injection: the kit records what the gates keep catching and hands it to a human-reviewed improvement pass, rather than feeding an automatic behavioural nudge back into the model. `test-review-gate.sh` gained a telemetry assertion alongside the two edit-time suites.

It closes two failure shapes with one control: an agent that cannot make a check pass editing the CHECK instead of the code, and a suppression list that fails OPEN, where a reverted allowlist and a correct one produce the identical green build.

**Tests**: `test-fact-gate.sh` (**24 passed, 0 failed**) and `test-protected-files-gate.sh` (**28 passed, 0 failed**), both end-to-end against a throwaway directory, each ending in its own mutation control (a copy of the hook with `deny` flipped to `allow` must let the probe through, so the suite is proven able to fail). They assert the deny's CONTENT rather than mere non-silence — that the message actually names the importers and the relative path — plus per-session isolation (one window's first touch cannot silence another's), both kill switches, fail-open on malformed input and on a missing session id, and JSON validity of every emitted payload. Measured cost is roughly 40 ms per hook, so about 80 ms per edit with both installed.

**The bug the tests caught on their first run** is the one worth repeating for anyone porting this: on macOS, `mktemp -d` returns a `/var/folders/...` path that is a symlink to `/private/var/folders/...`. Resolving the project directory through `realpath` on one side of the comparison only made every file inside the test project look external to it, and the gate allowed everything. Both sides now go through `realpath`. A hook exercised only against the real repository would never have surfaced it — which is the argument for the throwaway-directory harness, not just for the assertions.

### Reviewer discipline: a pre-report gate, proof for HIGH/CRITICAL, and zero findings as a valid result

The "REFERENCE: Agent Architecture" section of [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) now carries a **Reviewer discipline** block to put in the `code-reviewer` prompt body, adapted from ECC's `agents/code-reviewer.md` (MIT). An LLM reviewer's characteristic failure is not missing bugs, it is manufacturing findings to look thorough, and the output is indistinguishable from diligence until someone has to triage it.

Four rules: a **pre-report gate** of four questions before any finding is written (can I cite the exact line; can I name the input, the state and the bad outcome; have I read the callers, imports and tests; is the severity defensible to someone who disagrees) where any "no" drops or downgrades it; **HIGH and CRITICAL require proof** — the snippet with its line, the specific failure scenario, and why the guards already in place (types, schema validation, framework defaults, row-level security, your own hooks) do not catch it, or it demotes to MEDIUM; **zero findings is a valid review**, stated as "no findings" plus what was read; and a **standard false-positive list** to skip unless the failure can be shown.

The motivation is a measurement, not a preference. Under "every finding becomes a task", one month in the reference fleet filed **626 tasks and closed 215**, two thirds of them review children, and three review dumps had 41 of 73 findings already repaired within days and never closed. An open count is only a signal if filing tracks intent to act.

### Delegation Completion Contract

The `riper-cat.md` Delegation preamble gains five lines, origin ECC `rules/common/agents.md`: your final message IS the deliverable; a spawned task is not a completed task, so never end a turn "waiting for background agents"; if you delegate, you own collection — wait, integrate, then return; decompose only when the work genuinely cannot fit one context, because depth is an outcome and not a plan.

The observed failure is specific: research agents spawning children and returning "waiting for results", which ends the turn and orphans every child's output. Downstream, an orphaned result is indistinguishable from a child that had nothing to report — the same shape the rest of this kit exists to catch, arriving through the delegation path instead of the code path.

### TodoWrite is gone by default on current models

Claude Code 2.1.233 removed the todo/task tools by default on Opus 4.8, Sonnet 5, Fable, Mythos and newer; `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` restores them. `block-todowrite.sh` still ships and still denies the tool wherever it exists — on an older model, or in a session that re-enabled it — so nothing changes about the guidance. But the kit's board docs said "TodoWrite is blocked by our PreToolUse hook" as the reason to use the board, and on a current model there is now usually nothing there to block. The reason to use the board is that it survives the session; the hook was only ever the backstop.

### Permission model: `auto` replaces "bypassPermissions + deny list"

Claude Code ≥ 2.1.257 **ignores `defaultMode: "bypassPermissions"` in `.claude/settings.json` and `.claude/settings.local.json`** — and starts the session in Manual, the opposite of what that recommendation intended. The BOOTSTRAP settings template no longer sets a `defaultMode` at all (a project-level value outranks the user file for terminal sessions and would block a teammate's `auto`), and the "bypassPermissions + deny list" recommendation from the 2026-04 snapshot is withdrawn except for its documented use: a headless run inside a container (the VE Worker's `--permission-mode bypassPermissions` flag is unchanged). New guidance in Phase 6: auto mode is the built-in starting mode on Pro/Max/Team, it is honoured only from `~/.claude/settings.json`, it suspends the blanket `Bash(*)` allow and reviews commands with a classifier instead, and `autoMode.environment` is where you describe your infrastructure so routine ops stop being classified as unknown targets.

### `permissions.ask` for main-branch pushes

The template adds `"ask": ["Bash(git push*main*)"]` — spaceless, so the refspec forms `dev:main`, `HEAD:main` and `refs/heads/main` match too. *(corrected 2026-09-20 — see Corrections #5: true only where the host can show a prompt)* Ask rules are never auto-approved in any mode, including `auto` and `bypassPermissions`, which makes them the deterministic form of what the `riper-cat.md` template already states in prose (the reference project carries the same rule a second time in a `multi-window-coordination.md` that this kit does not ship): a push to `main` is a production deploy and needs the human's approval each time.

### Hook `timeout` is seconds

The template's hooks carried `"timeout": 5000` — read by Claude Code as 5000 **seconds** (83 minutes), not 5 s. Values corrected to 5–15 s per hook (30 s for a gitleaks scan, if you add one). Harmless in practice, but the number said something nobody meant.

### New: `05-DEVELOPER-SETUP.md` + `user-settings.template.json` + `merge-user-settings.py`

The permission-model change above created a step the kit never had: half of the configuration now lives in each developer's `~/.claude/settings.json` (`defaultMode: auto`, `autoMode.environment`, the self-configuration allow rule, per-model effort defaults), and no repo can carry it. Three new top-level files close the gap. The template ships with `<PLACEHOLDER>` environment entries covering the topics the classifier needs (org, source control and branches, cloud project, trusted buckets and domains, deploy targets, production hosts, protected IaC, secrets, sensitive data, shared-checkout house rules); the maintainer fills it in once — BOOTSTRAP Phase 6 now drafts it from the Phase 1 answers — and commits it; each developer runs the merge script once from a normal terminal. The script backs up the user file, touches only the four keys, refuses to run while any placeholder remains, and strips a dead `bypassPermissions` from `.claude/settings.local.json`. It is a human-run script by design: the auto-mode classifier blocks an agent from rewriting its own permission config, which is correct behaviour.

### Model rubric: Fable 5.1 is the default; capacity is no longer a tiering input

`skills/_shared/review-checklist.md` and `anthropic-configuration-guide.md` now carry the rule the reference fleet adopted on 2026-09-05 with the Claude Fable 5.1 release (`model: fable` → `claude-fable-5-1`, same $10/$50). The July rationales for keeping the Fable roster small are retired, each for a stated reason: the "Opus 5 within 0.5% of Fable" parity claim was true of Fable 5, not 5.1 (Terminal-Bench-Science 52.6 vs 29.0, CursorBench 73.4 vs 70.0); the cyber-classifier objection no longer holds (Fable 5.1 intervenes ~60% less often, and vulnerability-finding is permitted); and the reference project's founder withdrew capacity as a tiering input — quality over quota. The rule is now derived rather than listed: default to Fable for any agent that writes into a shared domain, produces claims that ship, does long-horizon or cross-domain work, or is a review gate; Opus keeps only agents that transcribe rather than author or decide. **Effort moved with it**: `high` is the Fable default (Anthropic's guidance — start high, raise only on measured gain), `xhigh` only where the deliverable is a decision or diagnosis rather than a document, `max` only for correctness-critical offline authoring. Two corrections to what earlier snapshots said: an omitted `effort:` **inherits the launching session's effort** rather than pinning `medium`, and `model:` values remain aliases — never pin a dated ID.

### Vibe Board MCP 2.1.0 — `deviation_flagged` is now a real action

`01-BOOTSTRAP.md` MODE 4 and `skills/review/SKILL.md` have instructed `board_log_activity(action: "deviation_flagged")` since the RIPER template was written — and the Vibe Board MCP validated `action` against a fixed enum that never contained that value. Every call failed Zod validation before reaching Firestore, so the "mandatory" deviation gate was never recordable. Found by an agent auditing its own board against the code: the instruction and the schema were each correct in isolation and were never checked against each other — the failure shape `silent-degradation.md` exists to catch, in the kit itself. In the reference fleet, agents had been retrying as `commented` with "DEVIATION FLAGGED" in the text, so the deviations existed but were unqueryable.

2.1.0 adds the value to the enum at all three sites in `src/tools/activity.ts` (the write tool, the `board_get_activity` filter, and `board_bulk_delete_activity`) and to the `ActivityLog` type, and corrects the tool description that said "or arbitrary actions" — the sentence that made an invented value look supported. Verified by execution against the built server, not by reading: a `deviation_flagged` write succeeds, `board_get_activity(action: "deviation_flagged")` returns exactly that entry, and a nonsense value is still rejected. Pull, `npm run build`, and **reconnect the MCP** — a running server keeps the old schema until restarted. It is a distinct value rather than a `commented` convention because the read filter uses the same enum: "show me every deviation" is one call.

### Fleet tier manifest — `agent-model-tier.py` + `agent-model-tiers.template.json`

The rubric has said for a while that a quota wall can force the fleet onto a fallback model and that the restore must come from a recorded assignment, not from an agent re-deriving one. The kit now ships the tooling that sentence assumed: a manifest with a `preferred` and a `fallback` model+effort pair and a `restore_tier` per agent, and a script whose `check` fails loudly on any disagreement between the manifest and `.claude/agents/` (a file with no entry, an entry with no file, an empty sweep, a missing `model:`/`effort:` line — every path that could report success while doing nothing is an error instead), and whose `apply` plans every file before writing any, so a malformed file is a no-op rather than a half-flipped roster. A tier-scoped `apply preferred --tier N` verifies against the mode it just applied (the reference copy verified against the stale declared mode and exited 1 on a fully successful partial restore — fixed in both copies the day this shipped) and `check --mode <target> --tier N` re-verifies a partial step. Drop the script in `scripts/`, the template at `.claude/agent-model-tiers.json`. `review-agents` now points at it: an agent on the fallback model while the manifest declares `fallback` is not a finding.

### Hooks: per-session review markers, a gitleaks gate, and the review gate's own test

Three changes to Phase 5, one of them a correction. **`review-gate.sh` in the kit had fallen behind the reference implementation**: since 2026-09-01 the live gate namespaces its marker by the session id Claude Code passes in the hook input (`/tmp/ve-review-complete.<session_id>`, consumed on use, 1-hour TTL), so one window's review can never authorize another window's commit — and the kit was still shipping the shared-path version whose deny message told the agent to `touch /tmp/ve-review-complete`. The template is now the live hook, and the deny message tells the agent to create the marker in a SEPARATE call (the hook runs before the command executes, so `touch … && git commit …` denies again). **`gitleaks-gate.sh`** (recommended) scans the staged diff with gitleaks before any commit and denies on a finding, warns-and-allows when gitleaks is not installed, and matches the same commit regex as the review gate; a starter `.gitleaks.toml` ships beside it. **`test-review-gate.sh`** is the gate's end-to-end test against a throwaway repo — compound commands, broad adds, `-a`, `git -C`, per-session markers, cross-window isolation, JSON validity — and Phase 11 now runs it (`24 passed, 0 failed`) instead of the hand-rolled probe that used the legacy marker path. The synced `bootstrap` and `review-security` skills that listed these hooks now describe files the kit actually installs.

## 2026-08 snapshot

### Delegation is context preservation — RIPER now says so in every mode

The `riper-cat.md` template in [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) previously carried an explicit `Delegation:` line in **EXECUTE only**. RESEARCH and INNOVATE were silent on it entirely, PLAN mentioned `assigned_agent` only as a field to fill in, and silence read as permission for the main agent to do the work itself. All four modes now carry an explicit delegation line, under a new preamble that states the rationale once:

- `/close` Step 3 now disposes each dirty file (discard / stash + `[CHORE] Pick up stash` board task / human task) so no stash is orphaned; `session-handoff.sh` prints the machine's `close/` stashes on every SessionStart; `review-board` Step 9a flags a `close/` stash older than 3 days with no task.
- **The rationale, which was written nowhere before**: delegation is not politeness or load-balancing — it is how the orchestrator preserves context. A specialist can spend 300k tokens and return two pages. Main holding those 300k tokens itself is how a session loses the ability to reason across domains, and it is why sessions hit compaction mid-task.
- **RESEARCH** — the specialist researches its own domain; main frames the question and verifies the answer. A specialist that already knows its domain's naming collisions finds in one pass what main hunts for over days. Domain knowledge, not effort.
- **INNOVATE** — options come from the domain owner. A design main authors inside someone else's domain tends to be wrong *in a way that looks correct*.
- **PLAN** — `assigned_agent` **is** the delegation decision, not paperwork.
- **EXECUTE** — main does not implement inside a specialist's domain. **"It's only a few lines" is the failure mode, not the exemption**; undelegated small edits are where defects concentrate, and a specialist catches them afterward anyway.

The preamble notes it only bites once specialist agents exist (the "REFERENCE: Agent Architecture" section, added whenever you're ready) — write the rule at Phase 3 anyway, so the habit is in place when the agents arrive.

### The review-gate conflict: three instructions, no possible winner

If your operator or harness config carries a line like **"do not call the AgentTool unless the user requested it,"** it directly contradicts two things this kit ships: `riper-cat.md` MODE 5's mandatory post-EXECUTE review, and `review-gate.sh`'s deny message telling the agent it has standing approval to auto-run the review. Nothing can satisfy all three.

Both MODE 5 and the `review-gate.sh` section now name the conflict explicitly and require it to be **surfaced on the first commit of the session** rather than resolved silently. The kit deliberately does **not** pick a winner — that's a config-level call for the human. Either relax the config for `code-reviewer` / `test-runner`, or accept human-initiated review and say so in the rule.

> The failure mode this closes is not *missing* the conflict. It is noting it as a known-issue commit after commit and never escalating — four flags, zero escalations, three defects shipped before any review ran.

### Same-commit upkeep — a session-end checklist is a backstop, not a mechanism

Doc, rule, and agent-file updates now ship **in the same commit as the change that motivated them**. Added to the `documentation.md` rule template, MODE 6 COMMIT, and the proactive-trigger tables in both [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) and [`02-VIBE-BOARD.md`](./02-VIBE-BOARD.md).

The reasoning generalizes past docs: **session end is exactly when a checklist is least likely to run.** Sessions get compacted, abandoned, or run out of context mid-task, so any upkeep gated on a clean ending mostly does not happen. That's a rule-design flaw, not a discipline problem — if a step only fires at session end, move it to where the work is.

### MODE 5 — prod-state mutations are reviewable output

REVIEW now explicitly covers changes that leave **no repo diff**: schema applied by hand, workflow edits through a UI or API, live config edits, secret writes, feature-flag toggles. A session can mutate production five ways with two lines of committed code and match none of the line-count-based review triggers. (The `stop-compliance-check.sh` hook was hardened for this in the 2026-07 snapshot; the rule text now matches the hook.)

---

## 2026-07 snapshot

### Opus 5 era — `model:` is an alias, and that's the whole lesson

This kit adopted **Claude Opus 5** (`claude-opus-5`) on 2026-07-27, at unchanged Opus pricing ($5 / $25 per MTok). The framework's model rubric moved with it, but the portable takeaway is smaller and more useful than the rubric itself:

- **Use the `opus` alias in agent frontmatter, never a version-pinned ID.** `model: opus` resolves to whatever Claude Code currently maps `opus` to. On the Opus 5 release, every alias-based agent in the reference fleet picked up the new model with **zero file edits** — the only stale artifacts were docs that had hardcoded "Opus 4.8" in prose. A pinned `claude-opus-4-8` does the opposite: it silently strands the agent on an old model while the docs claim otherwise. The rubric now flags pinned IDs as a review finding, and `review-checklist.md` documents why.
- **Two-model tiering, heavily weighted to Opus.** `model: opus` carries essentially everything, effort-tiered (`xhigh` for orchestration / security / complex-domain / blast-radius work, `medium` default for routine narrow-scope agents). `model: fable` (Claude Fable 5, $10 / $50) is reserved for the narrow case where its remaining edge in general intelligence *is* the deliverable — in the reference fleet, correctness-critical content authoring at `effort: max`.
- **Why so few agents stay on Fable**: Anthropic puts Opus 5 within 0.5% of Fable 5's peak CursorBench 3.2 score (measured at `max` effort) at half the cost; Fable's cyber classifiers refuse benign security work where Opus 5's "intervene around 85% less often"; and Opus 5 is Anthropic's most aligned model to date. On subscription plans Fable is also capacity-capped, which is a real constraint on how wide its roster can be.
- **Prompt-authoring notes for Opus 5**: it self-verifies, so explicit "double-check your work" instructions now cause *over*-verification — delete them rather than rewriting. It also delegates to subagents more readily than Opus 4.8 did (the opposite direction), so "delegate more" guidance written for 4.8 should come out and a cap should go in.
- Model table refreshed to Opus 5 / Fable 5 / Sonnet 5 / Haiku 4.5 across `skills/_shared/review-checklist.md` and `skills/_shared/anthropic-configuration-guide.md`.

> **Correction to the 2026-06 entry below**: it states that Fable 5 was "permanently pulled" by Anthropic. That was accurate when written, but Anthropic **reversed it on 2026-07-18** and Fable 5 is a current, generally-available model. The rubric above reflects the corrected state.

### Hardened review gate + stop compliance check

Both hooks shipped in [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) were rewritten after the previous versions were found to be bypassable or under-scoped in real multi-window use:

- **`review-gate.sh`** — the old version matched `git commit` only at position 0, so any compound command (`git add -A && git commit -m ...`) sailed straight past it; it now matches anywhere in the command. The review marker's TTL was cut to **1 hour** because `/tmp` is shared across all concurrent Claude windows, and a long-lived marker lets one window's review authorize a different window's commit. `.conf` / `.yml` / `.yaml` / `.toml` now count as code, and container/compose directories are no longer excluded — config files frequently auto-deploy.
- **`stop-compliance-check.sh`** — now asks about **prod-state mutations that leave no repo diff** (database DDL / grants / index / matview changes, workflow edits, live config edits), not just lines-of-code changed. A session can mutate production five ways with two lines of committed code, and the old LOC-based trigger missed exactly that case.
- Both hooks **fail open**: on a parse error they allow the action. A hook that blocks all work when it can't read its own input is worse than one that occasionally misses.

---

## 2026-06 snapshot

### Fable 5 retired — Opus 4.8 is the single agent tier *(superseded — see the 2026-07 correction above)*

Anthropic introduced **Claude Fable 5** (`claude-fable-5`) on 2026-06-09 as a short-lived successor tier above Opus 4.8, then **permanently pulled it in 2026-06**. *(Superseded: Anthropic reversed this on 2026-07-18 — Fable 5 is currently generally available. See the 2026-07 entry.)* The brief Fable sweep — which split agents across two models (Fable for orchestration / security / blast-radius / correctness-critical authoring; Opus for routine) — is **fully reverted**.

- **Single model tier**: every agent now runs on **Opus 4.8** (`claude-opus-4-8`). Reserved tiers unchanged: `claude-sonnet-4-6` (speed-critical edge cases), `claude-haiku-4-5` (read-only exploration).
- **Tiering is by effort only** (model is uniform): `effort: xhigh` for orchestration / security / complex-domain / blast-radius / request-path work, `effort: max` for correctness-critical authoring, `medium` (default) for routine narrow-scope agents.
- Agent frontmatter, the model rubric (`skills/_shared/review-checklist.md`), and the configuration guide all drop Fable as a usable model; the rubric now flags any agent still pinned to `model: fable` / `claude-fable-5` for correction.

### New skill — `/self-improve`

Added the **`/self-improve`** skill: mines Vibe Board review findings + worker-batch outcomes for **recurring** patterns and encodes preventive guardrails (LESSONS.md rules applied; agent/CLAUDE.md hardening proposed). The behavioral complement to the structural `/review-*` audits — turns "what reviewers keep catching" into "encoded so it stops happening." Governing rule: a one-off is never a rule (≥2 distinct occurrences required before a guardrail is encoded).

---

## 2026-05 snapshot

### Vibe Board MCP 2.0.0 — orphan-parent guard (breaking)

The Vibe Board MCP server itself is now versioned (jumped 1.0.0 → 2.0.0). The breaking change: `board_update_task(status="done")` now REJECTS the call when the task has open (non-done) children unless an explicit `on_open_children` directive is passed. Same enforcement on `board_bulk_update_tasks`.

**Why**: documented bidirectional reconciliation rule existed for months but recurringly failed — agents would close parents and silently orphan 5-9 real children that then rotted for weeks. Doc-only enforcement isn't enough; the data layer needs to refuse.

**The new API**:

```typescript
// Close a parent with no children — works as before
board_update_task({ task_id, status: "done" })

// Close a parent WITH open children — now REJECTS without directive
// → { error: "Refusing to close ...: has N open child(ren)",
//     open_children: [...], resolution: "Re-call with on_open_children=..." }

// Three options to proceed:
board_update_task({ task_id, status: "done", on_open_children: "close_all" })
// cascade-closes all children atomically via runTransaction

board_update_task({ task_id, status: "done", on_open_children: "detach" })
// clears parent_task_id on each open child (children become flat tasks)

board_update_task({ task_id, status: "done",
  on_open_children: "leave_attached",
  reason: "scope shifted — children belong to followup parent X" })
// closes parent anyway, leaves orphans; REQUIRES non-empty reason
```

**Child-close advisory** (additive, non-breaking): closing a child whose parent now has zero open siblings returns `parent_now_empty: { id, title }` in the response. Surfaces the parent-reconciliation opportunity inline.

**Bulk path** supports only `on_open_children: "leave_attached"`. For cascade in bulk, callers should use single-task `board_update_task` per parent so each cascade is its own atomic transaction.

**Implementation notes**: uses Firestore `runTransaction` (not `WriteBatch`) for cascade so concurrent child creation between the guard's read and the write is detected and retried — `WriteBatch` has no read-set and would silently orphan freshly-created children. Per-child activity_log entries cite the cascade source for audit attribution. Transactions cap at 500 ops; cascades beyond that (extremely rare) reject with a chunking instruction.

**Migration path for callers**: none of the in-tree callers were affected (n8n workflow audit + repo grep showed zero callers). The error message IS the migration path — any future caller hitting the rejection sees exactly what directive to add.

---

## 2026-04 snapshot

### Onboarding overhaul

Cold-visitor setup used to be "read the 1500-line BOOTSTRAP.md and figure it out." Three structural improvements:

**Three install paths, all convergent**:

1. **`curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash`** stages the kit in `.ve-kit/` and writes the exact Claude Code prompt. Detects fresh-setup vs upgrade automatically. Refuses to clobber unrelated git repos that happen to live at `.ve-kit/` (origin-URL assertion). Supports `VE_KIT_COMMIT=<sha>` pinning for reproducible team installs.
2. **Paste-a-prompt** — open Claude Code anywhere and tell it to fetch the bootstrap URL and run the protocol. Zero local files.
3. **`/bootstrap` skill** — once ve-kit is local, typing `/bootstrap` in a Claude Code session runs the protocol. `disable-model-invocation: true` so vague "help me set up" phrases can't auto-trigger it. Also handles upgrades against existing `.claude/` configs.

All three paths converge on the same interactive protocol: prerequisite checks → ~6 project questions → automated setup → self-verify. ~15-20 min for Layer 1 + Layer 2.

**README optimized for drive-by visitors**:

- Get Started sits as section 2, right after the "Why this exists" problem framing — you can start installing without scrolling past meta-sections.
- Compact 3-option quick-reference in the README; detailed walkthrough in [`00-GET-STARTED.md`](./00-GET-STARTED.md).
- Optional-companion section for `ve-gws` is a 2-line pointer in the README; full guide lives in [`04-GOOGLE-WORKSPACE-MCP.md`](./04-GOOGLE-WORKSPACE-MCP.md).

**Numbered file ordering**:

Top-level docs now sort in reading order when browsing the repo on GitHub:

```
00-GET-STARTED.md          ← start here
01-BOOTSTRAP.md            ← Layer 1 protocol (phases 0-11)
02-VIBE-BOARD.md           ← Layer 2 MCP server
03-VE-WORKER.md            ← Layer 3 Docker worker
04-GOOGLE-WORKSPACE-MCP.md ← optional companion (ve-gws)
05-DEVELOPER-SETUP.md      ← per-developer half (2026-09) + user-settings.template.json + merge-user-settings.py
agent-model-tier.py        ← fleet tier manifest tooling (2026-09) + agent-model-tiers.template.json
CHANGELOG.md               ← this file
README.md                  ← project overview
init.sh                    ← installer
skills/                    ← drop-in .claude/skills/
```
*(tree refreshed 2026-09-12; the 2026-04 snapshot shipped 00–04 only)*

### Opus 4.7 era — model + effort tiering

Anthropic released **Claude Opus 4.7** with a step-change in agentic coding + a new `xhigh` effort level (between `high` and `max`). The framework now leans into this:

- Default agent tier: `model: opus`, effort omitted (= `medium`)
- Complex-tier agents (orchestrators, security review, blast-radius infra, complex AI): add `effort: xhigh` — deeper reasoning where quality pays for itself
- Sonnet/Haiku: reserved for narrow use cases (read-only exploration, speed-critical checklists). Most agents on a Max-plan subscription are better off as Opus.

Rubric now codified in [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) and in the ve-worker config (see [`03-VE-WORKER.md`](./03-VE-WORKER.md)).

### `/review-*` skill family — periodic config audits

Eight new skills that systematically review the `.claude/` tree plus docs/memory/board. **Included in this package** under [`skills/review-*`](./skills/) — drop them into your project's `.claude/skills/` to get the same pattern:

| Skill | Audits |
|------|--------|
| `/review-agents` | `.claude/agents/*.md` frontmatter, staleness, model tier, Anthropic schema |
| `/review-skills` | `.claude/skills/*/SKILL.md` frontmatter, progressive-disclose, trigger clarity |
| `/review-rules` | `CLAUDE.md` + `.claude/rules/*.md` (size, cross-refs, rule-hook alignment) |
| `/review-docs` | `docs/**/*.md` (broken links, staleness, index currency) |
| `/review-memory` | Per-project memory dir (index currency, type correctness) |
| `/review-board` | Vibe Board itself (stale in-progress, orphans, abandoned projects) |
| `/review-security` | `.claude/` config security (secrets, permissions, fail-closed hooks) *(corrected 2026-09-20 — it audits whether each hook's failure behaviour matches its documentation; the hooks fail open)* |
| `/review-all` | Orchestrator — runs all the above |

Each skill files findings as severity-tiered subtasks on the board — never prose. Run quarterly or after major upgrades. Pattern documented in the bootstrap's "Recommended starter skills" section.

The package also includes:
- **RIPER workflow skills**: [`skills/go`](./skills/go/), [`skills/plan`](./skills/plan/), [`skills/review`](./skills/review/) — the scaffolding that turns single-session Claude Code into a disciplined workflow with plan/review gates.
- **Shared reference material**: [`skills/_shared/`](./skills/_shared/) — canonical Anthropic configuration guide + actionable review checklist cited by every review-* skill.

After copying into your own project, find-and-replace `<YOUR_AUDIT_PROJECT_ID>` and `<your-domain>` placeholders with your actual values.

### Security hardening

- **Hooks fail CLOSED on JSON parse errors**. Previously hooks that couldn't parse their input exited 0 (allow). Now they emit a deny response — safer default. *(corrected 2026-09-20 — see Corrections. This was reverted: the hooks in this kit fail OPEN, and this entry's claim outlived the behaviour it described by two snapshots.)*
- **`disallowedTools` pattern** for read-only review agents. `code-reviewer`, `test-runner`, `processor` now have `disallowedTools: [Write, Edit, NotebookEdit]`. Reduces blast radius if a prompt-injection attack lands in any review agent.
- **`bypassPermissions` + deny list** pattern (BOOTSTRAP recommendation). Comprehensive deny list covering destructive rm, git force-ops, DB drops, GCP deletions, Docker nukes. Eliminates prompt fatigue without reducing safety.

### Vibe Board — now 14 tools (five new: project-reassign, bulk moves, hard-delete, single-task get, activity-log read)

*(corrected 2026-09-20 — accurate as a record of what that release added; the total has since grown to 21 and the kit repeated "14" long after. See Corrections.)*

Filled the biggest gaps in the board MCP so day-to-day operations don't require dropping out to NocoDB or Firestore. Full tool list in [`02-VIBE-BOARD.md`](./02-VIBE-BOARD.md#mcp-tool-reference).

- **`board_update_project`** — change project status/name/description/metadata. Enforces status transitions (active → completed/archived). Archive a completed project without leaving the CLI.
- **`board_update_task` now accepts `project_id`** — move a task to a different project. Validates target exists, warns if subtasks orphaned in source. Direct enabler for consolidating small projects.
- **`board_bulk_update_tasks`** — apply the same update (project_id / status / priority / assigned_agent) to 1-100 tasks atomically. All-or-nothing. Used to consolidate 5 related sub-projects into one via a single call.
- **`board_get_task`** — fetch a single task by ID with all fields + ISO timestamps.
- **`board_delete_task`** — hard-delete with `require_done=true` safety guard by default (refuses to delete in-progress work unless you pass `require_done=false`). Optional `cascade_subtasks`. Deletes associated activity_log entries with atomic-batch ordering that can't orphan history on partial failure.
- **`board_get_activity`** — query the activity_log (filter by task_id / session_id / agent_name / action). Cursor-paginated, newest-first via server-side orderBy, returns `{entries, scanned, truncated}` so callers know when filters were too selective to fill the limit. Pairs with `board_log_activity` to close the write-then-read audit loop.

### Review-gate auto-run

Previously: `git commit` blocked → ask user to run review → user says yes → run review → commit. Now: `git commit` blocked → auto-invoke code-reviewer (and test-runner if applicable) → report findings → if no critical/high, commit. Only pauses for findings that need user judgement.

Removes rubber-stamp friction without weakening safety.

### Cost footprint — subscription + Vertex only

*(corrected 2026-09-20 — the "zero per-token API usage" principle still holds and is restated in the README's Tech + cost footprint section. Two details here are stale or never applied to the kit: the Vertex AI Gemini line describes the reference project's own application, not anything ve-kit ships or requires; and the pinned `--model claude-opus-4-7` is neither current nor kit doctrine — the worker's model is a per-project call. See Corrections.)*

Framework now verifies zero per-token Anthropic or OpenAI API usage. All AI either runs on:
- Claude Code subscription (agent work via `CLAUDE_CODE_OAUTH_TOKEN`)
- Google Vertex AI Gemini (app-level AI, already on project's GCP bill)

Admin/UI patterns that previously implied Anthropic/OpenAI direct API use have been removed. VE Worker pinned to `--model claude-opus-4-7` on the subscription auth path.

### Naming convention: `.env-example` (not `.env.example`)

Gitignore pattern `.env.*` was silently catching `.env.example` templates and not shipping them. The framework now uses `.env-example` for templates so they commit normally, with actual secrets in `.env` (still ignored).

---

## How to consume this snapshot

Three patterns work:

1. **Install via `init.sh`** (recommended) — run the curl-bash one-liner in [00-GET-STARTED.md](./00-GET-STARTED.md) from inside your target project.
2. **Point sharers at the repo** — [github.com/HuntsDesk/ve-kit](https://github.com/HuntsDesk/ve-kit) is browseable. Readers start with `README.md` → `00-GET-STARTED.md`.
3. **Fork / copy the files** — each file is self-contained; copying ve-kit's top-level `.md` files and `skills/` into another repo gets them started.

If you're on an older ve-kit snapshot (pre-2026-04), diff your files against this one to spot the new onboarding paths and file numbering.

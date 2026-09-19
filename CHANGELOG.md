# Changelog — Vibe Coding Framework

Snapshot-level changelog. Covers what's new in this share package since prior distributions. Version-stamped by date, not semver — this is a pattern library, not a package.

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

The template adds `"ask": ["Bash(git push*main*)"]` — spaceless, so the refspec forms `dev:main`, `HEAD:main` and `refs/heads/main` match too. Ask rules are never auto-approved in any mode, including `auto` and `bypassPermissions`, which makes them the deterministic form of the rule `riper-cat.md` and `multi-window-coordination.md` already state in prose: a push to `main` is a production deploy and needs the human's approval each time.

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
| `/review-security` | `.claude/` config security (secrets, permissions, fail-closed hooks) |
| `/review-all` | Orchestrator — runs all the above |

Each skill files findings as severity-tiered subtasks on the board — never prose. Run quarterly or after major upgrades. Pattern documented in the bootstrap's "Recommended starter skills" section.

The package also includes:
- **RIPER workflow skills**: [`skills/go`](./skills/go/), [`skills/plan`](./skills/plan/), [`skills/review`](./skills/review/) — the scaffolding that turns single-session Claude Code into a disciplined workflow with plan/review gates.
- **Shared reference material**: [`skills/_shared/`](./skills/_shared/) — canonical Anthropic configuration guide + actionable review checklist cited by every review-* skill.

After copying into your own project, find-and-replace `<YOUR_AUDIT_PROJECT_ID>` and `<your-domain>` placeholders with your actual values.

### Security hardening

- **Hooks fail CLOSED on JSON parse errors**. Previously hooks that couldn't parse their input exited 0 (allow). Now they emit a deny response — safer default.
- **`disallowedTools` pattern** for read-only review agents. `code-reviewer`, `test-runner`, `processor` now have `disallowedTools: [Write, Edit, NotebookEdit]`. Reduces blast radius if a prompt-injection attack lands in any review agent.
- **`bypassPermissions` + deny list** pattern (BOOTSTRAP recommendation). Comprehensive deny list covering destructive rm, git force-ops, DB drops, GCP deletions, Docker nukes. Eliminates prompt fatigue without reducing safety.

### Vibe Board — now 14 tools (five new: project-reassign, bulk moves, hard-delete, single-task get, activity-log read)

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

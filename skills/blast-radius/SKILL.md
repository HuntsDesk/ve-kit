---
name: blast-radius
description: Before a risky change (migration, RLS, payment, auth, shared module, infra, settings/hooks) or on "blast radius" / "what could this break" / "impact": runs scripts/blast-radius.sh, then names the fact the change is safe because of and proves it by running something.
argument-hint: "[--staged | --range A..B | --files <paths>]"
user-invocable: true
---

# /blast-radius — evidence, then one proven safety fact

The script gathers evidence. You supply the judgment: read what it flagged, say **"This is safe because <fact>"**, and prove that fact by executing something. An argument is not a proof; a passing command is.

Three disciplines sit under it: read every reader to the point where state actually changes, scope a fix by concept rather than by directory (and check parameter defaults, not just call sites), and treat an empty result as a claim about the search, not a fact about the system.

## 0. Setup

The engine is `scripts/blast-radius.sh`, a generic, read-only script; every project fact lives in its config, `.claude/blast-radius.conf` (format: the CONFIG block in the engine's header). It needs `git`, `jq` and ast-grep (`sg`); ripgrep is optional (it falls back to `git grep`). With no config, every run reports `PROBE_FAILED=config` and exits 2. `bash scripts/blast-radius.sh --self-test` proves the config parser, its fail-closed reasons and the `never_read` refusal, reading nothing.

## 1. Run the script

Pick the mode that matches the change. Pass `$ARGUMENTS` through when the user gave one.

| Change | Command |
|---|---|
| Staged, about to commit | `bash scripts/blast-radius.sh --staged` |
| Unstaged edits or a planned change | `bash scripts/blast-radius.sh --files <paths>` |
| Commits, e.g. before a push | `bash scripts/blast-radius.sh --range <base>..HEAD`, where `<base>` is the branch you push to (e.g. `origin/main`) |

Run it in full mode (no `--brief`); `--brief` is for hooks. Add `--guards` before a production push to also run the config's `banned_guard` script.

**Exit 2 means a probe failed, not that nothing was found.** Each `PROBE_FAILED=<name>` line names the blind spot. Fix the cause (missing `sg`/`jq`/ripgrep, bad range), or run that probe by hand, before you rely on any key it feeds. `IMPORTERS=UNKNOWN` and `TABLES=UNSEARCHED` are unknowns, never zeros. So are `KEY=SKIPPED(not configured: <directive>)` (the config does not cover that probe) and a value prefixed `UNCONTROLLED(no <directive>):` (a search with no positive control). `PROBE_FAILED=config (<reason>)` means `.claude/blast-radius.conf` failed to load, and nothing was evaluated.

## 2. Read what it flagged

Open each flagged reader with Read. The script finds candidates by module name and SQL shape; only reading tells you whether a reader depends on what you changed. Work through these, highest stakes first:

- **`ONE_WAY`**: anything listed here cannot be quietly rolled back by reverting a commit. The labels are the config's `one_way` lines.
- **`DUAL_ACCESS`**: the table is read by the frontend directly and by backend services. Plain names come from the config's dual-access list; `(derived)` means the script found readers in both tiers for a table that list misses. The `fe=`/`be=` counts tell you which tier you have not looked at yet; that is where breakage hides.
- **`SYMBOLS` marked `REMOVED`**: every remaining reference is a break.
- **`IMPORTERS`**: a changed signature, return shape or default value reaches every importer. Check the parameter **default**, not just the call sites.
- **`VENDORED`**: every byte-identical copy must change in the same diff (the config's `vendored_guard` checks it). `NOTES` names the intentional forks the guard does not cover.
- **`TRIGGERS_*`**: the services this deploys. Before a production push, check that none of them is midway through a long-running job: a deploy restarts it.
- **`FLAGS`**: a flag-gated surface is inert in production until the flag flips, which is often the actual safety fact.

Look past the obvious callers for the reader nobody imports: a cron or scheduled workflow, an RPC or view in `migrations/`, a second service querying the same column. The table readers exclude tests and migrations, so search those yourself when the change is to schema.

## 3. Name the fact and prove it

Write one sentence: **"This is safe because <fact>."** Pick the narrowest fact that, if false, would make the change unsafe. Then run something that would fail if the fact were false:

| Kind of fact | Proof that counts |
|---|---|
| "No other reader depends on X" | A search with a **positive control**: show it finds a known reader of X first, then show the count of others is 0. |
| "No row is in state Y" | A read-only query that cannot fail silently (`psql -v ON_ERROR_STOP=1`, stderr kept), showing the count. |
| "Behaviour is pinned" | Run the named test, then show it fails when the change is reverted (mutation), so the test is not decoration. Mutate a scratch copy or a worktree, never the shared tree: other windows commit from it. |
| "Surface is dark in prod" | The flag's production state, plus the gate's `file:line`. |
| "Copies are in sync" | The config's `vendored_guard` script exits 0. |

Cite `file:line` for every reader you rely on. If no command can prove the fact, say so and state the claim as unproven; do not upgrade it to "safe".

**When the proof needs a domain owner, name the specialist instead of guessing** (whoever owns schema, payments, auth, flags, deploys or infrastructure in your roster).

## 4. Report

Return this shape, under about 20 lines:

```
BLAST RADIUS: <files> — exit <rc>
Reaches: <tables / importers / services, with counts>
One-way doors: <list or none>
Safe because: <one fact>
Proof: <command> -> <result> (rc=<n>); readers read: <file:line, ...>
Unproven / needs owner: <claim> -> <specialist>
```

If the proof fails, the change is not safe yet. Say what would make it safe (flag-gate, migration-first, hold back; `multi-window-coordination.md` §2) instead of reporting a verdict.

## Limits of the script

- The script is a generic engine; every project fact (trigger map, vendored registry, dual-access list, flag patterns, controls, guards, `never_read` paths) is in `.claude/blast-radius.conf`. The trigger map there is a snapshot: the real filters live in your CI system, so re-derive them before a production push.
- Importers: ast-grep import statements, matched by module name. TS specs are resolved (relative, and the config's `ts_alias` prefixes); Python is scoped per `scope_root` directory, one build context each.
- Tables come from SQL keywords and `.from('t')` in changed lines (`ddl` = the change creates, alters or drops it, table or view; `write` = it otherwise writes to it; `ctx` = elsewhere in a changed file). Dynamic table names and ORM calls are invisible.
- Caps: readers are searched for 10 tables (`ddl` targets, then other writes, then the most-mentioned) and references for 12 symbols (removed or renamed first, then changed, then added); `TABLES_NOT_SEARCHED` / `SYMBOLS_NOT_SEARCHED` count the rest. `--brief` shows 6 items per list and says how many it cut.
- Paths are canonicalised before any check (`./`, `..`, case on macOS); a path outside the repo is `PROBE_FAILED=outside_repo`, not "none", and a directory is refused (`not_a_file`). `--self-test` proves that, the config's fail-closed reasons and the `never_read` refusal on strings, including variants derived from each entry.
- Paths under the config's `never_read` entries are refused before any lookup and excluded from every walker (git, ripgrep, ast-grep), including through symlinks.

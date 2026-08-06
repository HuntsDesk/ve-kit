# Changelog — Vibe Coding Framework

Snapshot-level changelog. Covers what's new in this share package since prior distributions. Version-stamped by date, not semver — this is a pattern library, not a package.

---

## 2026-08 snapshot

### Delegation is context preservation — RIPER now says so in every mode

The `riper-cat.md` template in [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) previously carried an explicit `Delegation:` line in **EXECUTE only**. RESEARCH and INNOVATE were silent on it entirely, PLAN mentioned `assigned_agent` only as a field to fill in, and silence read as permission for the main agent to do the work itself. All four modes now carry an explicit delegation line, under a new preamble that states the rationale once:

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
CHANGELOG.md               ← this file
README.md                  ← project overview
init.sh                    ← installer
skills/                    ← drop-in .claude/skills/
```

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

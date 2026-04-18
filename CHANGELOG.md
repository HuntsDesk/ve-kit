# Changelog — Vibe Coding Framework

Snapshot-level changelog. Covers what's new in this share package since prior distributions. Version-stamped by date, not semver — this is a pattern library, not a package.

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
- **`board_bulk_update_tasks`** — apply the same update (project_id / status / priority / assigned_agent) to 1-100 tasks atomically. All-or-nothing. Used to consolidate 5 NextGen sub-projects into one via a single call.
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

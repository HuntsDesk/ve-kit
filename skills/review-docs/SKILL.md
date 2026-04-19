---
name: review-docs
description: Review the docs/ hub for broken links, staleness, duplicate coverage, index currency, and size bloat. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Docs Review Protocol

Reviews the project documentation tree at `docs/**/*.md` plus the master index at `docs/README.md`.

Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md).

**Owner**: `docs-manager` agent.

## When to invoke

- After multiple features ship without doc updates
- Quarterly audit
- Before a new team member onboards
- After significant infrastructure changes (service migrations, architecture shifts)

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Inventory

- Glob `docs/**/*.md` (excluding `archive/` and `code-backup/`)
- Record: file path, line count, last git commit date (via `git log -1 --format=%cs -- <file>`)
- Parse `docs/README.md` — extract every link and match to actual file

## Step 2 — Index currency

For `docs/README.md`:
- Every top-level doc mentioned? (Glob `docs/*/README.md` + `docs/*.md`)
- Every link resolves (no broken paths)?
- Any docs in `docs/` not referenced from the README?
- Order/tier still accurate?

Flag:
- Orphaned docs (exist but unlisted)
- Dead links (listed but file missing)
- README section headers out of date

## Step 3 — Link integrity

For each doc file, check every markdown link `[text](path)`:
- Relative paths resolve
- External URLs still reachable (spot-check; full check is expensive — skip unless asked)
- Cross-repo links (pointing to CLAUDE.md, .claude/rules/, services/) resolve
- Line-anchor links (`#L42`) valid

## Step 4 — Staleness

For each doc, flag:
- Last commit > 9 months ago + file still referenced as "current" / "primary" (likely stale)
- References to Supabase Edge Functions (retired 2026-02-24)
- References to retired services, tables, or domains
- "Last updated" markers that are older than 6 months if the file implies ongoing currency
- Model ID references (should be Opus 4.7 / Sonnet 4.6 / Haiku 4.5)
- Deprecated Claude Code commands
- Stripe API version mismatch (currently `2025-08-27.basil`)

## Step 5 — Duplicate content

For the tree as a whole:
- Files covering the same topic in different directories (e.g., `docs/auth/` + `docs/authentication/`)
- Sections within files that duplicate content from other files
- Versioned docs (`-v1.md`, `-new.md`, `-updated.md`) — consolidate into single authoritative source

## Step 6 — Size and shape

| Doc type | Target | Hard limit |
|----------|--------|------------|
| Individual doc | < 500 lines | 800 lines |
| README.md in a sub-dir | < 200 lines | 300 lines |
| Master `docs/README.md` | < 150 lines (it's an index) | 250 lines |

Flag oversized docs for splitting.

## Step 7 — Orphan directories

- Directories with only archived content (should be moved to `docs/archive/`)
- Empty directories
- Directories without a `README.md` (convention violation)
- Nested directories beyond 3 levels deep (restructure)

## Step 8 — Code references

For each doc, spot-check (don't brute-force all):
- Referenced file paths exist (`src/…`, `services/…`)
- Referenced function names still exist (Grep)
- Referenced database tables still exist
- Referenced API endpoints still active

Flag broken references. Priority: docs that are canonical references for a feature (e.g., `CURRENT-TWO-TIER-ARCHITECTURE.md`) get stricter checks.

## Step 9 — Canonical source validation

For key docs flagged as "source of truth" in CLAUDE.md:
- `docs/case-law/CURRENT-TWO-TIER-ARCHITECTURE.md`
- `docs/chat/v4/README.md`
- `docs/stripe/README.md`
- `docs/deployment/cloud-build-migration.md`
- `docs/mig/README.md`
- `docs/n8n/architecture.md`
- `docs/security/CSP-Policy-Guide.md`

Each must be up-to-date, self-contained, and free of broken refs.

## Step 10 — File findings to the board

Create parent tasks per severity + subtasks on project `<YOUR_AUDIT_PROJECT_ID>`. Assigned agent: `docs-manager`.

## Step 11 — Summary

Return ≤ 100 words:

```
DOCS REVIEW COMPLETE
- [N] docs reviewed ([X] in archive — skipped)
- [C/H/M/L] findings per severity → board parent tasks
- [O] orphan docs
- [D] duplicate-content pairs
- [B] broken internal links
```

## Anti-patterns to flag

- Docs that reference removed features as current
- `-v2.md`, `-new.md`, `-updated.md` file naming
- README-less subdirectories
- Docs > 800 lines without a table of contents
- Index entries that don't match the linked doc's title
- "Coming soon" / "TODO" markers older than 6 months

## Tools used

- Read, Glob, Grep
- Bash (restricted): `git log -1 --format=%cs -- <file>` for last-modified dates
- Board MCP (create_task, update_task, log_activity)
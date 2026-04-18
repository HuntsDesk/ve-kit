---
name: review-memory
description: Review the per-project auto-memory directory at ~/.claude/projects/<slug>/memory/ for index currency, stale entries, duplicates, type correctness, and uncaptured patterns. Creates board tasks for every finding.
disable-model-invocation: true
user-invocable: true
---

# Memory Review Protocol

Reviews the auto-memory system that persists across Claude Code conversations. Scope for this project:

```
~/.claude/projects/<your-project-slug>/memory/
├── MEMORY.md          (index, always loaded into context — lines after 200 are truncated)
└── *.md               (individual memory files, loaded on demand)
```

Part of the `review-*` skill family. Cites [../_shared/review-checklist.md](../_shared/review-checklist.md).

**Owner**: `docs-manager` agent.

## When to invoke

- MEMORY.md approaching 200 lines (truncation risk)
- After multiple sessions create new memories without pruning
- Quarterly audit
- When memories start feeling stale or duplicated

## Output contract

Board tasks only. Lean summary to main agent.

---

## Step 1 — Inventory

- Read `~/.claude/projects/<your-project-slug>/memory/MEMORY.md` — record line count, every `- [Title](file.md) — hook` entry
- Glob every `*.md` in that directory (excluding `MEMORY.md`)
- For each memory file, parse frontmatter: `name`, `description`, `type` (user/feedback/project/reference)
- Record body length and last-modified time

## Step 2 — Index integrity

For `MEMORY.md`:
- **Line count < 200** (lines after 200 are truncated out of context — critical)
- Every `*.md` memory file referenced? (orphaned memory files are dead)
- Every `- [link](file.md)` resolves?
- Every entry has a one-line hook < 150 chars?
- No duplicate entries?
- Organized semantically (not chronologically)?

## Step 3 — Frontmatter validation

For each memory file:

| Issue | Severity |
|-------|----------|
| Missing frontmatter | high |
| `type` missing or invalid (must be user/feedback/project/reference) | high |
| `name` missing | medium |
| `description` missing or generic | medium |
| Body doesn't match declared type | high |

### Type correctness

- `user` — user role, preferences, responsibilities, knowledge
- `feedback` — guidance given by user, with Why: + How to apply:
- `project` — ongoing work, goals, initiatives, with Why: + How to apply:
- `reference` — pointers to external systems

Flag type mismatches (e.g., a `project` memory that's actually feedback).

## Step 4 — Staleness

For each memory file, check for:
- References to deleted files, retired services, removed features
- References to superseded architecture (e.g., pre-Supabase-shutdown patterns)
- Relative dates (must be absolute — "Thursday" is stale on the fourth day)
- Project memories from completed/cancelled initiatives (move to reference or delete)
- Feedback memories about behavior that's no longer desired

For `project` type memories specifically: they decay fastest. Flag any older than ~3 months that aren't `reference`-type pointers.

## Step 5 — Duplication

For the memory tree as a whole:
- Two memories covering the same rule/pattern
- Memories that duplicate content from CLAUDE.md or a rule (memory should be personal/project context, not codified rules)
- Multiple memory files with overlapping names (`ops_git.md` + `ops_git_hygiene.md`)

Recommend merging.

## Step 6 — Content freshness

For each memory file, spot-check:
- File paths mentioned exist
- Commit hashes still reachable (`git cat-file -e <hash>`)
- Service names, URLs, and ports current
- Memory should reference current terminology (Opus 4.7, not 4.6)

## Step 7 — Uncaptured patterns

Scan recent conversation artifacts (board activity, recent commits) for patterns that should be memories but aren't:
- Novel ops fixes
- User-confirmed behaviors ("yes, keep doing that")
- Operational gotchas that would help future sessions
- References to systems/tools not yet in the reference memories

Flag as "Capture pattern [X] as memory (type: Y)".

## Step 8 — Memory vs. rule boundary

Memory should be:
- Personal (user role, preferences)
- Project-specific (ongoing work context)
- Reference (pointers to external systems)
- Feedback (guidance)

Memory should NOT be:
- Codified rules (those belong in `.claude/rules/`)
- Ephemeral task state (that belongs on the Vibe Board)
- Generic code conventions (those belong in CLAUDE.md or rules)

Flag memories that are actually rules-in-disguise → recommend promotion to `.claude/rules/`.

## Step 9 — File findings to the board

Create parent tasks per severity + subtasks on project `<YOUR_AUDIT_PROJECT_ID>`. Assigned agent: `docs-manager` (or leave unassigned if the user should decide personally — memory is their domain).

## Step 10 — Summary

Return ≤ 100 words:

```
MEMORY REVIEW COMPLETE
- MEMORY.md: [N] lines (hard limit 200)
- [X] memory files reviewed
- [C/H/M/L] findings per severity → board parent tasks
- [S] stale memories
- [D] duplicates
- [U] uncaptured patterns
- [R] rule-promotion candidates
```

## Anti-patterns to flag

- MEMORY.md > 200 lines (content after 200 is silently dropped)
- Memory files without frontmatter
- Memories mixing types (half user preference, half project fact)
- Relative dates ("last Thursday", "next week")
- Memories that should be board tasks (ephemeral action items, not persistent knowledge)
- Duplicate memories from different sessions

## Tools used

- Read, Glob, Grep
- Bash (restricted): `ls ~/.claude/projects/...` to enumerate files
- Board MCP (create_task, update_task, log_activity)
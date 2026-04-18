---
name: bootstrap
description: Use when setting up a new project with the ve-kit framework, adding a layer to an existing setup, or upgrading an older .claude/ config. Runs the ve-kit BOOTSTRAP protocol interactively — prerequisite checks, project-info questions, writes all rules/hooks/skills/agents files, builds the Vibe Board MCP server, self-verifies at the end. Triggers on "/bootstrap", "set up this project with ve-kit", "run the bootstrap", or "upgrade my ve-kit setup".
user-invocable: true
disable-model-invocation: true
---

# /bootstrap — run the ve-kit BOOTSTRAP protocol

This skill runs the ve-kit project-setup protocol interactively. The protocol file (`01-BOOTSTRAP.md`) is written as executable steps, not just docs — you READ it and then DO the phases, asking the user questions as you go.

## When to invoke this skill

- User types `/bootstrap`
- User says "set up my project with ve-kit" / "run the bootstrap" / "follow @01-BOOTSTRAP.md"
- User says "upgrade my ve-kit" / "update my .claude/ config to the latest ve-kit"
- User says "add the Vibe Board to this project" (run Phase 4 only)
- User says "add the worker layer" (point them at `03-VE-WORKER.md` — the worker is a separate setup)

## Step 1 — Locate `01-BOOTSTRAP.md`

Check these paths in order, use the first one that exists:

1. `.ve-kit/01-BOOTSTRAP.md` — staged via `init.sh` (most common for first-time users)
2. `docs/ve-kit/01-BOOTSTRAP.md` — already inside a project that has ve-kit checked in
3. `~/github/ve-kit/01-BOOTSTRAP.md` — user has a separate ve-kit clone

If none exist, WebFetch `https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/01-BOOTSTRAP.md` and read from there. If WebFetch isn't available, tell the user to run `curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash` first.

## Step 2 — Detect fresh setup vs upgrade

- **Fresh setup**: no `CLAUDE.md`, no `.claude/` directory. Run the normal Phase 0 → Phase 11 flow.
- **Upgrade mode**: `CLAUDE.md` exists OR `.claude/` exists. Run the upgrade path documented at the END of `01-BOOTSTRAP.md` (the "When a user says 'upgrade @bootstrap.md'" section) — diff their existing config against the current ve-kit template, ask what to update, don't overwrite anything without confirmation.

## Step 3 — Run the protocol

Follow `01-BOOTSTRAP.md` literally. The phases are:

| Phase | What |
|---|---|
| 0 | Prerequisite check (gcloud, firebase, node, Docker optional, Claude Code CLI) |
| 1 | Project questions (name, description, language, GCP project ID, default branch, deny-list additions) |
| 2 | Create `.claude/`, `docs/`, `mcp-vibe-board/` directory structure |
| 3 | Write rule files: `riper-cat.md`, `code-quality.md`, `documentation.md`, `git-workflow.md`, `agent-board.md` |
| 4 | Set up Vibe Board (Firestore project, service account, MCP server, `.mcp.json`) |
| 5 | Install hooks: `block-todowrite.sh`, `session-handoff.sh`, `post-compact-recovery.sh`, `review-gate.sh`, `stop-compliance-check.sh` |
| 6 | Permissions + deny list (`settings.json` merged with hooks config) |
| 7 | Write `CLAUDE.md` using the user's Phase 1 answers |
| 8 | Write `docs/README.md` |
| 9 | Install code intelligence plugins (language-specific LSPs) |
| 10 | Install starter skills (`plan`, `review`, `go`, `/review-*` family, this `/bootstrap` skill) |
| 11 | Self-verify (check files exist, hooks executable, board connectivity, skills loaded) |

## Step 4 — User-specified layer choices

Listen for what the user wants:

- **"Layer 1 only"** (minimal): skip Phase 4 (Vibe Board). Skip `/review-board` skill. Do everything else.
- **"Layer 1 + 2"** (recommended default): include Phase 4. Skip `03-VE-WORKER.md` setup.
- **"Layer 1 + 2 + 3"** or **"all layers"**: after Phase 11, point them at `03-VE-WORKER.md` and offer to walk them through it. The worker is Docker-based — don't try to set it up in the same session; it has its own prerequisites.
- **"Just Vibe Board"**: jump to Phase 4, assume CLAUDE.md + rules + hooks already exist.

Ask if unclear. Don't assume.

## Step 5 — Self-verify

Run Phase 11 checks literally:
- File structure exists (rules, hooks, CLAUDE.md, docs/README.md, settings.json)
- Hook scripts pass smoke tests
- MCP board build succeeds (`npm run build` in `mcp-vibe-board/`)
- Vibe Board connects (try `board_get_projects` if available)
- Skills are in `.claude/skills/` with valid frontmatter

Report pass/fail per check. If anything fails, fix it before declaring complete.

## Step 6 — Teach the user

After all checks pass, show them the Phase 11 "Teach the User" message: how to use RIPER modes (`Enter R`, `Enter P`, `Enter E`), what the hooks do, where their board is. This is the handoff — don't skip it.

## Cleanup after success

If the bootstrap was staged via `init.sh` and lives in `.ve-kit/`, offer to remove it:

> "Your setup is complete. You can remove the staging directory now: `rm -rf .ve-kit/`"

Don't remove it without asking — some users want to keep it around as a reference.

## If the user interrupts mid-protocol

Track which phase you're on. If they stop in the middle:
- Write a quick status note somewhere they can find it (either a board task if Phase 4 already ran, or a plain `.ve-kit-status.md` file)
- Tell them how to resume: "/bootstrap resume" or just re-invoke this skill

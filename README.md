# Vibe Coding Framework & Persistent Memory — Shareable Package (ve-kit)

A three-part framework that turns Claude Code from a chat assistant into a persistent, auditable, semi-autonomous engineering system. **Fixes Claude Code's single biggest gap: memory that survives between sessions.**

> **Part of [Vibe Entrepreneurs](https://vibeentrepreneurs.com)** — a community for any vibe coders shipping real work with AI: solo indie builders, product-minded devs, agency folks, side-project makers. You don't need to use ve-kit to join. Come say hi: **[vibeentrepreneurs.com](https://vibeentrepreneurs.com)**.
>
> **Companion repo**: [`HuntsDesk/ve-gws`](https://github.com/HuntsDesk/ve-gws) — **VE Google Workspace MCP** (Gmail, Drive, Docs, Calendar, Sheets, Slides) that pairs with ve-kit. Install standalone or alongside.

## Why this exists

Three specific things break when you use Claude Code seriously over time. Each layer in this kit addresses one.

| Problem | What ships here |
|---------|----------------|
| Claude Code forgets everything when a session ends. Context compaction drops task state; the next session starts cold. | **Vibe Board** — a Firestore-backed MCP server for persistent tasks, sessions, and handoff notes. Work survives across sessions, compactions, and crashes. |
| Nothing enforces the process gate between "wrote code" and "committed code." Reviews get skipped under pressure. | **Hooks + RIPER-CAT** — Claude Code hooks that block `git commit` until a review marker exists, plus a PLAN → EXECUTE → REVIEW mode system with auto-transitions. |
| You can only code while you're at the keyboard. Task queues sit idle overnight. | **VE Worker** — a Docker agent that pulls tasks from the board, runs them in an isolated git worktree with quality gates (type-check per commit, code-reviewer every 3 tasks), and opens a PR for you to review in the morning. |

Adopt any layer standalone, or stack them. The board works without the worker. The hooks work without the board.

---

## Get started

Three paths. All converge on the same interactive Claude Code protocol (~15-20 min, ~6 questions).

**Option 1 — one-liner** (from inside your project directory):
```bash
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash
```
Open Claude Code and paste the prompt from `.ve-kit/PROMPT.txt` — open the file directly (don't copy off the terminal, which may have ANSI color codes).

**Option 2 — paste-a-prompt** (zero local files). Open Claude Code anywhere and paste this in full:
> Fetch `https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/01-BOOTSTRAP.md` and set up this project following the protocol. I want Layer 1 (foundation) + Layer 2 (Vibe Board). Walk me through Phase 0 prerequisites first, then ask the Phase 1 project questions. Once you have my answers, execute all phases end to end. Self-verify at the end and report pass/fail.

**Option 3 — `/bootstrap` slash** (if ve-kit is already local):
Type `/bootstrap` in Claude Code. The skill locates the protocol and runs it.

**→ [Full Get Started guide](./00-GET-STARTED.md)** covers phase-by-phase walkthrough, pinning to a specific commit, upgrade mode, troubleshooting common first-run issues, adding Layer 3 (the Docker worker), and env-var customization.

---

## Architecture

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

You can adopt layers **1 → 2 → 3** in order, or stop at any layer:
- **Just Layer 1** = a disciplined single-session Claude Code setup with process gates
- **1 + 2** = adds persistent task tracking so sessions hand off cleanly
- **1 + 2 + 3** = adds autonomous coding on your task queue

---

## What's in this package

| File / Dir | Source of truth | Covers |
|------|----------------|--------|
| [`00-GET-STARTED.md`](./00-GET-STARTED.md) | — | Full onboarding: three paths, phase walkthrough, troubleshooting, upgrade mode |
| [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) | Layer 1 | Fresh-project setup: CLAUDE.md, `.claude/rules/`, `.claude/hooks/`, permissions/deny list, skills library, specialist agents, process gates (RIPER-CAT) |
| [`02-VIBE-BOARD.md`](./02-VIBE-BOARD.md) | Layer 2 | Firestore-backed MCP server for persistent task + session tracking. Full Node.js source inlined. 10 tools. |
| [`03-VE-WORKER.md`](./03-VE-WORKER.md) | Layer 3 | Docker-based autonomous coding agent. Worker reads board tasks, executes with quality gates, commits to a feature branch for review. |
| [`04-GOOGLE-WORKSPACE-MCP.md`](./04-GOOGLE-WORKSPACE-MCP.md) | Companion | VE Google Workspace MCP (`ve-gws`) — when and how to add Gmail/Docs/Slides/Sheets/Drive/Calendar to your setup |
| [`init.sh`](./init.sh) | — | One-command installer (`curl ... | bash`) |
| [`skills/`](./skills/) | Reusable skills | Drop-in ready `.claude/skills/` files. See below. |
| [`CHANGELOG.md`](./CHANGELOG.md) | — | What's new in this snapshot (Opus 4.7 additions, `/review-*` skill family, security hardening, etc.) |

### Skills included

Drop these into `.claude/skills/` in your own project — already sanitized (project-specific board IDs and domains replaced with placeholders like `<YOUR_AUDIT_PROJECT_ID>` and `<your-domain>`).

**Setup + workflow** (core process):
- [`skills/bootstrap/`](./skills/bootstrap/) — `/bootstrap` runs the BOOTSTRAP protocol interactively (fresh setup or upgrade)
- [`skills/go/`](./skills/go/) — `/go <task>` full RIPER cycle in one command (RESEARCH → PLAN → REVIEW → EXECUTE → REVIEW)
- [`skills/plan/`](./skills/plan/) — `/plan` structured PLAN mode with board task creation + agent assignment
- [`skills/review/`](./skills/review/) — `/review` REVIEW mode with sub-agent invocation (auto-detects post-plan vs post-execute)

**`/review-*` audit family** (periodic config hygiene):
- [`skills/review-agents/`](./skills/review-agents/) — audit `.claude/agents/*.md`
- [`skills/review-skills/`](./skills/review-skills/) — audit `.claude/skills/*/SKILL.md`
- [`skills/review-rules/`](./skills/review-rules/) — audit `CLAUDE.md` + `.claude/rules/*.md`
- [`skills/review-docs/`](./skills/review-docs/) — audit `docs/**/*.md`
- [`skills/review-memory/`](./skills/review-memory/) — audit per-project auto-memory directory
- [`skills/review-board/`](./skills/review-board/) — audit Vibe Board state (stale tasks, orphans, abandoned projects)
- [`skills/review-security/`](./skills/review-security/) — audit `.claude/` config security (secrets, permissions, hook fail-closed behavior)
- [`skills/review-all/`](./skills/review-all/) — orchestrator that runs all review-* in sequence

**Shared reference material** (cited by multiple review skills):
- [`skills/_shared/anthropic-configuration-guide.md`](./skills/_shared/anthropic-configuration-guide.md) — canonical Anthropic frontmatter/model/skill schema reference (with citations to official docs)
- [`skills/_shared/review-checklist.md`](./skills/_shared/review-checklist.md) — actionable checklist cited by every review-* skill

Each review skill writes findings as severity-tiered subtasks on the Vibe Board — never as prose. Replace `<YOUR_AUDIT_PROJECT_ID>` with your own board project ID after dropping into your repo.

---

## Who this is for

Solo developers and small teams who want to use Claude Code seriously:
- Across many sessions with persistent state
- With process discipline (planning, review, commit gates)
- Optionally with autonomous worker runs on a task queue

The framework is **project-type-agnostic** — works for web apps, CLIs, infrastructure, data pipelines. The examples in the bootstrap are from a legal-education SaaS but the patterns transfer cleanly.

---

## What this is NOT

- **A tutorial.** Each layer has prerequisites (Node, gcloud, Firebase, Docker). Read each file top-to-bottom before running commands.
- **Supported software.** This is a shared pattern, not a product. No warranty, no backwards-compatibility promises.
- **Free of judgement calls.** You'll decide how strict your review gates are, what your deny list includes, which agents matter for your stack.

---

## Tech + cost footprint

**Required**:
- Claude Code CLI (free)
- Google Cloud / Firebase project (free tier sufficient — ~50k reads/20k writes per day)
- Node.js 18+ (free)

**Optional**:
- Docker (for ve-worker — free)
- Claude Pro/Max subscription (for ve-worker's `CLAUDE_CODE_OAUTH_TOKEN` — if you don't want per-token API billing)

**NOT required**:
- Anthropic API key (framework runs entirely on subscription or per-session CLI)
- OpenAI / other model provider keys
- Any paid observability tool

---

## Optional companion: VE Google Workspace MCP (ve-gws)

**[HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws)** — a Python fork of [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) extending Claude Code into Gmail, Drive, Docs, Calendar, Sheets, Slides, Forms, Tasks, Chat, Contacts, and Apps Script. Adds 28 authoring-focused tools on top — lets you write to Workspace, not just read from it.

Install it after the base bootstrap is running. **→ [Full companion guide](./04-GOOGLE-WORKSPACE-MCP.md)** with integration config, tool tiers, OAuth setup, and ve-* family context.

---

## Feedback

The patterns in this package evolve as real projects surface edge cases. If you build on this and hit something interesting, the lessons that drove changes are usually captured in the accompanying `LESSONS.md` or `CHANGELOG.md` in the source repo.

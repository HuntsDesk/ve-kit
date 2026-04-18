# Get started with ve-kit

The full guide to installing, configuring, and using the ve-kit on your own project. If you just want the 30-second version, see the [README quick start](./README.md#get-started).

---

## The core idea

You don't read the bootstrap — **you hand it to Claude Code and it runs the protocol for you**, interactively, asking the questions it needs along the way. The whole setup takes ~15-20 min for Layer 1 + Layer 2.

Three entry paths. All converge on the same protocol:

| Path | Best for | Needs |
|------|----------|-------|
| **A. curl-bash installer** | First-time cold install | `curl`, `git`, `bash`, Claude Code CLI |
| **B. Paste-a-prompt** | No local files, quick try | Claude Code with WebFetch enabled |
| **C. `/bootstrap` slash** | You already have ve-kit cloned locally | Claude Code + local ve-kit |

---

## Path A — curl-bash installer (recommended)

From inside the project directory you want to set up:

```bash
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash
```

### What happens

1. Script checks for `git` + `curl` + `bash`
2. Clones ve-kit (shallow, `main` branch) into `.ve-kit/`
3. Detects fresh setup vs upgrade mode (existing `.claude/` or `CLAUDE.md`)
4. Writes the appropriate Claude Code prompt to `.ve-kit/PROMPT.txt`
5. Prints next steps — "open Claude Code, paste the prompt from `.ve-kit/PROMPT.txt`"

**Safety**: refuses to operate if `.ve-kit/` exists and isn't a ve-kit git clone — protects against clobbering an unrelated repo someone happened to name `.ve-kit/`.

**Idempotent**: re-running refreshes `.ve-kit/` to latest `main`. Never modifies `.claude/`, `CLAUDE.md`, or anything outside `.ve-kit/`.

### Reading the prompt correctly

Open `.ve-kit/PROMPT.txt` directly — don't copy the prompt off the terminal, which may have ANSI color codes that break when pasted into Claude Code.

On macOS you can pipe it to the clipboard:
```bash
cat .ve-kit/PROMPT.txt | pbcopy
```

On Linux:
```bash
cat .ve-kit/PROMPT.txt | xclip -selection clipboard
```

### Pinning for reproducibility

Teams installing ve-kit across multiple machines should pin to a specific commit so everyone gets the same version:

```bash
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | VE_KIT_COMMIT=<sha> bash
```

Use a git tag or commit SHA from [the ve-kit repo](https://github.com/HuntsDesk/ve-kit/commits/main). Store the chosen SHA in your team's onboarding doc.

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `VE_KIT_REPO` | `https://github.com/HuntsDesk/ve-kit.git` | Clone from a different fork |
| `VE_KIT_BRANCH` | `main` | Clone from a different branch |
| `VE_KIT_COMMIT` | *(none)* | After clone, check out this specific commit |
| `VE_KIT_STAGE` | `.ve-kit` | Use a different staging directory |

---

## Path B — paste-a-prompt (zero scripts)

Open Claude Code anywhere and paste this prompt verbatim:

> Fetch `https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/01-BOOTSTRAP.md` and set up this project following the protocol. I want Layer 1 (foundation) + Layer 2 (Vibe Board). Walk me through Phase 0 prerequisites first (check for gcloud, firebase, node, claude CLI; tell me what's missing). Then ask me the Phase 1 project questions (name, description, main language, GCP project ID, default branch, anything to add to the deny list). Once you have my answers, execute all phases end to end. Self-verify at the end and report pass/fail.

**When this is right**: you want to try the framework on a throwaway project without committing local files. Claude Code WebFetches the BOOTSTRAP.md and runs it from memory.

**Slight downside**: no local copy of the protocol means if your Claude Code session crashes mid-setup, you re-paste the prompt and Claude starts over. Path A is friendlier for serious adoption because the local `.ve-kit/` files persist.

---

## Path C — already have ve-kit locally?

If you cloned ve-kit (or ran `init.sh` previously), the `/bootstrap` slash command is the smoothest entry:

```
/bootstrap
```

The skill locates `01-BOOTSTRAP.md` by trying these paths in order:

1. `.ve-kit/01-BOOTSTRAP.md` (staged via init.sh — most common)
2. `docs/ve-kit/01-BOOTSTRAP.md` (project has ve-kit as a subtree)
3. `~/github/ve-kit/01-BOOTSTRAP.md` (separate local clone)
4. WebFetch from the public repo as a fallback

Then it runs the protocol. Same as Path A but without the paste step.

The `/bootstrap` skill itself ships in the kit (see [`skills/bootstrap/`](./skills/bootstrap/)). Install it into `.claude/skills/` when you run the bootstrap (it's one of the 4 starter skills installed in Phase 10).

---

## What to expect — the setup session

Here's the actual flow once you paste the prompt:

### Phase 0: prerequisite check (~1 min)

Claude Code checks your machine:
- `gcloud` CLI installed + authenticated?
- `firebase` CLI installed?
- `node` + `npm` (v18+)?
- `claude` CLI (you already have this if you're reading this)
- `docker` (optional — only needed for Layer 3)

If anything's missing, Claude tells you and pauses. You install it, then say "continue."

### Phase 1: project questions (~2 min)

Claude asks ~6 questions. Typical answers:

| Question | Example |
|---|---|
| Project name | `my-api` |
| Project description | `Public REST API for X` |
| Primary language | `python` / `typescript` / `go` / etc. |
| GCP/Firebase project ID | `my-api-prod-123` (for the Vibe Board) |
| Default git branch | `main` |
| Anything unusual to add to the deny list? | e.g., "never run `./prod-deploy.sh` without approval" |

Answer conversationally. Claude will recap your choices before proceeding.

### Phases 2-11: automated setup (~10-15 min)

Claude Code executes the rest of the protocol without more input from you:

| Phase | What it does |
|---|---|
| 2 | Creates directory structure (`.claude/`, `docs/`, `mcp-vibe-board/`) |
| 3 | Writes rule files (riper-cat, code-quality, documentation, git-workflow, agent-board) |
| 4 | Sets up Vibe Board — Firestore project, service account, MCP server built, `.mcp.json` configured |
| 5 | Installs hooks (block-todowrite, session-handoff, post-compact-recovery, review-gate, stop-compliance-check) |
| 6 | Writes `settings.json` with permissions + deny list |
| 7 | Writes `CLAUDE.md` using your Phase 1 answers |
| 8 | Writes `docs/README.md` as your documentation index |
| 9 | Installs language-server plugins (typescript-lsp, pyright-lsp, etc., based on detected languages) |
| 10 | Installs starter skills (`bootstrap`, `plan`, `review`, `go`, + `/review-*` audit family) |
| 11 | Self-verify — checks files exist, hooks executable, MCP board connects, skills loaded, reports pass/fail |

If Phase 4 fails (GCP project doesn't exist, permission denied, billing not enabled), Claude tells you which step needs attention and how to fix it.

### Done

When Claude reports **"Your setup is complete"**, try one of these:

- `Enter R` — start a RESEARCH session
- `/plan <task>` — see the structured planning workflow
- `/review` — run a sub-agent review
- Create a board task via the MCP and watch it persist across sessions

You can remove `.ve-kit/` at this point — bootstrap was a one-time thing:
```bash
rm -rf .ve-kit/
```

---

## Upgrade mode

If you already have a `.claude/` directory or `CLAUDE.md` when you run `init.sh` or `/bootstrap`, Claude Code detects this and runs in **upgrade mode** instead of fresh setup.

Upgrade mode:
1. Reads your existing files
2. Diffs them against the current ve-kit template
3. Tells you what's new/changed upstream
4. Asks which upgrades you want to apply
5. Never overwrites anything without confirmation

This is how you keep your `.claude/` config current as ve-kit evolves. Re-run periodically (monthly/quarterly) or after a major release.

---

## Adding Layer 3 (VE Worker)

Layer 3 is the Docker autonomous worker. **Don't install it in the same session as the base bootstrap** — it has its own prerequisites and its own configuration surface.

Once Layer 1 + 2 are working, paste in Claude Code:

> Now add Layer 3 from `@.ve-kit/03-VE-WORKER.md` (or fetch it from the ve-kit repo if .ve-kit/ is gone). I'll need Docker running. Walk me through the worker setup.

### Layer 3 prerequisites

- Docker Desktop (or any Docker daemon)
- A Claude subscription token (`claude setup-token` — valid 1 year)
- GitHub CLI (`gh auth login`) if you want the worker to open PRs automatically

### What Layer 3 adds

- `docker/ve-worker/` directory with Dockerfile, docker-compose.yml, entrypoint.sh, mcp-config.json, LESSONS.md
- Worker services: `claude-go` (single task), `claude-triage` (board classification), `claude-worker` (batch mode)
- Quality gates baked in: type-check before every commit, code-reviewer every 3 tasks, branch-per-batch isolation, 500-line cap, 4-hour timeout

See [03-VE-WORKER.md](./03-VE-WORKER.md) for full worker configuration details.

---

## Troubleshooting first-run issues

### "Claude Code can't fetch URLs"
Your Claude Code install has WebFetch disabled or restricted. Use Path A (curl-bash) instead — it doesn't rely on WebFetch.

### "Phase 4 fails: Firestore is not enabled on this project"
Go to the Firebase Console for your GCP project, enable Firestore in Native mode, then tell Claude Code "retry Phase 4."

### "Phase 4 fails: service account lacks permissions"
The Firebase CLI handles most of this automatically. If it fails, you need `roles/datastore.user` on the service account. Run:
```bash
gcloud projects add-iam-policy-binding <YOUR_PROJECT> \
  --member="serviceAccount:<YOUR_SA_EMAIL>" \
  --role="roles/datastore.user"
```

### "The MCP board tools don't appear in Claude Code"
After Phase 11 completes, restart Claude Code. The MCP server registration happens via `.mcp.json` which Claude Code reads at startup.

### ".ve-kit/ exists but init.sh says it's not a ve-kit clone"
You have an unrelated directory at `.ve-kit/`. Either:
```bash
mv .ve-kit .ve-kit-old
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | bash
```
Or use a different staging dir:
```bash
curl -fsSL https://raw.githubusercontent.com/HuntsDesk/ve-kit/main/init.sh | VE_KIT_STAGE=.vekit-staging bash
```

### "Claude started phases but I lost the session"
If you had `.ve-kit/` staged (Path A), just paste the prompt again — Claude picks up where it left off using whatever was already written to disk. Upgrade mode will detect partial setup and resume.

If you used Path B (paste-a-prompt), re-paste and tell Claude: "I was partway through setup — detect what's already done and resume from there."

### "I want to start over from scratch"
```bash
rm -rf .claude/ CLAUDE.md docs/README.md mcp-vibe-board/ .mcp.json .claude/settings.json
# Then re-run init.sh
```
Review the `rm` carefully — it'll delete your entire ve-kit setup.

---

## Prefer to read the protocol first?

The protocol itself is documented top-to-bottom in [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md). It's 1500+ lines because each phase has its own rationale, commands, and verification steps.

Recommended reading order:
1. Phase 0 (prerequisites) — decide if you can run this at all
2. Phase 1 (project questions) — see what you'll need to answer
3. Phases 2-3 (directory structure + rules) — the core of Layer 1
4. Phase 4 (Vibe Board) — Layer 2, the persistence layer
5. Skip to Phase 10-11 — starter skills + self-verify

Phases 5-9 are capability-specific and worth skimming to understand what's being installed.

---

## What's next

- **[01-BOOTSTRAP.md](./01-BOOTSTRAP.md)** — the full phase-by-phase protocol
- **[02-VIBE-BOARD.md](./02-VIBE-BOARD.md)** — Vibe Board MCP server (Firestore-backed, inlined Node.js source)
- **[03-VE-WORKER.md](./03-VE-WORKER.md)** — Docker worker configuration
- **[CHANGELOG.md](./CHANGELOG.md)** — what's new in this snapshot
- **[../skills/](./skills/)** — drop-in `.claude/skills/` files

Companion: **[HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws)** — enhanced Google Workspace MCP server (Gmail, Drive, Docs, Calendar, Sheets, Slides, Forms). Install after the base bootstrap is running.

---

## Feedback

ve-kit evolves as real projects surface edge cases. If something's unclear or breaks on your setup, file an issue at [github.com/HuntsDesk/ve-kit/issues](https://github.com/HuntsDesk/ve-kit/issues).

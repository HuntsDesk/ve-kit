# VE Google Workspace MCP (ve-gws) — companion

ve-kit's official companion for extending Claude Code into Google Workspace. If your workflows cross the coding context into Gmail, Drive, Docs, Calendar, Sheets, Slides, Forms, Tasks, Contacts, or Chat — install ve-gws.

**Public repo**: [HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws)

---

## What it is

ve-gws is a fork of [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) that adds **28 authoring-focused tools** on top of the upstream's ~90 read/write tools (~120 total) — aimed at *authoring* Google Workspace content, not just reading it.

| Area | Extended capabilities |
|------|----------------------|
| **Slides** | Create shapes + text boxes · set backgrounds · reorder slides · duplicate slides · read/write speaker notes · style shapes + text + paragraphs · delete elements |
| **Docs** | Insert native markdown (rendered, not as code block) · insert person + file smart chips · read existing smart chips · find-and-replace · `apply_continuous_numbering` (convert plain-text "1. 2. 3." into a real numbered list with continuation across prompts/sub-bullets) |
| **Sheets** | Data validation rules · named ranges · range protection · sheet tab management (add/rename/delete/reorder) |
| **Drive** | Recursive folder copy · list revision history · restore prior revisions |

Feature ideas ported from [`blakesplay/apollo`](https://github.com/blakesplay/apollo), which was originally based on [`piotr-agier/google-drive-mcp`](https://github.com/piotr-agier/google-drive-mcp). All 822 tests pass (803 upstream + 19 new).

---

## When to install it

- You need Claude Code to **draft decks, docs, or sheets** — not just summarize them
- You're building workflows that **cross into Google Workspace** (e.g., generate a weekly report in Docs, build a pitch deck from notes, populate a tracking sheet)
- You want the `ve-kit` + `ve-worker` + `ve-gws` trio for a full agent-ready setup

If you only need read access to Google Workspace, the upstream [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) is lighter and may be enough.

---

## Installing alongside ve-kit

Install ve-gws **after** the base bootstrap (Layer 1 + Layer 2) is running. It's a separate MCP server with its own OAuth flow.

### Follow the ve-gws README

**The authoritative install guide lives in the [ve-gws README](https://github.com/HuntsDesk/ve-gws#-credential-configuration).** It covers:

1. OAuth 2.1 credential setup on your GCP project
2. `.mcp.json` entry format (Claude Code, Claude Desktop, LM Studio, VS Code)
3. Tool-tier configuration (core / extended / complete)
4. Remote OAuth 2.1 multi-user mode for centralized hosting

Don't rely on copy-paste install snippets in this doc — the canonical configuration is in the ve-gws README and stays current with the fork. In particular: ve-gws isn't published to PyPI separately (the `workspace-mcp` PyPI package is the upstream's), so installs typically run from source via `uvx --from git+https://github.com/HuntsDesk/ve-gws workspace-mcp` or a local clone with `uv run`. Confirm the current command in the ve-gws README before pasting into `.mcp.json`.

### Alongside the Vibe Board MCP

Your project's `.mcp.json` (created during ve-kit Phase 4) already has the Vibe Board entry. Add ve-gws as a sibling entry — the two MCPs operate independently. Restart Claude Code after editing `.mcp.json`; MCP servers are registered at session start.

### First-run OAuth

On first use, Claude Code prompts you with a Google OAuth URL. Authorize the scopes you need (Gmail, Drive, Calendar, Docs, Sheets, etc.). Credentials are cached locally — subsequent sessions skip this step.

---

## Scoping tool access

ve-gws supports **tool tiers** so you don't have to grant Claude Code access to the full ~120-tool surface. Define a tier in your `.mcp.json` config to expose only what each project needs.

Examples:
- **Read-only research**: Gmail read + Drive list + Docs read
- **Content authoring**: Docs + Slides + Sheets with full write access
- **Full admin**: All tools including Apps Script execution

See the [tool tiers docs](https://github.com/HuntsDesk/ve-gws#tool-tiers) for the exact tier configurations.

---

## Keeping ve-gws updated

ve-gws tracks `taylorwilsdon/google_workspace_mcp` as an upstream remote — you can pull new features from upstream periodically:

```bash
cd ~/github/ve-gws   # or wherever you cloned it
git fetch upstream && git merge upstream/main
# resolve any conflicts in gslides/, gdocs/, gsheets/, gdrive/, core/tool_tiers.yaml
# run: uv run pytest tests/   ← must pass before pushing
git push origin main
```

Full details on upstream tracking are in the [ve-gws README's "Pulling Upstream Changes" section](https://github.com/HuntsDesk/ve-gws#-pulling-upstream-changes).

Some feature ideas come from [`blakesplay/apollo`](https://github.com/blakesplay/apollo), which is TypeScript — those commits can't be mechanically cherry-picked into ve-gws (Python), so they're ported by hand when needed.

---

## Security model

ve-gws uses **OAuth 2.1 with PKCE** by default — no long-lived API keys. Token refresh is automatic. Credentials can live in your user-local config (Claude Code default) or via external auth server for multi-user hosting.

For hosting centrally (team/org), ve-gws supports:
- Remote OAuth 2.1 with bearer tokens
- External OAuth provider mode
- Stateless mode (container-friendly)
- Reverse proxy setup

See [ve-gws README security section](https://github.com/HuntsDesk/ve-gws#-security) for details.

---

## The ve-* family

ve-gws is one of three repos in the ve-* framework:

| Repo | Purpose |
|---|---|
| **[ve-kit](https://github.com/HuntsDesk/ve-kit)** | Claude Code productivity framework — bootstrap + Vibe Board + VE Worker |
| **[ve-gws](https://github.com/HuntsDesk/ve-gws)** | Google Workspace MCP server (this doc) |
| **ve-worker** | Docker autonomous agent (shipped as part of ve-kit Layer 3) |

Install whichever combination fits your workflow. They're all standalone and all pair cleanly.

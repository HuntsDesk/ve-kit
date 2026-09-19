# Developer setup — the per-developer half of Claude Code configuration

**Status**: current as of 2026-09-12 (Claude Code 2.1.269). Read this after BOOTSTRAP Phase 6. Every developer on the project runs it once per machine.

Almost everything BOOTSTRAP writes travels with `git pull`: `.claude/settings.json` (hooks, deny list, the production-push `ask` rule), `.claude/rules/`, `.claude/agents/`, `.claude/skills/`. **Four settings do not**, because Claude Code reads them only from each developer's own `~/.claude/settings.json`:

| Setting | Why it lives in the user file |
|---|---|
| `permissions.defaultMode: "auto"` | `auto` is ignored in project and local settings files (Claude Code ≥ 2.1.257). A project-file `defaultMode` of any value would outrank yours, so BOOTSTRAP's template sets none. |
| `autoMode.environment` | The auto-mode classifier reads `autoMode` only from user or managed settings, never from the repo (anti-injection). Without it, every cloud, host, and payment-provider target is "unknown infrastructure" and routine ops get blocked or prompted. |
| `autoMode.allow` (self-configuration rule) | Lets Claude edit Claude Code settings when **your own message** names the file and the key. Optional; the tightened wording is in the template. |
| `modelSettings` / `alwaysThinkingEnabled` | Effort defaults per model (Fable 5.1 → `high`, Opus 5 → `xhigh`), per Anthropic's model-configuration guidance. |

A repo cannot carry these for you. So the kit ships a template plus a merge script: the maintainer fills the template in once, and each developer merges it once.

## For the project maintainer — once per project

1. Copy [`user-settings.template.json`](./user-settings.template.json) and [`merge-user-settings.py`](./merge-user-settings.py) side by side into your repo. `docs/claude-code/` is the convention; any directory works, because the script finds the template next to itself.
2. Replace every `<PLACEHOLDER>` in `autoMode.environment` with prose about **your** project (see "Writing the environment" below). The script refuses to run while any placeholder remains.
3. Keep `"$defaults"` as the first entry of every `autoMode` list. Removing it replaces Anthropic's built-in rules instead of extending them.
4. Commit both files. When BOOTSTRAP Phase 6 runs, Claude drafts steps 1–2 from your Phase 1 answers; read the draft before committing it.

## For each developer — once per machine

From anywhere inside the checkout, in a normal terminal (not inside a Claude session):

```bash
git pull
python3 docs/claude-code/merge-user-settings.py          # add --dry-run to preview
```

The script backs up `~/.claude/settings.json`, merges only the four keys above (your own allow rules, directories, plugins and model are untouched), removes a dead `bypassPermissions` from `.claude/settings.local.json` if you have one, and prints what it changed. Then close every Claude Code window, reopen one, and run `claude auto-mode config | head -40`. You should see your project's entries.

### By hand instead

1. Open `~/.claude/settings.json` in your editor. If the file does not exist yet, create it with `{}`.
2. Open the filled-in `user-settings.template.json` next to it.
3. Copy `alwaysThinkingEnabled`, `modelSettings`, and `autoMode` into your file at the top level. Inside `permissions`, set `"defaultMode": "auto"` (add the `permissions` object if you have none). Keep everything else you already have.
4. **Remove** `"defaultMode": "bypassPermissions"` from `.claude/settings.local.json` in your checkout if it is there. Since 2.1.257 it is ignored and makes the session start in Manual — the opposite of the intent. This file is gitignored, so the repo cannot fix it for you.
5. Validate:
   ```bash
   python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print(d['permissions']['defaultMode'], len(d['autoMode']['environment']), 'env entries')"
   claude auto-mode config | head -40
   ```
6. Restart every Claude Code window. Settings load at session start only.
7. In a new session, `/permissions` → **Auto mode** tab should show "Extends the built-in default · from user settings" under Environment.

## What to expect afterwards

- Sessions start in **auto mode**: a classifier reviews each action; routine work runs without prompts; scope escalation, unknown infrastructure, production deploys, and secret handling are blocked or prompted. Denials name the rule in square brackets (for example `[Production Deploy]`); `/permissions` → Recently denied lets you retry one with `r`.
- **A push to the production branch always prompts** (the `ask` rule `Bash(git push*main*)` from Phase 6, adjusted to your branch name). That prompt is the "user approval" `riper-cat.md` requires. No prompt on a production push means the rule is missing from your checkout, not that you are cleared.
- Blanket `Bash(*)` allow rules are suspended in auto mode; narrow ones and the deny list still apply.
- Claude cannot edit `~/.claude/settings.json` or `.claude/settings.json` unless your message names the file and the change (the self-configuration rule). That is deliberate. The classifier treats an agent rewriting its own permission config as a bypass attempt, which is why a human runs the merge script.

## Writing the environment

The classifier reads `autoMode.environment` as prose, one topic per entry. The template's placeholders cover the topics that matter most:

| Entry | What to say |
|---|---|
| Organization | Who you are, what the product is, how many developers share a checkout |
| Source control | Host, org, repo, which branch is integration and which is production, any public mirrors |
| Cloud provider(s) | Project or account IDs, regions, DNS, payments, auth, task tracking |
| Trusted buckets / domains | What is inside the trust boundary for reads and probes; which writes are really deploys |
| Key internal services | CI system and what each branch push deploys; compute; secret store; automation platform |
| Org-specific CLIs | Repo scripts the agent should treat as sanctioned tooling (a read-only production probe especially) |
| CI/CD deploy targets | Exactly which command is a production deploy, and that the human approves it per push |
| Sensitive remote targets | Hosts that ARE production; which operations there are read-only diagnosis and which are changes |
| Protected IaC scopes | Files whose edit or import changes production immediately |
| Secrets management | Where secrets live; never print a value |
| Sensitive data | What the production database holds, and where it may and may not be reproduced |
| Additional context | House rules the classifier cannot infer — for example that `git add -A` is destructive to other windows' work on a shared checkout |

If the classifier keeps blocking something routine, add a sentence describing that system and run `claude auto-mode config` to confirm it loaded. `/auto-mode-setup` can draft entries from your recent sessions; `claude auto-mode critique` reviews custom rules for ambiguity.

## What is NOT affected

The VE Worker ([`03-VE-WORKER.md`](./03-VE-WORKER.md)) runs headless inside its container with `--permission-mode bypassPermissions` on the CLI, which is the documented correct use of that mode. Nothing here changes it.

## Related

- [`01-BOOTSTRAP.md`](./01-BOOTSTRAP.md) Phase 6 — the team-shared half (`.claude/settings.json`: hooks, deny list, the `ask` rule, and why there is no `defaultMode` in it)
- [`CHANGELOG.md`](./CHANGELOG.md) 2026-09 snapshot — why the older "bypassPermissions + deny list" advice was withdrawn
- Anthropic docs: [Permission modes](https://code.claude.com/docs/en/permission-modes), [Configure auto mode](https://code.claude.com/docs/en/auto-mode-config), [Settings](https://code.claude.com/docs/en/settings)

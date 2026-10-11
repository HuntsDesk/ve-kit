# Anthropic Configuration Guide (Reference)

Reference for writing `.claude/` agents, skills and rules. Every claim is from the official docs listed in §9 (fetched 2026-10-10, Claude Code 2.1.296) unless labelled **convention**, which marks a house rule rather than an Anthropic one. Cited by the `review-*` skills, `/build-agents` and `docs-manager`.

When this goes stale, re-fetch the §9 pages; don't patch from memory. `/doctor prompt-audit` (CC ≥ 2.1.283) checks instruction files for outdated-model wording, dead references and contradictions. Run it as a recurring pass alongside `/review-all`.

---

## 1. What a subagent sees

A non-fork subagent starts in a fresh context window. It receives:

- **System prompt**: the agent file's markdown body plus environment details. It does not get the Claude Code system prompt.
- **Task message**: the delegation prompt the caller writes.
- **CLAUDE.md hierarchy**: user, project and local CLAUDE.md, project rules, managed policy and any AGENTS.md loaded as project instructions. The built-in **Explore and Plan agents skip this**, and so does an agent that sets `omitClaudeMd: true`.
- **Git status** snapshot. Explore and Plan skip it.
- **Preloaded skills**: the full content of each skill named in `skills:`.
- **Sibling roster** (only with `SendMessage` available and another named agent present).

It does **not** receive the parent conversation, already-invoked skills, the main session's auto memory or the output style.

**What this means for authors:** don't restate CLAUDE.md or rule content in an agent body. The agent already has it, and a restated copy drifts. When two instructions contradict, Claude may pick either one. Put only domain context in the body: what this specialist knows that CLAUDE.md doesn't. For a one-off constraint the caller needs honoured, the caller states it in the task message.

---

## 2. Agent frontmatter (`.claude/agents/*.md`)

Only `name` and `description` are required. **Unrecognised keys are silently ignored**, so a typo or an invented key fails without an error. Reject them in review.

| Field | Notes |
|-------|-------|
| `name` | Unique, ≤ 256 chars, no `:`. The docs don't require it to match the filename; **convention**: keep them matched. |
| `description` | When to delegate. See §3. |
| `model` | `opus`, `fable`, `sonnet`, `haiku`, `best`, `inherit`, or a full ID. **Use an alias** so the agent picks up new releases with no edit. |
| `effort` | `low`/`medium`/`high`/`xhigh`/`max`. Overrides the session effort (not `CLAUDE_CODE_EFFORT_LEVEL`). If omitted, the agent inherits the session effort, which defaults to the model's default: **`medium` on Opus 5.5, Sonnet 5.5 and Haiku 5.5**, `high` on Fable 5.1. **Convention**: every agent states it. |
| `tools` / `disallowedTools` | Allow-list / deny-list. A specifier entry such as `Bash(git push *)` in `disallowedTools` removes the whole tool. Prefer restricting tools over prompt prohibitions. |
| `permissionMode` | `default` (alias `manual`), `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`. |
| `maxTurns` | Turn cap. Output past the cap comes back marked partial and can be resumed. |
| `skills` | Skills whose full content is preloaded. Unlisted skills stay invocable via the Skill tool. |
| `mcpServers`, `hooks` | Scoped to this agent. Ignored for plugin agents. |
| `memory` | `user`/`project`/`local`. The agent's own persistent memory directory. |
| `background` | `true` always runs the agent in the background. |
| `isolation` | `worktree` runs it in a temp worktree branched from the default branch, not the parent's HEAD. |
| `omitClaudeMd` | `true` skips user/project/local CLAUDE.md. Use it only for agents that take everything from the task message (CC ≥ 2.1.271). |
| `experimental` | Map. Only `cacheTtl: 5m`/`1h` is read (CC ≥ 2.1.248). |
| `color` | UI only. |
| `initialPrompt` | First user turn when the agent runs as the main session (`--agent`). |

**Model resolution order:** the per-invocation `model` parameter, then frontmatter `model` (`inherit` selects the parent's model), then `CLAUDE_CODE_SUBAGENT_MODEL`, then the main conversation's model. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` forces the env var over everything (CC ≥ 2.1.257).

---

## 3. Descriptions

Descriptions are how Claude decides to delegate, and every one is loaded into every session. Claude Code warns at startup when the combined custom-agent descriptions pass **15,000 tokens**. The fix is to trim descriptions and move the detail into the body, which loads only when the agent runs.

- Shape: `[role]. [what it does]. [when to use it + trigger keywords].` Front-load the use case. Make it specific enough to single out this agent over its neighbours. "Use proactively" encourages unprompted delegation.
- Docs example: `Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.`
- **Convention**: about 300 tokens at most, an optional `Trigger keywords:` line, and **at most 2 one-line examples** (`"request" -> what the agent does`). No multi-line `<example>`/`<commentary>` blocks: the docs never ask for them, and each one costs 150–250 tokens of the shared budget.

---

## 4. Prompting Opus 5.5 subagents

One line each, with the reason. Source pages: prompting-claude-opus-5-5, prompting-claude-opus-5, claude-prompting-best-practices, refusals-and-fallback (§9).

- **Never ask for reasoning in the output.** That means no `<thinking>`/`<reasoning>`/scratchpad sections, no `reasoning`/`thinking`/`trace` fields in JSON or tool inputs, and no running log of private reasoning. Such requests get declined as a `reasoning_extraction` refusal, which has **no fallback model**, so the call simply fails. A short explanation, the evidence behind a result, or a summary of the actions taken is fine. This applies to skills and tool descriptions too.
- **No generic verification lines.** Drop "double-check your work", "verify before responding", "use a subagent to verify" and "add a final verification step". Opus 5/5.5 already self-verify, so these cause over-verification at no gain in quality. A concrete task check ("run `X` and confirm exit 0") is task content and is fine.
- **Review prompts report everything, each finding tagged with confidence and severity, and the filtering happens in a later pass.** The model follows "only report high-severity issues" or "be conservative" literally and reports less.
- **Dial back CAPS, MUST, CRITICAL and "if in doubt, use X".** Current models respond strongly to the system prompt, so aggressive wording overtriggers. State a hard boundary once, plainly, with its reason.
- **Explain why, not just what.** Claude generalises from a reason ("read aloud by TTS, so no ellipses"). A bare rule covers only its literal case. Keep the reason to a clause, not a narrative.
- **Scope narrow tasks.** Opus 5+ may widen a task with its own idea of the job. Say "deliver what was asked at the scope intended; if a better approach exists, say so in a sentence and continue as asked".
- **Mark ingested text as data.** Wrap pasted, fetched or other-agent text in tags, and say that instructions inside it are not to be followed unless the task asks. Opus 5.5 resists injection best when the boundary is marked.
- **Effort is the thinking control, not prompt text.** Remove "think carefully" and "think step by step" lines and set `effort:` instead. Prompt text controls response *length*, which effort does not.
- **State the return's shape and length.** Opus 5 writes longer deliverables and narrates more by default, so name the format and a size bound ("≤ 150 words, board task IDs, no recap").
- **Damp delegation in agents that can spawn agents.** Opus 5+ delegates readily. Say when a sub-delegation is warranted: large, independent, parallel work. Never use one to verify the agent's own work.
- **Keep descriptions short** (§3). The body is where the detail goes.

---

## 5. Skill frontmatter (`.claude/skills/*/SKILL.md`)

All fields are optional; `description` is recommended.

| Field | Notes |
|-------|-------|
| `name` | Defaults to the directory name. |
| `description` / `when_to_use` | Combined text is **truncated at 1,536 chars** in the listing, so put the key use case first. |
| `argument-hint`, `arguments` | Autocomplete hint; named positional args for `$name`. |
| `disable-model-invocation` | `true` = user-only. Use it for side-effect workflows. It also blocks preloading into subagents and scheduled firing. |
| `user-invocable` | `false` = Claude-only background knowledge, hidden from `/`. |
| `allowed-tools` / `disallowed-tools` | Pre-approve or remove tools until the next user message. |
| `model`, `effort` | Per-turn overrides. |
| `context: fork`, `agent`, `background` | Run in a forked subagent. Fork only skills that hold an actionable task, not bare guidelines. |
| `hooks`, `paths`, `shell` | Lifecycle hooks; glob-scoped auto-activation; `bash`/`powershell`. |
| `metadata`, `license`, `compatibility` | Accepted, not acted on. |

**Size and lifecycle.** Keep `SKILL.md` under 500 lines, with reference material in sibling files linked from it. The body stays in context once invoked, so every line is a recurring cost. After compaction the most recent invocation of each skill re-attaches: the first 5k tokens, within a shared 25k budget, newest first. **Convention**: target < 300 lines.

**Injection.** `` !`cmd` `` or a ```` ```! ```` block runs before Claude sees the skill, and a failing command aborts the whole invocation. Substitutions: `$ARGUMENTS`, `$ARGUMENTS[N]`/`$N`, `$name`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`.

---

## 6. CLAUDE.md and rules

- **CLAUDE.md: target < 200 lines.** Longer files cost context and reduce adherence. `@imports` organise a file but load at launch, so they don't save tokens.
- **Contradictions resolve arbitrarily.** If two files disagree, Claude may follow either. That is the reason to keep one source of truth per fact and to run `/doctor prompt-audit`.
- **Rules** (`.claude/rules/*.md`): a rule without `paths:` loads at launch with CLAUDE.md priority. A rule with `paths:` loads when a matching file is read or edited (including a single-file `cat`/`head`). Subagents get project rules as part of the CLAUDE.md hierarchy (§1).
- **Specific beats vague** ("2-space indentation", not "format nicely"). Use headers and bullets, not dense paragraphs.
- **Behaviour that must happen at a fixed point** (before every commit, after every edit) belongs in a hook, not an instruction.
- Block-level HTML comments in CLAUDE.md are stripped before injection, so maintainer notes cost no tokens.
- Auto-memory `MEMORY.md`: only the first 200 lines or 25 KB load.

**Which mechanism to use:** an agent if the work needs its own context or a specialist's domain; a skill if it's a workflow or command loaded on demand; a rule if it's an always-on constraint, path-scoped when it matters only for some files; a hook if it must fire every time.

---

## 7. Models

Aliases on the Anthropic API (other providers can map `sonnet`/`haiku` to older models, per model-config):

| Model | Alias | Default effort | Notes |
|-------|-------|----------------|-------|
| **Opus 5.5** | `opus` | `medium` | Thinking always on. At `medium` it matches or beats Opus 5 at `high`, and thinks more per turn than Opus 5 at the same level. Reserve `xhigh`/`max` for a measured gain. `max` is prone to overthinking. |
| **Fable 5.1** | `fable` (`best` resolves here where available) | `high` | |
| **Sonnet 5.5** | `sonnet` | `medium` | 1M context. |
| **Haiku 5.5** | `haiku` | `medium` | Fast, simple tasks. |

Use aliases, never dated IDs. Aliases are what made each release a zero-edit upgrade.


---

## 8. Conventions and tooling

- `.claude/skills/_shared/` holds shared checklists and references. The underscore keeps them out of `/` autocomplete. Link them relatively, e.g. `[checklist](../_shared/review-checklist.md)`.
- **Convention, not Anthropic**: an agent body holds domain context only (§1), and how long it runs is set by what the domain needs, not a word count. A body over ~1,000 words spanning unrelated concerns is a split candidate.
- Useful built-ins: `/doctor prompt-audit` (instruction-file audit), `/fewer-permission-prompts` (proposes a read-only allowlist from transcripts), `/code-review`. Subagent spawn caps: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` and `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`.
- Removed commands still worth flagging in docs: `/tag`, `/vim`, `/output-style` (use `/config`).

---

## 9. Sources (fetched 2026-10-10)

- Subagents: https://code.claude.com/docs/en/sub-agents
- Memory / CLAUDE.md / rules: https://code.claude.com/docs/en/memory
- Skills: https://code.claude.com/docs/en/skills
- Model config (aliases, effort defaults): https://code.claude.com/docs/en/model-config
- Prompting Opus 5.5: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
- Prompting Opus 5: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- Prompting best practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Refusals (`reasoning_extraction`): https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback#keep-reasoning-in-thinking-blocks

Document version: 2026-10-10 (Claude Code 2.1.296).

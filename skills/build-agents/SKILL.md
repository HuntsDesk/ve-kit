---
name: build-agents
description: Interview a codebase for the specialist agents it actually deserves, then build them properly. Surveys structure, churn and fix-density; proposes a SMALL set of candidates with evidence; asks which to create; interviews you per candidate; writes valid `.claude/agents/<name>.md`; registers them in the roster and the tier manifest; verifies they load. Use when a project has no agents yet, when a new domain has grown an owner-shaped hole, or when someone asks "what agents should this repo have?". Not for re-tiering or auditing an existing roster.
user-invocable: true
disable-model-invocation: true
---

# /build-agents — interview the codebase, then build its specialists

Most projects do not deserve forty agents. Most deserve two to five, plus the two read-only
role agents. This skill finds which, using evidence from the repo rather than a wish list,
and then writes agent files that actually register and actually carry knowledge.

Companion to [`review-agents`](../review-agents/SKILL.md), which audits a roster that already
exists. This one creates. Schema authority: [`../_shared/anthropic-configuration-guide.md`](../_shared/anthropic-configuration-guide.md).
Model/effort authority: [`../_shared/review-checklist.md`](../_shared/review-checklist.md) § Model + effort rubric.

## When to invoke

- `/build-agents` typed directly
- "What agents should this project have?" / "Set up specialists for this repo"
- A new service, package or product surface landed and nothing owns it
- A generalist keeps getting one area wrong in the same way

**Not** for: changing an existing agent's model or effort (that is a fleet-tier job), rewriting
an agent's prompt body (edit the file), or auditing the roster (`/review-agents`).

## Non-negotiables

1. **Search before creating.** Read every existing `.claude/agents/*.md` first. If a domain is
   already owned — even partly — the answer is "extend that agent", never a second file. Never
   create `foo-specialist-v2`, `foo-specialist-new`, or `foo-specialist-2`.
2. **A multi-line `description` MUST be a YAML block scalar (`description: |`).** Without it,
   YAML parsing stops at the first blank line, the `<example>` blocks become invalid top-level
   keys, and the harness **silently** drops the agent. The file sits on disk looking fine and is
   not invocable. This is the single most common way a new agent fails.
3. **`model:` is an ALIAS, never a dated ID.** An alias inherits the next model release for free;
   a pinned ID turns a free upgrade into a fleet-wide migration.
4. **Review/consolidation agents are read-only** — deny `Write`, `Edit` and `NotebookEdit`.
5. **Propose few.** Read Step 2's sizing rule before naming a single candidate.

---

## Step 1 — SURVEY (read-only, cheap)

Do not open every file. You want shape, not content. Run these and keep the output to yourself.

```bash
# Layout: what are the top-level areas, and is this a monorepo?
ls -d */ 2>/dev/null | head -40
find . -maxdepth 3 -name package.json -o -maxdepth 3 -name pyproject.toml \
  -o -maxdepth 3 -name go.mod -o -maxdepth 3 -name Cargo.toml 2>/dev/null \
  | grep -v node_modules | head -30

# Size and language mix (a proxy for whether specialists are warranted at all)
git ls-files | grep -vE '(^|/)(node_modules|dist|build|vendor)/' | wc -l
git ls-files | sed -n 's/.*\.\([a-z0-9]\{1,5\}\)$/\1/p' | sort | uniq -c | sort -rn | head -12

# History depth — a repo younger than ~3 months has no churn signal worth reading
git log -1 --format=%as $(git rev-list --max-parents=0 HEAD | tail -1)

# CHURN: which areas actually move (90 days, two levels deep).
# The TOTAL is what the 5% threshold in Step 2 is measured against — print it.
git log --since="90 days ago" --name-only --pretty=format: -- . \
  | grep -v '^$' | awk -F/ 'NF>1{print $1"/"$2} NF==1{print $1}' \
  | sort | uniq -c | sort -rn | tee /dev/stderr | awk '{t+=$1} END{print "TOTAL:", t}'

# FIX DENSITY: where the same area keeps breaking (adjust the grep to your commit convention)
git log --since="90 days ago" --name-only --pretty=format: --grep='^fix' -- . \
  | grep -v '^$' | awk -F/ 'NF>1{print $1"/"$2} NF==1{print $1}' \
  | sort | uniq -c | sort -rn | head -12
```

Then read, briefly:

- `.claude/agents/*.md` — **every** one, plus `.claude/agents/README.md` if present. This is the
  search-before-creating pass.
- `CLAUDE.md` and `.claude/rules/*.md` — what the project already says about itself. A constraint
  already written down does not need an agent to carry it.
- `docs/` top level, or the README — named subsystems, and which of them have their own docs.
- Any archive directory (`docs/archive/`, `.claude/**/archive*`) — an agent retired six months ago
  is evidence, not a gap.

**Exclude from the churn read before you interpret it** — these produce enormous churn and are not
domains: `node_modules`, lockfiles, build output, generated clients, vendored code, and — the one
that will bite you in a repo using this kit — **the harness's own written artifacts**: agent memory
stores, shared-memory files, telemetry logs, scratch or workbench directories. On a mature project
those routinely rank in the top five by file count while owning no product surface at all. If an
area's churn is mostly files *an agent wrote*, drop it.

## Step 2 — PROPOSE, and propose FEW

### Two different things are being proposed

| Kind | What it is | How many |
|---|---|---|
| **Role agents** | `code-reviewer`, `test-runner`. Cross-cutting, read-only, no domain. | Exactly these two, if absent |
| **Domain owners** | Own a slice of the codebase and the invariants inside it. | See the sizing rule |

**Recommend the two role agents FIRST when they are missing**, before any domain owner, and
regardless of repo size — a ten-file project still benefits from a reviewer. Give the reviewer
the kit's reviewer-discipline block (in `01-BOOTSTRAP.md` § Agent Architecture) verbatim in its
prompt body: an LLM reviewer's characteristic failure is manufacturing findings to look thorough,
and that block is the counter-pressure. Both get `disallowedTools: [Write, Edit, NotebookEdit]`.

### The sizing rule (a ceiling, not a quota)

A directory earns a domain owner only if it clears **all four**:

1. **Churn** — it is in the top of the 90-day churn list, at roughly ≥5% of touched files.
2. **Fix density** — fixes keep landing there. Repeated repair is the signal; volume alone is not.
3. **A contract that spans files** — a schema, a wire format, an entitlement check, a state
   machine, a webhook, a migration path. Something where the *relationship between files* is what
   goes wrong, not any one file.
4. **Vocabulary a generalist gets wrong** — a word that means something specific here
   (`status` vs `state`, `active` vs `enabled`, a currency's minor units, a tenant boundary). If
   you cannot name the word, you do not yet have a domain.

Then cap it: **propose at most `ceil(qualifying_areas / 2)`, and at most 3 in one run.** Agents
are cheap to add and expensive to have — every description competes for the same selection budget,
and an agent nobody invokes is worse than no agent, because it makes the roster look covered.

The cap is per run, not per project. Say so in the hand-off: re-run when a new service lands or a
directory starts accumulating fixes. On a mature repo the common outcome is **zero** — every
qualifying area already has an owner, and the useful output is a merge/split observation, not a
new file. Report that as a result, not as a failure to find work.

**Say "none yet" when that is the honest answer**, and mean it. A repo with fewer than a few
hundred source files, or less than ~3 months of history, or a single deployable with no service
boundary, gets the two role agents and nothing else. Tell the user what would change your mind:
"come back when the payments code has its own directory and a month of fixes."

### What a proposal looks like

One short block per candidate — never a table of ten:

```
CANDIDATE: payments-specialist
  Owns:      packages/billing/**, src/checkout/**, the webhook handler
  Not owns:  the pricing page copy, the auth session it reads
  Evidence:  61 files touched in 90d (4th), 38 of them in fix commits (2nd);
             webhook -> entitlement write spans 3 files with no type link
  Vocabulary: "subscription status" is the provider's field; "entitlement state"
             is ours, and they disagree during a trial — a generalist conflates them
  Model:     opus / xhigh   (money decisions; under-thinking costs more)
```

Then present the alternatives honestly: **extend an existing agent**, **write a rule instead**
(an always-on constraint needs no context of its own), or **not yet**.

## Step 3 — ASK, then INTERVIEW

Ask which candidates to create. Use `AskUserQuestion` if available; otherwise a numbered list and
wait. **Create nothing before an answer** — this skill writes files.

Per accepted candidate, interview. Keep it to five questions and accept short answers; you are
harvesting what is *not* derivable from the code:

1. **Invariants** — "what must always be true here that nothing enforces?" The ones that produce a
   plausible wrong answer rather than an error are the valuable ones.
2. **Traps** — "what does review keep catching in this area?" and "what bit you that you had to
   discover twice?"
3. **Sources of truth** — when the code, the docs and a dashboard disagree, which wins? Name the
   file or the table.
4. **Never do** — the irreversible or expensive actions. Be specific: "never backfill without a
   dry-run count first", not "be careful".
5. **Boundaries** — at the edge of this domain, who takes over? Name the other agent, or the human.

If an answer is "I don't know", write that down as an open question in the agent body rather than
inventing a confident invariant. A confident wrong invariant is worse than a stated gap.

## Step 4 — GENERATE `.claude/agents/<name>.md`

Filename **must** equal `name`. Lowercase, hyphens.

**Full worked example, with per-section notes: [`agent-template.md`](agent-template.md).** Read it
before writing the first file; the skeleton is:

```yaml
---
name: <domain>-specialist
description: |
  <what it owns, and one clause on what it does NOT own>

  Trigger keywords: <8-12 words a user would actually type>

  <example>…<commentary>why a generalist gets this wrong</commentary></example>
  <example>…<commentary>…</commentary></example>
model: opus
effort: high        # xhigh only for decision/diagnosis domains
color: green
memory: project
---
```

Body sections: **Domain map** (a path table) · **Invariants — break any of these and nothing
errors** · **Known traps** · **Boundaries** (who takes over) · **Sources of truth** · **Memory**.

Rules for the generated file:

- **`description:` is a block scalar** (`|`) whenever it spans lines. Non-negotiable #2.
- **Two concrete `<example>` blocks**, each with a `<commentary>` saying *why the generalist gets
  it wrong*. An example that only restates the description teaches nothing.
- **Front-load trigger keywords** — they are how the router picks this agent over its neighbours.
- `description` + `when_to_use` combined stays under 1,536 characters.
- **Body 200–800 words** — 200–400 read-only, 300–600 execution, 400–800 coordination. Subagents
  see **only** their own prompt: no `CLAUDE.md`, no parent conversation. Write it self-contained.
- **`model` + `effort` per the rubric** in [`../_shared/review-checklist.md`](../_shared/review-checklist.md).
  Short form: the fleet default is `opus` at `effort: high`; raise to `xhigh` only where the
  deliverable is a **decision, diagnosis or gate verdict** (money, auth, schema and data
  integrity, outage-class infra, deploy, review gates) rather than a document. An omitted
  `effort:` **inherits the launching session** — and a session's default on Opus 5.5 is
  `medium` — so state it.
- **`memory: project`** on every agent. The harness owns the store; **do not hand-create a memory
  directory or invent a path for it.** If this project already keeps agent memory files on disk,
  look at a sibling agent's and seed a matching index stub in the same place — otherwise leave it.
- **Tools**: omit to inherit everything; restrict only with a reason. Reviewers get
  `disallowedTools: [Write, Edit, NotebookEdit]`.

## Step 5 — REGISTER

1. **`.claude/agents/README.md`** — add a row in the right section, with the same trigger keywords
   as the description, and update any count the file states.
2. **`.claude/agent-model-tiers.json`**, if the project has one — add an entry with a `preferred`
   pair, a `fallback` pair, a `restore_tier`, and a one-line `note` giving the rubric clause the
   tier follows. Then:
   ```bash
   # The bootstrap installs the script at scripts/; find it rather than assume.
   TIER=$(ls scripts/agent-model-tier.py agent-model-tier.py 2>/dev/null | head -1)
   [ -n "$TIER" ] || echo "agent-model-tier.py not found -- the manifest was NOT checked"
   python3 "$TIER" check     # non-zero = manifest and disk disagree
   python3 "$TIER" status    # which mode is declared
   ```
   If the script is not there, say so in your report. An unchecked manifest is not a passing one.
   **A missing entry makes the check fail for everyone**, so it lands in the same commit as the
   agent file. If the manifest declares `fallback` mode, write the agent file at the *fallback*
   pair and record `preferred` in the manifest — not the other way round.
3. **Re-grep for count sites before finishing.** A roster count is quoted in more places than the
   roster: `grep -rn "agent" --include="*.md" --include="*.json" --include="*.sh" . | grep -iE "[0-9]+ agents?"`.
   Every hit is a site that must move in this commit or go stale.

## Step 6 — VERIFY it registered

A written file is not a live agent. Prove it:

```bash
# 1. Frontmatter parses, and the description is a block scalar if multi-line
python3 - <<'PY'
import pathlib, re, sys
for f in sorted(pathlib.Path(".claude/agents").glob("*.md")):
    t = f.read_text()
    m = re.match(r"(?s)^---\n(.*?)\n---\n", t)
    if not m: print("NO FRONTMATTER:", f); continue
    fm = m.group(1)
    if re.search(r"^description:\s*\S", fm, re.M) and re.search(r"^\s+\S", fm, re.M):
        if not re.search(r"^description:\s*[|>]", fm, re.M):
            print("NOT A BLOCK SCALAR (agent will silently de-register):", f)
    if not re.search(r"^name:\s*"+re.escape(f.stem)+r"\s*$", fm, re.M):
        print("NAME != FILENAME:", f)
PY

# 2. The old breakage signature: an un-scalared "Examples:" line in frontmatter
grep -lE "^(  )?Examples:$" .claude/agents/*.md
```

Then tell the user the human check: **restart Claude Code, run `/agents`, and confirm the new name
is listed.** Registration failures are silent — the only other way to find one is a delegation that
returns "agent not found".

## Step 7 — Tell them when to SPLIT and when to RETIRE

Write these into the hand-off, because they are the part that never gets revisited.

**Split** when two or more hold at once: the description joins unrelated domains with "and";
trigger keywords fall into 2+ disjoint clusters; the body passes ~1000 words spanning separate
concerns; the agent is invoked for mutually exclusive reasons. Split by *decision boundary*, not
by directory — "who decides this" is the seam.

**Retire** when the surface is gone, the agent has not been invoked in ~6 months and its domain is
dead, or another agent's scope has grown over it. Move the file to an archive directory **outside
`.claude/agents/`** — the harness loads that tree recursively, so a tombstone left inside stays in
the live roster and keeps consuming the description budget. Add a dated header note naming the
successor, drop it from the roster and the tier manifest, and fix the references that pointed at it.

**Merge** when two agents overlap: descriptions are largely the same, trigger keywords overlap
heavily, same domain boundary, and they are almost always invoked in sequence.

## Anti-patterns

- Proposing one agent per top-level directory — that is a file listing, not a roster
- A candidate justified by "it would be nice to have" rather than churn plus repeated fixes
- Creating a second agent for a domain an existing agent already partly owns
- A multi-line `description` without `|` (silent de-registration)
- A version-pinned model ID instead of the `opus` / `fable` alias
- `<example>` blocks that restate the description instead of showing the generalist's error
- A body that assumes project context the subagent will never see
- Writing the agent file and skipping the roster row or the tier-manifest entry
- Inventing a memory directory layout the project does not already use

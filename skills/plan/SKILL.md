---
name: plan
description: Use when entering PLAN mode or when the user says "Enter P". Creates structured implementation plans with Vibe Board tasks and specialist agent assignments for each checklist item.
user-invocable: true
---

# PLAN Mode Protocol

You are entering PLAN mode. Follow this protocol exactly.

## Step 0: Detect Work Type (3-tier vs flat)

Before generating an implementation checklist, classify the work request. **Most invocations are flat — Step 0 is a fast routing check, not a ceremony.**

**Invoke 3-tier flow (story → design → tasks)** when ANY hold:
- Work spans 5+ implementation tasks
- Touches shared infra (DB schema, RLS, auth, billing, deployment pipeline)
- Crosses 2+ services
- Has external stakeholder visibility (founder asked for a named deliverable, or it'll appear in marketing/release notes)
- Requires architectural decision visible to non-engineers (e.g., choosing between competing approaches that have long-term implications)

**Use the flat flow (Steps 1-4 below — existing behavior)** when:
- Single-thread bug fix, refactor, or feature touching <5 tasks
- One-file change
- Adding a flag, deploying from existing template, routine ops
- Estimable in <4 hours

**When in doubt** → ask the user with choice-based clarification (ONE multiple-choice question at a time, never a 10-question waterfall):

> This looks like substantial work. Should I:
> 1. Create a STORY (with "why" + success metric) + DESIGN RFC (with ripple effects + ADRs) + implementation tasks
> 2. Just create a flat implementation task list (skip story + design — faster, less anchoring)

**If 3-tier is selected**: invoke `project-coordinator` to produce the STORY task + DESIGN task per its 3-Tier Decomposition Protocol, THEN return here for Step 2 to decompose the design into implementation tasks. The implementation tasks should reference their parent design in description ("Design: <design_task_id>") so reviewers can trace back.

**Soft task_type convention** (until Vibe Board MCP gains a native `task_type` field per ADK-8): title prefixes carry the type — `[STORY]`, `[DESIGN]`, `[BUG]`, `[CHORE]`, `[INVESTIGATION]`. Plain titles = regular implementation task. See `.claude/rules/agent-board.md` § Task Type Convention.

## Step 1: Research & Design

Analyze the task and create an exhaustive implementation specification:
- File names, function signatures, data flows
- Dependencies and execution order
- Risk areas and edge cases

## Step 2: Create Board Tasks

For EACH item in your implementation checklist, call `board_create_task` with:
- `title`: Clear, actionable description
- `assigned_agent`: The specialist agent who should execute this task (MANDATORY — see mapping below)
- `status`: `todo`
- `riper_mode`: `plan`
- `depends_on`: Task IDs of prerequisites (if any)
- `priority`: Based on blocking relationships (`critical` if it blocks others, `high` if important, `medium` default)
- `description`: Must include ALL of the following:
  1. **Context**: Enough for the assigned agent to execute without additional research
  2. **Acceptance criteria**: Specific, verifiable conditions that define "done" — not just "build X" but "build X with [specific behavior], [specific config], [specific output]". These are what post-execute review checks against.
  3. **Key spec points**: Any user-specified requirements (schedule, trigger method, notification behavior, etc.) that distinguish this from a generic implementation

**Why acceptance criteria matter**: Post-execute review compares implementation against these criteria. Without them, review can only check "does it run?" not "does it match the plan?" — which is how plan drift goes undetected.

## Agent Assignment Mapping

| Task Type | Assign To |
|-----------|-----------|
| DB schema, migration, RLS policy | `database-specialist` |
| React component, page, layout, styling | `ui-specialist` |
| Chat/LangChain service code | `chat-specialist` |
| Long-form grading service code | `grading-specialist` |
| Scenario-assessment service code | `assessment-specialist` |
| Document-analysis service code | `doc-analysis-specialist` |
| Corpus enrichment/vector search | `corpus-specialist` |
| Study plan/syllabus service | `planning-specialist` |
| Practice/quiz/content-library features | `practice-specialist` |
| Security review, code quality | `code-reviewer` |
| Tests, type-check, validation | `test-runner` |
| Cloud Build, GCS, deployment | `deployment` |
| Auth flow, JWT, Firebase | `auth-specialist` |
| Stripe, billing, subscription | `subscription-specialist` |
| Marketing copy, UTM, analytics | `marketing-specialist` |
| Mobile, Capacitor, iOS/Android | `mobile-specialist` |
| Gemini AI, prompt caching | `ai-infrastructure` |
| GCP infra, gcloud, IAM | `gcp-infra` |
| Cloud Run Docker/config | `cloud-run-specialist` |
| Dashboard widgets, progress display | `dashboard-specialist` |
| Course/module/lesson, video hosting | `courses-specialist` |
| Blog content, static site, image CDN | `blog-specialist` |
| Outline template creation/editing | `outline-manager` |
| n8n workflow logic | `n8n-automator` |
| n8n infrastructure/deployment | `n8n-manager` |
| Knowledge-graph integration | `intelligence-specialist` |
| Flagship product-line features | `product-line-specialist` |
| Structured content authoring | `content-writer` |
| Community, discussions, threads, @mentions | `community-specialist` |
| Dashboard widgets, study stats display | `dashboard-specialist` |
| MIG-hosted service ops (Docker, listmonk, n8n, AI containers) | `mig-specialist` |
| Automation strategy / what-to-automate audits | `automation-architect` |
| Bulk sub-agent output consolidation | `processor` |
| Cross-domain coordination (3+ areas) | `project-coordinator` |
| Documentation, agent/skill lifecycle, /review-* audits | `docs-manager` |

If a task spans multiple domains, assign the primary specialist and note secondary reviewers in the description.

## Step 3: Output Checklist

Present the numbered implementation checklist with board task IDs and assignments:

```
IMPLEMENTATION CHECKLIST:
1. [Task title] — assigned: [agent] — board: [task_id]
2. [Task title] — assigned: [agent] — board: [task_id]
...
```

## Step 4: Auto-Transition

After the checklist is complete, state:
"Plan created with [N] board tasks. Auto-transitioning to REVIEW for plan validation."

Then enter REVIEW mode to validate the plan (invoke the `/review` skill or manually verify assignments).

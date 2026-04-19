---
name: plan
description: Use when entering PLAN mode or when the user says "Enter P". Creates structured implementation plans with Vibe Board tasks and specialist agent assignments for each checklist item.
user-invocable: true
---

# PLAN Mode Protocol

You are entering PLAN mode. Follow this protocol exactly.

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
| Essay Coach service code | `essay-coach-specialist` |
| Issue Spotter service code | `issue-spotter-specialist` |
| Outline IQ service code | `outline-iq-specialist` |
| Case enrichment/vector search | `case-law-specialist` |
| Study plan/syllabus service | `study-plan-specialist` |
| Flashcards/study mode/Question Bank | `study-specialist` |
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
| Course/module/lesson, Gumlet video | `courses-specialist` |
| Blog content, Astro, TwicPics | `blog-specialist` |
| Outline template creation/editing | `outline-manager` |
| n8n workflow logic | `n8n-automator` |
| n8n infrastructure/deployment | `n8n-manager` |
| Learning Intelligence integration | `intelligence-specialist` |
| NextGen bar prep features | `nextgen-specialist` |
| NextGen question/MCQ authoring | `nextgen-question-writer` |
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

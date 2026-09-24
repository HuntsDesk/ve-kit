---
name: close
description: Wind this window down so it can be closed without losing anything. Stashes this session's own uncommitted edits by explicit path, returns its in-progress Vibe Board tasks, ends the board session with a handoff, and files anything that needs a HUMAN on the human task board. Run when the user types /close, or when a cross-session message quotes the user's instruction to close windows. Never self-initiate.
user-invocable: true
---

# /close — shut this window down cleanly

You are being shut down. The user has too many windows open and is closing them all. Your job is to **leave**, not to resume: park what is yours, hand off what is open, and file for a human anything only a human can do. Then say you are ready to close. The user closes the tab.

**Assume the codebase has moved since you last looked.** Windows sit idle for days while other windows commit and push. Do not "catch up" on the tree, do not re-run the work you were doing, do not start anything new, and **do not commit**. A window that has been idle cannot judge deploy-safety, and any commit on shared `dev` can be swept to prod by another window.

**Budget: about ten tool calls.** Every step below is a handful of calls. If something would take more, it goes into the handoff or the human task as a pointer, not into this session.

## Step 1 — Re-orient in three commands

```bash
git branch --show-current && git log --oneline -3
git status --short
git stash list | head
```

`git status` shows the whole shared tree. **Most of what it lists is not yours.** Only the files *you edited in this conversation* are yours to act on. If you cannot tell from your own transcript that you edited a file, you did not.

## Step 2 — Inventory what this session owns

From your own transcript, list:

- **Files you edited that are still uncommitted** (cross-check against `git status`).
- **Vibe Board tasks you moved to `in_progress`** (`board_get_tasks(project_id, status='in_progress')` on the project you were working in; match `assigned_agent` or the task IDs you remember).
- **Sub-agents still running.** Do not wait more than one tool round. Whatever they have not returned is recorded as "collection abandoned at close" in the handoff.
- **Promises you made to the user that are not delivered** — a summary owed, a check you said you would run, a decision you asked for and never received.
- **Doc, rule, or agent files you were mid-edit on.**

## Step 3 — Park your uncommitted edits, by explicit path only

**Decide each of your dirty files first; a stash is the middle option, not the default.** Nobody sees a stash: it is local to this machine and appears on no board. So:

- **Throwaway** (a probe, a scratch edit, something already superseded on HEAD) → discard it (`git checkout -- <path>` for a tracked file, `rm` for one you created) and say so in the report block. Do not stash junk.
- **Worth keeping** → stash it (below) **and, in Step 4, create a Vibe Board task** titled `[CHORE] Pick up stash close/<window>: <topic>` assigned to the owning specialist, with the stash name, the paths, and whether the work was reviewed. That task is the only thing that makes the stash findable; the SessionStart hook also lists `close/` stashes to every new window on this machine.
- **Needs a person** (a draft to send, a decision) → Step 5 human task, which names the stash too.

For the files you are keeping:

```bash
git stash push -u -m "close/<session-name>: <one-line topic>" -- <path> <path> ...
```

- **`-u` is required whenever one of your paths is a file you created this session.** Without it git refuses the untracked path ("did not match any file(s) known to git") and aborts the whole command, leaving even your tracked files dirty. With `-u` **and** explicit paths it stashes exactly those files.
- **Explicit paths only. Never a bare `git stash`, never a bare `git stash -u`, never `git add -A`.** The tree is shared; a bare stash swallows every other window's work, and a bare `-u` swallows their new files too. If the command errors, fix the path list, never drop it.
- If you know another window is also editing one of those files, **leave that file alone** and name it in the handoff instead. Git cannot tell whose hunks are whose.
- A finished edit that never went through post-execute review is still stashed, not committed. Say in the human task that the stash holds reviewed or unreviewed work so the next window knows what it is picking up.
- Nothing dirty of yours? Skip this step. Do not touch other windows' files to "tidy".

## Step 4 — Return your board tasks

For each task you hold `in_progress`:

- Finished and verified → `board_update_task(status='done')`.
- Not finished → `board_log_activity(action='commented')` with exactly where it stands (files, stash name, what is left), then `board_update_task(status='todo')`. An `in_progress` task with no live session behind it is an orphan; return it so the next window can claim it.

Then, before ending the session, two checks from `02-VIBE-BOARD.md` Ending a session that this protocol keeps:

- **Every agent-side follow-up you know about exists as a board task.** If you also file a human task in Step 5 that depends on it, link the two both ways there. A promise from Step 2 that an agent (not a person) should keep — "finish the migration", "re-run the batch", "propagate the fix to the sibling file" — gets `board_create_task` now, with the stash name and file paths in its description. Handoff prose is not a task; it is read once and forgotten.
- **Shared-memory check.** If this session learned something cross-developer-valuable with a rule and a reason (a wrong endpoint, a postgres trap, a convention), `board_save_shared_memory` it now. Most sessions have nothing; that is fine.


Then end the session:

```
board_end_session(session_id, progress_summary, handoff_notes, context_artifacts)
```

`handoff_notes` cites task IDs and the stash name.

**If your board session is already ended, or its ID was lost to compaction, do NOT call `board_create_session` to get one to close.** That call auto-abandons every active session on the project, and other windows are working there right now. Instead put the close state (stash name, files, human task id) in a `board_log_activity(action='commented')` on the task you touched most recently, and say "session already ended" in the report block. The handoff is what matters, not the session record.

**If the board MCP is unavailable in this window** (a `No such tool available: mcp__vibe-board` error), skip the board calls and put the handoff text into the human task description in Step 5. That is the fallback that survives the window.

## Step 5 — File what needs a HUMAN, on the human board

The Vibe Board tracks agent work. Human work — a decision, an approval, a manual check — goes on the project's **human task board**, and the closing window writes to it so the ask outlives the tab. Which board that is depends on the project: a dedicated admin surface, an external tracker, or a human-only project inside the same Vibe Board instance with `assigned_agent` set to the person (`02-VIBE-BOARD.md` § Human tasks on the same board). The rules below hold for any of them; only the write path differs.

**File a task only when a person has to act.** That means: a decision you were waiting on; an approval (a push to main, a flag flip, a spend, an email send); a manual check only the user can do (their inbox, Stripe dashboard, a phone call); a deliverable you drafted that they need to send or paste; reviewed work sitting in a stash that someone should commit. "Continue the code work" is **not** a human task — that is a Vibe Board task, and Step 4 already covers it.

**Apply your own recommendation first.** If the ask is "close or backlog these", "which project should this live in", or any other board-hygiene call where you already hold a recommendation, **do it** and note it in the handoff. A human task is for a decision only a person can make, not for a decision you can make and have not. And **name the things**: a task that points at "the ~18 tasks in session X's handoff" cannot be acted on; list the ids.

**Re-verify the ask at HEAD before you file it.** You have been idle; the decision you were waiting on may have been made. For each board task you are about to cite, read the `board_get_task` result you fetched for the back-link: a `status` of `done`, or `metadata.queue_status = "decided"` / `decided_by` / `decision`, means the question is answered — quote the decision in your handoff and do not file it. (2026-09-16: a window filed five decisions for the project owner, two of which the owner had answered nine days earlier; both were marked decided on the board.)

**Look before you file — someone may already have.** Read the open human tasks that cite any board id you are about to cite, or that match your title. If one is the same ask in other words, add your note to it and file nothing new.

**One ask per task.** Bundle only decisions that share one context AND one action type. If two items differ in *what the person does* (send vs decide vs run vs approve) or *when* (one has a due date, the other does not), they are separate tasks, even if they came from the same window. (2026-09-16: "send a teammate a summary" and "run /self-improve on the 23rd" were filed as one task; the send was done within the hour and the task title stayed wrong for the week.)

The description must let the user act without reopening this window. Include, in this order: the window's topic and session name; what exactly they need to do; where the artifacts are (stash name, file paths, board task IDs, a doc path); and what happens if it is ignored. Full fidelity, no truncation. One task per distinct ask; usually zero or one per window.

**Link both directions.** Every board task the human task cites must point back at it in its `metadata` (the human-task-ids array your board convention names), so an agent closing that board task later knows there is a human task to update. **The metadata merge is shallow: the array is replaced, not appended.** So for each board id: `board_get_task` it, take its existing array, and write the union. Passing only the new id silently unlinks an earlier human task, which then reads "waiting on you" forever. A board id that appears in your description but not in the back-link set is a filing error; the report block below makes the count visible.


**Nothing needs a human?** File nothing. A clean close is silent.

## Step 6 — Report and stop

End with this block and nothing after it:

```
READY TO CLOSE — <session-name>
Stashed:      <stash name + paths> | none
Board:        <task IDs returned or closed> | none held
Human task:   <id + title> · vibe refs passed: <n> · board ids named in description: <n> | none needed
Left in tree: <files of yours you deliberately left, and why> | none
Session:      ended <session_id> | already ended, close state on <task id> | board unavailable, handoff in human task
```

Do not summarize your session's history, do not offer follow-ups, do not ask a question. The user closes the tab.

## What this skill is not

- Not a review gate. Post-execute review is normally required before a session ends (`riper-cat.md` MODE 5); this protocol carves that out on purpose, because a closing window commits nothing. Unreviewed work goes into a stash labelled as unreviewed (Step 3), and the review runs in the window that picks it up.
- Not a sweep of the shared tree. You act on your files only.
- Not a commit path. If the user wants a stash committed, a fresh window does that with the normal RIPER flow.

## Related

- `02-VIBE-BOARD.md` Ending a session — the board half of this protocol

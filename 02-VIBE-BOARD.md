# Vibe Board: Persistent Task Tracking for AI Coding Agents

A Firebase Firestore-backed MCP server that gives AI coding agents (Claude Code, etc.) persistent memory across sessions. Tasks, projects, and session handoffs survive when conversations end.

**The problem**: AI coding sessions are stateless. When a conversation ends, all context — what was planned, what was done, what's next — evaporates. Plans get lost, steps get skipped, and every new session starts from scratch.

**The solution**: A shared task board that lives outside any single conversation. Agents create tasks during planning, track progress during execution, and write handoff notes when sessions end. The next session picks up exactly where the last one left off.

---

## What You Get

- **14 MCP tools** for task/project/session management (see [full list below](#mcp-tool-reference))
- **Session handoff protocol** — relay race, not marathon
- **Activity log** — audit trail of every decision and change, queryable via `board_get_activity`
- **RIPER mode tracking** — optional workflow mode integration
- **Task project-reassignment + bulk operations** — move tasks between projects, consolidate projects, hard-delete with safety guards
- **Free tier** — Firebase Firestore free tier handles thousands of sessions

## Architecture

```
Claude Code / AI Agent
    |
    | (MCP stdio)
    v
mcp-vibe-board (Node.js)
    |
    | (Firebase Admin SDK)
    v
Firestore (4 collections)
    - projects
    - tasks
    - sessions
    - activity_log
```

---

## Setup (15 minutes)

### Prerequisites

- Node.js 18+
- `gcloud` CLI authenticated
- A Google Cloud / Firebase project (or create one)

### Step 1: Create a Firebase Project

```bash
# Option A: Use an existing GCP project
# Option B: Create a new one at https://console.firebase.google.com

# Enable Firestore API
gcloud services enable firestore.googleapis.com --project=YOUR_PROJECT_ID

# Create Firestore database (Native mode, pick your region)
gcloud firestore databases create \
  --project=YOUR_PROJECT_ID \
  --location=us-central1 \
  --type=firestore-native
```

### Step 2: Create a Service Account

```bash
# Create service account
gcloud iam service-accounts create vibe-board \
  --project=YOUR_PROJECT_ID \
  --display-name="Vibe Board MCP"

# Grant Firestore access
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:vibe-board@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

# Download key (store securely, never commit to git)
gcloud iam service-accounts keys create ~/.config/gcloud/vibe-board-key.json \
  --iam-account=vibe-board@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

### Step 3: Create the MCP Server

Create a directory called `mcp-vibe-board/` in your project root.

#### `package.json`

```json
{
  "name": "mcp-vibe-board",
  "version": "1.0.0",
  "type": "module",
  "private": true,
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.26.0",
    "firebase-admin": "^13.6.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "typescript": "^5.7.0"
  }
}
```

#### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

#### `.gitignore`

```
node_modules/
dist/
```

#### `src/firestore-client.ts`

```typescript
import { initializeApp, cert, type ServiceAccount } from "firebase-admin/app";
import { getFirestore, Firestore } from "firebase-admin/firestore";
import { readFileSync } from "node:fs";

let db: Firestore | null = null;

export function getDb(): Firestore {
  if (db) return db;

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credPath) {
    throw new Error(
      "GOOGLE_APPLICATION_CREDENTIALS environment variable is required"
    );
  }

  const serviceAccount = JSON.parse(
    readFileSync(credPath, "utf-8")
  ) as ServiceAccount;

  const app = initializeApp({
    credential: cert(serviceAccount),
  });

  db = getFirestore(app);
  return db;
}
```

#### `src/types.ts`

```typescript
import { Timestamp } from "firebase-admin/firestore";

export interface Project {
  name: string;
  description: string | null;
  status: "active" | "completed" | "archived";
  metadata: Record<string, unknown>;
  created_at: Timestamp;
  updated_at: Timestamp;
}

export interface Task {
  project_id: string;
  title: string;
  description: string | null;
  status: "backlog" | "todo" | "in_progress" | "blocked" | "review" | "done";
  priority: "critical" | "high" | "medium" | "low";
  assigned_agent: string | null;
  parent_task_id: string | null;
  depends_on: string[];
  riper_mode:
    | "research"
    | "innovate"
    | "plan"
    | "execute"
    | "review"
    | "commit"
    | null;
  metadata: Record<string, unknown>;
  created_at: Timestamp;
  updated_at: Timestamp;
  started_at: Timestamp | null;
  completed_at: Timestamp | null;
}

export interface Session {
  project_id: string;
  session_type: "solo" | "team" | "background";
  status: "active" | "completed" | "crashed" | "abandoned";
  started_at: Timestamp;
  ended_at: Timestamp | null;
  progress_summary: string | null;
  handoff_notes: string | null;
  context_artifacts: {
    files_modified?: string[];
    decisions_made?: string[];
    blockers?: string[];
    next_steps?: string[];
    [key: string]: unknown;
  };
  metadata: Record<string, unknown>;
}

export interface ActivityLog {
  task_id: string | null;
  session_id: string | null;
  agent_name: string;
  action:
    | "created"
    | "updated"
    | "claimed"
    | "blocked"
    | "completed"
    | "commented"
    | "mode_changed"
    | "session_started"
    | "session_ended";
  details: string | null;
  metadata: Record<string, unknown>;
  created_at: Timestamp;
}

export const TASK_STATUSES = [
  "backlog",
  "todo",
  "in_progress",
  "blocked",
  "review",
  "done",
] as const;

export const TASK_PRIORITIES = [
  "critical",
  "high",
  "medium",
  "low",
] as const;

export const SESSION_TYPES = ["solo", "team", "background"] as const;

export const RIPER_MODES = [
  "research",
  "innovate",
  "plan",
  "execute",
  "review",
  "commit",
] as const;
```

#### `src/tools/projects.ts`

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Firestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

export function registerProjectTools(server: McpServer, db: Firestore) {
  server.tool(
    "board_get_projects",
    "List all projects with task count summaries per status",
    {
      status: z
        .enum(["active", "completed", "archived"])
        .optional()
        .describe("Filter by project status"),
    },
    async ({ status }) => {
      let query: FirebaseFirestore.Query = db.collection("projects");
      if (status) {
        query = query.where("status", "==", status);
      }

      const snapshot = await query.orderBy("updated_at", "desc").get();
      const projects = await Promise.all(
        snapshot.docs.map(async (doc) => {
          const data = doc.data();
          const tasksSnap = await db
            .collection("tasks")
            .where("project_id", "==", doc.id)
            .get();

          const taskCounts: Record<string, number> = {};
          tasksSnap.docs.forEach((t) => {
            const s = t.data().status as string;
            taskCounts[s] = (taskCounts[s] || 0) + 1;
          });

          return {
            id: doc.id,
            ...data,
            created_at: data.created_at?.toDate?.()?.toISOString() ?? null,
            updated_at: data.updated_at?.toDate?.()?.toISOString() ?? null,
            task_counts: taskCounts,
            total_tasks: tasksSnap.size,
          };
        })
      );

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(projects, null, 2),
          },
        ],
      };
    }
  );

  server.tool(
    "board_create_project",
    "Create a new project for tracking tasks and sessions",
    {
      name: z.string().describe("Project name"),
      description: z
        .string()
        .optional()
        .describe("Project description"),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Additional metadata"),
    },
    async ({ name, description, metadata }) => {
      const now = Timestamp.now();
      const docRef = await db.collection("projects").add({
        name,
        description: description ?? null,
        status: "active",
        metadata: metadata ?? {},
        created_at: now,
        updated_at: now,
      });

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                id: docRef.id,
                name,
                status: "active",
                message: `Project "${name}" created successfully`,
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );
}
```

#### `src/tools/tasks.ts`

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

export function registerTaskTools(server: McpServer, db: Firestore) {
  server.tool(
    "board_get_tasks",
    "Get tasks for a project, filterable by status, priority, or assignment",
    {
      project_id: z.string().describe("Project ID to get tasks for"),
      status: z
        .enum(["backlog", "todo", "in_progress", "blocked", "review", "done"])
        .optional()
        .describe("Filter by task status"),
      priority: z
        .enum(["critical", "high", "medium", "low"])
        .optional()
        .describe("Filter by priority"),
      assigned_agent: z
        .string()
        .optional()
        .describe("Filter by assigned agent name"),
      include_done: z
        .boolean()
        .optional()
        .describe("Include done tasks (default: false)"),
    },
    async ({ project_id, status, priority, assigned_agent, include_done }) => {
      let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> = db
        .collection("tasks")
        .where("project_id", "==", project_id);

      if (status) {
        query = query.where("status", "==", status);
      } else if (!include_done) {
        query = query.where("status", "!=", "done");
      }

      if (priority) {
        query = query.where("priority", "==", priority);
      }

      if (assigned_agent) {
        query = query.where("assigned_agent", "==", assigned_agent);
      }

      const snapshot = await query.get();
      const priorityOrder: Record<string, number> = {
        critical: 0,
        high: 1,
        medium: 2,
        low: 3,
      };

      const tasks = snapshot.docs
        .map((doc) => {
          const data = doc.data();
          return {
            id: doc.id,
            project_id: data.project_id as string,
            title: data.title as string,
            description: data.description as string | null,
            status: data.status as string,
            priority: data.priority as string,
            assigned_agent: data.assigned_agent as string | null,
            parent_task_id: data.parent_task_id as string | null,
            depends_on: data.depends_on as string[],
            riper_mode: data.riper_mode as string | null,
            metadata: data.metadata as Record<string, unknown>,
            created_at: data.created_at?.toDate?.()?.toISOString() ?? null,
            updated_at: data.updated_at?.toDate?.()?.toISOString() ?? null,
            started_at: data.started_at?.toDate?.()?.toISOString() ?? null,
            completed_at: data.completed_at?.toDate?.()?.toISOString() ?? null,
          };
        })
        .sort(
          (a, b) =>
            (priorityOrder[a.priority] ?? 99) -
            (priorityOrder[b.priority] ?? 99)
        );

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(tasks, null, 2),
          },
        ],
      };
    }
  );

  server.tool(
    "board_create_task",
    "Create a new task in a project",
    {
      project_id: z.string().describe("Project ID"),
      title: z.string().describe("Task title"),
      description: z.string().optional().describe("Task description"),
      status: z
        .enum(["backlog", "todo", "in_progress", "blocked", "review", "done"])
        .optional()
        .describe("Initial status (default: todo)"),
      priority: z
        .enum(["critical", "high", "medium", "low"])
        .optional()
        .describe("Priority (default: medium)"),
      assigned_agent: z
        .string()
        .optional()
        .describe("Agent name to assign to"),
      parent_task_id: z
        .string()
        .optional()
        .describe("Parent task ID for subtasks"),
      depends_on: z
        .array(z.string())
        .optional()
        .describe("Task IDs this task depends on"),
      riper_mode: z
        .enum(["research", "innovate", "plan", "execute", "review", "commit"])
        .optional()
        .describe("Current RIPER mode"),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Additional metadata"),
    },
    async ({
      project_id,
      title,
      description,
      status,
      priority,
      assigned_agent,
      parent_task_id,
      depends_on,
      riper_mode,
      metadata,
    }) => {
      const now = Timestamp.now();
      const taskStatus = status ?? "todo";

      const docRef = await db.collection("tasks").add({
        project_id,
        title,
        description: description ?? null,
        status: taskStatus,
        priority: priority ?? "medium",
        assigned_agent: assigned_agent ?? null,
        parent_task_id: parent_task_id ?? null,
        depends_on: depends_on ?? [],
        riper_mode: riper_mode ?? null,
        metadata: metadata ?? {},
        created_at: now,
        updated_at: now,
        started_at: taskStatus === "in_progress" ? now : null,
        completed_at: taskStatus === "done" ? now : null,
      });

      await db.collection("activity_log").add({
        task_id: docRef.id,
        session_id: null,
        agent_name: assigned_agent ?? "system",
        action: "created",
        details: `Task "${title}" created with status ${taskStatus}`,
        metadata: {},
        created_at: now,
      });

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                id: docRef.id,
                title,
                status: taskStatus,
                priority: priority ?? "medium",
                message: `Task "${title}" created successfully`,
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );

  server.tool(
    "board_update_task",
    "Update a task's status, assignment, priority, RIPER mode, or other fields",
    {
      task_id: z.string().describe("Task ID to update"),
      status: z
        .enum(["backlog", "todo", "in_progress", "blocked", "review", "done"])
        .optional()
        .describe("New status"),
      priority: z
        .enum(["critical", "high", "medium", "low"])
        .optional()
        .describe("New priority"),
      assigned_agent: z
        .string()
        .optional()
        .describe("New agent assignment (empty string to unassign)"),
      riper_mode: z
        .enum(["research", "innovate", "plan", "execute", "review", "commit"])
        .optional()
        .describe("New RIPER mode"),
      title: z.string().optional().describe("Updated title"),
      description: z.string().optional().describe("Updated description"),
      depends_on: z
        .array(z.string())
        .optional()
        .describe("Updated dependency list"),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Metadata to merge"),
    },
    async ({
      task_id,
      status,
      priority,
      assigned_agent,
      riper_mode,
      title,
      description,
      depends_on,
      metadata,
    }) => {
      const taskRef = db.collection("tasks").doc(task_id);
      const taskSnap = await taskRef.get();

      if (!taskSnap.exists) {
        return {
          content: [
            {
              type: "text" as const,
              text: JSON.stringify({ error: `Task ${task_id} not found` }),
            },
          ],
        };
      }

      const oldData = taskSnap.data()!;
      const now = Timestamp.now();
      const updates: Record<string, unknown> = { updated_at: now };
      const changes: string[] = [];

      if (status !== undefined) {
        updates.status = status;
        changes.push(`status: ${oldData.status} -> ${status}`);

        // Set started_at when first moving to in_progress (preserve on re-entry from blocked/review)
        if (status === "in_progress" && !oldData.started_at) {
          updates.started_at = now;
        }
        // Clear started_at if task is sent back to todo/backlog (genuinely un-started)
        if ((status === "todo" || status === "backlog") && oldData.started_at) {
          updates.started_at = null;
        }

        if (status === "done" && oldData.status !== "done") {
          updates.completed_at = now;
        } else if (status !== "done" && oldData.status === "done") {
          updates.completed_at = null;
        }
      }

      if (priority !== undefined) {
        updates.priority = priority;
        changes.push(`priority: ${oldData.priority} -> ${priority}`);
      }

      if (assigned_agent !== undefined) {
        updates.assigned_agent = assigned_agent === "" ? null : assigned_agent;
        changes.push(
          `assigned: ${oldData.assigned_agent ?? "none"} -> ${assigned_agent || "none"}`
        );
      }

      if (riper_mode !== undefined) {
        updates.riper_mode = riper_mode;
        changes.push(`riper_mode: ${oldData.riper_mode ?? "none"} -> ${riper_mode}`);
      }

      if (title !== undefined) {
        updates.title = title;
        changes.push(`title updated`);
      }

      if (description !== undefined) {
        updates.description = description;
        changes.push(`description updated`);
      }

      if (depends_on !== undefined) {
        updates.depends_on = depends_on;
        changes.push(`dependencies updated`);
      }

      if (metadata !== undefined) {
        updates.metadata = { ...oldData.metadata, ...metadata };
        changes.push(`metadata updated`);
      }

      await taskRef.update(updates);

      const action = status === "done" ? "completed" :
                     status === "blocked" ? "blocked" :
                     assigned_agent !== undefined ? "claimed" :
                     riper_mode !== undefined ? "mode_changed" : "updated";

      await db.collection("activity_log").add({
        task_id,
        session_id: null,
        agent_name: (assigned_agent !== undefined && assigned_agent !== "")
          ? assigned_agent
          : oldData.assigned_agent ?? "system",
        action,
        details: changes.join(", "),
        metadata: {},
        created_at: now,
      });

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                id: task_id,
                changes,
                message: `Task updated: ${changes.join(", ")}`,
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );
}
```

#### `src/tools/sessions.ts`

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

export function registerSessionTools(server: McpServer, db: Firestore) {
  server.tool(
    "board_create_session",
    "Start a new session. Abandons any stale active sessions and returns handoff context from the previous session.",
    {
      project_id: z.string().describe("Project ID"),
      session_type: z
        .enum(["solo", "team", "background"])
        .optional()
        .describe("Session type (default: solo)"),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Additional metadata"),
    },
    async ({ project_id, session_type, metadata }) => {
      const now = Timestamp.now();

      // 1. Abandon stale active sessions
      const activeSessions = await db
        .collection("sessions")
        .where("project_id", "==", project_id)
        .where("status", "==", "active")
        .get();

      const batch = db.batch();
      activeSessions.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "abandoned",
          ended_at: now,
          progress_summary: doc.data().progress_summary ?? "Session abandoned (new session started)",
        });
      });

      // 2. Create new session
      const sessionRef = db.collection("sessions").doc();
      batch.set(sessionRef, {
        project_id,
        session_type: session_type ?? "solo",
        status: "active",
        started_at: now,
        ended_at: null,
        progress_summary: null,
        handoff_notes: null,
        context_artifacts: {},
        metadata: metadata ?? {},
      });

      await batch.commit();

      // 3. Log activity
      await db.collection("activity_log").add({
        task_id: null,
        session_id: sessionRef.id,
        agent_name: "system",
        action: "session_started",
        details: `New ${session_type ?? "solo"} session started${activeSessions.size > 0 ? ` (${activeSessions.size} stale session(s) abandoned)` : ""}`,
        metadata: {},
        created_at: now,
      });

      // 4. Build handoff context
      const handoff = await buildHandoffContext(db, project_id);

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                session_id: sessionRef.id,
                abandoned_sessions: activeSessions.size,
                handoff: handoff,
                message: "Session started successfully",
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );

  server.tool(
    "board_end_session",
    "End the current session with a progress summary and handoff notes for the next session",
    {
      session_id: z.string().describe("Session ID to end"),
      progress_summary: z
        .string()
        .describe("Summary of what was accomplished"),
      handoff_notes: z
        .string()
        .optional()
        .describe("Notes for the next session"),
      context_artifacts: z
        .object({
          files_modified: z.array(z.string()).optional(),
          decisions_made: z.array(z.string()).optional(),
          blockers: z.array(z.string()).optional(),
          next_steps: z.array(z.string()).optional(),
        })
        .passthrough()
        .optional()
        .describe("Structured context artifacts"),
    },
    async ({ session_id, progress_summary, handoff_notes, context_artifacts }) => {
      const sessionRef = db.collection("sessions").doc(session_id);
      const sessionSnap = await sessionRef.get();

      if (!sessionSnap.exists) {
        return {
          content: [
            {
              type: "text" as const,
              text: JSON.stringify({ error: `Session ${session_id} not found` }),
            },
          ],
        };
      }

      const now = Timestamp.now();
      await sessionRef.update({
        status: "completed",
        ended_at: now,
        progress_summary,
        handoff_notes: handoff_notes ?? null,
        context_artifacts: context_artifacts ?? {},
      });

      await db.collection("activity_log").add({
        task_id: null,
        session_id,
        agent_name: "system",
        action: "session_ended",
        details: progress_summary,
        metadata: {},
        created_at: now,
      });

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                session_id,
                status: "completed",
                message: "Session ended successfully. Handoff notes saved.",
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );

  server.tool(
    "board_get_handoff",
    "Get the handoff context from previous sessions: last session notes, active tasks, and recent activity. This is THE tool for cross-session continuity.",
    {
      project_id: z.string().describe("Project ID"),
    },
    async ({ project_id }) => {
      const handoff = await buildHandoffContext(db, project_id);

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(handoff, null, 2),
          },
        ],
      };
    }
  );
}

async function buildHandoffContext(db: Firestore, project_id: string) {
  // Get project info
  const projectSnap = await db.collection("projects").doc(project_id).get();
  const projectData = projectSnap.exists ? projectSnap.data() : null;

  // Get last completed or abandoned session
  const lastSessionSnap = await db
    .collection("sessions")
    .where("project_id", "==", project_id)
    .where("status", "in", ["completed", "abandoned"])
    .orderBy("ended_at", "desc")
    .limit(1)
    .get();

  const lastSession = lastSessionSnap.docs[0]
    ? (() => {
        const data = lastSessionSnap.docs[0].data();
        return {
          id: lastSessionSnap.docs[0].id,
          status: data.status,
          progress_summary: data.progress_summary,
          handoff_notes: data.handoff_notes,
          context_artifacts: data.context_artifacts,
          started_at: data.started_at?.toDate?.()?.toISOString() ?? null,
          ended_at: data.ended_at?.toDate?.()?.toISOString() ?? null,
        };
      })()
    : null;

  // Get all non-done tasks sorted by priority
  const tasksSnap = await db
    .collection("tasks")
    .where("project_id", "==", project_id)
    .where("status", "!=", "done")
    .get();

  const priorityOrder: Record<string, number> = {
    critical: 0,
    high: 1,
    medium: 2,
    low: 3,
  };

  const activeTasks = tasksSnap.docs
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        title: data.title,
        status: data.status,
        priority: data.priority,
        assigned_agent: data.assigned_agent,
        riper_mode: data.riper_mode,
        depends_on: data.depends_on,
      };
    })
    .sort(
      (a, b) =>
        (priorityOrder[a.priority] ?? 99) - (priorityOrder[b.priority] ?? 99)
    );

  // Get recent activity
  const activitySnap = await db
    .collection("activity_log")
    .orderBy("created_at", "desc")
    .limit(20)
    .get();

  const recentActivity = activitySnap.docs
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        action: data.action,
        agent_name: data.agent_name,
        details: data.details,
        task_id: data.task_id,
        session_id: data.session_id,
        created_at: data.created_at?.toDate?.()?.toISOString() ?? null,
      };
    });

  return {
    project: projectData
      ? {
          id: project_id,
          name: projectData.name,
          status: projectData.status,
          description: projectData.description,
        }
      : null,
    last_session: lastSession,
    active_tasks: activeTasks,
    active_task_count: activeTasks.length,
    recent_activity: recentActivity,
  };
}
```

#### `src/tools/activity.ts`

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";

export function registerActivityTools(server: McpServer, db: Firestore) {
  server.tool(
    "board_log_activity",
    "Log an activity entry (comment, status change, or arbitrary action)",
    {
      agent_name: z.string().describe("Name of the agent logging this activity"),
      action: z
        .enum([
          "created",
          "updated",
          "claimed",
          "blocked",
          "completed",
          "commented",
          "mode_changed",
          "session_started",
          "session_ended",
        ])
        .describe("Type of action"),
      details: z.string().optional().describe("Human-readable details"),
      task_id: z.string().optional().describe("Related task ID"),
      session_id: z.string().optional().describe("Related session ID"),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Additional metadata"),
    },
    async ({ agent_name, action, details, task_id, session_id, metadata }) => {
      const docRef = await db.collection("activity_log").add({
        task_id: task_id ?? null,
        session_id: session_id ?? null,
        agent_name,
        action,
        details: details ?? null,
        metadata: metadata ?? {},
        created_at: Timestamp.now(),
      });

      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(
              {
                id: docRef.id,
                action,
                message: "Activity logged successfully",
              },
              null,
              2
            ),
          },
        ],
      };
    }
  );
}
```

#### `src/index.ts`

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { getDb } from "./firestore-client.js";
import { registerProjectTools } from "./tools/projects.js";
import { registerTaskTools } from "./tools/tasks.js";
import { registerSessionTools } from "./tools/sessions.js";
import { registerActivityTools } from "./tools/activity.js";

const db = getDb();

const server = new McpServer({
  name: "vibe-board",
  version: "1.0.0",
});

registerProjectTools(server, db);
registerTaskTools(server, db);
registerSessionTools(server, db);
registerActivityTools(server, db);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Step 4: Build and Install

```bash
cd mcp-vibe-board
npm install
npm run build
```

### Step 5: Create Firestore Composite Indexes

These are required for multi-field queries. Without them, `board_create_session` and `board_get_handoff` will fail.

```bash
# Index 1: Sessions — for handoff queries
gcloud firestore indexes composite create \
  --project=YOUR_PROJECT_ID \
  --collection-group=sessions \
  --field-config field-path=project_id,order=ascending \
  --field-config field-path=status,order=ascending \
  --field-config field-path=ended_at,order=descending

# Index 2: Tasks — for active task queries
gcloud firestore indexes composite create \
  --project=YOUR_PROJECT_ID \
  --collection-group=tasks \
  --field-config field-path=project_id,order=ascending \
  --field-config field-path=status,order=ascending
```

Wait 1-5 minutes for indexes to build. Check status at:
https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore/indexes

### Step 6: Configure Claude Code

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "vibe-board": {
      "command": "node",
      "args": ["mcp-vibe-board/dist/index.js"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/ABSOLUTE/PATH/TO/vibe-board-key.json"
      }
    }
  }
}
```

Add tool permissions to `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__vibe-board__board_get_projects",
      "mcp__vibe-board__board_create_project",
      "mcp__vibe-board__board_update_project",
      "mcp__vibe-board__board_get_tasks",
      "mcp__vibe-board__board_get_task",
      "mcp__vibe-board__board_create_task",
      "mcp__vibe-board__board_update_task",
      "mcp__vibe-board__board_bulk_update_tasks",
      "mcp__vibe-board__board_delete_task",
      "mcp__vibe-board__board_create_session",
      "mcp__vibe-board__board_end_session",
      "mcp__vibe-board__board_get_handoff",
      "mcp__vibe-board__board_log_activity",
      "mcp__vibe-board__board_get_activity"
    ]
  },
  "enabledMcpjsonServers": ["vibe-board"]
}
```

### Step 7: Verify

Start a new Claude Code session and ask it to call `board_get_projects`. If it returns an empty array `[]`, you're live.

---

## MCP Tool Reference

All 14 tools. The code for the first 9 is inlined in Step 3 above. The 5 newer tools (**bolded**) are additions from the 2026-04 release — their implementations aren't inlined to keep this doc navigable; check the maintainer's canonical source for the full code.

### Projects

| Tool | Purpose |
|---|---|
| `board_get_projects` | List all projects with task count summaries |
| `board_create_project` | Create a new project |
| **`board_update_project`** | Update name/description/status/metadata. Enforces status transitions (active → completed/archived, etc.). Use `status: "archived"` to archive completed projects. |

### Tasks

| Tool | Purpose |
|---|---|
| `board_get_tasks` | List tasks for a project (filterable by status, priority, assignment) |
| **`board_get_task`** | Fetch a single task by ID with all fields + ISO timestamps |
| `board_create_task` | Create a task (supports parent_task_id for subtasks) |
| `board_update_task` | Update status/priority/assignment/RIPER mode. **Now supports `project_id` to move tasks between projects** — validates target project exists, warns if subtasks are orphaned in source. |
| **`board_bulk_update_tasks`** | Apply same update (project_id/status/priority/agent) to 1-100 tasks atomically. All-or-nothing: preflight fails if any task missing. Direct fit for consolidating small projects. |
| **`board_delete_task`** | Hard-delete a task + its activity_log entries. Default safety: `require_done=true` refuses if status != done. Optional `cascade_subtasks` cleans up children. Irreversible. |

### Sessions

| Tool | Purpose |
|---|---|
| `board_create_session` | Start a session; abandons stale sessions; returns last session's handoff |
| `board_end_session` | End session with progress summary + handoff notes for the next one |
| `board_get_handoff` | Fetch the most recent completed session's handoff mid-session |

### Activity

| Tool | Purpose |
|---|---|
| `board_log_activity` | Write an activity log entry (action types: created, updated, claimed, blocked, completed, commented, mode_changed, session_started, session_ended) |
| **`board_get_activity`** | Query the activity log. Filter by task_id / session_id / agent_name / action. Cursor-paginated, newest-first, default limit 50 / max 200. Returns `{entries, scanned, truncated}` so callers know if filters were too selective to fill the limit. |

---

## Agent Rules (add to CLAUDE.md or equivalent)

Copy this into your project's instructions file so every session follows the protocol:

```markdown
## Vibe Board

Persistent task tracking across sessions via Firebase Firestore MCP tools (`board_*`).
**Mandatory for every substantive session** (any session where you read, write, plan, debug, or deploy code).

### Use Board Tasks, NOT TodoWrite

TodoWrite is ephemeral — it dies when the session ends. Board tasks persist forever and enable cross-session handoff. When you would reach for TodoWrite to track multi-step work, use `board_create_task` instead.

**Nothing exists unless it's on the board.** If an action item, future phase, recommendation, or follow-up is mentioned in conversation or discovered in a document but has no board task, it WILL be forgotten. The board is the single source of truth for "what needs to be done." Conversation text, plan docs, and strategy docs are reference material — the board is the task list. When in doubt, create the task. A redundant board task costs nothing; a forgotten action item costs real work.

### Proactive Triggers

These are condition → action pairs. When the condition is true, take the action immediately.

| Condition | Action |
|-----------|--------|
| Session starts (substantive work) | `board_create_session` before any other work |
| Context compacted / continuation session | `board_create_session` IMMEDIATELY — compaction loses the active session ID |
| Multi-step task (3+ steps) | `board_create_task` for each step |
| Batch of items (fix 5 bugs, review 3 files) | Parent task + subtask per item via `board_create_task` |
| New work discovered during execution | `board_create_task` immediately |
| Significant decision or blocker | `board_log_activity` |
| Start working on a task | `board_update_task` → `in_progress` + set `assigned_agent` to your name |
| Finish a task | `board_update_task` → `done` |
| Review/audit produces findings | Parent task per severity tier + subtask per finding |
| Deploying a new service for the first time | `board_create_task` for: verify deployment, create CI/CD trigger, push to prod |
| Committing + pushing code | `board_log_activity` with commit hash; update related tasks |
| You read a doc/plan with unbuilt phases or pending items | `board_create_task` for each actionable item not already on the board |
| You mention a future action item in conversation | `board_create_task` immediately — conversation text is ephemeral, board tasks are permanent |
| A sub-agent reports a finding or recommendation | `board_create_task` if it requires future work (don't let it exist only in conversation) |
| User says "handoff" or signals session end | Create board tasks for ALL pending next steps, THEN `board_end_session` |
| Session ending OR context getting long | `board_end_session` with handoff notes |

**The test**: If this session died right now, could the next session reconstruct what you were doing from the board alone? If not, you haven't been proactive enough.

**The second test**: If a documented plan has unchecked items, unbuilt phases, or "pending" status markers — and there's no corresponding board task — that's a gap. Every actionable item in every plan doc should have a board task. Plans without board tasks get forgotten.

### Session Lifecycle

**Starting a session** (before any other work — **including after context compaction**):

**Context compaction destroys the active session ID.** If you're continuing from a compacted conversation, you MUST call `board_create_session` before doing anything else. This is the #1 failure mode — compaction preserves your behavioral patterns but loses board state.

1. Call `board_get_projects` to see all active projects
2. **Match work to the correct project** — read project names/descriptions and pick the best fit. Do NOT default to one project for everything. Use a general catch-all project only when no specific project fits.
3. Call `board_create_session` with the matched `project_id`
   - This auto-abandons any stale sessions and returns handoff context
   - Read the handoff carefully — it contains what the last session accomplished and what's next
4. Review active tasks via the handoff response or `board_get_tasks`

**During a session:**
- **PLAN mode**: Create all tasks on the board immediately with status `todo` and `riper_mode: "plan"`. This ensures the plan survives even if the session crashes before execution.
- **REVIEW mode**: Review the *task list on the board*, not just prose. Call `board_get_tasks`, then use `board_log_activity` with `task_id` and `action: "commented"` to attach review comments to specific tasks. ALL review output MUST go through the board — conversation text disappears when sessions end.
- **Review findings → board tasks**: When a review produces findings (FAILs, WARNs, issues, blockers), every finding must become a board task — not just an activity log comment. Create one parent task per severity tier (e.g., "Tier 1: BLOCKING items"), then subtasks for each finding using `parent_task_id`. Map priorities: BLOCKING/FAIL → `critical`, HIGH/WARN → `high`, LOW/INFO → `low`. Include enough context in each subtask's description to fix the issue without re-reading the review.
- **EXECUTE mode**: Move tasks to `in_progress` as work begins, then `done` when complete. `started_at` is set automatically on first move to `in_progress` — work duration = `completed_at - started_at`.
- **COMMIT mode**: Log the commit hash via `board_log_activity` on related tasks. When deploying a new service for the first time, create follow-up tasks: (1) verify deployment in browser, (2) create CI/CD trigger for auto-deploy, (3) push to production. These are predictable follow-ups — don't wait for the user to ask.
- **Tracking your own work**: The board isn't just for project plans — it tracks what YOU are doing right now. When you receive a batch of items (e.g., "fix these 5 issues", "review these 3 files"), create a **parent task** for the batch and **subtasks** for each item using `parent_task_id`. Move each subtask to `in_progress` -> `done` as you work. This creates a recoverable checkpoint: if the session dies mid-batch, the next agent sees exactly which items are done and which remain.
- **Sub-agent board delegation**: When spawning specialist sub-agents that produce detailed findings, instruct them to write results directly to the board. Include the `project_id` and parent task ID in the prompt. The sub-agent returns only a brief summary (e.g., "Found 8 issues, 3 critical. All logged to board under parent task X."). This keeps the main agent's context lean while preserving full detail on the board. Pattern: `"Write all findings to the Vibe Board (project: PROJECT_ID, parent task: TASK_ID). Return only a 1-sentence summary to me."`
- **All modes**: Log notable events via `board_log_activity`. Create additional tasks as new work is discovered — the board should always reflect the current state of work.

**Ending a session** (before the session ends or when the user signals they're done):
1. **Scan your tasks**: Check for any tasks still `in_progress` that you own — mark them `done` if complete, or add a `board_log_activity` comment explaining what remains.
2. **Create tasks for all next steps**: Every pending follow-up must exist as a board task BEFORE ending. Do not list future work only in handoff prose — if it's worth mentioning as a next step, it's worth tracking as a task.
3. Call `board_end_session` with progress_summary, handoff_notes (referencing task IDs, not just prose), and context_artifacts.

**This is the most critical step.** A session without handoff notes is a session whose context is lost forever.

**Proactive ending:** If you sense the conversation is getting long or you are approaching context limits, call `board_end_session` immediately — even a partial handoff is infinitely better than an abandoned session with no notes.

### Task Status Flow

backlog -> todo -> in_progress -> review -> done
                       |
                    blocked

### Priority Levels

- **critical**: Blocking other work, needs immediate attention
- **high**: Important, should be next
- **medium**: Standard priority (default)
- **low**: Nice to have, do when time allows
```

---

## RIPER Mode Integration (Optional)

RIPER is a structured workflow mode system. If you use it, tasks track which mode they're in:

| Mode | Purpose | Board Action |
|------|---------|-------------|
| **RESEARCH** | Observe and understand | Read tasks, log findings |
| **INNOVATE** | Brainstorm options | Log ideas as activity comments |
| **PLAN** | Create implementation spec | Create all tasks with `riper_mode: "plan"` |
| **EXECUTE** | Implement the plan | Move tasks through `in_progress` -> `done` |
| **REVIEW** | Validate output | Review task list, attach comments via `board_log_activity`, convert findings into subtasks by severity tier |
| **COMMIT** | Finalize and persist | Log commit hash via `board_log_activity`, create deployment follow-up tasks, end session with handoff notes |

The `riper_mode` field on tasks is optional. If you don't use RIPER, just ignore it — everything else works the same.

---

## Agent Organization (Optional)

If you use multiple specialist sub-agents, the Vibe Board enables a delegated hierarchy that prevents context bloat. Without this, every sub-agent dumps its full output back to the main agent — overwhelming it with raw data instead of letting it think strategically.

### The Problem: Star Topology

```
Main Agent (overloaded)
  /   |   |   |   \
sub  sub  sub  sub  sub   ← all output flows back to center
```

Every specialist returns full findings. The main agent spends 80% of its capacity processing raw output instead of coordinating.

### The Solution: Delegated Hierarchy

```
User (direction, decisions, approvals)
  |
Main Agent (routing, user communication)
  |
├── Project Coordinator (team lead - task lifecycle, delegation)
│     ├── Processor (raw output → board tasks → lean summaries)
│     └── Specialists (domain experts)
│
└── Direct specialists (simple single-domain tasks)
```

### Processor Agent

Create an agent whose only job is consolidation. When specialists produce detailed findings:

1. Route raw output to the processor
2. Processor categorizes by severity, creates board tasks (parent per tier, subtask per finding)
3. Processor returns a 1-sentence summary to the caller
4. Full details live on the board, not in anyone's context window

**Prompt pattern for the processor:**
```
You are the processor agent. Your job is to take raw specialist output and:
1. Create parent tasks on the Vibe Board per severity tier
2. Create subtasks for each individual finding with enough context to fix standalone
3. Return ONLY a brief summary (e.g., "Processed 12 findings: 3 critical, 5 high, 4 low. All on board.")
Never return the full raw findings — that defeats your purpose.
```

### Delegation Patterns

**Simple task (one specialist):**
```
Main Agent → Specialist → Result back to main agent
```

**Complex task (multiple specialists):**
```
Main Agent → Project Coordinator → creates board tasks
  → Specialists (parallel where possible)
  → Processor (findings → board tasks + lean summary)
  → Coordinator returns clean summary to main agent
```

**Review / Audit (bulk findings):**
```
Main Agent → Specialist(s) in parallel
  → Processor (findings → board subtasks by severity)
  → Lean summary back to main agent
```

This is entirely optional. If you only use one agent, the session lifecycle and board tools work fine on their own. The organizational layer matters when you're coordinating 3+ specialists and their output starts overwhelming the main agent's context.

---

## Tool Reference

| Tool | Purpose |
|------|---------|
| `board_get_projects` | List projects with task count summaries |
| `board_create_project` | Create a new project |
| `board_update_project` | Update project status (active / completed / archived), name, description, metadata |
| `board_get_tasks` | Get tasks (filterable by status, priority, assignment; includes `started_at`/`completed_at` for duration) |
| `board_create_task` | Create a task with title, description, priority, dependencies |
| `board_update_task` | Update status, priority, assignment, description, dependencies |
| `board_create_session` | Start session (auto-abandons stale ones, returns handoff) |
| `board_end_session` | End session with summary + handoff notes |
| `board_get_handoff` | Get previous session's handoff context |
| `board_log_activity` | Log decisions, comments, blockers, or arbitrary events |

---

## Viewing Your Board

Go to https://console.firebase.google.com/project/YOUR_PROJECT_ID/firestore to browse all collections, tasks, sessions, and activity logs in the Firebase Console UI.

---

## Cost

Firebase Firestore free tier: 50,000 reads, 20,000 writes, 1GB storage per day. This easily handles hundreds of agent sessions before you'd ever see a bill.

---

## License

MIT. Use it however you want.

# Collaboration Phase 7 — Task Assignment + Member Progress

## Model

Responsibility is a separate concept from authorization:

| Field | Meaning | Authorizes writes? |
|-------|---------|--------------------|
| `editorUIDs: [String]` (Phase 6) | who may modify the task | Yes |
| `assigneeUID: String?` (Phase 7) | who is responsible for completing it | **No** |

One assignee per task, on **root tasks only**. Subtasks inherit the root's responsibility for
presentation (`TaskItem.effectiveAssigneeUID`) and never carry their own `assigneeUID`.

## Schema

- SwiftData: `TodoshiSchemaV7` adds `TaskItem.assigneeUID: String?`. Additive optional, no
  migration stage, no destructive reset. Existing tasks (personal and shared) open with `nil`.
- Firestore task documents: `assigneeUID: string | null`. Subtask documents always write `null`.
- `FirestoreTaskDTO.assigneeUID` carries the value both ways and coerces subtasks to `nil`.

## Authority

Only the project **Owner** may change `assigneeUID`. Full and restricted members cannot assign,
self-assign, unassign themselves, or mutate assignment during an ordinary task write.

An assignee must be a current member of the same project (`projects/{id}/members/{uid}` must
exist). `memberIds` alone is not sufficient.

## Assignment ↔ ACL

`TaskAssignmentPolicy.plan(assignTo:currentEditorUIDs:)` produces one atomic root-task update:

| Assignee | `editorUIDs` effect |
|----------|---------------------|
| Owner | none |
| Full member | none |
| Restricted member already in `editorUIDs` | none |
| Restricted member absent | UID added in the same write |
| Unassign (`nil`) | **none** — grants are never revoked |
| Reassign B → C | C added if restricted; B retained |

Todoshi does not track whether a grant came from assignment or from manual Phase 6 permission
management, so unassignment is deliberately not a revocation. Owners revoke separately.

Rules never treat `assigneeUID == auth.uid` as authorization. Edit rights still come only from
owner, full membership, or root `editorUIDs`.

## Integrity guards

- `TaskAssignmentIntegrityPolicy.canRemoveEditor` blocks removing the current **restricted**
  assignee from `editorUIDs`; both owner ACL surfaces show
  `task.assignment.aclGuard` instead of silently stranding them.
- `rootTasksNeedingRepair(forDemotedUID:rootTasks:)` runs before `full → restricted`, adding the
  member to `editorUIDs` on every live root task assigned to them. Idempotent.
- Recurring successors inherit both `assigneeUID` and `editorUIDs` from the previous occurrence.

## Firestore Rules

- `isValidAssigneeUIDField(projectId)`: `null`, or a non-empty string ≤128 chars that is a current
  member **and** whose document has `parentTaskId == null`.
- `preservesAssigneeUID()` on member updates; `preservesAssigneeUIDOnCreate()` on member creates.
- Owner writes bypass both preservation checks but still pass field validation.

## UX

- **Task Detail** (shared root tasks): owner gets an assignee picker over the membership snapshot
  (`displayName` only, never `/users/{uid}`, never raw UIDs); members see it read-only.
  A footer notes that a restricted member also receives edit access.
- **Task cards**: shared root cards show `person.fill` + assignee name when assigned. Personal
  projects show nothing.
- **Project Detail**: segmented `All Tasks` / `My Tasks` for shared projects.
  `My Tasks` = `root.assigneeUID == current Firebase UID`, reset on account change.
- **Member Detail**: assigned-task counts by status (Total / Backlog / Todo / In Progress /
  Review / Done) plus the member's assigned root tasks, from mirrored SwiftData.

## Progress source

Derived from the task's live `status`. No separate progress field, no manual percentage, no new
listener — the existing shared task listener drives Owner-side updates in realtime.

## Queries and indexes

No new Firestore query or listener was added; Project Detail and Member Detail filter locally
over mirrored SwiftData. **No new composite index is required.** `firestore.indexes.json`
is unchanged.

## Out of scope

Multiple assignees, subtask-specific assignment, assignee notifications, FCM, activity feed,
@mentions, workload balancing, time tracking, member removal, custom roles, Firebase Storage.

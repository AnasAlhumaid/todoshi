# Collaboration Phase 6 — Member Access Levels + Per-Task Edit Permissions

## Model

Roles remain:

- `owner`
- `member`

Separate membership field:

- `accessLevel`: `full` | `restricted`

Task ACL field (root tasks):

- `editorUIDs: [String]`

Assignment (`assigneeUIDs`) is **not** implemented in Phase 6.

## Migration / defaults

| Situation | Behavior |
|-----------|----------|
| Existing membership missing `accessLevel` | Treated as **`full`** (legacy compatibility) |
| New invite acceptance | Persists **`restricted`** |
| Owner bootstrap / CF create | Persists **`full`** |
| Owner membership stored value | Prefer `accessLevel = full`; owner always has full task access regardless |

## Authorization summary

| Actor | Task content | Create root | Create subtask | Manage `accessLevel` / `editorUIDs` | Comments |
|-------|--------------|-------------|----------------|--------------------------------------|----------|
| Owner | Always | Yes | Yes | Yes | Yes |
| Member + full | All tasks | Yes | Yes | No | Yes |
| Member + restricted | Only if UID ∈ root `editorUIDs` | No | Only under allowed root | No | Yes (independent of edit ACL) |

Subtasks inherit ACL from their **root** parent (two-level hierarchy only).

## Firestore

Membership: `projects/{id}/members/{uid}` includes `accessLevel`.

Only the project owner may update another member’s `accessLevel` (dedicated update rule).

Only the owner may change task `editorUIDs`. Members must preserve `editorUIDs` on ordinary task writes.

## App UX

- **Members → Member Detail**: owner sets Full Access vs Selected Tasks Only; restricted shows root-task toggles.
- **Task Detail**: owner sees task permissions section; restricted members without ACL see read-only task content; comments remain collaborative.
- Realtime membership + task listeners apply grant/revoke without relaunch.
- Permission-denied cloud writes reconcile from Firestore and surface `task.permissions.revoked`.

## Out of scope

Custom roles, assignment UX, member removal, FCM, activity log, per-field / per-checklist-item ACL.

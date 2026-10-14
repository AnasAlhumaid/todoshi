# Phase 5 — Role Permissions + Realtime Task Comments

## Roles

| Action | Owner | Member |
|--------|-------|--------|
| Read collaboration data | ✓ | ✓ |
| Edit project metadata | ✓ | ✗ |
| Invite members | ✓ | ✗ |
| Create/edit/delete tasks & subtasks | ✓ | ✓ |
| Checklist / labels / cloud resources | ✓ | ✓ |
| Create comments | ✓ | ✓ |
| Edit own comment body | ✓ | ✓ |
| Soft-delete own comment | ✓ | ✓ |
| Soft-delete any comment (moderate) | ✓ | ✗ |
| Rewrite another author's body | ✗ | ✗ |

Authorization authority remains `projects/{projectId}/members/{uid}` (not `memberIds[]`).

## Comments

Path: `projects/{projectId}/tasks/{taskId}/comments/{commentId}`

Fields: `id`, `authorUID`, `authorDisplayName`, `body`, `createdAt`, `updatedAt`, `deletedAt`

- UUID document IDs
- Body: trimmed, 1…4000 characters, plain text
- Soft delete only; UI hides deleted comments
- No create when parent task `deletedAt != null`
- Firestore-only (not in SwiftData / Home / Search / Widgets)
- Per–Task Detail listener only; stopped on disappear

## Offline

Firestore offline persistence may queue writes; no custom comment queue.

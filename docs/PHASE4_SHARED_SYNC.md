# Phase 4 — Full Shared Project Cloud Sync

## Authority

| Mode | Source of truth |
|------|-----------------|
| Personal | SwiftData only |
| Shared | Firestore authoritative; SwiftData = local working copy / widgets |

## Labels policy

Shared-project labels live under `projects/{id}/labels/{labelId}` and reconcile into the existing global `LabelTag` table by UUID. Personal labels remain local. Labels attached to shared tasks are treated as collaboration data.

## Binary attachments

Image/PDF/file resources stay device-local. Cloud sync allows link/text/code/command only. Firebase Storage is deferred — the only major shared-data gap after Phase 4.

## Sign-out / account switch

Shared projects are hidden while signed out and filtered by `collaborationOwnerUID`. They are never converted to Personal. User B must not see User A’s shared cache.

## Soft delete

Cloud entities use `deletedAt` tombstones. Local shared deletes set `deletedAt` and sync; remote tombstones remove local copies.

## Subtasks (contentSchemaVersion 2)

Subtasks live in the flat `projects/{id}/tasks/{taskId}` collection with `parentTaskId` set to the parent task UUID. They use the same mutation hook / listener path as root tasks.

### Migration: v1 → v2

Projects seeded under schema v1 may have `contentSeededAt` set while local subtasks were never uploaded (createSubtask did not emit cloud mutations). Owner devices with `contentSchemaVersion < 2` run an idempotent merge repair: upsert all live local tasks (roots + subtasks), then set `contentSchemaVersion = 2`. Existing remote documents are merge-updated; UUIDs are preserved (no duplicates).

### Parent deletion

Deleting a shared root task soft-deletes the root and all descendants (`deletedAt`) and upserts each tombstone to Firestore — same convergent cascade as local shared delete.

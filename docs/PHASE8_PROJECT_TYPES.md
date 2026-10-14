# Collaboration Phase 8 — Project Types + Shared Checklist Projects

## Model

```swift
enum ProjectType: String {
    case tasks      // full Todoshi board experience
    case checklist  // single vertical list of root TaskItems
}
```

Persisted on `Project.projectTypeRaw`. Legacy missing value → `.tasks`.

A project has exactly one type. Conversion after creation is **not** supported.

## Schema

- SwiftData: `TodoshiSchemaV8` additive optional `projectTypeRaw`.
- Firestore project documents: `projectType: "tasks" | "checklist"` written explicitly on create/share.
- Legacy remote documents without the field resolve as `tasks`.

## Checklist product contract

| Capability | Tasks | Checklist |
|------------|-------|-----------|
| Board / Backlog / Review | Yes | No |
| Statuses | all five | `todo`, `inProgress`, `done` |
| Subtasks | Yes | No (root only) |
| Nested task checklist | Yes | Hidden |
| Resources | Yes | Hidden |
| Assignment / ACL / Comments | Yes | Yes (when shared) |

Checklist rows **are** root `TaskItem`s — not a second entity.

## Status interaction

Primary control cycles `todo → inProgress → done`. Completed items do **not** auto-cycle back; reopen via the status menu.

## Sync

Reuses `SharedProjectSyncService`. No separate checklist sync service.

`projectType` is written on bootstrap/share and preserved on metadata updates (immutable).

## Rules

- Bootstrap create requires a valid `projectType`.
- Project updates must `preservesProjectType()`.
- Checklist tasks: `parentTaskId == null` and status ∈ `{todo, inProgress, done}`.
- Tasks projects retain full Phase 2–7 behavior.

## Indexes

No new Firestore queries → no new indexes.

## Out of scope

Member removal, activity history, FCM, multiple assignees, custom roles, checklist templates, Storage, App Store release.

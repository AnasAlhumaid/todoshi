# Collaboration Phase 8.1 — Checklist Completion Attribution

## Schema

SwiftData `TodoshiSchemaV9` adds optional:

- `TaskItem.completedByUID`
- `TaskItem.completedByDisplayName`

Legacy completed items remain `nil` (no guessing).

## Semantics

When a **Shared Checklist** item transitions into `done`:

- `completedByUID` = authenticated Firebase UID who performed the action
- `completedByDisplayName` = membership `displayName` snapshot
- `completedAt` = existing completion timestamp behavior

Independent of `assigneeUID` (Phase 7 responsibility).

Reopen (`done → todo|inProgress`) clears attribution (+ `completedAt` per existing rules).
Done→Done edits preserve attribution.
Re-complete after reopen replaces the actor.

## Rules

Checklist projects:

- Entering Done / create-as-Done requires `completedByUID == request.auth.uid`
- Display name is bounded (`≤ 200`); app populates from membership snapshot
- Leaving Done requires both attribution fields `null`
- Done→Done must preserve attribution (no spoof rewrite)

Tasks projects: attribution optional (no regression); spoofed UIDs still rejected when fields are present.

## UI

Checklist list/detail only — secondary “Completed by …” / “أنجزها …” line.
Personal Checklist does not invent account attribution.

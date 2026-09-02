# Persistence

## Stores

| Kind | Use |
|------|-----|
| In-memory | Unit tests and SwiftUI previews |
| File URL | Widget/read-path tests, isolated probes |
| App Group (`group.com.anashamad.Nexus`) | Production app + widgets |
| Application Support (default ModelConfiguration) | Fallback when App Group is unavailable (e.g. some simulators) |

## Schema versions

| Version | Contents |
|---------|----------|
| **V1** | Project, TaskItem, LabelTag, ChecklistItem |
| **V2** | Optional `TaskItem.reminderDate` |
| **V3** | TaskResource attachments + relationship on TaskItem |
| **V4** | Optional recurrence metadata on `TaskItem` (rule, interval, series ID, generation, next/previous occurrence IDs) |

`NexusSchemaMigrationPlan` currently registers **V4 only** as the active versioned schema. Listing identical `@Model` types across multiple versions triggers SwiftData’s “Duplicate version checksums” crash. New optional attributes open existing stores non-destructively when the active sole version advances and models remain compatible. Release never runs destructive reset.

Widgets and the main app share the same `NexusSchema` / migration plan. The widget path **never** deletes store files.

### V4 recurrence fields (optional; default = no recurrence)

| Field | Role |
|-------|------|
| `recurrenceRuleRaw` | Kind raw value (`daily`, `weekdays`, …) or nil |
| `recurrenceInterval` | Custom interval (1…365); non-custom kinds use 1 |
| `recurrenceSeriesID` | Stable series identity (UUID), not title/date |
| `recurrenceGeneration` | Occurrence sequence (0 for first open occurrence in series) |
| `nextOccurrenceID` | Successor created on complete (idempotency) |
| `previousOccurrenceID` | Predecessor when generated |

Invalid / unknown raw values parse as **no active recurrence**.

## App Group schema failures

`ModelContainerFactory` opens the App Group SQLite store with the current schema (V4).

If the store cannot be opened (e.g. pre-release model drift):

| Build | Behavior |
|-------|----------|
| **DEBUG** | `StoreResetPolicy.allowsDestructiveAppGroupReset == true`. The factory may delete the incompatible store files and create a fresh empty store. Developer/data loss is accepted for local iteration. |
| **RELEASE** | Destructive reset is **disabled**. Failure is shown as a non-destructive store unavailable UI. User data is **not** deleted silently. |

## Local notifications

- Task reminders use identifiers `nexus.task.<UUID>`.
- Optional daily summary uses `nexus.dailySummary` with **count-only** content.
- Scheduling lives in the app target (`LocalNotificationScheduler`); pure policy lives in `NexusCore`.
- Recurring tasks use one-time reminders on each occurrence (no repeating UNCalendar triggers).

## Labels / checklists / subtasks / resources

Cascade rules unchanged from prior phases. Subtasks: depth 2 (root + children). Root-only filters apply on Dashboard, Kanban columns, search task hits, widgets, and calendar rows.

### Resource storage safety

- Relative paths only; traversal rejected  
- Max import **25 MB**  
- Orphan cleanup: once per app launch, utility priority, age **≥ 24 hours**, non-fatal, does not block launch  
- Code/command UI uses LTR for monospaced content  

### Recurrence copy policies

- Checklist: copy titles, reset incomplete, new IDs  
- Labels: reuse `LabelTag` models  
- Text/link/code/command resources: new records  
- Imported files: **not** copied  

## Calendar (Phase 12)

Read-only schedule over `dueDate`. No additional persisted models. Archived projects and subtasks excluded from main calendar rows.

## Release log policy

Release builds must not log task titles, notes, descriptions, labels, resource paths, code, commands, filenames, or notification bodies. Diagnostics use coarse categories in Debug only (`NexusDiagnostics`).

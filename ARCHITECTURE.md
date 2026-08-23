# Architecture

Nexus is a local-first SwiftUI + SwiftData iOS app with an embedded WidgetKit extension. Both share `NexusCore` for models, policies, and read helpers.

## Source of truth

**SwiftData is the single source of truth** for projects, tasks, labels, checklists, resources, and recurrence metadata.

- Views and widgets never invent parallel stores.
- Widgets open the App Group store **read-focused** and never destructively reset it.
- Managed file bytes live outside SwiftData under Application Support `Nexus/Resources/…`.

## Layers

| Layer | Location | Responsibility |
|-------|----------|----------------|
| UI | `Nexus/Features/*` | SwiftUI screens, sheets, accessibility |
| ViewModels | App target | Thin orchestration, drafts, permission explainer |
| Repositories | `NexusCore` | Writes, validation, fractional positions, cascade rules |
| Policies | `NexusCore` | Pure date/status/recurrence/search/calendar/widget classification |
| Models | `NexusCore` | `@Model` types shared by app + widgets |
| Notifications | App target | UserNotifications scheduling & reconcile |
| Widgets | `NexusWidgets` + `NexusCore` loaders | Timeline entries, deep links |

## Write path

1. UI / ViewModel collects draft values  
2. Repository validates and mutates models  
3. Single logical `context.save()` where expected  
4. `NexusDataChangeCenter.post(event)`  
5. App reloads widgets / may reconcile notifications based on `WidgetReloadClassifier`

Views must not call `ModelContext.save()` for product mutations outside repositories.

## Schema strategy

Single active versioned schema: **V4** (`NexusSchemaV4`).

- Multi-version listings of identical `@Model` graphs are avoided (duplicate checksum crashes).
- Optional new attributes open existing stores non-destructively when models remain compatible.
- **Release:** `StoreResetPolicy.allowsDestructiveAppGroupReset == false`  
- **Debug:** may wipe incompatible App Group store after open failure  

See `Packages/NexusCore/Docs/Persistence.md`.

## App Group

| Target | Bundle ID | Group |
|--------|-----------|--------|
| Nexus | `com.anashamad.Nexus` | `group.com.anashamad.Nexus` |
| NexusWidgets | `com.anashamad.Nexus.widgets` | same |

Store URL: app group container `/Library/Application Support/Nexus/Nexus.store`.

## Notifications

- Identifiers: `nexus.task.<UUID>`, `nexus.dailySummary`
- Policy/planning in `NexusCore`; scheduling in app
- No remote push

## Resources

- Relative paths only; path traversal rejected  
- Max import size 25 MB  
- Orphan cleanup: once per launch, age ≥ 24h, non-fatal  
- Code/command UI uses LTR layout inside otherwise RTL UIs  

## Recurrence

Complete-to-generate-next; calendar math in `TaskRecurrencePolicy`; idempotent via `nextOccurrenceID`.

## Calendar

Presentation layer over existing due dates (`CalendarScheduleBuilder`). No EventKit.

## Deep links

Shared parser: `NexusDeepLink`

```text
nexus://dashboard
nexus://projects
nexus://quick-add
nexus://task/{UUID}
nexus://project/{UUID}
```

## Navigation

`AppRouter` + per-tab `NavigationStack` paths. Tabs: Dashboard, Projects, Calendar, Search, Settings.

## Product boundaries (MVP)

Local only. No accounts, smart lists, external calendars, multi-level subtasks beyond root→child, RRULE, or collaboration.

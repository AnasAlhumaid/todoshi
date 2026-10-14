# Architecture

Todoshi is a local-first SwiftUI + SwiftData iOS app with an embedded WidgetKit extension. Both share `TodoshiCore` for models, policies, and read helpers.

## Source of truth

**SwiftData is the single source of truth** for projects, tasks, labels, checklists, resources, and recurrence metadata.

- Views and widgets never invent parallel stores.
- Widgets open the App Group store **read-focused** and never destructively reset it.
- Managed file bytes live outside SwiftData under Application Support `Todoshi/Resources/…`.

## Layers

| Layer | Location | Responsibility |
|-------|----------|----------------|
| UI | `Todoshi/Features/*` | SwiftUI screens, sheets, accessibility |
| ViewModels | App target | Thin orchestration, drafts, permission explainer |
| Repositories | `TodoshiCore` | Writes, validation, fractional positions, cascade rules |
| Policies | `TodoshiCore` | Pure date/status/recurrence/search/calendar/widget classification |
| Models | `TodoshiCore` | `@Model` types shared by app + widgets |
| Notifications | App target | UserNotifications scheduling & reconcile |
| Widgets | `TodoshiWidgets` + `TodoshiCore` loaders | Timeline entries, deep links |

## Write path

1. UI / ViewModel collects draft values  
2. Repository validates and mutates models  
3. Single logical `context.save()` where expected  
4. `TodoshiDataChangeCenter.post(event)`  
5. App reloads widgets / may reconcile notifications based on `WidgetReloadClassifier`

Views must not call `ModelContext.save()` for product mutations outside repositories.

## Schema strategy

Single active versioned schema: **V5** (`TodoshiSchemaV5`).

- Multi-version listings of identical `@Model` graphs are avoided (duplicate checksum crashes).
- Optional new attributes open existing stores non-destructively when models remain compatible.
- **Release:** `StoreResetPolicy.allowsDestructiveAppGroupReset == false`  
- **Debug:** may wipe incompatible App Group store after open failure  

See `Packages/TodoshiCore/Docs/Persistence.md`.

## App Group

| Target | Bundle ID | Group |
|--------|-----------|--------|
| Todoshi | `com.anashamad.Todoshi` | `group.com.anashamad.Todoshi` |
| TodoshiWidgets | `com.anashamad.Todoshi.widgets` | same |

Store file: `Todoshi.store` in the App Group container (migrated once from legacy `Nexus.store` / `group.com.anashamad.Nexus`).

## Notifications

- Identifiers: `todoshi.task.<UUID>`, `todoshi.dailySummary`
- Legacy cancellation compatibility: `nexus.task.*`, `nexus.dailySummary`
- Policy/planning in `TodoshiCore`; scheduling in app
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

Shared parser: `TodoshiDeepLink`

Canonical scheme:

```text
todoshi://dashboard
todoshi://projects
todoshi://quick-add
todoshi://task/{UUID}
todoshi://project/{UUID}
todoshi://widget/project-picker?baseProjectID={UUID}
```

Legacy compatibility (parser only; new URLs must use `todoshi://`):

```text
nexus://…
```

## Navigation

`AppRouter` + per-tab `NavigationStack` paths. Tabs: Home, Calendar, Search, Settings.

## Product boundaries (MVP)

Local only. No accounts, smart lists, external calendars, multi-level subtasks beyond root→child, RRULE, or collaboration.

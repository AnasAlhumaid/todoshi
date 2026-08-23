# Nexus

Local-first iOS task manager for projects, Kanban, dashboard focus, search, calendar, labels, checklists, subtasks, attachments, recurrence, Home Screen / Lock Screen widgets, and local notifications.

**Version:** 0.1.0 (build 1) — internal release candidate (MVP)

## Features (frozen MVP)

| Area | Notes |
|------|--------|
| Projects | Active / archived, cascade delete with resource cleanup |
| Tasks | Status, priority, due, reminder, notes |
| Kanban | Fractional ordering per column |
| Dashboard | Due today, overdue, productivity summary, Quick Add |
| Search | Root tasks + projects, relevance ranking, recent queries |
| Calendar | Day / Week / Month, upcoming, unscheduled |
| Labels | Many-to-many, global catalog |
| Checklists | Per-task, cascade |
| Subtasks | One level under root only |
| Resources | Links, text/code/commands, imported files (managed storage) |
| Recurrence | Complete-to-generate-next (limited patterns) |
| Widgets | Today, High Priority, Project, Lock Screen |
| Notifications | Task reminders + optional daily summary |

## Requirements

- Xcode 16+ recommended (iOS 17 deployment target)
- iPhone (iOS 17.0+)
- Apple Developer Team for physical device App Groups / notifications
- App Group: `group.com.anashamad.Nexus`

## Project layout

```text
Nexus/                    # App target (SwiftUI features)
NexusWidgets/             # WidgetKit extension
Packages/NexusCore/       # Shared domain, SwiftData models, pure policies
scripts/generate_xcodeproj.py
```

## Build

```bash
# Regenerate Xcode project after adding app source files
python3 scripts/generate_xcodeproj.py

# Unit tests (NexusCore)
cd Packages/NexusCore && swift test

# Simulator build
xcodebuild -scheme Nexus \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Open `Nexus.xcodeproj` in Xcode for signing, schemes, and archive.

## Signing & App Group

1. Select **Nexus** target → Signing & Capabilities  
2. Enable **Automatically manage signing** and choose your **Team**  
3. Confirm capability **App Groups** includes `group.com.anashamad.Nexus`  
4. Select **NexusWidgets** target → same Team and same App Group  
5. Bundle IDs:  
   - App: `com.anashamad.Nexus`  
   - Widgets: `com.anashamad.Nexus.widgets`  
6. Install on a **signed physical device** (simulator App Group behavior can differ)  

Deep link scheme: `nexus://` (see ARCHITECTURE.md).

## Tests

```bash
cd Packages/NexusCore && swift test
```

Tests use fixed calendars/timezones and in-memory SwiftData. Widget/store App Group tests open the group only when available.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)
- [QA_MATRIX.md](QA_MATRIX.md)
- [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)
- [Packages/NexusCore/Docs/Persistence.md](Packages/NexusCore/Docs/Persistence.md)

## Privacy (summary)

Data is local. No accounts, no CloudKit, no analytics. Imported files live under Application Support. Widgets read the App Group store. Notifications are local. Details in Settings → Privacy & Data.

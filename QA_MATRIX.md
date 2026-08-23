# QA Matrix — Nexus 0.1.0

## Environments

| ID | Device / Simulator | OS | Build | Notes |
|----|--------------------|-----|-------|--------|
| S1 | iPhone 16 Simulator | iOS 18.x (Xcode host) | Debug 0.1.0 (1) | Automated unit tests + compile |
| S2 | iPhone SE (3rd gen) Simulator | iOS 17.x or 18.x | Debug | Small layout smoke (manual) |
| D1 | Physical iPhone (owner) | iOS 17+ | Signed Debug/Release | **Required** for App Group + push-like local notify |

Fill D1 after install:

| Field | Value |
|-------|--------|
| Device model | _pending physical QA_ |
| iOS version | _pending_ |
| Install method | Xcode / ad-hoc / TestFlight |
| Tester | |

## Automated (always)

| Check | Result | Notes |
|-------|--------|--------|
| NexusCore unit tests (129+) | Pass (this phase) | Fixed calendar/timezone |
| Nexus scheme build Debug-sim | Pass | Embeds widgets |
| Store reset policy tests | Pass | DEBUG vs RELEASE compile gates |

## Feature regression (manual)

### Core tasks

| Case | S1 | D1 |
|------|----|----|
| Create project + task | ☐ | ☐ |
| Kanban move columns | ☐ | ☐ |
| Quick Add | ☐ | ☐ |
| Search open task | ☐ | ☐ |
| Complete ordinary task | ☐ | ☐ |
| Complete recurring → one successor | ☐ | ☐ |
| Labels / checklist / subtask / resource | ☐ | ☐ |
| Delete occurrence vs project | ☐ | ☐ |

### Calendar

| Case | S1 | D1 |
|------|----|----|
| Day / Week / Month | ☐ | ☐ |
| First weekday locale | ☐ | ☐ |
| Today overdue section | ☐ | ☐ |
| Upcoming / Unscheduled | ☐ | ☐ |
| Create for date / reschedule | ☐ | ☐ |
| Show completed | ☐ | ☐ |

### Widgets (device preferred)

| Case | D1 |
|------|-----|
| Today / HP / Project add to HS | ☐ |
| Empty and busy states | ☐ |
| Arabic long titles | ☐ |
| Deep link task/project/quick add | ☐ |
| Archived project widget | ☐ |
| Force quit + refresh | ☐ |

### Notifications (device)

| Case | D1 |
|------|-----|
| Auth paths | ☐ |
| Reminder 5 min out | ☐ |
| Complete before fire | ☐ |
| Recurring rem offset | ☐ |
| Daily summary | ☐ |
| Cold launch deep link | ☐ |

### Accessibility / RTL

| Case | S1 | D1 |
|------|----|----|
| Dark Mode tabs | ☐ | ☐ |
| Arabic RTL calendar + form | ☐ | ☐ |
| Code/command LTR blocks | ☐ | ☐ |
| Dynamic Type XXL rows | ☐ | ☐ |
| VoiceOver complete / calendar | ☐ | ☐ |

### Persistence

| Case | D1 |
|------|-----|
| Relaunch keeps data | ☐ |
| Restart keeps App Group | ☐ |
| Import file survives relaunch | ☐ |

## UI smoke sequence (manual, ~10 min)

1. Launch → Create Project → Create Task  
2. Project Kanban → move status  
3. Dashboard Quick Add  
4. Search → open task  
5. Calendar → create dated task  
6. Detail → checklist toggle  
7. Detail → subtask  
8. Settings → Labels + Privacy  

## Known automation gaps

- No XCUITest target (by choice for Phase 13)  
- Physical App Group / notification delivery cannot be fully proven in CI here  
- WidgetKit timeline refresh is system best-effort  

## Phase 13 completion note

Simulator compile and full unit suite are green. Device matrix cells marked ☐ await signed-device exercise; document results in this file when finished.

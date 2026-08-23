# Known Limitations — Nexus 0.1.0

Intentional product boundaries for the local-first MVP. These are not accidental bugs.

## Platform & accounts

- Local only; no CloudKit, iCloud Drive sync, or multi-device merge  
- No accounts, collaboration, or sharing  
- No analytics, crash SDKs, or advertising identifiers  

## Scheduling

- No EventKit / Apple Calendar / Google Calendar integration  
- No meeting time blocks, multi-day events, or task duration  
- Calendar shows **persisted** occurrences only; does not pre-generate future recurrences  

## Recurrence

- Limited patterns (daily, weekdays, weekly, monthly, yearly, custom N days/weeks/months)  
- No RRULE, multiple weekdays, “nth weekday,” or series bulk edit/delete  
- Imported file resources are not copied to the next occurrence  
- Subtasks never recur  

## Hierarchy

- Maximum depth: root + one subtask level  
- Subtasks excluded from root-only surfaces (Dashboard lists, Kanban, widgets, main calendar rows, global search)  

## Search

- Root tasks and projects only  
- No standalone checklist / subtask / resource body search  

## Widgets

- Best-effort reload; OS may delay timeline refresh  
- No direct completion toggles on widgets  
- Configuration required for Project widget  

## Notifications

- Local scheduling only; delivery is system-managed  
- No notification action buttons (complete from banner)  
- Reminder times are absolute; changing due date does not auto-shift existing reminder  

## Files

- Managed under Application Support; device-local  
- Max import size 25 MB  
- Share/preview uses sandboxed copies; no remote vault  

## Encryption claims

- Standard iOS app sandbox and file protection as provided by the system  
- No application-layer encrypt-at-rest claim beyond platform defaults  

## Internationalization

- Strings are English-centralized for now (Arabic content in task fields is supported)  
- Code and terminal resource bodies intentionally remain LTR  

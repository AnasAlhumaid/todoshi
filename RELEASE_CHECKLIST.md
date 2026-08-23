# Release Checklist — Nexus 0.1.0 (build 1)

Use for internal candidates and TestFlight. Do not ship unlisted items as “done.”

## Identity

- [ ] Marketing version `0.1.0`
- [ ] Build number `1` (or incremented for successive builds)
- [ ] Display name **Nexus**
- [ ] Bundle ID `com.anashamad.Nexus`
- [ ] Widget bundle ID `com.anashamad.Nexus.widgets`
- [ ] App Group `group.com.anashamad.Nexus` on app + widget
- [ ] URL scheme `nexus`
- [ ] Development Team set for both targets

## Build & tests

- [ ] `cd Packages/NexusCore && swift test` — all green  
- [ ] Debug build (simulator) succeeds  
- [ ] Release build (simulator or device) succeeds  
- [ ] Widget extension embeds in the app product  
- [ ] Archive (Product → Archive) succeeds when Team is configured  
- [ ] Validate archive: app + appex, no test bundles, correct entitlements  

## Release safety

- [ ] `StoreResetPolicy.allowsDestructiveAppGroupReset` is false under `#if !DEBUG`  
- [ ] No destructive data reset UI in Settings Release  
- [ ] User-facing errors do not dump SwiftData technical strings  
- [ ] Release logging omits titles, notes, paths, code, URLs  

## Persistence

- [ ] Fresh install creates store  
- [ ] Relaunch retains data  
- [ ] Force quit + relaunch  
- [ ] App update over existing V4 data (when applicable)  
- [ ] Release open-failure does not wipe store  

## App Group / widgets (physical device)

- [ ] Create data in app → appears in widgets  
- [ ] Edit task → widget refresh (best-effort; force refresh if needed)  
- [ ] Force quit app → widgets still load  
- [ ] Device restart → store still available  
- [ ] Archive/delete configured project → project widget empty/unavailable gracefully  
- [ ] Cold/warm deep links from widgets  

## Notifications (device)

- [ ] Authorization flows  
- [ ] Future task reminder fires  
- [ ] Complete/delete/archive cancels reminder  
- [ ] Recurring successor reminder  
- [ ] Daily summary enable/disable  
- [ ] Cold/warm notification deep links  

## Resources

- [ ] Import under 25 MB, reject empty/oversized  
- [ ] Cancel staged import removes staged file  
- [ ] Delete task cleans managed files  
- [ ] Missing file shows unavailable 

## Accessibility / locale

- [ ] Dark Mode smoke all primary tabs  
- [ ] Arabic/RTL smoke Dashboard, Calendar, Kanban, Form  
- [ ] Dynamic Type largest sizes on task rows + forms  
- [ ] VoiceOver: complete task, calendar select, checklist toggle  

## Signed install

- [ ] Install Release/internal build on physical iPhone  
- [ ] Smoke: project → task → calendar date → complete recurring → widget → reminder  
- [ ] `QA_MATRIX.md` results filled  

## Documentation

- [ ] README, ARCHITECTURE, this checklist, QA_MATRIX, KNOWN_LIMITATIONS current  

## Explicit non-goals this release

- App Store submission (unless separately approved)  
- Cloud sync, accounts, EventKit, analytics SDKs  

## Sign-off

| Role | Name | Date | Result |
|------|------|------|--------|
| Engineering | | | ☐ Pass ☐ Blocked |
| QA | | | ☐ Pass ☐ Blocked |

**Recommendation gate:** only mark *Ready for TestFlight* when App Group + notifications pass on a signed device.

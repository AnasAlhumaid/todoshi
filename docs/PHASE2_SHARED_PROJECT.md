# Shared Project Bootstrap (Phase 2)

## Goal

Convert a personal SwiftData project into a Firebase-backed shared project identity
with owner membership. Task collaboration is **not** enabled until a later phase.

```
Shared project identity/ownership established.
Task collaboration not enabled until Phase 4.
```

## Why Firestore-only (not Cloud Functions)

Cloud Functions for Firebase require the **Blaze** plan. Todoshi deliberately stays on
Spark for Phase 2.

Initial **brand-new project + creator as owner** bootstrap can be expressed securely as a
two-document Firestore atomic `WriteBatch`, validated by Security Rules using
`getAfter()` / `existsAfter()`.

Trusted server infrastructure may still be introduced later for invitations or other
sensitive membership mutations.

## Local metadata (SwiftData V5)

Additive optional fields on `Project`:

| Field | Personal | Shared |
|-------|----------|--------|
| `sharingModeRaw` | `personal` (or nil → personal) | `shared` |
| `remoteProjectID` | nil | `id.uuidString` |
| `sharedAt` | nil | non-nil |

Migration: sole active schema **V5**. Optional properties open existing stores
non-destructively. No store reset.

## Remote documents

```
projects/{localProjectUUID}
projects/{localProjectUUID}/members/{ownerUID}
```

Bootstrap snapshot only — title/description edits remain local until a later sync phase.

## Atomic client bootstrap

```
FirestoreSharedProjectBootstrapService
  → WriteBatch
      set projects/{id}
      set projects/{id}/members/{uid}
  → commit
```

Rules allow this **only** when:

* `ownerId == auth.uid`
* `memberIds == [auth.uid]`
* paired owner membership exists in the same resulting batch
* parent project did **not** already exist before membership create

After bootstrap, client membership writes remain denied.

## Authorization

```
projects/{projectId}/members/{uid}  = authorization authority
projects.memberIds[]                = query/discovery index only
```

## Recovery

If remote bootstrap succeeds but local SwiftData save fails:

* Do **not** delete the remote project.
* Retry Share with the same local UUID.
* Service detects readable owned project + owner membership and repairs local metadata.

## Future invitations

Invitation/member-add security will be designed separately.
If invite acceptance requires trusted backend authority, reassess Blaze or another backend then.
Do not weaken bootstrap rules in anticipation.

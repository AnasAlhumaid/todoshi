# Firebase Collaboration Architecture (Phase 0)

Todoshi is a local-first SwiftData task manager preparing for optional multi-user shared projects via Firebase. Phase 0 establishes boundaries only — no login UI, no sharing, no sync, and no schema migration.

## 1. Why Firebase

Firebase provides a managed collaboration stack aligned with Todoshi’s future needs:

- **Firebase Authentication** for identity (Phase 1: Sign in with Apple)
- **Cloud Firestore** for realtime shared project data and membership queries
- **Firebase Storage** (future) for shared attachments
- **Cloud Functions** (future) for trusted invite acceptance and membership mutations
- **App Check** (future) for production hardening

Firestore snapshot listeners cover realtime updates without a separate realtime framework.

## 2. Personal vs Shared Projects

| Mode | Source of truth | Account required | Network required |
|------|-----------------|------------------|------------------|
| **Personal** | SwiftData | No | No |
| **Shared** (future) | Firestore | Yes | Yes (with offline cache) |

Existing personal projects continue working exactly as today. Nothing is uploaded automatically.

## 3. Firebase Auth Boundary

- Firebase Auth UIDs are **strings** (`CollaborationUser.id`), never UUIDs.
- Auth/session token persistence is owned by Firebase Auth SDK.
- The app does **not** manually persist ID tokens, refresh tokens, or access tokens.
- Phase 0: no login UI. `CollaborationBackend.currentSession()` returns `nil` when unauthenticated.

## 4. Firestore Document Structure (planned)

```
users/{uid}

projects/{projectId}
    ownerId
    title
    description
    color
    position
    memberIds[]
    createdAt
    updatedAt
    deletedAt?

projects/{projectId}/members/{uid}
    role
    joinedAt

projects/{projectId}/tasks/{taskId}
    ...

projects/{projectId}/labels/{labelId}
    ...

invites/{inviteId}
    projectId
    invitedBy
    tokenHash
    role
    expiresAt
    acceptedAt?
    createdAt
```

Document IDs for projects/tasks/labels/invites use `UUID.uuidString`. User documents use Firebase UID strings.

## 5. Membership Model

MVP roles (`ProjectMemberRole`):

- **owner** — manage project, invite/remove members, stop sharing, delete shared project
- **member** — view project, add/edit tasks, change statuses

### Single authorization authority

| Field / path | Purpose |
|--------------|---------|
| `projects/{projectId}/members/{uid}` | **Authorization authority** — access is granted only when this document exists |
| `projects.memberIds[]` | **Query optimization / project discovery only** — must never by itself grant access |

Firestore Security Rules use membership-document existence:

```
exists(/databases/.../projects/{projectId}/members/{request.auth.uid})
```

They do **not** authorize with:

```
request.auth.uid in resource.data.memberIds
```

Query results from `memberIds arrayContains` must still pass Security Rules per document.

### Consistency invariant

For every shared member, these must correspond:

```
uid ∈ project.memberIds   ⟺   projects/{projectId}/members/{uid} exists
```

Future trusted membership operations (Cloud Functions) must update **both** atomically.

**If the two become inconsistent:**

- Membership document controls authorization
- `memberIds` does **not** grant additional privileges
- Stale `memberIds` entries may appear in discovery queries but cannot expand access

### Owner authority

Owner operations verify:

```
resource.data.ownerId == request.auth.uid
```

Clients cannot transfer ownership via ordinary project updates. `ownerId` is immutable on client updates. Ownership transfer is not part of MVP.

### `memberIds` protection

Clients cannot mutate `memberIds[]` through ordinary project editing:

```
request.resource.data.memberIds == resource.data.memberIds
```

Future membership add/remove updates both `memberIds[]` and `members/{uid}` through trusted server-side logic only.

Denormalized query (discovery only):

```
projects where memberIds arrayContains currentUser.uid
```

Index: `firebase/firestore.indexes.json`

## 6. Firestore Security Rules Model

Rules live in `firebase/firestore.rules`. Principles:

- Secure by default — no `allow read, write: if true`
- `signedIn()` requires `request.auth != null`
- **Authorization:** membership document existence at `projects/{projectId}/members/{uid}`
- **Not authorization:** `memberIds[]` array membership alone
- Project read, task read/write, label read/write require valid membership document
- Owner update/delete uses `ownerId`; `ownerId` and `memberIds` are immutable on client updates
- Client project **create** is denied — shared-project bootstrap requires trusted server operation
- Clients cannot create/update/delete `members` documents
- Invite documents store **tokenHash only**, never raw tokens

Mandatory emulator rule tests before production deploy: `firebase/PHASE1_EMULATOR_RULE_TESTS.md`

## 7. Invite / Token Security

Invitation URLs (future):

```
https://todoshi.app/invite/<raw-token>
```

- Raw token exists only in the URL shown to the invitee
- Firestore stores `tokenHash` only
- Acceptance occurs through a trusted Cloud Function (Admin SDK), not direct client membership writes
- Knowing a project UUID or invite document ID must not grant access

## 8. SwiftData Responsibilities (unchanged in Phase 0)

SwiftData remains the source of truth for **personal** projects:

| Entity | Phase 0 change |
|--------|----------------|
| `Project` | None |
| `TaskItem` | None |
| `LabelTag` | None |
| `ChecklistItem` | None |
| `TaskResource` | None |

Future shared-project metadata (not yet in schema):

- sharing mode
- remote project ID
- remote updatedAt
- sync state

Recurrence and parent/subtask relationships were audited; no Phase 0 schema changes.

## 9. Firestore Offline Cache Considerations

Future shared projects may use Firestore offline persistence, but Phase 0 does **not** enable a second competing cache.

Before sync implementation, explicitly decide:

```
Firestore = collaboration authority (remote)
SwiftData = local app representation for shared projects
```

Avoid three competing truths: SwiftData-only local, Firestore cache, and remote Firestore.

## 10. Future Sync Service

Not implemented in Phase 0. Direction:

```
Firestore snapshot listener
        ↓
CollaborationSyncService (future)
        ↓
local shared project representation
        ↓
SwiftUI
```

Policies:

- Client-generated UUIDs
- Firestore server timestamps where appropriate
- `updatedAt` / `deletedAt` soft deletion
- Idempotent writes
- Initial conflict strategy: last-write-wins for simple scalar fields

No CRDT, operational transforms, or event sourcing in MVP.

## 11. Realtime Listeners

Firestore listeners will feed a future `CollaborationSyncService`. Listeners must **not** be attached inside SwiftUI views or WidgetKit extensions.

## 12. Firebase Storage Direction

Personal `TaskResource` files remain local. Future shared attachments:

```
Firestore resource metadata + private Storage object
```

Access restricted to project members. No Storage uploads in Phase 0.

## 13. Cloud Functions Direction

Trusted server operations (future):

- Accept invitation tokens (hash verify + membership create)
- Atomic membership changes
- Invite invalidation
- Notification fan-out
- Sensitive owner/member operations

No custom Node server. No Functions implemented in Phase 0.

## 14. Widget Boundary

Widgets continue reading App Group / local SwiftData snapshots only.

```
Main app syncs Firebase → local data updates → widget reload
```

No Firebase Auth or Firestore in WidgetKit.

## 15. App Check Direction

App Check is production hardening only — not authorization. Enable after Debug, TestFlight, and production token configuration are validated. Not enforced in Phase 0.

## 16. Code Boundaries (Phase 0)

```
Views / Features
        ↓
CollaborationBackend (protocol, TodoshiCore)
        ↓
FirebaseCollaborationBackend (Todoshi app target)
        ↓
Firebase Core / Auth / Firestore SDKs
```

Bootstrap:

- `FirebaseBootstrap.configureIfAvailable()` — single entry point in `TodoshiApp.init()`
- If `GoogleService-Info.plist` is absent → local-only mode, no crash

### Developer setup

1. Create a Firebase iOS app in Firebase Console
2. Download `GoogleService-Info.plist`
3. Place at `Todoshi/Resources/GoogleService-Info.plist` (gitignored)
4. See `Todoshi/Resources/GoogleService-Info.plist.example` for shape

## 17. Shared Project Conversion (future)

When owner taps **Share Project**:

1. Require authentication
2. Trusted operation creates Firestore project **atomically** with:
   - `ownerId = currentUser.uid`
   - `memberIds = [currentUser.uid]`
   - `projects/{projectId}/members/{ownerUID}` with role `owner`
3. Upload collaboration data
4. Mark local project as shared
5. Begin sync
6. Enable invitations

**Bootstrap problem:** A client cannot safely create a shared project alone because:

- Client project `create` is denied in Security Rules (Phase 0)
- `members/{uid}` writes are denied to clients
- `memberIds` cannot be self-modified

Shared-project creation must occur through a trusted Cloud Function or Admin SDK transaction that writes project + owner membership + initial `memberIds` consistently.

No automatic upload of existing personal projects. Sharing is explicit user intent.

## 17.1 Shared Project Bootstrap (Phase 2 — Firestore-only)

Cloud Functions require the Blaze plan. Initial project-owner bootstrap can be securely
expressed as a two-document Firestore atomic batch validated by Security Rules /
`getAfter()`. Therefore Todoshi uses **Firestore-only bootstrap** for MVP and stays on Spark.

```
FirestoreSharedProjectBootstrapService
  → WriteBatch (project + owner membership)
  → Security Rules validate paired create
```

This exception applies **only** to:

```
brand-new project + creator as owner
```

It does **not** authorize general membership management. After bootstrap, client
membership writes remain denied. `memberIds[]` remains a discovery index only;
authorization continues via `projects/{id}/members/{uid}` existence.

Invitation/member-add security will be designed separately. If future invite acceptance
requires trusted backend authority, reassess Blaze or another Admin SDK backend then.

See `Docs/PHASE2_SHARED_PROJECT.md` and `firebase/functions/DEFERRED.md`.

## 18. Authentication (Phase 1 — implemented)

Primary: **Sign in with Apple** integrated with Firebase Auth (secure nonce flow).

- No mandatory login at launch; personal SwiftData workflows remain account-free
- Settings → **Account / الحساب** for sign-in and sign-out
- Reusable `AuthenticationView` sheet for future Share Project (not shown at launch)
- Single `AuthSessionController` observes Firebase Auth state
- Minimal Firestore bootstrap at `users/{uid}` after sign-in (displayName, email, createdAt, updatedAt)
- `CollaborationAuthGate` for future collaboration actions
- Bundle ID: `com.anashamad.Todoshi`

Account deletion in-app is documented as a pre-release requirement; not implemented in Phase 1.

Potential later fallback: email link / email auth. No password-based MVP unless explicitly requested later.

## 18.1 User Profile (Phase 1.1 — implemented)

Settings → Account → **Profile** when signed in.

Editable collaboration identity:

- `displayName`
- email (read-only)
- generated initials avatar (local, not persisted)

**Firebase Storage is not enabled for the current MVP.**  
Profile avatars use generated initials.  
Storage will be enabled later for shared attachments/profile images.

Optional Firestore field `avatarPath` may exist for forward compatibility but is **not written** by the current app.

Sign Out lives on Profile.

Secure Storage rules are retained in `firebase/storage.rules` for a future phase and are **not** part of active `firebase.json` deploy configuration.

### Future member identity (documented only — not implemented)

When project sharing lands, collaboration UI can show generated initials + displayName:

```text
[AH] Anas Hamad
[أ ح] أنس الحميد
```

without requiring Storage. Prefer membership-aware projections over making `users/{uid}` globally readable.

## 18.2 Google Sign-In (Phase 1.2)

Google is an **alternative** Firebase Authentication provider alongside Sign in with Apple.

```
AuthenticationView / Account
  → AuthSessionController
  → FirebaseAuthService
  → GoogleSignInCoordinator
  → Google Sign-In SDK
  → FirebaseAuth (GoogleAuthProvider)
  → CollaborationSession (same domain model)
```

- Firebase Auth remains the session authority and Firestore `users/{uid}` profile sync is reused.
- Collaboration membership continues to use **Firebase UID only**.
- Provider linking / Connected Accounts UI is deferred (`AuthProviderLinkingPolicy`).
- Account collision (`accountExistsWithDifferentCredential` / email already in use) surfaces a safe message; no automatic merge.
- URL scheme for Google callbacks is injected at build time from `REVERSED_CLIENT_ID` in the local `GoogleService-Info.plist` (preserves `todoshi://` and `nexus://`).

Developer must enable Google under Firebase Authentication → Sign-in methods and download a refreshed plist that includes `CLIENT_ID` / `REVERSED_CLIENT_ID`.

## 19. Firebase Emulator

Repository includes:

- `firebase.json`
- `firebase/firestore.rules`
- `firebase/storage.rules` — **deferred**; not deployed while Storage is disabled
- `firebase/firestore.indexes.json`
- `firebase/PHASE1_EMULATOR_RULE_TESTS.md` — mandatory rules tests before deploy

Firebase Storage is not enabled for the current MVP. Profile avatars use generated initials. Storage will be enabled later for shared attachments/profile images.

When Storage is intentionally enabled later:

```bash
firebase deploy --only storage --project "$PROJECT_ID"
```

Emulator is optional for local development. Not required for local-only app launch.

**Phase 1:** Automated harness at `firebase/tests/firestore.rules.test.js`. Run:

```bash
cd firebase && npm install && npm run test:rules
```

Requires Firebase CLI and **JDK 21+** for the Firestore emulator.

## 20. MVP Non-Goals

- Organizations / teams / workspaces
- Advanced roles beyond owner/member
- Comments, mentions, task chat, activity feed
- Web or Android clients
- CRDT / operational transforms
- Automatic cloud migration or upload of personal projects
- Login UI, sharing UI, sync engine, Storage, Functions, App Check enforcement

These may be revisited in later phases.

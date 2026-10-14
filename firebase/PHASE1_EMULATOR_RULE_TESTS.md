# Phase 1 Mandatory Firestore Emulator Rule Tests

These cases must be validated with the Firebase Emulator rules test suite before deploying
`firebase/firestore.rules` to production. Swift unit tests do **not** substitute for these.

Run against: `firebase/firestore.rules` (membership-document authority model)

## Prerequisites

- Firebase CLI installed
- `@firebase/rules-unit-testing` (or equivalent rules test harness)
- Emulator started: `firebase emulators:start --only firestore`

## Mandatory Cases

### 1. Non-member cannot read project

- **Given:** authenticated user `alice`, project `p1` exists
- **Given:** no `projects/p1/members/alice` document
- **Expect:** `get projects/p1` → **denied**

### 2. UID in `memberIds` only — still denied

- **Given:** authenticated user `bob`, project `p1` with `memberIds: ["bob"]`
- **Given:** no `projects/p1/members/bob` document
- **Expect:** `get projects/p1` → **denied**
- **Expect:** `get projects/p1/tasks/t1` → **denied**

### 3. Membership document exists — project read allowed

- **Given:** authenticated user `carol`, `projects/p1/members/carol` exists
- **Expect:** `get projects/p1` → **allowed**

### 4. Member can read project tasks

- **Given:** authenticated user `carol`, valid membership document for `p1`
- **Expect:** `get projects/p1/tasks/t1` → **allowed**

### 5. Non-member cannot read tasks

- **Given:** authenticated user `dave`, no membership document for `p1`
- **Expect:** `get projects/p1/tasks/t1` → **denied**

### 6. Member cannot create own membership

- **Given:** authenticated user `eve`
- **Expect:** `set projects/p1/members/eve` → **denied**

### 7. Owner cannot alter `memberIds` through ordinary project edit

- **Given:** authenticated owner `frank`, valid membership for `p1`
- **When:** `update projects/p1` with changed `memberIds`
- **Expect:** **denied**

### 8. Owner cannot change `ownerId`

- **Given:** authenticated owner `frank`, valid membership for `p1`
- **When:** `update projects/p1` with changed `ownerId`
- **Expect:** **denied**

### 9. Anonymous user cannot read shared data

- **Given:** unauthenticated context
- **Expect:** `get projects/p1` → **denied**
- **Expect:** `get projects/p1/tasks/t1` → **denied**

## Additional Recommended Cases (Phase 1)

- Client `create projects/p1` → **denied** (trusted bootstrap only)
- Owner with `ownerId` match but no membership document cannot read project contents
- Invite read allowed for project member; denied for non-member non-inviter
- Member can read `projects/p1/members/*` for collaboration UI

## Consistency Note

If `memberIds` and membership documents diverge, authorization follows membership documents only.
Emulator tests should verify that stale `memberIds` entries do not expand access.

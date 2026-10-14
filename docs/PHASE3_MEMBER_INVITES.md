# Phase 3 — Member Invitations & Join Project

Capability-style single-use invites via `projectInvites/{token}` (token = document ID / bearer secret).

## Security note

The invite token is a **bearer secret** (256-bit `SecRandomCopyBytes`). Anyone with a valid unused unrevoked unexpired URL may join. Collection listing is denied. No Firebase Dynamic Links; URL builder can later switch to `https://todoshi.app/invite/<token>` without changing the domain model.

## Out of scope (stop here)

- Task synchronization (Phase 4)
- Member removal (Phase 3.1)
- Cloud Functions / Storage / Blaze

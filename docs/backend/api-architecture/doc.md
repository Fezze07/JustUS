# System Communication Architecture & Service Dependency Map

## Overview

This document provides a reverse-engineering analysis of the communication topology, service interaction patterns, API endpoints, backend middleware chains, external third-party integrations, and direct Supabase database access boundaries in JustUS.

---

## High-Level Communication Topology

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                      Flutter Client                     │
                  └──────────┬──────────────────┬─────────────────┬─────────┘
                             │                  │                 │
              Direct RLS API │                  │ Custom Express  │ WebSocket
              (PostgREST /   │                  │ API (/api/v1)   │ Realtime
              Stored RPCs)   │                  │                 │ Channel
                             ▼                  ▼                 │
                   ┌──────────────────┐  ┌───────────────┐        │
                   │ Supabase Cloud   │  │ Node.js/      │        │
                   │ PostgreSQL /     │  │ Express       │        │
                   │ Auth Service     │  │ Backend Server│        │
                   └─────────▲────────┘  └───────┬───────┘        │
                             │                   │                │
                             │ Admin ServiceRole │                │
                             └───────────────────┼────────────────┘
                                                 │
                   ┌─────────────────────────────┼──────────────────────────────┐
                   │                             │                              │
                   ▼                             ▼                              ▼
      ┌─────────────────────────┐   ┌────────────────────────────────────────────┐
      │   Cloudflare R2 Bucket   │   │            Firebase Admin FCM API          │
      │  (Pre-signed PUT / GET) │   │           (Push Notification SDK)          │
      └─────────────────────────┘   └────────────────────────────────────────────┘
```

---

## Service Inventory & Base URLs

| Service / System | Role / Purpose | Base URL / Entry Point | Auth Mechanism |
|---|---|---|---|
| **Node.js Express Backend** | Custom API business logic, media signing, push dispatch | `https://api.justus.app/api/v1` (or local port) | Supabase JWT Bearer + HMAC Signatures |
| **Supabase Auth & Database** | Primary DB, Auth sessions, Row Level Security (RLS), Realtime WS | `https://<ref>.supabase.co` | JWT Bearer (`anon` / `authenticated` / `service_role`) |
| **Cloudflare R2 Storage** | Object storage for Drive media & Profile pictures | `https://<bucket>.<account>.r2.cloudflarestorage.com` | AWS S3 V4 Pre-signed URLs |
| **Firebase Cloud Messaging** | Mobile Push Notifications (Android/iOS) | Firebase Admin Node.js SDK v14 | Service Account Private Key JSON |

---

## Hybrid Architectural Boundary: Direct Supabase vs. Backend API

The Flutter client uses a **hybrid architecture** by design:

1. **Direct Supabase Access (PostgREST / RLS / RPC)**:
   - Used for domain CRUD operations that map directly to single tables or PostgreSQL views with strict Row-Level Security (RLS) policies.
   - **Direct Access Features**: Mood tracking (`moods`, RPC `mood_set`), Miss-You signals (`missyou`, RPC `missyou_send`), Bucket List (`bucket_items`), Game questions & answers (`game_questions`, `game_answers`, `game_question_bank`), Drive metadata & favorites (`drive_items`, `favorites`, `v_drive_dashboard`, RPC `emoji_get_or_create`), Partnership acceptance (`rpc/partnership_accept`).
   - **Architectural Justification**: Eliminates backend boilerplate for simple CRUD while leveraging PostgreSQL RLS for multi-tenant isolation.

2. **Node.js Express Backend API (`/api/v1`)**:
   - Used for operations requiring elevated privileges, third-party API orchestration, HMAC signing, heavy rate limiting, or atomic domain wipes.
   - **Backend API Features**: Pre-signed media upload/download (`/api/v1/media/*`), Push notification dispatch (`/api/v1/notify/*`), Installation ID registration and revocation (`/api/v1/auth/installation-id`, `/api/v1/auth/installation-id-revoke`, `/api/v1/auth/installation-id-revoke-all`), Session binding (`/api/v1/auth/session-bind`), Account data wipe (`/api/v1/users/wipe`), Partnership cancellation acceptance (`/api/v1/partnership/cancel/accept`).

---

## Endpoints Inventory (`/api/v1`)

### 1. Media & Cloudflare R2 Endpoints

#### `POST /api/v1/media/upload-url`
- **Controller**: `presignUploadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_media_upload")` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `signed("media-upload-url")` $\rightarrow$ `validated({ body: presignSchema })`
- **Request Body**: `{ type, filename, mimeType, size, folder }`.
- **Response**: `{ success: true, uploadUrl, filename, expiresIn }`.
- **External Dependencies**: AWS S3 SDK / Cloudflare R2 API generating pre-signed `PUT` URL.

#### `POST /api/v1/media/complete`
- **Controller**: `completeUploadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_media_upload")` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `signed("media-complete")` $\rightarrow$ `validated({ body: completeSchema })`
- **Behavior**: If `kind === "profile"`, updates `user_profiles.profile_pic_url`. Otherwise inserts record into `drive_items`.

#### `GET /api/v1/media/file`
- **Controller**: `redirectToSignedDownloadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `validated({ query: fileQuerySchema })`
- **Behavior**: Verifies user access in `drive_items`, generates S3/R2 pre-signed download URL, and responds with HTTP 302 redirect.

#### `POST /api/v1/media/delete`
- **Controller**: `deleteMediaController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_media_upload")` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `signed("media-delete")` $\rightarrow$ `validated({ body: deleteSchema })`
- **Request Body**: `{ id }` (positive integer drive item id).
- **Behavior**: Reads the `drive_items` row; idempotent (row already gone → `200` no-op); rejects `403 AUTH-FAIL-004` unless the caller is `user_id` or `partner_id`; deletes the row first (favorites/reactions cascade), re-asserting ownership in the DELETE predicate; then best-effort R2 object cleanup (`DeleteObjectCommand`) — failures are logged and never block the response, with the orphaned object reclaimed by the retention sweep (`retentionJob.js` `sweepStaleOrphanObjects`, 24 h cutoff).
- **Flutter Consumer**: `DriveRepository.deleteDriveItem(id)` → `ApiService.deleteMediaItem(id)` — replaces the old direct SQL delete; a `DB-NOT_FOUND-001` response is treated as success so optimistic deletes are not resurrected on stale retries.

---

### 2. Authentication & Device Endpoints

#### `POST /api/v1/auth/installation-id`
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `signed("auth-installation-id")` $\rightarrow$ `validated({ body: updateInstallationSchema })`
- **Database Behavior**: Upserts `user_devices` table with `installation_id`, `user_id`, `locale`, `user_agent`, `last_ip`.

#### `POST /api/v1/auth/installation-id-revoke`
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `signed("auth-installation-id-revoke")` $\rightarrow$ `validated({ body: revokeInstallationSchema })`
- **Request Body**: `{ installationId }` (same 16–512 char constraint as the registration schema).
- **Database Behavior**: Deletes the caller's own `user_devices` row — `installation_id` **and** `user_id` must match, so a late logout can never remove a row another account has already re-registered on the same device. Idempotent (row already gone → `200`); a DB failure surfaces as `500 DB-WRITE-001` instead of a silent success.
- **Flutter Consumer**: `AuthRepository.revokeInstallationId()` → `ApiService.revokeInstallationId()`, called by `AuthState._revokeInstallationId()` as the first step of `logout()` while the JWT and binding secret still exist. Best-effort: bounded by a 5 s timeout, never blocks the local teardown, and a `401` does not re-enter the logout callback.

#### `POST /api/v1/auth/installation-id-revoke-all`
- **Controller**: `revokeOtherInstallationIds` ([`auth.routes.js`](file:///f:/JustUS/Backend/features/auth/auth.routes.js), [`auth.controller.js`](file:///f:/JustUS/Backend/features/auth/auth.controller.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `signed("auth-installation-id-revoke-all")` $\rightarrow$ `validated({ body: revokeInstallationSchema })`
- **Request Body**: `{ installationId }` (same 16–512 char constraint; here it is the installation id to **keep**).
- **Database Behavior**: Deletes every `user_devices` row of the caller except the one whose `installation_id` matches the body — `user_id = me AND installation_id != mine` — so the password change that triggers it stops pushes to all other devices at once while the caller's own registration survives. Durable: a deleted device cannot re-register, because the registration route is `authenticated()` and its Supabase session was already revoked. A DB failure surfaces as `500 DB-WRITE-001`.
- **Flutter Consumer**: `AuthRepository.revokeOtherInstallations()` → `ApiService.revokeOtherInstallations()`, called by `AuthState._revokeOtherInstallations()` right after `_revokeOtherSessions()` on both password writes. Best-effort (5 s cap, `401` does not re-enter the teardown, an empty local installation id skips the call); the 30-day retention sweep is the backstop.

#### `POST /api/v1/auth/session-bind`
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `freshNonce("auth-session-bind")` $\rightarrow$ `validated({ body: sessionBindSchema })`
- **Behavior**: generates a fresh `binding_secret`, hashes `device_fingerprint`, upserts `session_bindings` (revoking any stale session of the same user + device first), returns `{ success, anomalies, bindingSecret }`. The secret is rotated on **every** call; the client stores it only if the response arrives, so a lost response leaves the client signing with the previous secret until `ApiService` re-binds on the resulting `SEC-AUTH-002`.

#### `POST /api/v1/auth/invite-user`
- **Controller**: `inviteUserController` ([`auth.routes.js`](file:///f:/JustUS/Backend/features/auth/auth.routes.js), [`auth.controller.js`](file:///f:/JustUS/Backend/features/auth/auth.controller.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(inviteUserRateLimit)` $\rightarrow$ `signed("auth-invite-user")` $\rightarrow$ `validated({ body: inviteUserSchema })`
- **Request Body**: `{ email, redirectTo? }` (`redirectTo` is the client's platform redirect, e.g. `justus://auth/callback` on Android/iOS; GoTrue validates it against the project redirect allow-list).
- **Behavior**: Calls `adminSupabase.auth.admin.inviteUserByEmail()`; GoTrue creates the invitee's Auth account and sends the hosted "Invite user" email. Account-only — no `partnerships` row. Rate-limited to 5/user and 10/IP per window because each call sends an email. An address that already has a confirmed account returns `409 API-VALIDATION-002` (GoTrue `email_exists` / `user_already_exists`); an invited-but-unconfirmed address is re-invited; any other GoTrue failure returns `500 API-FAIL-001`.
- **Flutter Consumer**: `PartnershipRepository.inviteUnregisteredPartner()` → `ApiService.inviteUnregisteredPartner()`, called by `AuthState.inviteUnregisteredPartner()` from `PartnerInviteEmailDialog`.

---

### 3. Push Notification Endpoints

#### `POST /api/v1/notify/partner` / `POST /api/v1/notify/:type`
- **Controller**: `sendNotificationController` ([`notify.routes.js`](file:///f:/JustUS/Backend/features/notifications/notify.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(notifyRateLimit)` $\rightarrow$ `validated({ body: notifySchema })`
- **External Dependencies**: Firebase Admin SDK (`messaging.sendEachForMulticast`). Resolves partner Firebase Installation IDs (FIDs) from `user_devices` table and dispatches localized push notification.
- **Cancellation Push Partner**: `cancellationRequested` resolves via `getCancellationPartnerId` (uses `partnership_get_cancellation_partner`); `cancellationAccepted` is sent directly by the acceptance endpoint.

---

### 4. User Domain Operations

#### `POST /api/v1/partnership/cancel/accept`
- **Controller/Service**: `acceptCancellation` in `features/partnership/*` ([`partnership.routes.js`](file:///f:/JustUS/Backend/features/partnership/partnership.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(cancelRateLimit)` $\rightarrow$ `signed("partnership-cancel-accept")` $\rightarrow$ `validated({ body: { partnershipId } })`
- **Behavior**: Loads the cancelled row as service_role, validates the caller is the non-requester member and not expired (calls `partnership_expire_cancellations()` on expiry → `API-VALIDATION-014`), calls `partnership_cancel_accept(partnershipId, actorId)` (service_role RPC), best-effort deletes `uploads/<user1>/` and `uploads/<user2>/` via `deleteObjectsByPrefix` (no `profile/`), sends `cancellationAccepted` to the requester, returns `{ success: true }`. R2 failure does not roll back the DB delete.
- **Flutter caller**: `ApiService.acceptPartnershipCancellation({required int partnershipId})` posts `{ partnershipId }` to `ApiRoutes.partnershipCancelAccept` with `requireSignature: true`; `PartnershipRepository.acceptCancellation` wraps it after clearing the partnership cache.

#### `POST /api/v1/users/wipe`
- **Controller**: `wipeUserDataController` ([`user.routes.js`](file:///f:/JustUS/Backend/features/user/user.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(userRateLimit)`
- **Database Dependencies**: Invokes `adminSupabase.rpc("debug_wipe_user_data", { p_user_id: userId })`.
- **Scope — developer-only**: test-data reset tool, not a production account-deletion feature. The only Flutter entry point is the wipe tile inside the `kDebugMode` block (`profile_screen.dart:468`), so a release build cannot reach it; the `debug_` prefix on the RPC is deliberate and documents that intent (10.17, see `docs/fixing-phase-log.md` § Item index). The route itself carries no env gate — a release-build client that called it directly would still be served.
- **R2 Cleanup**: after the RPC succeeds, `deleteUserR2Objects(userId)` resolves the accepted partner id and deletes all objects under `uploads/{userId}/`, `profile/{userId}/`, `uploads/{partnerId}/`, `profile/{partnerId}/` (`r2.service` `listObjectKeys` + batched `DeleteObjectsCommand`). Uses `SYS-FAIL-001` if R2 cleanup fails (DB rows are already purged; re-running the wipe retries the R2 sweep).

---

### 5. System & Health Routes

#### `GET /api/v1/ping`
- Returns `{ status: "ok" }` health check.

#### `GET /api/v1/app-version`
- Queries `app_versions` table for latest app version info and minimum supported build number.

---

## Document Status

Document created and saved to [`docs/backend/api-architecture/doc.md`](file:///f:/JustUS/docs/backend/api-architecture/doc.md).

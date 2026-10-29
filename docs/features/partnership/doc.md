# Partnership System - JustUS

## Overview

This document provides a reverse-engineered analysis of the **Partnership Subsystem** in the JustUS application. It traces the full lifecycles, data flows, state transitions, validation logic, database objects, API boundaries, and real-time synchronization loops for partner linking.

The partnership subsystem is the foundation of the JustUS platform: it links two users together in a 1:1 relationship, enabling shared features such as mood updates, bucket list items, joint memory drive files, and interactive couple games.

---

## Architecture & Component Mapping

The partnership architecture spans three main layers:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER FRONTEND LAYER                         │
│  PartnerScreen • PartnerInviteDialog • PartnerState • AuthState          │
│  PartnershipRepository • RealtimeSyncService • SplashScreen               │
└────────────────────┬───────────────────────────────▲────────────────────┘
                     │                               │
       REST API /    │                               │ Supabase Realtime
       Supabase SDK  │                               │ Postgres Changes
                     ▼                               │ (table: partnerships)
┌───────────────────────────────────────┐            │
│          NODE.JS / EXPRESS API        │            │
│  POST /api/v1/auth/invite             │            │
│  (validate; partnership_request RPC)  │            │
│  POST /api/v1/auth/invite-user        │            │
│  (Supabase Auth admin invite → SMTP)  │            │
└────────────────────┬──────────────────┘            │
                     │ Service Role /                │
                     │ RPC Delegation                │
                     ▼                               │
┌────────────────────────────────────────────────────┴────────────────────┐
│                             SUPABASE LAYER                              │
│  Tables: public.partnerships, public.users, public.user_profiles        │
│  View: v_active_partnership (security_invoker = true)                   │
│  RPCs: partnership_request, partnership_accept, partnership_cancel_*    │
│  Triggers: user_create_from_auth, guard_public_partnerships_status      │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [partner_screen.dart](file:///f:/JustUS/Flutter/lib/features/partnership/screens/partner_screen.dart): UI rendering for personal partnership code, partner card, pending received requests, pending sent requests, add partner action, and the "your partner doesn't have Just Us? Invite them now!" entry point.
   - [partner_state.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partner_state.dart): State manager for fetching partnership data, sending/accepting/rejecting requests, and performing optimistic state updates.
   - [partner_invite_dialog.dart](file:///f:/JustUS/Flutter/lib/features/partnership/widgets/partner_invite_dialog.dart): email + 6-char code pairing request. [partner_invite_email_dialog.dart](file:///f:/JustUS/Flutter/lib/features/partnership/widgets/partner_invite_email_dialog.dart): account-only invite (email address only).
   - [partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart): Network client interacting with Supabase client (direct query on `v_active_partnership`, `partnership_get_pending_invitations` RPC, `partnership_accept` RPC, `partnership_reject` RPC for rejection, cancellation RPCs) and Node Express API (`_api.inviteUser`, `_api.inviteUnregisteredPartner`, `_api.acceptPartnershipCancellation`).
   - [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart): `AuthState.invitePartner(email, code)` (pairing request) and `AuthState.inviteUnregisteredPartner(email)` (account-only invite; forwards `emailRedirectTo`).
   - [partnership_models.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_models.dart): Data models `PartnershipResponse`, `PendingRequests`, and `PartnershipInvitation`.
   - [refetch_realtime_handler.dart](file:///f:/JustUS/Flutter/lib/core/realtime/refetch_realtime_handler.dart): `RefetchRealtimeHandler` (unified debounced-refetch strategy) subscribes to Postgres change events on `public.partnerships`, debounces 150 ms, invalidates `BaseRepository` cache, and updates `PartnerState` / `AuthState`. Wired by `RealtimeSyncService` (`lib/core/realtime/realtime_sync_service.dart`) with an `isRelevant` predicate + `refetch` closure.

2. **Backend API (Node.js / Express)**:
   - [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js): `invitePartnerController` resolves recipient email + partnership code via `resolveRequestedPartnerOrNull`, checks self-invitation, and calls `adminSupabase.rpc('partnership_request')`. `inviteUserController` calls `adminSupabase.auth.admin.inviteUserByEmail(email, { redirectTo })`, remapping GoTrue's `email_exists` / `user_already_exists` to `409 API-VALIDATION-002`.
   - [auth.schemas.js](file:///f:/JustUS/Backend/features/auth/auth.schemas.js): Zod schemas `inviteSchema` (email format + 6-character partnership code) and `inviteUserSchema` (`email` + optional `redirectTo` URL).
   - [partnershipUtils.js](file:///f:/JustUS/Backend/utils/misc/partnershipUtils.js): Single source of truth for backend partnership lookups — `getPartnerId()`, `getCancellationPartnerId()`, `getPartnershipId()`, `getPartnershipById()`, `isPartnershipParticipant()` and `isPartnershipMember()`. No other backend module queries `public.partnerships` directly; `partnership.service.js` validates cancellation acceptance through these helpers.

3. **Database Layer (Supabase / PostgreSQL)**:
   - `public.partnerships`: Main database table storing pair relationships with columns `id`, `user_id_1`, `user_id_2`, `status`, `anniversary_date`, `created_at`, `updated_at`, plus the cancellation state fields `cancel_requested_by`, `cancel_expires_at`, `cancel_declined_at`. The cancellation fields are constrained (`status IN ('pending', 'accepted', 'cancelled')`, requester must be a member, requester and expiry set only while `cancelled`), and the `guard_public_partnerships_status` trigger enforces the request/revert transition whitelist (`API-VALIDATION-010` / `-011` / `-012`) with the cancellation fields read-only outside those transitions. `partnership_request_cancel(p_partnership_id)` writes a request for either member, subject to the 24h cooldown, `partnership_cancel_revert(p_partnership_id)` restores the row for either member, and `partnership_expire_cancellations()` reverts every expired request (service-role/backend only); `partnership_get_cancellation()` is the scoped read for the PartnerScreen cancellation state, with lazy expiry.
   - `public.user_profiles`: Stores user profile metadata including unique `partnership_code`.
   - `public.moods`: Mood rows carry `partnership_id` (`FK -> public.partnerships(id) ON DELETE CASCADE`, indexed). `mood_set` writes the caller's `accepted` partnership (NULL when the caller has none), and the insert/update policies require `partnership_id IS NULL OR partnership_is_member(partnership_id)`, so a client cannot attach a mood to another pair. The table was empty at rollout, so no backfill was needed.
   - `v_active_partnership`: PostgreSQL view returning the accepted partner's profile details (`partner_id`, `partner_display_name`, `partner_profile_pic_url`).
   - Stored Procedures: `partnership_request(partner_email, partner_code, override_sender_id)`, `partnership_accept(p_partnership_id)`, `partnership_request_cancel(p_partnership_id)`, `partnership_cancel_revert(p_partnership_id)`, `partnership_expire_cancellations()`, `partnership_get_cancellation()`, `partnership_get_cancellation_partner(p_user_id)`, `partnership_cancel_accept(p_partnership_id, p_actor_id)`, and `partnership_get_pending_invitations()` (pending-request identity for the caller only).

---

## Partnership State Machine & Transitions

### Partnership States

The partnership subsystem defines four logical states per user:

| State | Status Column | Description |
|---|---|---|
| **None** | `none` (or no row) | User has no active partnership and no pending invitations (sent or received). |
| **Pending** | `pending` | A partnership request has been created in `public.partnerships` with `status = 'pending'`, waiting for acceptance or rejection. |
| **Accepted** | `accepted` | An active partnership is established (`status = 'accepted'`). Both users are linked. |
| **Cancelled** | `cancelled` | One member asked to end the pair. Both are frozen out of couple features until reverts/declines/expiry return the row to `accepted`, or the partner accepts and the row (with the couple data) is deleted. |

### State Transition Diagram

```
                ┌────────────────────────────────────────┐
                │                  NONE                  │
                └───────────────────┬────────────────────┘
                                    │
                                    │ Send Request (partnership_request RPC)
                                    ▼
                ┌────────────────────────────────────────┐
                │                PENDING                 │
                └───────┬────────────────────────┬───────┘
                        │                        │
  Reject Request        │                        │ Accept Request
  (partnership_reject)  │                        │ (partnership_accept RPC)
                        ▼                        ▼
                ┌───────────────┐        ┌───────────────┐
                │     NONE      │        │   ACCEPTED    │
                └───────────────┘        └───────────────┘
```

An `accepted` pair can additionally move to `cancelled` (see §6–§8): a member requests it, the pair returns to `accepted` on restore/decline/expiry, and the row plus couple data are deleted when the other member accepts.

### Transition & Invariant Rules

1. **Request Initiation**:
   - **Who can initiate**: Any authenticated user who does not already have a pending, accepted or cancelled partnership.
   - **Self-Invitation Prevention**: A user who names their own email + code is rejected by the backend controller ([auth.controller.js:210](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L210)) with `API-VALIDATION-006`; the same code is raised by the `partnership_request` RPC guard for any direct caller. The client localizes it via `ErrorCodes.userMessage`.
   - **Duplicate Requests**: Prevented by checking existing `pending`, `accepted` and `cancelled` records for the sender in `partnership_request` RPC (raises `API-VALIDATION-004`), so a member whose partnership is frozen by a cancellation request cannot start a new pairing until it is restored or expires.
   - **Recipient Availability**: The same RPC also rejects a request whose *recipient* already holds an `accepted` or `cancelled` row (`API-VALIDATION-004`), so an unpaired user cannot send a phantom invitation to someone who could never accept it. Recipient `pending` rows are deliberately allowed: receiving several invitations at once is legitimate.
   - **Recipient Matching**: Initiator must provide **both** the exact target email (case-insensitive) and exact 6-character `partnership_code`; a mismatch raises `API-VALIDATION-005`.

2. **Rejection Handling**:
   - When a user rejects an incoming request or withdraws a sent one, Flutter invokes `partnership_reject(p_partnership_id)` ([partnership_repository.dart:119](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L119)). The RPC deletes a row only where the caller is a member and `status = 'pending'`, and the `partnerships_delete_own` policy enforces the same `status = 'pending'` condition on a raw `DELETE`.
   - The row is permanently removed from the database. The system transitions back to the **None** state.

3. **Acceptance Handling**:
   - When a recipient accepts a request, Flutter invokes PostgreSQL stored procedure `partnership_accept(p_partnership_id)` ([partnership_repository.dart:97](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L97)).
   - The RPC updates `public.partnerships`:
     - Sets `status = 'accepted'`.
     - Sets `anniversary_date = CURRENT_DATE`.
     - Updates `updated_at = CURRENT_TIMESTAMP`.
   - The system transitions to the **Accepted** state.

4. **Multiple Active Partnerships**:
   - **NOT PERMITTED**. The system architecture enforces a strict 1:1 pairing constraint. The database view `v_active_partnership` and application logic treat partnership as a single 1:1 relationship.

5. **`v_active_partnership` Resolution Logic**:
   - The view filters `public.partnerships` where the querying user is either `user_id_1` or `user_id_2` and `status = 'accepted'`.
   - It returns the partner's profile (`partner_id`, `partner_display_name`, `partner_profile_pic_url`). The partner's `users` row is not read: `partner_id` is derived from `user_id_1`/`user_id_2` and joined directly to `user_profiles`.
   - Pending invitations are **not** part of this view. They are fetched separately through the scoped `partnership_get_pending_invitations()` RPC, which returns only the caller's pending rows.

---

## Partnership Code Specification & Security

Each user profile automatically receives a unique **Partnership Code** upon registration.

### Properties & Constraints

- **Length**: Exactly 6 characters ([auth.schemas.js:25](file:///f:/JustUS/Backend/features/auth/auth.schemas.js#L25)).
- **Allowed Characters**: Upper-case alphanumeric strings (e.g., `ABC123`).
- **Generation**: Created automatically inside database trigger `user_create_from_auth()` on user profile creation.
- **Uniqueness**: Enforced at the database schema level by a `UNIQUE` constraint on `user_profiles.partnership_code` ([supabase-schema](file:///f:/JustUS/.agents/skills/supabase-schema/SKILL.md#L150)).
- **Expiration & Reuse**: The code is static and tied permanently to the `user_profiles` record. It does not expire and cannot be changed or reused by another user.
- **Brute-Force Resistance**:
  - A partnership code alone is insufficient to send a request.
  - The request payload requires **both** `email` AND `partnershipCode`.
   - In `auth.controller.js`, `resolveRequestedPartnerOrNull` queries `users` by email and `user_profiles` by `partnership_code` through the backend's `service_role` client (RLS-bypassing). If either fails to match, the request fails silently or returns null, preventing code enumeration attacks. Direct `authenticated` access to `public.users` is self-only, so this lookup is not possible from the client.

---

## Email Policy: Account Invites by Email, Pairing Requests In-App

The partnership feature uses two distinct channels, by design:

| Layer | Component | Capability | Actual Implementation |
|---|---|---|---|
| **Flutter Frontend** | `PartnershipRepository.inviteUser()` / `PartnerInviteDialog` | Ask an existing account to connect | HTTP POST to `/api/v1/auth/invite` (email + 6-char code), signed |
| **Flutter Frontend** | `PartnershipRepository.inviteUnregisteredPartner()` / `PartnerInviteEmailDialog` | Invite a partner who has no account yet | HTTP POST to `/api/v1/auth/invite-user` (email only), signed |
| **Backend API** | `POST /api/v1/auth/invite` | Create the pending pairing request | Validates input, resolves user in DB, invokes RPC `partnership_request`; **no email** |
| **Backend API** | `POST /api/v1/auth/invite-user` | Create the invitee's Auth account | `adminSupabase.auth.admin.inviteUserByEmail(email, { redirectTo })`; GoTrue sends the "Invite user" email through Supabase Auth SMTP (Resend) |
| **Supabase** | `partnership_request` RPC | Database request creation | Inserts row into `public.partnerships` with `status = 'pending'` |

> [!IMPORTANT]
> **Decision (2026-10-12)**: pairing requests never send an email. Every pairing request requires the recipient to already have a JustUs account (email + 6-char code), so the request itself is delivered in-app: the recipient sees it on `PartnerScreen` and is notified by push. The only partnership-related email is the Supabase Auth **"Invite user"** email, sent by `/api/v1/auth/invite-user` to someone who has no account yet. That invite is **account-only**: it does not create a `partnerships` row, so the pairing still happens through email + code once the invitee registers.

### The "Invite user" email (`POST /api/v1/auth/invite-user`)

- **Middleware chain**: `authenticated()` → `limited(inviteUserRateLimit)` (10/IP, 5/user per window) → `signed("auth-invite-user")` → `validated({ body: inviteUserSchema })`.
- **Request body**: `{ email, redirectTo? }`. `redirectTo` is the client's platform redirect (`justus://auth/callback` on Android/iOS, the server callback URL on web/desktop — `AuthState.emailRedirectTo`); GoTrue validates it against the project's redirect allow-list, and omitting it falls back to the project Site URL.
- **Success**: `200 { success: true }` after GoTrue accepted the invite.
- **Already registered**: GoTrue answers `422 email_exists`, remapped to `409 API-VALIDATION-002`; the dialog asks the user to request the partner's 6-character code instead. An address that was invited but never confirmed is re-invited instead of refused.
- **Any other GoTrue failure**: `500 API-FAIL-001`.
- **Template**: the hosted Supabase project owns the "Invite user" template (custom Italian copy, `{{ .Email }}` / `{{ .ConfirmationURL }}`); the local `supabase/config.toml` entry stays commented because the hosted dashboard is authoritative (see `docs/audits/email.md`).

---

## Functional Behavior & User Flow

### 1. Sending a Request
- **User Action**: User opens `PartnerInviteDialog`, enters the partner's email and 6-character code, and taps "Send".
- **Validation**: Client validates inputs are non-empty (`partner_fillAllFields`). Backend validates schema (`email`, `partnershipCode.length(6)`).
- **Execution**: Calls `POST /api/v1/auth/invite` -> Backend checks `resolveRequestedPartnerOrNull` -> Checks self-invitation -> Calls `adminSupabase.rpc('partnership_request')`.
- **UI Update**: Flutter receives the success response; `AuthState.invitePartner` refreshes the sent-invitations list (`fetchSentInvitations`), sets the confirmation message (`partner_inviteSuccess`), and the dialog pops. The global `AuthMessageHost` listener in `MaterialApp.builder` renders the message, so it survives the dialog's pop.

### 2. Receiving & Viewing Requests
- **Data Source**: `PartnershipRepository.getPendingInvitations()` calls the `partnership_get_pending_invitations()` RPC, which returns only the caller's pending rows (`invitation_id`, `partner_id`, `partner_display_name`, `is_received`). No direct read of the counterpart's `users`/`user_profiles` row occurs.
- **UI Element**: `PartnerScreen` renders `_buildInvitationsList` with `receivedInvitations` and `sentInvitations`.
- **Item Cards**: Display partner display name and timestamp. Provides "Accept" (Check icon) and "Reject" (Close icon) buttons.

### 3. Accepting a Request
- **User Action**: User taps "Accept" on a received invitation tile.
- **Execution**: Calls `AuthState.acceptInvitation(invite.id)` -> Invokes `PartnershipRepository.acceptPartnerRequest(invite.id)` -> Runs Supabase RPC `partnership_accept(p_partnership_id = invite.id)`.
- **Side Effects**:
  - Triggers asynchronous partner push notification (`notifyPartnerOnce`, key `requestAccepted`).
  - Calls `fetchPartnership()` and `ProfileState.loadProfile(force: true)`.
  - Calls `StorageService.savePartner` to store partner ID and username locally.
  - Replaces navigation stack with `MainShell`.

### 4. Rejecting a Request
- **User Action**: User taps "Decline" or "Cancel Request".
- **Execution**: Calls `AuthState.rejectInvitation(invite.id)` -> Runs `PartnershipRepository.rejectPartnerRequest(invite.id)` -> Calls RPC `partnership_reject(p_partnership_id = invite.id)`, deleting a pending row where the caller is a member (either sender or recipient).
- **UI Update**: Pending invitation is removed from local list. (Direct `DELETE` from Flutter is not used; the flow goes through the `partnership_reject` RPC.)

### 5. Inviting a Partner Who Has No Account
- **Entry Point**: `PartnerScreen` shows "Il tuo partner non ha Just Us? Invitalo ora!" (`partner_inviteEmailPrompt`) whenever the caller has no partner.
- **User Action**: Opens `PartnerInviteEmailDialog`, enters the partner's email, taps "Send".
- **Execution**: `AuthState.inviteUnregisteredPartner(email)` -> `PartnershipRepository.inviteUnregisteredPartner(email, AuthState.emailRedirectTo)` -> `POST /api/v1/auth/invite-user` -> `adminSupabase.auth.admin.inviteUserByEmail()`.
- **Side Effects**: GoTrue creates the invitee's Auth account (`user_create_from_auth` provisions `public.users` / `user_profiles`) and sends the hosted "Invite user" email; no `partnerships` row is written.
- **Error**: an address that already has an account returns `409 API-VALIDATION-002` and the dialog points the user at the 6-character code flow.

### 6. Partnership Cancellation (Flutter)
- **Model**: `PartnershipCancellation` (`partnership_repository.dart` / `partnership_models.dart`) carries `partnershipId`, `partnerId`, `partnerDisplayName`, `partnerProfilePicUrl` and `requestedByMe`, mapped from `partnership_get_cancellation()`.
- **Repository**: `PartnershipRepository.requestCancellation(id)` -> `partnership_request_cancel` + fire-and-forget `cancellationRequested` push; `revertCancellation(id)` -> `partnership_cancel_revert` + `cancellationDeclined` push; `acceptCancellation(id)` -> signed `POST /api/v1/partnership/cancel/accept` (`ApiService.acceptPartnershipCancellation`, `requireSignature: true`); `getCancellation()` -> `partnership_get_cancellation` (the only call that exposes the cancelled state, because `v_active_partnership`/`AuthState.hasPartner` stay empty while cancelled). Every mutation clears the static `_activePartnershipFuture` cache before calling the server.
- **State**: `PartnerState` holds `PartnershipCancellation? cancellation`, fetches it after `getPartnership()` in both `fetchPartnership()` and `refreshFromRealtime()`, and clears it when the read returns no row. A cancelled row must not populate `partner`/`partnershipInfo` as an active pair.
- **Reconciliation**: `acceptCancellation` treats the deletion as successful only when the read finds no cancellation *and* no accepted partner; an expired request (row back to `accepted`) keeps the original `API-VALIDATION-014` error instead of the "ended" copy. The screen refreshes `AuthState` on that path as well.
- **Realtime**: `isRelevantPartnership` accepts sparse DELETE payloads (PK-only under the default replica identity), and a delete that removes a known cancellation routes to `PartnerScreen` through `ErrorHandler.navigatorKey` so it also works above pushed routes.

### 7. Requesting Cancellation from Profile
- **Entry point**: `ProfileScreen` renders a danger-styled `InkWell` tile (`Icons.heart_broken_outlined`, `profile_cancelRequest`) above the logout tile, only when `AuthState.hasPartner` is true. It is not debug-gated.
- **Confirmation**: a simple `VPDialog` (`profile_cancelRequestTitle` / `profile_cancelRequestContent` / `profile_cancelRequestConfirm`) explaining that the partner must approve and the pair is paused until then; no type-to-confirm.
- **Execution**: `PartnerState.requestCancellation(partnershipId)` -> `partnership_request_cancel`. On success the repository sends the `cancellationRequested` push, then the screen clears the partnership cache, refreshes `AuthState` + `PartnerState` (the no-partner refresh also clears cached partner storage), shows `profile_cancelRequestSent` and `pushReplacementNamed(AppRoutes.partner)`.
- **Failure**: the mapped error (including the 24h `API-VALIDATION-013` cooldown) is shown and the user stays on Profile.

### 8. PartnerScreen Cancellation States
- **Requested by me**: a waiting card (`partner_cancellationWaiting(partnerName)`, no countdown or expiry date) plus a plain `partner_restorePartnership` button. The personal-code card, "New Connection" and both invitation lists are hidden. Restore calls `revertCancellation` and returns to `MainShell` with the pair `accepted`.
- **Requested by partner**: the reusable `InvitationTile` (`partner_cancellationRequested(partnerName)` / `partner_cancellationSubtitle`) with accept and decline actions; its optional title, subtitle, leading icon, tooltips and per-action visibility default to the normal invitation copy, so existing invitation cards are unchanged. Decline calls `revertCancellation` and returns to `MainShell`; the trigger records `cancel_declined_at`.
- **Accept**: a simple confirmation (`partner_cancellationEndTitle` / `partner_cancellationEndContent`) followed by `PartnerState.acceptCancellation` (the signed backend endpoint). On success (or a lost response whose row is gone) the screen shows `partner_cancellationEnded` and the empty PartnerScreen, so the user can pair again. If the request is still present, the error is shown and the state stays cancelled. There is no server tombstone: the ended copy is local to the session.
- **Requester cannot accept**: only the `requestedByMe == false` branch renders accept/decline; this mirrors `partnership_cancel_accept` rejecting the requester.
- **Logout** stays available in the footer while cancelled, and lazy expiry refreshes the same screen back to the accepted/normal state.

### 9. Cancellation Lifecycle & Acceptance Endpoint
- **Freeze**: while a row is `cancelled`, `partnership_is_member()` requires `status = 'accepted'`, so both members lose access to every couple feature and the couple's data. A frozen member cannot start a new pairing (`partnership_request` treats `cancelled` like `accepted` for the sender) or accept a different invitation (`partnership_accept` rejects it with `API-VALIDATION-012`). Logout, app close and restart change nothing.
- **Request**: one cancellation request per partnership, created by either member. It stores `cancel_requested_by = caller` and `cancel_expires_at = now() + 7 days`; the partner receives the `cancellationRequested` push and the requester waits on `PartnerScreen`. No data is deleted on request, restore/decline, expiry, logout or app close — only acceptance deletes.
- **Restore / decline**: either member may revert a non-expired request to `accepted`, clearing both cancel fields. A non-requester revert is a decline and records `cancel_declined_at`; the requester can re-request immediately, while a declined pair must wait 24 hours (`API-VALIDATION-013`).
- **Expiry**: after 7 days the row returns to `accepted` with no grace window — acceptance at that point is rejected and the request is reverted. Expiry is silent (no push) and runs both in the 6-hourly `sweepExpiredCancellations()` retention job and lazily inside `partnership_get_cancellation()`. The UI shows no expiry date or countdown.
- **Acceptance**: only the member who did not request the cancellation may accept, before `cancel_expires_at`. The client calls the signed `POST /api/v1/partnership/cancel/accept` endpoint (`authenticated()` -> `limited(cancelRateLimit)` -> `signed("partnership-cancel-accept")` -> `validated({ body: { partnershipId } })`, `requireSignature: true` in Flutter). The service loads the row through `getPartnershipById()` (service_role), rejects a non-cancelled row, a non-member or the requester (`API-VALIDATION-012`), and on an expired request runs `partnership_expire_cancellations()` then returns `API-VALIDATION-014`. Otherwise it calls `partnership_cancel_accept(partnershipId, caller)`, deletes `uploads/<user1>/` and `uploads/<user2>/` from R2 (never `profile/<uid>/`), sends the `cancellationAccepted` push to the requester and returns `{ success: true }`. R2 failures are logged and do not roll back the database delete; the orphan sweep removes leftovers.
- **What acceptance deletes**: the partnership row cascades `drive_items` (with favourites and reactions), `bucket_items`, `game_questions` (with answers), `missyou` and `moods`. There is no tombstone and no restore. Unrelated pending invitations for either user are not touched, and profile pictures plus non-partnership objects are kept.
- **In-flight uploads**: only `media-complete` may finish a file whose signed URL was issued while the pair was `accepted`; if the row is now `cancelled` it resolves the cancelled partnership's id through `getPartnershipId()` and inserts the drive item against it. The item is cascade-deleted if the partner accepts and kept if they decline. `createUploadUrl` stays accepted-only, so no new upload can start while cancelled; if the row is already gone, completion fails normally and the object is reclaimed by the orphan sweep. The presigned-URL lifetime bounds how long this in-flight exception can apply; the `cancellationRequested` push resolves the recipient separately through `getCancellationPartnerId()`.
- **Notifications**: `cancellationRequested` is sent by the requester's client to the partner, `cancellationDeclined` by the client after a revert to the other member, and `cancellationAccepted` by the backend endpoint to the requester. Expiry sends nothing. Notification taps add no new tab: the app opens its normal destination — `PartnerScreen` while the row is cancelled or after acceptance (no active partner), `MainShell` after a decline or restore — and a cold start follows the same `hasPartner` routing.

---

## Realtime Synchronization & Redirection Rules

### Realtime Event Pipeline

```
Database Event on public.partnerships (INSERT / UPDATE / DELETE)
                           │
                           ▼
Supabase Realtime Channel ('justus-sync-{userId}-{gen}')
                           │
                           ▼
RefetchRealtimeHandler.handle()
                            │
                            ├── 1. Filters relevance (RealtimeSyncSession.isRelevantPartnership: checks user_id_1, user_id_2; a DELETE is kept even when the payload is PK-only)
                            ├── 2. Deduplicates event key (RealtimeSyncSession.markSeen)
                            ├── 3. Debounces execution (150ms timer)
                           │
                           ▼
Clear local cache (BaseRepository.clearPartnershipCache())
                           │
                           ▼
Trigger UI state refreshes:
  ├── PartnerState.refreshFromRealtime()  (partnership + cancellation read)
  └── AuthState.refreshPartnershipFromRealtime()
```

When the refresh proves that a known cancellation is gone because the partner accepted (no accepted partnership and no cancellation row), `PartnerState` replaces the stack with `PartnerScreen` through `ErrorHandler.navigatorKey`; the redirect is not limited to `MainShell` and shows no dialog. The redirect lands on the empty PartnerScreen — the `partner_cancellationEnded` snackbar is only shown to the member who accepts (or whose lost response proves the row is gone), while the requester is informed by the `cancellationAccepted` push. A requester restore/partner decline keeps the pair `accepted`, and an expiry reverts the same way, so neither triggers the redirect.

### Automatic Redirection to PartnerScreen

App entry navigation routing is governed by `SplashScreen` ([splash_screen.dart:22-41](file:///f:/JustUS/Flutter/lib/features/auth/screens/splash_screen.dart#L22-L41)):

1. App launches and calls `AuthState.init()` (capped at 8 s; a timeout or initialization error is logged only and does not change the destination).
2. `AuthNavigationUtils.determinePostAuthDestination` checks `AuthState.isLoggedIn`:
   - `false` -> Navigate to `LoginScreen`.
   - `true` -> Execute `PartnerState.fetchPartnership()`.
3. Checks `PartnerState.partner`:
   - `partner != null` (Accepted partnership exists) -> Navigate to `MainShell`.
   - `partner == null` (No active partnership) -> Navigate to `PartnerScreen`.

---

## Security & Authorization Boundaries

1. **Row Level Security (RLS)**:
   - `public.partnerships`: SELECT and UPDATE policies restrict access strictly to the two members of the partnership (`user_id_1 = user_current_id() OR user_id_2 = user_current_id()`). The DELETE policy adds `status = 'pending'`, so a member can only withdraw a still-pending request; an accepted or cancelled row (and the couple data that cascades from it) cannot be destroyed from the client, and `anon` holds no `DELETE`/`TRUNCATE` grant.
   - `v_active_partnership`: Configured with `security_invoker = true`, enforcing that view execution inherits the RLS credentials of the calling user.
2. **RPC Function Restrictions**:
   - `partnership_request(partner_email, partner_code, override_sender_id)`: `SECURITY INVOKER`. **Not executable by clients** — `GRANT EXECUTE` revoked from `PUBLIC`/`anon`/`authenticated` and granted only to `postgres`, `service_role`. The Node backend calls it as `service_role` to create pending rows; clients cannot call it directly. The backend supplies `override_sender_id` from the JWT-verified profile (`auth.controller.js:218`), so an app user cannot choose the sender. A sender who already has a `pending`, `accepted` or `cancelled` row is rejected (`API-VALIDATION-004`), so a cancellation request freezes the member out of new pairings too; the recipient is rejected with the same code when they already hold an `accepted` or `cancelled` row, while several pending invitations to one recipient remain allowed.
   - `partnership_accept(p_partnership_id)`: `SECURITY INVOKER`. It only updates a pending row where `id = p_partnership_id AND user_id_2 = public.user_current_id() AND status = 'pending'` — **recipient-only** (the sender cannot accept their own request). Before that update it refuses a recipient who already holds a different `accepted` or `cancelled` partnership (`API-VALIDATION-012`), so a paired or frozen user cannot end up with a second active row. RLS provides no INSERT policy on `partnerships`, so there is no way for a client to forge an `accepted` row, and the `guard_public_partnerships_status` trigger rejects a direct `UPDATE` of `status` by the sender (`API-VALIDATION-008`) and any `UPDATE` that changes `user_id_1` / `user_id_2` on any row (`API-VALIDATION-009`), so an accepted pair cannot be re-pointed to a third party. The same trigger now whitelists the cancellation states: a member may request (`accepted → cancelled` with themselves as requester and an expiry, `API-VALIDATION-010`) and either member may revert (`cancelled → accepted` with both fields cleared, `API-VALIDATION-011`), while a cancelled row's requester/expiry are immutable (`-012`). The trigger is also the only writer of `cancel_declined_at`: a partner decline (a non-requester revert) records `now()` for the 24h cooldown, while a requester restore, the service-role expiry and every other update keep the stored value. The whitelist applies to raw PostgREST `PATCH` writes as well as the RPCs, so no client can bypass the state rules by writing the table directly.
   - `partnership_reject(p_partnership_id)`: `SECURITY INVOKER`. Deletes a pending row only if the caller is `user_id_1` or `user_id_2` and `status = 'pending'`; the same restriction is enforced on a raw `DELETE` by the `partnerships_delete_own` policy.
   - `partnership_request_cancel(p_partnership_id)`: `SECURITY INVOKER`. It locks the caller's `accepted` row (`FOR UPDATE`), takes `p_partnership_id` only when the caller is `user_id_1` or `user_id_2`, and writes `status = 'cancelled'`, `cancel_requested_by = caller` and `cancel_expires_at = now() + interval '7 days'`. A missing/non-accepted/non-member row raises `API-VALIDATION-010` / SQLSTATE `42501`; a partner decline inside the last 24 hours raises `API-VALIDATION-013` / SQLSTATE `P0001`. Revoked from `PUBLIC`/`anon`; granted to `authenticated`, `postgres`, `service_role`.
   - `partnership_cancel_revert(p_partnership_id)`: `SECURITY INVOKER`. It updates the caller's own `cancelled` row to `accepted` and clears `cancel_requested_by` and `cancel_expires_at`; `cancel_declined_at` is left to the `guard_public_partnerships_status` trigger, which records it when the caller is not the requester and preserves it on a requester restore. A non-member or a row that is not `cancelled` raises `API-VALIDATION-011` / SQLSTATE `42501`. Revoked from `PUBLIC`/`anon`; granted to `authenticated`, `postgres`, `service_role`.
   - `partnership_expire_cancellations()`: `SECURITY DEFINER`, returns the number of rows reverted. Reverts every row with `status = 'cancelled' AND cancel_expires_at <= now()` to `accepted`, clearing both cancel fields and leaving `cancel_declined_at` to the guard trigger (an expiry is not a decline). Backend-only: revoked from `PUBLIC`/`anon`/`authenticated`; granted to `postgres`, `service_role`.
   - `partnership_get_cancellation()`: `SECURITY DEFINER`, the single read for both PartnerScreen cancellation states. Runs `partnership_expire_cancellations()` first (lazy expiry), then returns the caller's `cancelled` row only: `partnership_id`, `partner_id`, `partner_display_name`, `partner_profile_pic_url`, `requested_by_me`. A non-member gets no row, and an expired request is already back to `accepted` by the time the read returns. Revoked from `PUBLIC`/`anon`; granted to `authenticated`, `postgres`, `service_role`.
   - `partnership_cancel_accept(p_partnership_id integer, p_actor_id integer)`: `SECURITY DEFINER`. Validates the row is `cancelled`, `p_actor_id` is a member but not `cancel_requested_by`, and `cancel_expires_at > now()`. Deletes the partnership row (`DELETE FROM partnerships`), which cascades the couple data via existing FK `ON DELETE CASCADE`. Unrelated pending rows are not touched. Invalid/non-member/requester or expired → `API-VALIDATION-012` / SQLSTATE `42501` or `API-VALIDATION-014` / SQLSTATE `P0001`. Backend-only: revoked from `PUBLIC`/`anon`/`authenticated`; granted to `postgres`, `service_role`.
   - `partnership_get_cancellation_partner(p_user_id)`: `SECURITY DEFINER`, backend-only (`postgres`/`service_role`), returns the other member of the `cancelled` row involving `p_user_id`. The Node helper `getCancellationPartnerId()` uses it for the `cancellationRequested` push. `media-complete` resolves the partnership row directly via `getPartnershipId()` (accepted first, then cancelled); `getPartnerId()` stays accepted-only for upload authorization.
3. **Backend Middleware Enforcement**:
   - Endpoint `POST /api/v1/auth/invite` requires `authenticated()`, `limited(authRateLimit)` and `signed("auth-invite")`; the signature stops a stolen JWT from creating pairing rows or spam requests on the caller's behalf.
   - Endpoint `POST /api/v1/auth/invite-user` requires `authenticated()`, `limited(inviteUserRateLimit)` and `signed("auth-invite-user")`; the signature stops a stolen JWT from being used to spray the "Invite user" email.

---

## Discovered Bugs, Defects, and Inconsistencies

During the reverse-engineering analysis, the following technical findings and bugs were identified:

### 1. NOTE: Pairing Requests Deliberately Send No Email

* **WHAT**: The "Invite Partner" flow (email + 6-char code) creates a pending `partnerships` row via `partnership_request` RPC; it does **not** send an email.
* **WHERE**: `invitePartnerController` ([auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js)) and `PartnershipRepository.inviteUser` ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **WHY**: By design — a pairing request requires the recipient to already have a JustUs account, so the request is delivered in-app (PartnerScreen + push notification) instead of by email. Email is reserved for the account-only invite (`/api/v1/auth/invite-user`), which is the only way to reach someone without an account. See § Email Policy.
* **WHEN**: Anytime a user sends a pairing request through the in-app dialog.
* **IMPACT**: The recipient learns about the request from the app or a push notification; the 6-char code is still shared out-of-band.
* **CONFIDENCE**: **HIGH**

---



## Edge Cases

1. **Simultaneous Mutual Invitations**: If User A sends a request to User B, and User B simultaneously sends a request to User A, `partnership_request` RPC handles conflict resolution by checking existing pending records.
2. **Realtime Disconnection during Acceptance**: If Realtime socket drops when partner accepts an invitation, `RealtimeSyncService` fallback timer (polling every 15s) or pull-to-refresh on `PartnerScreen` ensures eventual consistency.
3. **User Deletion / Account Wipe**: `debug_wipe_couple_data` is a debug-only, per-couple reset. It resolves the caller's `accepted` partnership and deletes that couple's shared rows plus both members' user-scoped rows, but it does **not** delete the `partnerships` row — the couple stays linked (login and connection are preserved). A caller with no accepted partnership clears only their own user-scoped rows; pending/cancelled invitations are not a couple and are left untouched.
4. **Third-Party Invitations**: An unpaired user cannot create a pending invitation addressed to someone who already has an `accepted` or `cancelled` partnership: `partnership_request` rejects it with `API-VALIDATION-004` and writes no row, so no phantom invitation reaches the recipient's pending list or fires a push. Pending recipients are still allowed (several simultaneous invitations are legitimate). This closes the old gap where only `partnership_accept` refused the row at accept time (`API-VALIDATION-012`).

---

## Rollout Notes

### Pre-flight check: duplicate accepted rows (2026-10-28)

The old double-accept hole could leave a user holding two `accepted` rows. Before relying on the paired-recipient guard in `partnership_accept`, the linked project was checked with:

```sql
SELECT user_id, count(*) FROM (
  SELECT user_id_1 AS user_id FROM partnerships WHERE status = 'accepted'
  UNION ALL
  SELECT user_id_2 AS user_id FROM partnerships WHERE status = 'accepted'
) t GROUP BY user_id HAVING count(*) > 1;
```

Result: **no rows**. No manual repair was needed, so the guard applies to a clean dataset.

---

## Dependencies

- **Flutter**: `provider`, `supabase_flutter`, `flutter_dotenv`.
- **Backend**: `express`, `zod`, `@supabase/supabase-js`.
- **Database**: PostgreSQL 15+ with Supabase RLS and `pg_graphql` extensions.

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Personal Code Display & Clipboard Copy | **IMPLEMENTED** | `PartnerScreen._buildYourCodeCard` |
| Pending Request Identity | **IMPLEMENTED** | `partnership_get_pending_invitations` RPC (scoped `SECURITY DEFINER`, no direct `users`/`user_profiles` read) |
| Send Request (Email + 6-Char Code) | **IMPLEMENTED** | `partnership_request` RPC |
| View Pending Sent & Received Requests | **IMPLEMENTED** | `partnership_get_pending_invitations` RPC |
| Accept Request Flow | **IMPLEMENTED** | `partnership_accept` RPC + notification |
| Reject Request Flow | **IMPLEMENTED** | `partnership_reject` RPC deletes pending row for caller only |
| Request Cancellation (RPC) | **IMPLEMENTED** | `partnership_request_cancel` RPC: either member, `accepted` only, 24h cooldown (`API-VALIDATION-013`) |
| Cancellation Revert (RPC) | **IMPLEMENTED** | `partnership_cancel_revert` RPC: either member restores `cancelled -> accepted`; a partner revert records the cooldown timestamp |
| Cancellation Expiry (RPC) | **IMPLEMENTED** | `partnership_expire_cancellations` RPC: reverts every expired request; backend-only |
| Cancellation Read (RPC) | **IMPLEMENTED** | `partnership_get_cancellation` RPC: caller's cancelled row + counterpart identity + `requested_by_me`, with lazy expiry |
| Cancellation Push Partner (RPC) | **IMPLEMENTED** | `partnership_get_cancellation_partner` RPC: resolves the ex-partner for the request push; backend-only |
| Cancellation Accept (RPC) | **IMPLEMENTED** | `partnership_cancel_accept` RPC: partner deletes the row and cascades couple data; backend-only |
| Cancellation Acceptance Endpoint | **IMPLEMENTED** | Signed `POST /api/v1/partnership/cancel/accept`: member-but-not-requester only, expired requests revert and return `API-VALIDATION-014`, R2 sweep of both `uploads/<uid>/` prefixes only, `cancellationAccepted` push, DB delete never rolled back |
| Couple-scoped Moods | **IMPLEMENTED** | `moods.partnership_id` FK with `ON DELETE CASCADE`; `mood_set` stores the caller's accepted pair; insert/update require membership; no backfill needed |
| Cancellation Client Calls | **IMPLEMENTED** | `PartnershipRepository.requestCancellation` / `revertCancellation` (RPCs + `cancellationRequested` / `cancellationDeclined` pushes), `acceptCancellation` (signed backend endpoint), `getCancellation` (read RPC); cache cleared before each mutation |
| Cancellation State | **IMPLEMENTED** | `PartnerState.cancellation` fetched with the partnership (fetch + realtime); `AuthState.hasPartner` stays false while cancelled |
| Cancellation Request UI | **IMPLEMENTED** | `ProfileScreen` danger tile (visible only with a partner) -> simple `VPDialog` -> `requestCancellation` -> PartnerScreen; cooldown/errors stay on Profile |
| Cancellation Result UI | **IMPLEMENTED** | Reusable `InvitationTile` for the partner branch (accept with final-deletion dialog, decline), waiting card + restore for the requester, ended copy on deletion/lost response |
| Cancellation Realtime / Reverse Redirect | **IMPLEMENTED** | PK-only DELETE relevance, `ErrorHandler.navigatorKey` redirect from pushed routes once a known request resolves, lost accept response resolved against the accepted-partnership read |
| Invite Partner With No Account | **IMPLEMENTED** | `POST /auth/invite-user` → `admin.inviteUserByEmail()`; hosted "Invite user" email; account-only, no `partnerships` row |
| Realtime State Sync | **IMPLEMENTED** | `RealtimeSyncService` listens to `partnerships` table |
| Automatic Redirection on Login | **IMPLEMENTED** | `SplashScreen` routes based on `partnerState.partner` |

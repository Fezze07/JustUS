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
│  RPCs: partnership_request, partnership_accept                          │
│  Triggers: user_create_from_auth                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [partner_screen.dart](file:///f:/JustUS/Flutter/lib/features/partnership/screens/partner_screen.dart): UI rendering for personal partnership code, partner card, pending received requests, pending sent requests, add partner action, and the "your partner doesn't have Just Us? Invite them now!" entry point.
   - [partner_state.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partner_state.dart): State manager for fetching partnership data, sending/accepting/rejecting requests, and performing optimistic state updates.
   - [partner_invite_dialog.dart](file:///f:/JustUS/Flutter/lib/features/partnership/widgets/partner_invite_dialog.dart): email + 6-char code pairing request. [partner_invite_email_dialog.dart](file:///f:/JustUS/Flutter/lib/features/partnership/widgets/partner_invite_email_dialog.dart): account-only invite (email address only).
   - [partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart): Network client interacting with Supabase client (direct query on `v_active_partnership`, `partnership_get_pending_invitations` RPC, `partnership_accept` RPC, `partnerships` DELETE for rejection) and Node Express API (`_api.inviteUser`, `_api.inviteUnregisteredPartner`).
   - [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart): `AuthState.invitePartner(email, code)` (pairing request) and `AuthState.inviteUnregisteredPartner(email)` (account-only invite; forwards `emailRedirectTo`).
   - [partnership_models.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_models.dart): Data models `PartnershipResponse`, `PendingRequests`, and `PartnershipInvitation`.
   - [refetch_realtime_handler.dart](file:///f:/JustUS/Flutter/lib/core/realtime/refetch_realtime_handler.dart): `RefetchRealtimeHandler` (unified debounced-refetch strategy) subscribes to Postgres change events on `public.partnerships`, debounces 150 ms, invalidates `BaseRepository` cache, and updates `PartnerState` / `AuthState`. Wired by `RealtimeSyncService` (`lib/core/realtime/realtime_sync_service.dart`) with an `isRelevant` predicate + `refetch` closure.

2. **Backend API (Node.js / Express)**:
   - [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js): `invitePartnerController` resolves recipient email + partnership code via `resolveRequestedPartnerOrNull`, checks self-invitation, and calls `adminSupabase.rpc('partnership_request')`. `inviteUserController` calls `adminSupabase.auth.admin.inviteUserByEmail(email, { redirectTo })`, remapping GoTrue's `email_exists` / `user_already_exists` to `409 API-VALIDATION-002`.
   - [auth.schemas.js](file:///f:/JustUS/Backend/features/auth/auth.schemas.js): Zod schemas `inviteSchema` (email format + 6-character partnership code) and `inviteUserSchema` (`email` + optional `redirectTo` URL).

3. **Database Layer (Supabase / PostgreSQL)**:
   - `public.partnerships`: Main database table storing pair relationships with columns `id`, `user_id_1`, `user_id_2`, `status`, `anniversary_date`, `created_at`, `updated_at`.
   - `public.user_profiles`: Stores user profile metadata including unique `partnership_code`.
   - `v_active_partnership`: PostgreSQL view returning the accepted partner's profile details (`partner_id`, `partner_display_name`, `partner_profile_pic_url`).
   - Stored Procedures: `partnership_request(partner_email, partner_code)`, `partnership_accept(p_partnership_id)`, and `partnership_get_pending_invitations()` (pending-request identity for the caller only).

---

## Partnership State Machine & Transitions

### Partnership States

The partnership subsystem defines three logical states per user:

| State | Status Column | Description |
|---|---|---|
| **None** | `none` (or no row) | User has no active partnership and no pending invitations (sent or received). |
| **Pending** | `pending` | A partnership request has been created in `public.partnerships` with `status = 'pending'`, waiting for acceptance or rejection. |
| **Accepted** | `accepted` | An active partnership is established (`status = 'accepted'`). Both users are linked. |

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
  (DELETE partnerships) │                        │ (partnership_accept RPC)
                        ▼                        ▼
                ┌───────────────┐        ┌───────────────┐
                │     NONE      │        │   ACCEPTED    │
                └───────────────┘        └───────────────┘
```

### Transition & Invariant Rules

1. **Request Initiation**:
   - **Who can initiate**: Any authenticated user who does not already have an active or pending partnership.
   - **Self-Invitation Prevention**: A user who names their own email + code is rejected by the backend controller ([auth.controller.js:210](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L210)) with `API-VALIDATION-006`; the same code is raised by the `partnership_request` RPC guard for any direct caller. The client localizes it via `ErrorCodes.userMessage`.
   - **Duplicate Requests**: Prevented by checking existing active/pending records in `partnership_request` RPC (raises `API-VALIDATION-004`).
   - **Recipient Matching**: Initiator must provide **both** the exact target email (case-insensitive) and exact 6-character `partnership_code`; a mismatch raises `API-VALIDATION-005`.

2. **Rejection Handling**:
   - When a user rejects an incoming request or cancels a sent request, Flutter executes a direct SQL `DELETE` on `public.partnerships` where `id = partnershipId` and `status = 'pending'` ([partnership_repository.dart:110](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L110)).
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
| **Flutter Frontend** | `PartnershipRepository.inviteUser()` / `PartnerInviteDialog` | Ask an existing account to connect | HTTP POST to `/api/v1/auth/invite` (email + 6-char code) |
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
                            ├── 1. Filters relevance (RealtimeSyncSession.isRelevantPartnership: checks user_id_1, user_id_2)
                            ├── 2. Deduplicates event key (RealtimeSyncSession.markSeen)
                            ├── 3. Debounces execution (150ms timer)
                           │
                           ▼
Clear local cache (BaseRepository.clearPartnershipCache())
                           │
                           ▼
Trigger UI state refreshes:
  ├── PartnerState.refreshFromRealtime()
  └── AuthState.refreshPartnershipFromRealtime()
```

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
   - `public.partnerships`: SELECT and UPDATE policies restrict access strictly to the two members of the partnership (`user_id_1 = user_current_id() OR user_id_2 = user_current_id()`).
   - `v_active_partnership`: Configured with `security_invoker = true`, enforcing that view execution inherits the RLS credentials of the calling user.
2. **RPC Function Restrictions**:
   - `partnership_request(partner_email, partner_code, override_sender_id)`: `SECURITY INVOKER`. **Not executable by clients** — `GRANT EXECUTE` revoked from `PUBLIC`/`anon` and granted only to `postgres`, `service_role`. The Node backend calls it as `service_role` to create pending rows; clients cannot call it directly. It remains vulnerable to the `override_sender_id` parameter in general, but that is moot since only the backend uses it and the endpoint requires authentication.
   - `partnership_accept(p_partnership_id)`: `SECURITY INVOKER`. It only updates a pending row where `id = p_partnership_id AND user_id_2 = public.user_current_id() AND status = 'pending'` — **recipient-only** (the sender cannot accept their own request). RLS provides no INSERT policy on `partnerships`, so there is no way for a client to forge an `accepted` row, and the `guard_public_partnerships_status` trigger rejects a direct `UPDATE` of `status` by the sender (`API-VALIDATION-008`) and any `UPDATE` that changes `user_id_1` / `user_id_2` on any row (`API-VALIDATION-009`), so an accepted pair cannot be re-pointed to a third party.
   - `partnership_reject(p_partnership_id)`: `SECURITY INVOKER`. Deletes a pending row only if the caller is `user_id_1` or `user_id_2` and `status = 'pending'`.
3. **Backend Middleware Enforcement**:
   - Endpoint `POST /api/v1/auth/invite` requires `authenticated()` middleware, verifying valid JWT authentication before processing request logic. The backend resolves the recipient and calls `partnership_request` via `service_role`.
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
3. **User Deletion / Account Wipe**: When `debug_wipe_user_data` RPC is called, associated `partnerships` records are deleted via database foreign key cascading (`ON DELETE CASCADE`), resetting linked partner states back to **None**.

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
| Invite Partner With No Account | **IMPLEMENTED** | `POST /auth/invite-user` → `admin.inviteUserByEmail()`; hosted "Invite user" email; account-only, no `partnerships` row |
| Realtime State Sync | **IMPLEMENTED** | `RealtimeSyncService` listens to `partnerships` table |
| Automatic Redirection on Login | **IMPLEMENTED** | `SplashScreen` routes based on `partnerState.partner` |

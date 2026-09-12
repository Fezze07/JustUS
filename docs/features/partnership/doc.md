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
│  POST /api/v1/auth/invite-partner     │            │
│  (Validates input, checks self-invite,│            │
│   invokes request_partnership RPC)    │            │
└────────────────────┬──────────────────┘            │
                     │ Service Role /                │
                     │ RPC Delegation                │
                     ▼                               │
┌────────────────────────────────────────────────────┴────────────────────┐
│                             SUPABASE LAYER                              │
│  Tables: public.partnerships, public.users, public.user_profiles        │
│  View: v_active_partnership (security_invoker = true)                   │
│  RPCs: request_partnership, accept_partnership                          │
│  Triggers: handle_new_auth_user                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [partner_screen.dart](file:///f:/JustUS/Flutter/lib/features/partnership/screens/partner_screen.dart): UI rendering for personal partnership code, partner card, pending received requests, pending sent requests, and add partner action.
   - [partner_state.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partner_state.dart): State manager for searching users, fetching partnership data, handling debounced search, and performing optimistic state updates.
   - [partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart): Network client interacting with Supabase client (direct query on `v_active_partnership`, `accept_partnership` RPC, `partnerships` DELETE for rejection) and Node Express API (`_api.requestPartnership`).
   - [partnership_models.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_models.dart): Data models `PartnershipResponse`, `PendingRequests`, and `PartnershipInvitation`.
   - [realtime_sync_service.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart): Subscribes to Postgres change events on `public.partnerships`, invalidates `BaseRepository` cache, and updates `PartnerState` / `AuthState`.

2. **Backend API (Node.js / Express)**:
   - [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L164-L182): Handles `invitePartnerController`. Resolves recipient email + partnership code via `resolveRequestedPartnerOrNull`, checks self-invitation, and calls `adminSupabase.rpc('request_partnership')`.
   - [auth.schemas.js](file:///f:/JustUS/Backend/features/auth/auth.schemas.js#L23-L27): Zod schema `invitePartnerSchema` enforcing email format and 6-character partnership code length.

3. **Database Layer (Supabase / PostgreSQL)**:
   - `public.partnerships`: Main database table storing pair relationships with columns `id`, `user_id_1`, `user_id_2`, `status`, `anniversary_date`, `created_at`, `updated_at`.
   - `public.user_profiles`: Stores user profile metadata including unique `partnership_code`.
   - `v_active_partnership`: PostgreSQL view returning active partner details, pending sent array (`pending_sent`), and pending received array (`pending_received`).
   - Stored Procedures: `request_partnership(partner_email, partner_code)` and `accept_partnership(p_partnership_id)`.

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
                                    │ Send Request (request_partnership RPC)
                                    ▼
                ┌────────────────────────────────────────┐
                │                PENDING                 │
                └───────┬────────────────────────┬───────┘
                        │                        │
  Reject Request        │                        │ Accept Request
  (DELETE partnerships) │                        │ (accept_partnership RPC)
                        ▼                        ▼
                ┌───────────────┐        ┌───────────────┐
                │     NONE      │        │   ACCEPTED    │
                └───────────────┘        └───────────────┘
```

### Transition & Invariant Rules

1. **Request Initiation**:
   - **Who can initiate**: Any authenticated user who does not already have an active or pending partnership.
   - **Self-Invitation Prevention**: Enforced at the backend controller level ([auth.controller.js:169](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L169)) throwing `API_VALIDATION_001` ("Non puoi invitare te stesso").
   - **Duplicate Requests**: Prevented by checking existing active/pending records in `request_partnership` RPC.
   - **Recipient Matching**: Initiator must provide **both** the exact target email (case-insensitive) and exact 6-character `partnership_code`.

2. **Rejection Handling**:
   - When a user rejects an incoming request or cancels a sent request, Flutter executes a direct SQL `DELETE` on `public.partnerships` where `id = partnershipId` and `status = 'pending'` ([partnership_repository.dart:110](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L110)).
   - The row is permanently removed from the database. The system transitions back to the **None** state.

3. **Acceptance Handling**:
   - When a recipient accepts a request, Flutter invokes PostgreSQL stored procedure `accept_partnership(p_partnership_id)` ([partnership_repository.dart:97](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L97)).
   - The RPC updates `public.partnerships`:
     - Sets `status = 'accepted'`.
     - Sets `anniversary_date = CURRENT_DATE`.
     - Updates `updated_at = CURRENT_TIMESTAMP`.
   - The system transitions to the **Accepted** state.

4. **Multiple Active Partnerships**:
   - **NOT PERMITTED**. The system architecture enforces a strict 1:1 pairing constraint. The database view `v_active_partnership` and application logic treat partnership as a single 1:1 relationship.

5. **`v_active_partnership` Resolution Logic**:
   - The view filters `public.partnerships` where the querying user is either `user_id_1` or `user_id_2`.
   - If an `accepted` row exists, it returns `status = 'accepted'` along with the partner's profile (`partner_id`, `partner_display_name`, `partner_profile_pic_url`, `partner_bio`).
   - If only `pending` rows exist, it aggregates outgoing requests into `pending_sent` (JSONB array) and incoming requests into `pending_received` (JSONB array).

---

## Partnership Code Specification & Security

Each user profile automatically receives a unique **Partnership Code** upon registration.

### Properties & Constraints

- **Length**: Exactly 6 characters ([auth.schemas.js:25](file:///f:/JustUS/Backend/features/auth/auth.schemas.js#L25)).
- **Allowed Characters**: Upper-case alphanumeric strings (e.g., `ABC123`).
- **Generation**: Created automatically inside database trigger `handle_new_auth_user()` on user profile creation.
- **Uniqueness**: Enforced at the database schema level by a `UNIQUE` constraint on `user_profiles.partnership_code` ([supabase-schema](file:///f:/JustUS/.agents/skills/supabase-schema/SKILL.md#L150)).
- **Expiration & Reuse**: The code is static and tied permanently to the `user_profiles` record. It does not expire and cannot be changed or reused by another user.
- **Brute-Force Resistance**:
  - A partnership code alone is insufficient to send a request.
  - The request payload requires **both** `email` AND `partnershipCode`.
  - In `auth.controller.js`, `resolveRequestedPartnerOrNull` queries `users` by email and `user_profiles` by `partnership_code`. If either fails to match, the request fails silently or returns null, preventing code enumeration attacks.

---

## Email Invitation Flow: Declared Capability vs. Implemented Functionality

The codebase contains references to an "email invitation flow", but reverse engineering reveals a clear discrepancy between declared capabilities and actual implementation:

| Layer | Component | Declared Capability | Actual Implementation |
|---|---|---|---|
| **Flutter Frontend** | `PartnershipRepository.inviteUser()` | "Send invitation via email and code" | Sends HTTP POST to `/api/v1/auth/invite-partner` |
| **Backend API** | `POST /api/v1/auth/invite-partner` | "Invite Partner API endpoint" | Validates input, resolves user in DB, and invokes RPC `request_partnership` |
| **Backend Mailer** | SMTP / SendGrid / Resend / Nodemailer | External email delivery to recipient | **NOT IMPLEMENTED**. No mailer service, SMTP configuration, or email templates exist for invitations in `Backend/` |
| **Supabase** | `request_partnership` RPC | Database request creation | Inserts row into `public.partnerships` with `status = 'pending'` |

> [!IMPORTANT]
> **Finding**: The email invitation feature does **not** send external emails to target users. It is an in-app request mechanism that creates a pending record in `public.partnerships`. Target users only see the request when they log in to the application.

---

## Functional Behavior & User Flow

### 1. Searching for Partners (Email Debounce)
- **User Action**: In `PartnerScreen`, user types a recipient email into the search text field.
- **Debounce Mechanism**: `PartnerState.setEmailQuery()` ([partner_state.dart:30-40](file:///f:/JustUS/Flutter/lib/features/partnership/partner_state.dart#L30-L40)) manages a `Timer` with a **300ms debounce delay**.
- **Execution**: When the timer fires, `_fetchSuggestions()` invokes `PartnershipRepository.searchPartner(query)` which performs a Supabase ILIKE query: `users.select().or('email.ilike.%$query%').limit(20)`.

### 2. Sending a Request
- **User Action**: User opens `PartnerInviteDialog`, enters the partner's email and 6-character code, and taps "Send".
- **Validation**: Client validates inputs are non-empty (`partner_fillAllFields`). Backend validates schema (`email`, `partnershipCode.length(6)`).
- **Execution**: Calls `POST /api/v1/auth/invite-partner` -> Backend checks `resolveRequestedPartnerOrNull` -> Checks self-invitation -> Calls `adminSupabase.rpc('request_partnership')`.
- **UI Update**: Flutter receives success response, calls `fetchPartnership()`, re-populates `sentRequests`, and shows SnackBar ("Richiesta inviata a $email").

### 3. Receiving & Viewing Requests
- **UI Element**: `PartnerScreen` renders `_buildInvitationsList` with `receivedInvitations` and `sentInvitations`.
- **Item Cards**: Display partner display name / email and timestamp. Provides "Accept" (Check icon) and "Reject" (Close icon) buttons.

### 4. Accepting a Request
- **User Action**: User taps "Accept" on a received invitation tile.
- **Execution**: Calls `AuthState.acceptInvitation(invite.id)` -> Invokes `PartnershipRepository.acceptPartnerRequest(invite.id)` -> Runs Supabase RPC `accept_partnership(p_partnership_id = invite.id)`.
- **Side Effects**:
  - Triggers asynchronous partner push notification (`notifyPartnerOnce`, key `requestAccepted`).
  - Calls `fetchPartnership()` and `ProfileState.loadProfile(force: true)`.
  - Calls `StorageService.savePartner` to store partner ID and username locally.
  - Replaces navigation stack with `MainShell`.

### 5. Rejecting a Request
- **User Action**: User taps "Decline" or "Cancel Request".
- **Execution**: Calls `AuthState.rejectInvitation(invite.id)` -> Runs `PartnershipRepository.rejectPartnerRequest(invite.id)` -> Deletes row from `public.partnerships` where `id = invitationId` and `status = 'pending'`.
- **UI Update**: Pending invitation is removed from local list.

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
RealtimeSyncService._handlePartnershipPayload()
                           │
                           ├── 1. Filters relevance (_isRelevantPartnership: checks user_id_1, user_id_2)
                           ├── 2. Deduplicates event key (_markSeen)
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

App entry navigation routing is governed by `SplashScreen` ([splash_screen.dart:22-55](file:///f:/JustUS/Flutter/lib/features/auth/screens/splash_screen.dart#L22-L55)):

1. App launches and calls `AuthState.init()`.
2. Checks `AuthState.isLoggedIn`:
   - `false` -> Navigate to `LoginScreen`.
   - `true` -> Execute `PartnerState.fetchPartnership()`.
3. Checks `PartnerState.partner`:
   - `partner != null` (Accepted partnership exists) -> Navigate to `MainShell`.
   - `partner == null` (No active partnership) -> Navigate to `PartnerScreen`.

---

## Security & Authorization Boundaries

1. **Row Level Security (RLS)**:
   - `public.partnerships`: SELECT and UPDATE policies restrict access strictly to the two members of the partnership (`user_id_1 = current_user_id() OR user_id_2 = current_user_id()`).
   - `v_active_partnership`: Configured with `security_invoker = true`, enforcing that view execution inherits the RLS credentials of the calling user.
2. **RPC Function Restrictions**:
   - `accept_partnership`: Configured with `SECURITY INVOKER`, checking that the caller is a valid member of the target partnership row before applying the `accepted` status update.
3. **Backend Middleware Enforcement**:
   - Endpoint `POST /api/v1/auth/invite-partner` requires `authenticated()` middleware, verifying valid JWT authentication before processing request logic.

---

## Discovered Bugs, Defects, and Inconsistencies

During the reverse-engineering analysis, the following technical findings and bugs were identified:

### 1. DEFECT: Optimistic Rejection Filter ID Mismatch in `PartnerState`

* **WHAT**: `PartnerState.rejectPartner(int partnershipId)` fails to correctly remove the rejected request from `receivedRequests` in local state.
* **WHERE**: [partner_state.dart:128-131](file:///f:/JustUS/Flutter/lib/features/partnership/partner_state.dart#L128-L131)
  ```dart
  received: receivedRequests.where((u) => u.id != partnershipId).toList(),
  ```
* **WHY**: `receivedRequests` contains `User` instances mapped via `PartnershipResponse.fromJson`. `u.id` represents the **partner's user ID** (`m['user_id']`), whereas `partnershipId` is the **primary key of the `partnerships` table**. Comparing `u.id != partnershipId` compares two distinct identifier domains, causing the filter to fail to match or mistakenly remove the wrong entry.
* **WHEN**: Happens every time a user declines an incoming invitation from `PartnerState`.
* **IMPACT**: UI fails to update optimistically after rejecting a request, requiring a manual swipe-to-refresh to clear the item.
* **CONFIDENCE**: **HIGH**

### 2. INCONSISTENCY: Declared Email Invitation vs. RPC-Only Backend

* **WHAT**: The feature is labeled "Invite Partner via Email", but no emails are sent.
* **WHERE**: [auth.controller.js:164-182](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L164-L182) and [partnership_repository.dart:53-59](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L53-L59)
* **WHY**: The backend controller invokes `adminSupabase.rpc('request_partnership')` directly. No email transport service (e.g. Nodemailer, Resend) is integrated.
* **WHEN**: Happens whenever a user expects an email notification to be delivered to an offline target partner.
* **IMPACT**: Users inviting unregistered or offline partners expect an email to be sent, but nothing is delivered externally.
* **CONFIDENCE**: **HIGH**

### 3. DEFECT: Asymmetrical Database Operation for Request Rejection

* **WHAT**: Request acceptance uses a stored procedure (`accept_partnership` RPC), while request rejection performs direct table modification (`sbClient.from('partnerships').delete()`).
* **WHERE**: [partnership_repository.dart:97 & 111](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart#L97)
* **WHY**: Inconsistency in database encapsulation patterns. Rejection relies on direct RLS DELETE policies on `public.partnerships`, whereas acceptance relies on RPC logic.
* **WHEN**: Executing accept vs reject actions in `PartnershipRepository`.
* **IMPACT**: Maintenance complexity and divergence in error handling / logging auditing paths.
* **CONFIDENCE**: **MEDIUM**

---

## Edge Cases

1. **Simultaneous Mutual Invitations**: If User A sends a request to User B, and User B simultaneously sends a request to User A, `request_partnership` RPC handles conflict resolution by checking existing pending records.
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
| Partner Search with Email Debounce | **IMPLEMENTED** | 300ms Timer in `PartnerState` |
| Send Request (Email + 6-Char Code) | **IMPLEMENTED** | `request_partnership` RPC |
| View Pending Sent & Received Requests | **IMPLEMENTED** | `v_active_partnership` view aggregation |
| Accept Request Flow | **IMPLEMENTED** | `accept_partnership` RPC + notification |
| Reject Request Flow | **PARTIALLY IMPLEMENTED** | DB deletion works, but optimistic UI filter has ID mismatch bug |
| External Email Delivery | **NOT IMPLEMENTED** | Labeled as email invite, but only performs DB request insertion |
| Realtime State Sync | **IMPLEMENTED** | `RealtimeSyncService` listens to `partnerships` table |
| Automatic Redirection on Login | **IMPLEMENTED** | `SplashScreen` routes based on `partnerState.partner` |

# Supabase Database-Side Logic & Automation Analysis

## Overview

This document provides a technical specification and analysis of all **Supabase-side database logic** in the JustUS platform. It details database views, PostgreSQL Stored Procedures (RPCs), triggers, automated maintenance jobs, and integrity enforcement logic running directly on the database engine.

---

## 1. Database Views

### `v_active_partnership`
* **SQL Source:** `supabase/schemas/public/views/v_active_partnership.sql`
* **Purpose:** Provides a single, unified view of the current user's active relationship, including status, anniversary date, and the partner's profile details (display name, profile picture). The partner's `users` row is intentionally not read.
* **Security Context:** `WITH (security_invoker = true)`
  - Inherits RLS policies of underlying tables (`partnerships`, `user_profiles`) based on the authenticated caller's JWT token.
* **Inputs:** None (Implicitly uses `public.user_current_id()` derived from `auth.uid()`).
* **Outputs:** `partnership_id`, `status`, `anniversary_date`, `partner_id`, `partner_display_name`, `partner_profile_pic_url`, `user_id_a`, `user_id_b`.
* **Tables Touched:** `public.partnerships` (READ), `public.user_profiles` (READ).
* **Execution Condition:** `(user_id_1 = user_current_id() OR user_id_2 = user_current_id()) AND status = 'accepted'`.
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **Side Effects:** None (Read-only view).
* **Failure Behavior:** Returns 0 rows if no active accepted partnership exists for the executing user.

---

### `v_drive_dashboard`
* **SQL Source:** `supabase/schemas/public/views/v_drive_dashboard.sql`
* **Purpose:** Aggregates drive files and folders with file type metadata, current user bookmark status (`is_favorite`), and aggregated user emoji reactions (`reactions`).
* **Security Context:** `WITH (security_invoker = true)`
* **Inputs:** Implicitly relies on `public.user_current_id()`.
* **Outputs:** `id`, `partnership_id`, `name`, `original_name`, `type`, `size`, `created_at`, `updated_at`, `extension`, `mime_type`, `icon_slug`, `is_favorite` (boolean), `reactions` (JSON array of `{ user_id, emoji_char }`).
* **Tables Touched:** `public.drive_items` (READ), `public.drive_file_types` (READ), `public.favorites` (READ), `public.drive_item_reactions` (READ), `public.emojis` (READ).
* **Execution Condition:** Filtered by `public.partnership_is_member(d.partnership_id)`.
* **Caller:** Flutter Frontend ([drive_repository.dart](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart)).
* **Side Effects:** None (Read-only view).

---

## 2. Stored Procedures (RPC Functions)

### `partnership_request(partner_email text, partner_code text, override_sender_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_request.sql`
* **Purpose:** Initiates a new relationship connection request between two users.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`, `anon`, `authenticated`. Granted to `postgres`, `service_role`.
  - Invoked only by the backend through the `service_role` client (`adminSupabase.rpc`), which bypasses RLS for the recipient lookup. Clients cannot execute it: they lack the grant, and there is no INSERT policy on `partnerships`.
* **Inputs:** `partner_email` (`text`), `partner_code` (`text`), `override_sender_id` (`integer` DEFAULT NULL, backend-only: supplied from the JWT-verified profile).
* **Outputs:** `integer` (ID of created `partnerships` row).
* **Tables Touched:** `public.partnerships` (READ, INSERT), `public.users` (READ), `public.user_profiles` (READ).
* **Execution Conditions & Validation Rules:**
  1. Identifies the sender via `override_sender_id` (backend-supplied) or `public.user_current_id()`.
  2. Raises EXCEPTION if user is not authenticated (`API-VALIDATION-003`).
  3. Checks if user is already in a `'pending'`, `'accepted'` or `'cancelled'` partnership. Raises EXCEPTION if true (`API-VALIDATION-004`).
  4. Looks up recipient matching BOTH `email = partner_email` and `partnership_code = UPPER(partner_code)`. Raises EXCEPTION if not found (`API-VALIDATION-005`).
  5. Prevents self-invitation (`v_partner_id = v_current_user_id`). Raises EXCEPTION (`API-VALIDATION-006`).
* **Error Contract:** Every raise is `RAISE EXCEPTION '<CODE>: <developer text>';`. `wrapRpc` ([dbUtils.js](file:///f:/JustUS/Backend/utils/db/dbUtils.js)) reads the code prefix and turns it into an `AppError` with that code, so the client localizes it through `ErrorCodes.userMessage` (see [localization/doc.md](file:///f:/JustUS/docs/app/localization/doc.md)). The text after the prefix is a developer-facing note only; it never reaches the UI.
* **Caller:** Node backend (`invitePartnerController` in [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js)) through the `service_role` client.
* **Side Effects:** Inserts a row in `public.partnerships` with `status = 'pending'`.

---

### `partnership_accept(p_partnership_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_accept.sql`
* **Purpose:** Accepts a pending partnership request and establishes the anniversary date.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`, `anon`. Granted to `authenticated`, `postgres`, `service_role`.
* **Inputs:** `p_partnership_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `public.partnerships` (UPDATE).
* **Execution Conditions:** Updates row where `id = p_partnership_id`, caller is member (`user_id_1` or `user_id_2`), and `status = 'pending'`. Sets `status = 'accepted'` and `anniversary_date = CURRENT_DATE`. When the row is pending and the caller is `user_id_2`, a different `accepted` or `cancelled` partnership of the caller raises `API-VALIDATION-012` with SQLSTATE `42501` and leaves the row pending.
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **Side Effects:** Mutates partnership state to `'accepted'`.

---

### `partnership_request_cancel(p_partnership_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_request_cancel.sql`
* **Purpose:** Requests the cancellation of the caller's accepted partnership without deleting anything.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`; RLS limits the row to the two members.
* **Inputs:** `p_partnership_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `public.partnerships` (SELECT `FOR UPDATE`, UPDATE).
* **Execution Conditions:** Locks the row where `id = p_partnership_id`, `status = 'accepted'`, and the caller is `user_id_1` or `user_id_2`. Zero rows raise `API-VALIDATION-010` with SQLSTATE `42501`. A `cancel_declined_at` inside the last 24 hours raises `API-VALIDATION-013` with SQLSTATE `P0001`. Otherwise sets `status = 'cancelled'`, `cancel_requested_by = caller`, `cancel_expires_at = now() + interval '7 days'`.
* **Caller:** none yet; granted to `authenticated` for the cancellation flow.
* **Side Effects:** Freezes the partnership until a member reverts or the request expires; no row or couple data is deleted.

---

### `partnership_cancel_revert(p_partnership_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_cancel_revert.sql`
* **Purpose:** Reverts a cancellation request: the requester restores the pair or the partner declines it.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`; RLS limits the row to the two members.
* **Inputs:** `p_partnership_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `public.partnerships` (UPDATE).
* **Execution Conditions:** Updates the row where `id = p_partnership_id`, `status = 'cancelled'`, and the caller is `user_id_1` or `user_id_2`; sets `status = 'accepted'` and clears `cancel_requested_by` / `cancel_expires_at`. Zero rows raise `API-VALIDATION-011` with SQLSTATE `42501`. `cancel_declined_at` is not written here: the guard trigger records it on a partner decline and preserves it on a requester restore.
* **Caller:** none yet; granted to `authenticated` for the cancellation flow.
* **Side Effects:** Unfreezes the partnership; no data is deleted.

---

### `partnership_expire_cancellations()`
* **SQL Source:** `supabase/schemas/public/functions/partnership_expire_cancellations.sql`
* **Purpose:** Reverts every expired cancellation request in one statement, so a stale request cannot freeze a pair forever.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'` (the backend/expiry job calls it without a user JWT). Not executable by `authenticated` or `anon`.
* **Inputs:** none.
* **Outputs:** `integer` — the number of rows reverted.
* **Tables Touched:** `public.partnerships` (UPDATE).
* **Execution Conditions:** Reverts every row with `status = 'cancelled'` and `cancel_expires_at <= now()` to `status = 'accepted'`, clearing `cancel_requested_by` / `cancel_expires_at`. `cancel_declined_at` is not written: the guard trigger preserves it, so an expiry never counts as a decline.
* **Caller:** none yet; intended for the backend expiry job on `service_role`.
* **Side Effects:** Unfreezes expired pairs; no row or couple data is deleted.

---

### `partnership_get_cancellation()`
* **SQL Source:** `supabase/schemas/public/functions/partnership_get_cancellation.sql`
* **Purpose:** One scoped read for both PartnerScreen cancellation states, so the client renders "you requested the cancellation" or "your partner requested it" without touching `partnerships` or `user_profiles` directly.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`. The result is filtered by `public.user_current_id()`, so a non-member (or a caller with no session) gets no row.
* **Inputs:** none.
* **Outputs:** `TABLE (partnership_id integer, partner_id integer, partner_display_name text, partner_profile_pic_url text, requested_by_me boolean)`.
* **Tables Touched:** `public.partnerships` (UPDATE via the expiry sweep, then SELECT), `public.user_profiles` (SELECT).
* **Execution Conditions:** Calls `partnership_expire_cancellations()` first, then returns the caller's `cancelled` row and the counterpart's profile fields. `requested_by_me` is true when `cancel_requested_by` is the caller. An expired request is reverted by the sweep, so the read returns no row and the pair is already back to `accepted`.
* **Caller:** PartnerScreen via the `partnership_get_cancellation` RPC (`authenticated`); granted to `authenticated`, `postgres`, `service_role` and revoked from `PUBLIC`, `anon`.
* **Side Effects:** May revert the caller's expired request (and any other expired request) to `accepted`; deletes nothing.

---

### `partnership_get_cancellation_partner(p_user_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_get_cancellation_partner.sql`
* **Purpose:** Lets the backend address the cancellation-request push to the other member of a cancelled pair, without a client-readable "who is my ex-partner" lookup.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`, `STABLE`. Backend-only: not executable by `authenticated` or `anon`.
* **Inputs:** `p_user_id integer`.
* **Outputs:** `integer` — the other member's user id, or NULL when the user has no `cancelled` row.
* **Tables Touched:** `public.partnerships` (SELECT).
* **Execution Conditions:** Selects the most recent (`id DESC`) `cancelled` row where `p_user_id` is `user_id_1` or `user_id_2` and returns the opposite member; accepted/pending rows are ignored.
* **Caller:** none yet; intended for the backend request push on `service_role`.
* **Side Effects:** Read-only.

---

### `partnership_cancel_accept(p_partnership_id integer, p_actor_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_cancel_accept.sql`
* **Purpose:** The only path that destroys couple data. Accepts a cancellation on behalf of the partner who did not request it.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`. Backend-only; not executable by `authenticated` or `anon`.
* **Inputs:** `p_partnership_id integer`, `p_actor_id integer`.
* **Outputs:** `void`.
* **Tables Touched:** `public.partnerships` (SELECT FOR UPDATE, DELETE). Deletions cascade via `ON DELETE CASCADE` to `drive_items`, `bucket_items`, `game_questions`, `game_answers`, `missyou`, `moods` and related tables.
* **Execution Conditions:** Locks the row; requires `status = 'cancelled'`, `p_actor_id` is a member, `p_actor_id <> cancel_requested_by`, and `cancel_expires_at > now()`. Otherwise raises `API-VALIDATION-012` / SQLSTATE `42501` (not found/wrong status/wrong actor/requester) or `API-VALIDATION-014` / SQLSTATE `P0001` (expired). Deletes only that partnership row; unrelated pending rows are not touched.
* **Caller:** backend endpoint on `service_role` (B.6 wiring later).
* **Side Effects:** Permanently deletes the couple and all cascaded couple data; no restore path.

---

### `debug_wipe_user_data(p_user_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/debug_wipe_user_data.sql`
* **Purpose:** Developer-only cleanup procedure, invoked from the debug-build profile screen to reset test data. Permanently deletes all partnership-related content and user data for both partners in a relationship. The `debug_` name prefix is deliberate — this is not a production account-deletion feature (10.17, see `docs/fixing-phase-log.md` § Item index).
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`, `anon`. Granted strictly to `postgres`, `service_role`.
* **Inputs:** `p_user_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `partnerships` (READ), `drive_items` (DELETE), `bucket_items` (DELETE), `game_questions` (DELETE), `game_answers` (DELETE), `missyou` (DELETE), `favorites` (DELETE), `drive_item_reactions` (DELETE), `moods` (DELETE), `user_profiles` (UPDATE), `logs_notifications` (DELETE).
* **Caller:** Backend `POST /api/v1/users/wipe` (`wipeUserDataController`) via `service_role`; reached from the debug-build profile screen only.
* **Side Effects:** Massive destructive purge of user & partner files, games, bucket list items, reactions, moods, notifications, and profile details (picture reset to NULL).

---

### `partnership_get_names(p_user_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/partnership_get_names.sql`
* **Purpose:** Retrieves the display names of both members of an active accepted partnership.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`. Granted strictly to `postgres`, `service_role`.
* **Inputs:** `p_user_id` (`integer`).
* **Outputs:** `jsonb` (`{ "name1": "...", "name2": "..." }`).
* **Tables Touched:** `partnerships` (READ), `user_profiles` (READ).
* **Caller:** No current application caller. It is granted only to `postgres`/`service_role`; the removed AI question flow was its last consumer. Game option labels are now resolved client-side from the partnership/display-name data via `resolvePlayerName`.
* **Failure Behavior:** If no active accepted partnership is found, returns fallback object `{ "name1": "Partner 1", "name2": "Partner 2" }`.

---

### `partnership_get_pending_invitations()`
* **SQL Source:** `supabase/schemas/public/functions/partnership_get_pending_invitations.sql`
* **Purpose:** Returns the caller's pending partnership invitations (both sent and received) without exposing another user's full `users`/`user_profiles` row.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`, `anon`. Granted to `authenticated`, `postgres`, `service_role`.
* **Inputs:** None (scoped to `public.user_current_id()`).
* **Outputs:** table rows of `invitation_id`, `status`, `created_at`, `partner_id`, `partner_display_name`, `is_received` (true when the caller is the recipient).
* **Tables Touched:** `partnerships` (READ), `user_profiles` (READ).
* **Execution Condition:** Rows where the caller is `user_id_1` or `user_id_2` and `status = 'pending'`. Returns 0 rows otherwise.
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart), `getPendingInvitations`).
* **Failure Behavior:** Never returns unrelated users; the only identity fields exposed are `display_name` and `email` of the pending counterpart.

---

### `missyou_send()`
* **SQL Source:** `supabase/schemas/public/functions/missyou_send.sql`
* **Purpose:** Inserts a "Miss You" signal for the caller's active relationship.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** None.
* **Outputs:** `void`.
* **Tables Touched:** `partnerships` (READ), `missyou` (INSERT).
* **Execution Condition:** Requires active partnership (`status = 'accepted'`). Raises EXCEPTION (`API-VALIDATION-007`) if missing. Called directly from the client, so the code is resolved by `ErrorCodes.resolveServerCode` ([error_codes.dart](file:///f:/JustUS/Flutter/lib/core/error_handling/error_codes.dart)).
* **Caller:** Flutter Frontend ([missyou_repository.dart](file:///f:/JustUS/Flutter/lib/features/home/missyou_repository.dart)).

---

### `mood_set(p_emoji_char text)`
* **SQL Source:** `supabase/schemas/public/functions/mood_set.sql`
* **Purpose:** Records user mood state by looking up or dynamically registering the emoji character and attaching the caller's `accepted` partnership id (NULL when unpaired).
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** `p_emoji_char` (`text`).
* **Outputs:** `void`.
* **Tables Touched:** `emojis` (READ, INSERT via `emoji_get_or_create`), `partnerships` (READ), `moods` (INSERT).
* **Caller:** Flutter Frontend ([mood_repository.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart)).

---

### `partnership_generate_code()`
* **SQL Source:** `supabase/schemas/public/functions/partnership_generate_code.sql`
* **Purpose:** Generates a random 6-character uppercase alphanumeric code and verifies unicity against `user_profiles`.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
  - **Execution Grants:** Backend-only. Revoked from `PUBLIC`, `anon`, `authenticated`. Granted to `postgres`, `service_role`; `user_create_from_auth()` reaches it as the function owner, so the sign-up trigger is unaffected.
* **Outputs:** `text` (e.g. `'A8F3K9'`).
* **Tables Touched:** `user_profiles` (READ).
* **Caller:** Internal database helper called by `user_create_from_auth()`.

---

### `logs_cleanup(p_days integer DEFAULT 90)`
* **SQL Source:** `supabase/schemas/public/functions/logs_cleanup.sql`
* **Purpose:** Database maintenance. Deletes API access logs, error logs, security events, and notification logs older than `p_days` days (default **90**, matching the Node `LOG_RETENTION_DAYS` window).
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
  - **Execution Grants:** Backend-only. Revoked from `PUBLIC`, `anon`, `authenticated`. Granted to `postgres`, `service_role`.
* **Inputs:** `p_days` (default `90`); raises an exception when NULL or `< 1`.
* **Outputs:** `void`.
* **Tables Touched:** `logs_api_access` (DELETE), `logs_api_errors` (DELETE), `logs_security_events` (DELETE), `logs_notifications` (DELETE).
* **Execution Condition:** `created_at < NOW() - make_interval(days => p_days)`.
* **Caller:** Not `pg_cron`-scheduled. Node.js `retentionJob.js` (`sweepOldLogs`) is the single active retention driver (daily, `LOG_RETENTION_DAYS = 90`); the SQL function may be invoked manually with the same 90-day default.

---

## 3. Database Triggers & System Automation

### Trigger 1: User Sign-Up Automation (`on_auth_user_created`)
* **Event:** `AFTER INSERT ON auth.users`
* **Target Function:** `user_create_from_auth()` (`SECURITY DEFINER`, `SET search_path TO 'public'`)
* **Grants:** Execution REVOKED from `PUBLIC`. Granted to `postgres`, `service_role`.
* **Automated Workflow:**
  1. Inserts new record into `public.users (auth_id, email)` using `NEW.id` and `NEW.email`.
  2. Generates unique 6-character partnership code via `public.partnership_generate_code()`.
  3. Inserts initial profile into `public.user_profiles` setting `display_name = split_part(email, '@', 1)` and `partnership_code`.
  4. Fetches ID for role `'user'` from `public.roles`. If missing, inserts default role `'user'`.
  5. Assigns role to user in `public.user_roles (user_id, role_id)`.
* **Side Effects:** Automatically initializes full public profile, partnership code, and RBAC role instantly upon Supabase Auth registration without client interaction.

---

### Trigger 2: Automatic Timestamp Maintenance
* **Event:** `BEFORE UPDATE`
* **Target Function:** `util_set_updated_at()`
* **Applied Tables:** `users`, `user_profiles`, `partnerships`, `user_roles`, `drive_items`.
* **Action:** Automatically updates `NEW.updated_at = NOW()`.

---

### Trigger 3: Game Question Completion (`tr_game_answers_update_question_status`)
* **Event:** `AFTER INSERT OR UPDATE ON public.game_answers`
* **Target Function:** `game_update_question_status()` (`SECURITY DEFINER`, `SET search_path TO 'public'`, returns `trigger`)
* **Grants:** Execution REVOKED from `PUBLIC`, `anon`, `authenticated`. Granted to `postgres`, `service_role` only — PostgreSQL does not check `EXECUTE` when firing a trigger, so no client role requires it.
* **Action:** When `COUNT(game_answers WHERE game_id = NEW.game_id) >= 2`, sets the matching `game_questions.status` to `'both_answered'`.
* **Side Effects:** Moves the `both_answered` transition off the client entirely, so a second player disconnecting before acknowledging no longer leaves the question stuck at `'pending'`. The resulting `game_questions` UPDATE is emitted on the realtime channel and consumed by `handleQuestionUpdate`; the game's answer INSERT and this status UPDATE can land within the same 150 ms burst, which the `GameEventBuffer` FIFO flush replays in delivery order.

---

### Trigger 4: User Identity Immutability (`guard_public_users_identity`)
* **Event:** `BEFORE UPDATE ON public.users`
* **Target Function:** `users_guard_identity()` (`SET search_path TO 'public'`)
* **Grants:** Execution REVOKED from `PUBLIC`, `anon`, `authenticated`. Granted to `postgres`, `service_role`; PostgreSQL does not check `EXECUTE` when firing a trigger.
* **Action:** Raises `API-VALIDATION-015` / SQLSTATE `42501` when a caller other than `postgres` / `service_role` changes `auth_id` or `email`. Other columns (for example `updated_at`) stay writable.
* **Side Effects:** A client can no longer rewrite its `auth_id` (to a random UUID or `NULL`), which would make `public.user_current_id()` return `NULL` and lock the row out of every RLS predicate. Insert-time provisioning by `user_create_from_auth()` is unaffected.

---

## Non-Obvious Database-Side Behaviors

1. **Automatic Partner Code Assignment:**
   - The application client never generates partnership codes. Code generation happens entirely inside PostgreSQL via MD5 random substring loop on user sign-up.

2. **Cascade Deletions:**
   - Deleting a user in `public.users` cascades to `user_profiles`, `user_roles`, `user_devices`, `partnerships`, `moods`, `favorites`, `game_answers`, `drive_item_reactions`, and `logs_auth_failures`.

3. **View Security Invoker Policy Resolution:**
   - Views `v_active_partnership` and `v_drive_dashboard` enforce `security_invoker = true`. If a policy on `partnerships` or `drive_items` changes, view output immediately reflects the modified RLS restriction without rebuilding the view definition.

---

## Implementation Status

- **Automated Sign-Up Trigger (`user_create_from_auth`):** **100% IMPLEMENTED**
- **Game Completion Trigger (`game_update_question_status`):** **100% IMPLEMENTED**
- **Security Invoker Views (`v_active_partnership`, `v_drive_dashboard`):** **100% IMPLEMENTED**
- **RPC Stored Procedures & Validation:** **100% IMPLEMENTED**
- **Log Cleanup (`logs_cleanup(p_days)`):** **IMPLEMENTED** (parameterized, `DEFAULT 90`; not `pg_cron`-scheduled — Node `retentionJob.js` is the single active driver)

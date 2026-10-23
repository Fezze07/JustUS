# Supabase Database Schema & Architecture Analysis

## Overview

This document presents the reverse-engineering analysis of the **Supabase PostgreSQL Database Schema** for the JustUS platform. 

> [!NOTE]
> **Authoritative Remote Database Schema Synchronized**
> The full database schema has been dumped directly from the live Supabase database instance into `supabase/schema/remote_schema.sql` and exported declaratively to `supabase/schemas/public/` (via `npx supabase db pull --declarative`). All objects, data types, constraints, functions, triggers, and RLS policies documented herein are **100% verified against real database SQL definitions**.

---

## Database Source & Verification Status

- **Declarative Schema Path:** `supabase/schemas/public/`
- **Single-File Dump Path:** `supabase/schema/remote_schema.sql`
- **Verification Status:** **100% VERIFIED FROM REAL DATABASE DEFINITION**

---

## Table & Constraint Specifications (26 Tables)

### 1. Core Users & Partnership Domain

#### `users`
- **SQL Source:** `supabase/schemas/public/tables/users.sql`
- **Columns:**
  - `id`: `integer` NOT NULL DEFAULT `nextval('users_id_seq'::regclass)`
  - `auth_id`: `uuid` UNIQUE
  - `email`: `character varying(255)` UNIQUE
  - `created_at`: `timestamp with time zone` DEFAULT `now()`
  - `updated_at`: `timestamp with time zone` DEFAULT `now()`
- **Constraints:**
  - `users_pkey` (PRIMARY KEY: `id`)
  - `users_auth_id_key` (UNIQUE: `auth_id`)
  - `users_email_key` (UNIQUE: `email`)
  - `users_auth_id_fkey` (FOREIGN KEY: `auth_id` REFERENCES `auth.users(id)` ON DELETE CASCADE)
- **Triggers:** `set_public_users_updated_at` (BEFORE UPDATE EXECUTE `util_set_updated_at()`)
- **RLS Policies:**
  - `users_select_self` (FOR SELECT, `TO authenticated`, USING `auth_id = (SELECT auth.uid())`)
  - `users_insert_self` (FOR INSERT WITH CHECK `(SELECT auth.uid()) = auth_id`)
  - `users_update_self` (FOR UPDATE USING + WITH CHECK `id = user_current_id()`)

#### `user_profiles`
- **SQL Source:** `supabase/schemas/public/tables/user_profiles.sql`
- **Columns:**
  - `user_id`: `integer` NOT NULL
  - `display_name`: `text`
  - `profile_pic_url`: `text`
  - `partnership_code`: `text` UNIQUE
  - `created_at`: `timestamp with time zone` DEFAULT `now()`
  - `updated_at`: `timestamp with time zone` DEFAULT `now()`
- **Constraints:**
  - `user_profiles_pkey` (PRIMARY KEY: `user_id`)
  - `user_profiles_partnership_code_key` (UNIQUE: `partnership_code`)
  - `user_profiles_user_id_fkey` (FOREIGN KEY: `user_id` REFERENCES `users(id)` ON DELETE CASCADE)
- **Triggers:** `set_public_user_profiles_updated_at` (BEFORE UPDATE EXECUTE `util_set_updated_at()`)
- **RLS Policies:**
  - `profiles_insert_self` (FOR INSERT WITH CHECK `user_id = user_current_id()`)
  - `profiles_select_self_or_partner` (FOR SELECT, `TO authenticated`, USING `user_id = user_current_id() OR private.is_related_user(user_id)`)
  - `profiles_update_self` (FOR UPDATE USING + WITH CHECK `user_id = user_current_id()`)

#### `partnerships`
- **SQL Source:** `supabase/schemas/public/tables/partnerships.sql`
- **Columns:**
  - `id`: `integer` NOT NULL DEFAULT `nextval('partnerships_id_seq'::regclass)`
  - `user_id_1`: `integer`
  - `user_id_2`: `integer`
  - `status`: `character varying(50)` DEFAULT `'accepted'`
  - `anniversary_date`: `date`
  - `created_at`: `timestamp with time zone` DEFAULT `now()`
  - `updated_at`: `timestamp with time zone` DEFAULT `now()`
  - `cancel_requested_by`: `integer` (FK -> `users.id` ON DELETE CASCADE) — member who requested cancellation
  - `cancel_expires_at`: `timestamp with time zone` — request deadline; the row reverts to `accepted` when it passes
  - `cancel_declined_at`: `timestamp with time zone` — last partner decline, drives the 24h re-request cooldown
- **Constraints:**
  - `partnerships_pkey` (PRIMARY KEY: `id`)
  - `partnerships_user_id_1_fkey` (FOREIGN KEY: `user_id_1` REFERENCES `users(id)` ON DELETE CASCADE)
  - `partnerships_user_id_2_fkey` (FOREIGN KEY: `user_id_2` REFERENCES `users(id)` ON DELETE CASCADE)
  - `partnerships_cancel_requested_by_fkey` (FOREIGN KEY: `cancel_requested_by` REFERENCES `users(id)` ON DELETE CASCADE)
  - `partnerships_status_check` (CHECK: `status IN ('pending', 'accepted', 'cancelled')`)
  - `partnerships_cancel_requester_check` (CHECK: `cancel_requested_by IS NULL OR cancel_requested_by = user_id_1 OR cancel_requested_by = user_id_2`)
  - `partnerships_cancel_state_check` (CHECK: `status = 'cancelled'` ⇔ `cancel_requested_by` and `cancel_expires_at` are both non-NULL)
- **Triggers:** `set_public_partnerships_updated_at` (BEFORE UPDATE EXECUTE `util_set_updated_at()`), `guard_public_partnerships_status` (BEFORE UPDATE EXECUTE `partnership_guard_status()`) — rejects any change to `user_id_1` / `user_id_2` (`API-VALIDATION-009`), then enforces a status whitelist for signed-in callers: `pending → accepted` only by `user_id_2` (`-008`); `accepted → cancelled` only by a member, with `cancel_requested_by = caller` and `cancel_expires_at` set (`-010`); `cancelled → accepted` only by a member, clearing both cancel fields (`-011`); `cancelled → cancelled` only with the requester and expiry unchanged (`-012`); any other status change (`-012`). A non-status update may not change `cancel_requested_by` / `cancel_expires_at` (`-012`). Callers with no user row (`service_role` backend and expiry job) skip the status checks. The trigger is also the only writer of `cancel_declined_at`: a partner decline (`cancelled → accepted` by a caller other than `OLD.cancel_requested_by`) sets it to `now()`, while a requester restore, the service-role expiry and every other update keep the stored value.
- **RLS Policies:**
  - `partnerships_select_own` (FOR SELECT, `TO authenticated`, USING `user_id_1 = user_current_id() OR user_id_2 = user_current_id()`)
  - `partnerships_update_own` (FOR UPDATE, `TO authenticated`, USING + WITH CHECK `user_id_1 = user_current_id() OR user_id_2 = user_current_id()`)
  - `partnerships_delete_own` (FOR DELETE, `TO authenticated`, USING `(user_id_1 = user_current_id() OR user_id_2 = user_current_id()) AND status = 'pending'`) — only a pending request can be deleted from the client; accepted/cancelled rows survive, and `anon` holds no `DELETE`/`TRUNCATE` grant.
  - **No INSERT policy** — the `INSERT` grant is held by `authenticated`, `postgres`, `service_role` only, and RLS still denies the insert to `authenticated` (no policy). Rows are created only through the `partnership_request` RPC, executed by the backend with the `service_role` key.

---

### 2. Feature Domain Tables

#### `moods`
- **SQL Source:** `supabase/schemas/public/tables/moods.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('moods_id_seq')`), `user_id` (`integer`, FK -> `users.id` ON DELETE CASCADE), `mood_type_id` (`bigint`, FK -> `emojis.id`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE, indexed), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** `moods_related_access` (SELECT user or accepted partner), `moods_manage_own` (INSERT WITH CHECK `user_id = user_current_id() AND (partnership_id IS NULL OR partnership_is_member(partnership_id))`), `moods_update_own` (UPDATE USING `user_id = user_current_id()`, same `WITH CHECK`), `moods_delete_own` (DELETE self).

#### `missyou`
- **SQL Source:** `supabase/schemas/public/tables/missyou.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('missyou_id_seq')`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** `missyou_related` (FOR ALL, `USING` + `WITH CHECK` on `partnership_is_member(partnership_id)`).

#### `bucket_items`
- **SQL Source:** `supabase/schemas/public/tables/bucket_items.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('bucket_items_id_seq')`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `text` (`text` NOT NULL), `category` (`character varying`), `done` (`boolean` DEFAULT `false`), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** `bucket_items_partnership_access` (FOR ALL, `USING` + `WITH CHECK` on `partnership_is_member(partnership_id)`).

#### `game_question_bank`, `game_questions` & `game_answers`
- **SQL Source:** `game_question_bank.sql`, `game_questions.sql`, `game_answers.sql`
- **`game_question_bank`:** `question_code` (`text` NOT NULL), `locale` (`text` NOT NULL), `text` (`text` NOT NULL), `created_at` (`timestamp with time zone`, DEFAULT `now()`), `updated_at` (`timestamp with time zone`, DEFAULT `now()`). PRIMARY KEY `(question_code, locale)`. Trigger `set_public_game_question_bank_updated_at` (BEFORE UPDATE).
- **`game_question_bank` RLS:** `game_question_bank_read_all` (FOR SELECT, `TO PUBLIC`, `USING (true)`) — the static, world-readable question catalog. No INSERT/UPDATE/DELETE policy exists, so client roles cannot write it.
- **`game_questions`:** `id` (`integer`, PK, DEFAULT `nextval('game_questions_id_seq'::regclass)`), `created_at` (`timestamp with time zone`, DEFAULT `now()`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `question_code` (`text`), `status` (`text`, DEFAULT `'pending'`), `user_id_a` / `user_id_b` (`integer`, FK -> `users.id`). Indexes on `partnership_id`, `user_id_a`, `user_id_b`, `question_code`.
- **`game_questions` RLS:** `game_questions_related` (FOR ALL, `USING` + `WITH CHECK` on `partnership_is_member(partnership_id)`).
- **`game_answers`:** `game_id` (`integer`, FK -> `game_questions.id` ON DELETE CASCADE), `user_id` (`integer`, FK -> `users.id` ON DELETE CASCADE), `selected_option` (`integer`), `created_at` / `updated_at` (`timestamp with time zone`). PRIMARY KEY: `(game_id, user_id)`. Trigger `tr_game_answers_update_question_status` (AFTER INSERT OR UPDATE -> `game_update_question_status()` sets the parent `game_questions.status` to `'both_answered'` once both partners have answered).
- **`game_answers` RLS:** `game_answers_manage_own` (INSERT WITH CHECK self + game in accepted partnership), `game_answers_update_own` (UPDATE USING self, WITH CHECK self + game in accepted partnership), `game_answers_delete_own` (DELETE self), `game_answers_related_select` (SELECT through the parent game in an accepted partnership).

#### `drive_items`, `drive_item_reactions`, `favorites`, `drive_file_types`, `emojis`
- **`drive_items`:** `id` (`integer`, PK), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `name` (`text` NOT NULL), `original_name`, `type` (`character varying`), `mime_type`, `size` (`bigint`), `file_type_id` (`bigint`, FK -> `drive_file_types.id`), `metadata` (`jsonb`), `created_at`, `updated_at`.
- **`drive_items` RLS:** `drive_items_related` (FOR ALL, `USING` + `WITH CHECK` on `partnership_is_member(partnership_id)`).
- **`drive_item_reactions`:** `id` (`integer`, PK), `user_id` (FK -> `users.id`), `item_id` (FK -> `drive_items.id` ON DELETE CASCADE), `emoji_id` (FK -> `emojis.id` ON DELETE CASCADE), `created_at`. UNIQUE `(user_id, item_id)`.
- **`drive_item_reactions` RLS:** `drive_item_reactions_manage_own` (INSERT WITH CHECK self + item in accepted partnership), `drive_item_reactions_update_own` (UPDATE USING self, WITH CHECK self + item in accepted partnership), `drive_item_reactions_delete_own` (DELETE self), `drive_item_reactions_related_select` (SELECT through the parent item in an accepted partnership).
- **`favorites`:** `user_id` (FK -> `users.id`), `item_id` (FK -> `drive_items.id` ON DELETE CASCADE), PRIMARY KEY `(user_id, item_id)`.
- **`favorites` RLS:** `favorites_own` (FOR ALL, USING + WITH CHECK self AND item in accepted partnership).
- **`emojis`:** `id` (`bigint`, PK), `emoji_char` (`text` NOT NULL UNIQUE).
- **`drive_file_types`:** `id` (`bigint`, PK), `extension` (`text` NOT NULL UNIQUE), `mime_type`, `icon_slug`.

---

### 3. Security, Authentication & Session Tables

#### `session_bindings`
- **SQL Source:** `supabase/schemas/public/tables/session_bindings.sql`
- **Columns:** `session_id` (`uuid`, PK, FK -> `auth.sessions(id)` ON DELETE CASCADE), `device_fingerprint_hash` (`text` NOT NULL), `binding_secret` (`text` NOT NULL), `country_code` (`text`), `created_at` (`timestamptz`), `last_seen_at` (`timestamptz`).

#### `request_nonces`
- **SQL Source:** `supabase/schemas/public/tables/request_nonces.sql`
- **Columns:** `id` (`bigint`, PK), `nonce` (`text` NOT NULL UNIQUE), `namespace` (`text` NOT NULL), `user_id` (`integer`), `created_at`, `expires_at`.

#### `user_devices`
- **SQL Source:** `supabase/schemas/public/tables/user_devices.sql`
- **Columns:** `id` (`bigint`, PK), `user_id` (`integer`, FK -> `users.id` ON DELETE CASCADE), `installation_id` (`text` UNIQUE), `device_type`, `user_agent`, `last_ip`, `created_at`.
- **RLS:** own rows only (`user_id = user_current_id()` on SELECT/INSERT/UPDATE/DELETE).

#### `roles`, `permissions`, `roles_permissions`, `user_roles`
- **`roles`:** `id` (`bigint`, PK), `name` (`text` NOT NULL UNIQUE).
- **`permissions`:** `id` (`bigint`, PK), `slug` (`text` NOT NULL UNIQUE), `description`.
- **`roles_permissions`:** `id` (`bigint`, PK), `role_id` (FK -> `roles.id` ON DELETE CASCADE), `permission_id` (FK -> `permissions.id` ON DELETE CASCADE).
- **`user_roles`:** `user_id` (FK -> `users.id` ON DELETE CASCADE), `role_id` (FK -> `roles.id` ON DELETE CASCADE), PRIMARY KEY `(user_id, role_id)`.

---

### 4. Audit & Logging Tables

- `logs_api_access`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `method`, `path`, `status_code`, `duration_ms`, `created_at`.
- `logs_api_errors`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `method`, `path`, `error_json` (`jsonb`), `created_at`.
- `logs_auth_failures`: `id` (`uuid`, PK), `request_id` (`text`), `user_id` (FK -> `users.id`), `ip_address`, `path`, `error_code` (`text` NOT NULL), `error_message`, `reason`, `severity` (`text` NOT NULL), `payload` (`jsonb`), `stack`, `created_at`. RLS: `service_role_only` (FOR ALL, USING + WITH CHECK `auth.role() = 'service_role'`).
- `logs_notifications`: `id` (`integer`, PK), `user_id` (FK -> `users.id`), `type`, `status`, `created_at`.
- `logs_security_events`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `type` (`text` NOT NULL), `path`, `error_json` (`jsonb`), `created_at`.

---

## Database Views

### 1. `v_active_partnership`
- **SQL Source:** `supabase/schemas/public/views/v_active_partnership.sql`
- **Security:** `WITH (security_invoker = true)`.
- **Query:** Joins `partnerships` and `user_profiles` to expose active partner details for `user_current_id()`. The partner's `users` row is not read; `partner_id` is derived from `user_id_1`/`user_id_2`.

### 2. `v_drive_dashboard`
- **SQL Source:** `supabase/schemas/public/views/v_drive_dashboard.sql`
- **Security:** `WITH (security_invoker = true)`.
- **Query:** Joins `drive_items`, `drive_file_types`, `favorites`, and aggregate `drive_item_reactions` count filtered by active partnership.

---

## Stored Procedures (RPC Functions)

All 22 PostgreSQL functions in `supabase/schemas/public/functions/`:

1. `partnership_accept(p_partnership_id integer)`: Updates partnership status to `'accepted'` and sets `anniversary_date = CURRENT_DATE`.
2. `partnership_request(partner_email text, partner_code text, override_sender_id integer)`: `SECURITY INVOKER` SET `search_path = public`. Revoked from `PUBLIC`, granted to `authenticated`, `postgres`, `service_role`.
3. `user_current_id()`: Converts `auth.uid()` (`uuid`) to internal `users.id` (`integer`).
4. `partnership_generate_code()`: Generates random 6-character uppercase alphanumeric code checking unicity against `user_profiles`.
5. `partnership_get_accepted_partner(target_user_id integer)`: STABLE function returning single active partner user ID.
6. `emoji_get_or_create(p_emoji_char text)`: Inserts emoji into `emojis` if missing and returns ID.
7. `partnership_get_names(p_user_id integer)`: `SECURITY DEFINER` returning `{ name1, name2 }` JSON. Executable only by `service_role`.
8. `partnership_get_pending_invitations()`: `SECURITY DEFINER` SET `search_path = public`. Returns the caller's pending invitations (scoped by `user_current_id()`) exposing only `invitation_id`, `status`, `created_at`, `partner_id`, `partner_display_name`, `is_received`. Revoked from `PUBLIC`, `anon`; granted to `authenticated`, `postgres`, `service_role`.
9. `user_create_from_auth()`: `SECURITY DEFINER` trigger function on `auth.users` insert. Revoked from `PUBLIC`, granted only to `postgres`, `service_role`.
10. `partnership_is_member(p_partnership_id integer)`: RLS validation helper returning `true` only when the caller is a member of the partnership **and** its `status = 'accepted'`.
11. `partnership_is_partner(other_user_id integer)`: RLS validation helper returning `true` only when the caller and the target share a partnership whose `status = 'accepted'`.
12. `missyou_send()`: Inserts `missyou` record for caller's active partnership.
13. `mood_set(p_emoji_char text)`: Inserts `moods` record looking up or creating emoji and attaching the caller's `accepted` partnership id (NULL when unpaired).
14. `logs_cleanup(p_days integer DEFAULT 90)`: `SECURITY INVOKER` maintenance function deleting logs older than `p_days` days (default 90, guarding NULL/`< 1`); not `pg_cron`-scheduled — Node `retentionJob.js` is the single active retention driver.
15. `debug_wipe_user_data(p_user_id integer)`: `SECURITY DEFINER` admin procedure. Revoked from `PUBLIC`, granted to `service_role`.
16. `util_set_updated_at()`: Trigger function setting `NEW.updated_at = now()`.
17. `util_update_updated_at()`: Trigger function setting `NEW.updated_at = now()`.
18. `drive_change_probe()`: `STABLE SECURITY INVOKER`, returns a single row `{ max_updated_at timestamptz, item_count bigint }` over `drive_items` for the caller's active partnership. Powers the Drive/Favorites revalidation gate: `max_updated_at` detects inserts/updates since the client checkpoint, `item_count` detects server-side deletions (invisible to an `updated_at` cursor). Reading the table directly avoids materializing `v_drive_dashboard` (joins + reaction aggregate) to obtain two scalars. Revoked from `PUBLIC`; granted to `authenticated`, `postgres`, `service_role`.
19. `game_update_question_status()`: `SECURITY DEFINER` SET `search_path = public` trigger function (returns `trigger`) on `game_answers`; sets `game_questions.status = 'both_answered'` when `COUNT(game_answers WHERE game_id = NEW.game_id) >= 2`. Revoked from `PUBLIC`, `anon`, `authenticated`; granted only to `postgres`, `service_role`. PostgreSQL performs no `EXECUTE` privilege check when firing a trigger, so no client role needs the grant and the function is not reachable over PostgREST RPC.
20. `partnership_request_cancel(p_partnership_id integer)`: `SECURITY INVOKER` SET `search_path = public`. Locks (`FOR UPDATE`) the caller's `accepted` partnership and sets `status = 'cancelled'`, `cancel_requested_by = caller`, `cancel_expires_at = now() + interval '7 days'`. A row that is missing, not `accepted`, or not the caller's raises `API-VALIDATION-010` / SQLSTATE `42501`; a partner decline inside the last 24 hours (`cancel_declined_at`) raises `API-VALIDATION-013` / SQLSTATE `P0001`. Revoked from `PUBLIC`, `anon`; granted to `authenticated`, `postgres`, `service_role`.
21. `partnership_cancel_revert(p_partnership_id integer)`: `SECURITY INVOKER` SET `search_path = public`. Updates the caller's `cancelled` partnership to `accepted` and clears `cancel_requested_by` / `cancel_expires_at`; `cancel_declined_at` stays with the guard trigger (recorded on a partner decline, preserved on a requester restore). A row that is missing, not `cancelled`, or not the caller's raises `API-VALIDATION-011` / SQLSTATE `42501`. Revoked from `PUBLIC`, `anon`; granted to `authenticated`, `postgres`, `service_role`.
22. `partnership_expire_cancellations()`: `SECURITY DEFINER` SET `search_path = public`, returns the number of reverted rows (`integer`). Reverts every `cancelled` partnership whose `cancel_expires_at <= now()` to `accepted`, clearing both cancel fields; `cancel_declined_at` is left to the guard trigger. Revoked from `PUBLIC`, `anon`, `authenticated`; granted to `postgres`, `service_role`.

> `private.is_related_user(target_user_id integer)` (`SECURITY DEFINER`, non-exposed `private` schema, `USAGE` granted to `authenticated`) backs `profiles_select_self_or_partner` and returns true only for an `accepted` partnership.

---

## Database Triggers & Automation

- **`on_auth_user_created`:** `AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION user_create_from_auth();`
- **`set_public_users_updated_at`:** `BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION util_set_updated_at();`
- **`set_public_user_profiles_updated_at`:** `BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION util_set_updated_at();`
- **`set_public_partnerships_updated_at`:** `BEFORE UPDATE ON public.partnerships FOR EACH ROW EXECUTE FUNCTION util_set_updated_at();`
- **`set_public_user_roles_updated_at`:** `BEFORE UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION util_set_updated_at();`
- **`set_public_drive_items_updated_at`:** `BEFORE UPDATE ON public.drive_items FOR EACH ROW EXECUTE FUNCTION util_set_updated_at();`
- **`tr_game_answers_update_question_status`:** `AFTER INSERT OR UPDATE ON public.game_answers FOR EACH ROW EXECUTE FUNCTION game_update_question_status();` - flips `game_questions.status` to `'both_answered'` once both players have answered, so the transition no longer depends on a client call. Emits a `game_questions` UPDATE that the Flutter realtime layer already handles.

---

## Implementation Status

- **Database Tables & Definitions:** **100% IMPLEMENTED & VERIFIED**
- **Views & Security Invoker Settings:** **100% IMPLEMENTED & VERIFIED**
- **RPC Stored Procedures & Grants:** **100% IMPLEMENTED & VERIFIED**
- **Triggers & Updated At Handlers:** **100% IMPLEMENTED & VERIFIED**
- **Declarative Schema Repositoried:** **100% IMPLEMENTED & VERIFIED** (`supabase/schemas/public/`)

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

## Table & Constraint Specifications (25 Tables)

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
- **Triggers:** `set_public_users_updated_at` (BEFORE UPDATE EXECUTE `set_current_timestamp_updated_at()`)
- **RLS Policies:**
  - `users_select_authenticated` (FOR SELECT USING `auth.role() = 'authenticated'`)
  - `users_update_self` (FOR UPDATE USING `id = current_user_id()`)

#### `user_profiles`
- **SQL Source:** `supabase/schemas/public/tables/user_profiles.sql`
- **Columns:**
  - `user_id`: `integer` NOT NULL
  - `display_name`: `text`
  - `profile_pic_url`: `text`
  - `bio`: `text`
  - `partnership_code`: `text` UNIQUE
  - `created_at`: `timestamp with time zone` DEFAULT `now()`
  - `updated_at`: `timestamp with time zone` DEFAULT `now()`
- **Constraints:**
  - `user_profiles_pkey` (PRIMARY KEY: `user_id`)
  - `user_profiles_partnership_code_key` (UNIQUE: `partnership_code`)
  - `user_profiles_user_id_fkey` (FOREIGN KEY: `user_id` REFERENCES `users(id)` ON DELETE CASCADE)
- **Triggers:** `set_public_user_profiles_updated_at` (BEFORE UPDATE EXECUTE `set_current_timestamp_updated_at()`)
- **RLS Policies:**
  - `profiles_insert_self` (FOR INSERT WITH CHECK `user_id = current_user_id()`)
  - `profiles_select_authenticated` (FOR SELECT USING `auth.role() = 'authenticated'`)
  - `profiles_update_self` (FOR UPDATE USING `user_id = current_user_id()`)

#### `partnerships`
- **SQL Source:** `supabase/schemas/public/tables/partnerships.sql`
- **Columns:**
  - `id`: `integer` NOT NULL DEFAULT `nextval('partnerships_id_seq'::regclass)`
  - `user_id_1`: `integer`
  - `user_id_2`: `integer`
  - `status`: `character varying(20)` DEFAULT `'pending'`
  - `anniversary_date`: `date`
  - `created_at`: `timestamp with time zone` DEFAULT `now()`
  - `updated_at`: `timestamp with time zone` DEFAULT `now()`
- **Constraints:**
  - `partnerships_pkey` (PRIMARY KEY: `id`)
  - `partnerships_user_id_1_fkey` (FOREIGN KEY: `user_id_1` REFERENCES `users(id)` ON DELETE CASCADE)
  - `partnerships_user_id_2_fkey` (FOREIGN KEY: `user_id_2` REFERENCES `users(id)` ON DELETE CASCADE)
- **Triggers:** `set_public_partnerships_updated_at` (BEFORE UPDATE EXECUTE `set_current_timestamp_updated_at()`)
- **RLS Policies:**
  - `partnerships_select_members` (FOR SELECT USING `current_user_id() IN (user_id_1, user_id_2)`)
  - `partnerships_update_members` (FOR UPDATE USING `current_user_id() IN (user_id_1, user_id_2)`)

---

### 2. Feature Domain Tables

#### `moods`
- **SQL Source:** `supabase/schemas/public/tables/moods.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('moods_id_seq')`), `user_id` (`integer`, FK -> `users.id` ON DELETE CASCADE), `mood_type_id` (`bigint`, FK -> `emojis.id`), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** `moods_select_partner` (SELECT if user or partner), `moods_insert_self` (INSERT if `user_id = current_user_id()`).

#### `missyou`
- **SQL Source:** `supabase/schemas/public/tables/missyou.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('missyou_id_seq')`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** `missyou_select_partnership` (SELECT if user in partnership), `missyou_insert_partnership` (INSERT if user in partnership).

#### `bucket_items`
- **SQL Source:** `supabase/schemas/public/tables/bucket_items.sql`
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('bucket_items_id_seq')`), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `text` (`text` NOT NULL), `category` (`character varying`), `done` (`boolean` DEFAULT `false`), `created_at` (`timestamp with time zone`, DEFAULT `now()`).
- **RLS:** Policy checking `is_in_partnership(partnership_id)` for SELECT, INSERT, UPDATE, DELETE.

#### `game_questions` & `game_answers`
- **SQL Source:** `game_questions.sql`, `game_answers.sql`
- **`game_questions`:** `id` (`integer`, PK), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `text` (`text` NOT NULL), `created_at`.
- **`game_answers`:** `game_id` (`integer`, FK -> `game_questions.id`), `user_id` (`integer`, FK -> `users.id`), `selected_option` (`integer`), `created_at`. UNIQUE/PK: `(game_id, user_id)`.

#### `drive_items`, `drive_item_reactions`, `favorites`, `drive_file_types`, `emojis`
- **`drive_items`:** `id` (`integer`, PK), `partnership_id` (`integer`, FK -> `partnerships.id` ON DELETE CASCADE), `name` (`text` NOT NULL), `original_name`, `type` (`character varying`), `mime_type`, `size` (`bigint`), `file_type_id` (`bigint`, FK -> `drive_file_types.id`), `metadata` (`jsonb`), `created_at`, `updated_at`.
- **`drive_item_reactions`:** `id` (`integer`, PK), `user_id` (FK -> `users.id`), `item_id` (FK -> `drive_items.id` ON DELETE CASCADE), `emoji_id` (FK -> `emojis.id` ON DELETE CASCADE), `created_at`. UNIQUE `(user_id, item_id)`.
- **`favorites`:** `user_id` (FK -> `users.id`), `item_id` (FK -> `drive_items.id` ON DELETE CASCADE), PRIMARY KEY `(user_id, item_id)`.
- **`emojis`:** `id` (`bigint`, PK), `emoji_char` (`text` NOT NULL UNIQUE).
- **`drive_file_types`:** `id` (`bigint`, PK), `extension` (`text` NOT NULL UNIQUE), `mime_type`, `icon_slug`.

---

### 3. Security, Authentication & Session Tables

#### `auth_sessions`
- **SQL Source:** `supabase/schemas/public/tables/auth_sessions.sql`
- **Columns:** `id` (`bigint`, PK), `session_id` (`text` NOT NULL UNIQUE), `user_id` (`integer` NOT NULL), `auth_user_id` (`uuid`), `device_fingerprint_hash` (`text` NOT NULL), `device_label`, `user_agent`, `user_agent_hash`, `ip_address`, `ip_range`, `country_code`, `binding_secret`, `request_profile_hash`, `created_at`, `last_seen_at`, `revoked_at`.

#### `request_nonces`
- **SQL Source:** `supabase/schemas/public/tables/request_nonces.sql`
- **Columns:** `id` (`bigint`, PK), `nonce` (`text` NOT NULL UNIQUE), `namespace` (`text` NOT NULL), `user_id` (`integer`), `created_at`, `expires_at`.

#### `user_devices`
- **SQL Source:** `supabase/schemas/public/tables/user_devices.sql`
- **Columns:** `id` (`bigint`, PK), `user_id` (`integer`, FK -> `users.id` ON DELETE CASCADE), `device_token` (`text` UNIQUE), `device_type`, `user_agent`, `last_ip`, `created_at`.

#### `roles`, `permissions`, `roles_permissions`, `user_roles`
- **`roles`:** `id` (`bigint`, PK), `name` (`text` NOT NULL UNIQUE).
- **`permissions`:** `id` (`bigint`, PK), `slug` (`text` NOT NULL UNIQUE), `description`.
- **`roles_permissions`:** `id` (`bigint`, PK), `role_id` (FK -> `roles.id` ON DELETE CASCADE), `permission_id` (FK -> `permissions.id` ON DELETE CASCADE).
- **`user_roles`:** `user_id` (FK -> `users.id` ON DELETE CASCADE), `role_id` (FK -> `roles.id` ON DELETE CASCADE), PRIMARY KEY `(user_id, role_id)`.

---

### 4. Audit & Logging Tables

- `logs_api_access`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `method`, `path`, `status_code`, `duration_ms`, `created_at`.
- `logs_api_errors`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `method`, `path`, `error_json` (`jsonb`), `created_at`.
- `logs_auth_failures`: `id` (`uuid`, PK), `request_id` (`text`), `user_id` (FK -> `users.id`), `ip_address`, `path`, `error_code` (`text` NOT NULL), `error_message`, `reason`, `severity` (`text` NOT NULL), `payload` (`jsonb`), `stack`, `created_at`.
- `logs_notifications`: `id` (`integer`, PK), `user_id` (FK -> `users.id`), `type`, `status`, `created_at`.
- `logs_security_events`: `id` (`bigint`, PK), `request_id` (`uuid`), `device_id` (FK -> `user_devices.id`), `type` (`text` NOT NULL), `path`, `error_json` (`jsonb`), `created_at`.

---

## Database Views

### 1. `v_active_partnership`
- **SQL Source:** `supabase/schemas/public/views/v_active_partnership.sql`
- **Security:** `WITH (security_invoker = true)`.
- **Query:** Joins `partnerships`, `users`, `user_profiles` to expose active partner details for `current_user_id()`.

### 2. `v_drive_dashboard`
- **SQL Source:** `supabase/schemas/public/views/v_drive_dashboard.sql`
- **Security:** `WITH (security_invoker = true)`.
- **Query:** Joins `drive_items`, `drive_file_types`, `favorites`, and aggregate `drive_item_reactions` count filtered by active partnership.

---

## Stored Procedures (RPC Functions)

All 17 PostgreSQL functions in `supabase/schemas/public/functions/`:

1. `accept_partnership(p_partnership_id integer)`: Updates partnership status to `'accepted'` and sets `anniversary_date = CURRENT_DATE`.
2. `request_partnership(partner_email text, partner_code text, override_sender_id integer)`: `SECURITY DEFINER` SET `search_path = public`. Revoked from `PUBLIC`, granted to `authenticated`, `postgres`, `service_role`.
3. `current_user_id()`: Converts `auth.uid()` (`uuid`) to internal `users.id` (`integer`).
4. `generate_unique_partnership_code()`: Generates random 6-character uppercase alphanumeric code checking unicity against `user_profiles`.
5. `get_accepted_partner(target_user_id integer)`: STABLE function returning single active partner user ID.
6. `get_game_stats(p_uid bigint, p_partner_id bigint)`: `SECURITY DEFINER` function counting matched game answers between partners.
7. `get_or_create_emoji(p_emoji_char text)`: Inserts emoji into `emojis` if missing and returns ID.
8. `get_partnership_names(p_user_id integer)`: `SECURITY DEFINER` returning `{ name1, name2 }` JSON. Executable only by `service_role`.
9. `handle_new_auth_user()`: `SECURITY DEFINER` trigger function on `auth.users` insert. Revoked from `PUBLIC`, granted only to `postgres`, `service_role`.
10. `is_in_partnership(p_partnership_id integer)`: RLS validation helper returning `boolean`.
11. `is_partner_of(other_user_id integer)`: RLS validation helper returning `boolean`.
12. `send_missyou()`: Inserts `missyou` record for caller's active partnership.
13. `set_mood(p_emoji_char text)`: Inserts `moods` record looking up or creating emoji.
14. `cleanup_old_logs()`: `SECURITY DEFINER` function deleting logs > 30 days old.
15. `debug_wipe_user_data(p_user_id integer)`: `SECURITY DEFINER` admin procedure. Revoked from `PUBLIC`, granted to `service_role`.
16. `set_current_timestamp_updated_at()`: Trigger function setting `NEW.updated_at = now()`.
17. `update_updated_at_column()`: Trigger function setting `NEW.updated_at = now()`.

---

## Database Triggers & Automation

- **`on_auth_user_created`:** `AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user();`
- **`set_public_users_updated_at`:** `BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION set_current_timestamp_updated_at();`
- **`set_public_user_profiles_updated_at`:** `BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION set_current_timestamp_updated_at();`
- **`set_public_partnerships_updated_at`:** `BEFORE UPDATE ON public.partnerships FOR EACH ROW EXECUTE FUNCTION set_current_timestamp_updated_at();`
- **`set_public_user_roles_updated_at`:** `BEFORE UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION set_current_timestamp_updated_at();`
- **`set_public_drive_items_updated_at`:** `BEFORE UPDATE ON public.drive_items FOR EACH ROW EXECUTE FUNCTION set_current_timestamp_updated_at();`

---

## Implementation Status

- **Database Tables & Definitions:** **100% IMPLEMENTED & VERIFIED**
- **Views & Security Invoker Settings:** **100% IMPLEMENTED & VERIFIED**
- **RPC Stored Procedures & Grants:** **100% IMPLEMENTED & VERIFIED**
- **Triggers & Updated At Handlers:** **100% IMPLEMENTED & VERIFIED**
- **Declarative Schema Repositoried:** **100% IMPLEMENTED & VERIFIED** (`supabase/schemas/public/`)

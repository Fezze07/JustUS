# Supabase Database-Side Logic & Automation Analysis

## Overview

This document provides a technical specification and analysis of all **Supabase-side database logic** in the JustUS platform. It details database views, PostgreSQL Stored Procedures (RPCs), triggers, automated maintenance jobs, and integrity enforcement logic running directly on the database engine.

---

## 1. Database Views

### `v_active_partnership`
* **SQL Source:** `supabase/schemas/public/views/v_active_partnership.sql`
* **Purpose:** Provides a single, unified view of the current user's active relationship, including status, anniversary date, partner user details (email, display name, bio, profile picture), and names of both partners.
* **Security Context:** `WITH (security_invoker = true)`
  - Inherits RLS policies of underlying tables (`partnerships`, `users`, `user_profiles`) based on the authenticated caller's JWT token.
* **Inputs:** None (Implicitly uses `public.current_user_id()` derived from `auth.uid()`).
* **Outputs:** `partnership_id`, `status`, `anniversary_date`, `partner_id`, `partner_email`, `partner_display_name`, `partner_profile_pic_url`, `partner_bio`, `user_id_a`, `user_id_b`, `user_a_name`, `user_b_name`.
* **Tables Touched:** `public.partnerships` (READ), `public.users` (READ), `public.user_profiles` (READ).
* **Execution Condition:** `(user_id_1 = current_user_id() OR user_id_2 = current_user_id()) AND status = 'accepted'`.
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **Side Effects:** None (Read-only view).
* **Failure Behavior:** Returns 0 rows if no active accepted partnership exists for the executing user.

---

### `v_drive_dashboard`
* **SQL Source:** `supabase/schemas/public/views/v_drive_dashboard.sql`
* **Purpose:** Aggregates drive files and folders with file type metadata, current user bookmark status (`is_favorite`), and aggregated user emoji reactions (`reactions`).
* **Security Context:** `WITH (security_invoker = true)`
* **Inputs:** Implicitly relies on `public.current_user_id()`.
* **Outputs:** `id`, `partnership_id`, `name`, `original_name`, `type`, `size`, `created_at`, `updated_at`, `extension`, `mime_type`, `icon_slug`, `is_favorite` (boolean), `reactions` (JSON array of `{ user_id, emoji_char }`).
* **Tables Touched:** `public.drive_items` (READ), `public.drive_file_types` (READ), `public.favorites` (READ), `public.drive_item_reactions` (READ), `public.emojis` (READ).
* **Execution Condition:** Filtered by `public.is_in_partnership(d.partnership_id)`.
* **Caller:** Flutter Frontend ([drive_repository.dart](file:///f:/JustUS/Flutter/lib/features/drive/drive_repository.dart)).
* **Side Effects:** None (Read-only view).

---

## 2. Stored Procedures (RPC Functions)

### `request_partnership(partner_email text, partner_code text, override_sender_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/request_partnership.sql`
* **Purpose:** Initiates a new relationship connection request between two users.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`. Granted exclusively to `authenticated`, `postgres`, `service_role`.
* **Inputs:** `partner_email` (`text`), `partner_code` (`text`), `override_sender_id` (`integer` DEFAULT NULL).
* **Outputs:** `integer` (ID of created `partnerships` row).
* **Tables Touched:** `public.partnerships` (READ, INSERT), `public.users` (READ), `public.user_profiles` (READ).
* **Execution Conditions & Validation Rules:**
  1. Identifies caller ID via `override_sender_id` or `public.current_user_id()`.
  2. Raises EXCEPTION if user is not authenticated (`'Utente non autenticato o ID non valido'`).
  3. Checks if user is already in a `'pending'` or `'accepted'` partnership. Raises EXCEPTION if true (`'Hai gia una partnership o una richiesta attiva'`).
  4. Looks up recipient matching BOTH `email = partner_email` and `partnership_code = UPPER(partner_code)`. Raises EXCEPTION if not found (`'Email o Codice Partner non validi'`).
  5. Prevents self-invitation (`v_partner_id = v_current_user_id`). Raises EXCEPTION (`'Non puoi invitare te stesso'`).
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **Side Effects:** Inserts a row in `public.partnerships` with `status = 'pending'`.

---

### `accept_partnership(p_partnership_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/accept_partnership.sql`
* **Purpose:** Accepts a pending partnership request and establishes the anniversary date.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** `p_partnership_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `public.partnerships` (UPDATE).
* **Execution Conditions:** Updates row where `id = p_partnership_id`, caller is member (`user_id_1` or `user_id_2`), and `status = 'pending'`. Sets `status = 'accepted'` and `anniversary_date = CURRENT_DATE`.
* **Caller:** Flutter Frontend ([partnership_repository.dart](file:///f:/JustUS/Flutter/lib/features/partnership/partnership_repository.dart)).
* **Side Effects:** Mutates partnership state to `'accepted'`.

---

### `debug_wipe_user_data(p_user_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/debug_wipe_user_data.sql`
* **Purpose:** Admin testing and cleanup procedure. Permanently deletes all partnership-related content and user data for both partners in a relationship.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`. Granted strictly to `postgres`, `service_role`.
* **Inputs:** `p_user_id` (`integer`).
* **Outputs:** `void`.
* **Tables Touched:** `partnerships` (READ), `drive_items` (DELETE), `bucket_items` (DELETE), `game_questions` (DELETE), `game_answers` (DELETE), `missyou` (DELETE), `favorites` (DELETE), `drive_item_reactions` (DELETE), `moods` (DELETE), `user_profiles` (UPDATE), `logs_notifications` (DELETE).
* **Caller:** Backend Integration Tests / Admin Tools via `service_role`.
* **Side Effects:** Massive destructive purge of user & partner files, games, bucket list items, reactions, moods, notifications, and profile details (bio and picture reset to NULL).

---

### `get_partnership_names(p_user_id integer)`
* **SQL Source:** `supabase/schemas/public/functions/get_partnership_names.sql`
* **Purpose:** Retrieves the display names of both members of an active accepted partnership for AI prompt customization.
* **Security Context:** `SECURITY DEFINER`, `SET search_path TO 'public'`
  - **Execution Grants:** Revoked from `PUBLIC`. Granted strictly to `postgres`, `service_role`.
* **Inputs:** `p_user_id` (`integer`).
* **Outputs:** `jsonb` (`{ "name1": "...", "name2": "..." }`).
* **Tables Touched:** `partnerships` (READ), `user_profiles` (READ).
* **Caller:** Node.js Backend AI Engine.
* **Failure Behavior:** If no active accepted partnership is found, returns fallback object `{ "name1": "Partner 1", "name2": "Partner 2" }`.

---

### `send_missyou()`
* **SQL Source:** `supabase/schemas/public/functions/send_missyou.sql`
* **Purpose:** Inserts a "Miss You" signal for the caller's active relationship.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** None.
* **Outputs:** `void`.
* **Tables Touched:** `partnerships` (READ), `missyou` (INSERT).
* **Execution Condition:** Requires active partnership (`status = 'accepted'`). Raises EXCEPTION (`'No active partnership found'`) if missing.
* **Caller:** Flutter Frontend ([missyou_repository.dart](file:///f:/JustUS/Flutter/lib/features/home/missyou_repository.dart)).

---

### `set_mood(p_emoji_char text)`
* **SQL Source:** `supabase/schemas/public/functions/set_mood.sql`
* **Purpose:** Records user mood state by looking up or dynamically registering the emoji character.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** `p_emoji_char` (`text`).
* **Outputs:** `void`.
* **Tables Touched:** `emojis` (READ, INSERT via `get_or_create_emoji`), `moods` (INSERT).
* **Caller:** Flutter Frontend ([mood_repository.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart)).

---

### `generate_unique_partnership_code()`
* **SQL Source:** `supabase/schemas/public/functions/generate_unique_partnership_code.sql`
* **Purpose:** Generates a random 6-character uppercase alphanumeric code and verifies unicity against `user_profiles`.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Outputs:** `text` (e.g. `'A8F3K9'`).
* **Tables Touched:** `user_profiles` (READ).
* **Caller:** Internal database helper called by `handle_new_auth_user()`.

---

### `cleanup_old_logs()`
* **SQL Source:** `supabase/schemas/public/functions/cleanup_old_logs.sql`
* **Purpose:** Scheduled database maintenance. Deletes API access logs, error logs, security events, and notification logs older than 30 days.
* **Security Context:** `SECURITY INVOKER`, `SET search_path TO 'public'`
* **Inputs:** None.
* **Outputs:** `void`.
* **Tables Touched:** `logs_api_access` (DELETE), `logs_api_errors` (DELETE), `logs_security_events` (DELETE), `logs_notifications` (DELETE).
* **Execution Condition:** `created_at < NOW() - INTERVAL '30 days'`.
* **Caller:** Scheduled `pg_cron` background job (03:00 AM daily).

---

## 3. Database Triggers & System Automation

### Trigger 1: User Sign-Up Automation (`on_auth_user_created`)
* **Event:** `AFTER INSERT ON auth.users`
* **Target Function:** `handle_new_auth_user()` (`SECURITY DEFINER`, `SET search_path TO 'public'`)
* **Grants:** Execution REVOKED from `PUBLIC`. Granted to `postgres`, `service_role`.
* **Automated Workflow:**
  1. Inserts new record into `public.users (auth_id, email)` using `NEW.id` and `NEW.email`.
  2. Generates unique 6-character partnership code via `public.generate_unique_partnership_code()`.
  3. Inserts initial profile into `public.user_profiles` setting `display_name = split_part(email, '@', 1)` and `partnership_code`.
  4. Fetches ID for role `'user'` from `public.roles`. If missing, inserts default role `'user'`.
  5. Assigns role to user in `public.user_roles (user_id, role_id)`.
* **Side Effects:** Automatically initializes full public profile, partnership code, and RBAC role instantly upon Supabase Auth registration without client interaction.

---

### Trigger 2: Automatic Timestamp Maintenance
* **Event:** `BEFORE UPDATE`
* **Target Function:** `set_current_timestamp_updated_at()`
* **Applied Tables:** `users`, `user_profiles`, `partnerships`, `user_roles`, `drive_items`.
* **Action:** Automatically updates `NEW.updated_at = NOW()`.

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

- **Automated Sign-Up Trigger (`handle_new_auth_user`):** **100% IMPLEMENTED**
- **Security Invoker Views (`v_active_partnership`, `v_drive_dashboard`):** **100% IMPLEMENTED**
- **RPC Stored Procedures & Validation:** **100% IMPLEMENTED**
- **Daily Maintenance Cron Job (`cleanup_old_logs`):** **100% IMPLEMENTED**

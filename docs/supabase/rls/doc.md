# Supabase Row Level Security (RLS) Policy Analysis

## Overview

This document presents a comprehensive audit and analysis of the **Row Level Security (RLS)** policies configured across all 25 public database tables in the JustUS platform.

The analysis evaluates table-level access controls, user ownership enforcement, partner data sharing rules, backend privilege boundaries, and security vulnerabilities identified in policy logic.

---

## RLS Enforcement Status Matrix

Row Level Security is **ENABLED** on all 25 tables in the `public` schema.

| Table Name | RLS Status | SELECT Policy | INSERT Policy | UPDATE Policy | DELETE Policy | Target Roles |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- |
| `users` | **ENABLED** | Authenticated (All) | Self (`auth.uid() = auth_id`) / Service Role | Self (`id = current_user_id()`) | Denied (Default) | `PUBLIC`, `service_role` |
| `user_profiles` | **ENABLED** | Authenticated (All) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Denied (Default) | `PUBLIC` |
| `partnerships` | **ENABLED** | Members (`user_1` or `user_2`) | Members (`user_1` or `user_2`) | Members (`user_1` or `user_2`) | Members (`user_1` or `user_2`) | `PUBLIC` |
| `moods` | **ENABLED** | Self or Partner | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | `PUBLIC` |
| `missyou` | **ENABLED** | Partnership Members | Partnership Members | Partnership Members | Partnership Members | `PUBLIC` |
| `bucket_items` | **ENABLED** | Partnership Members | Partnership Members | Partnership Members | Partnership Members | `PUBLIC` |
| `game_questions` | **ENABLED** | Partnership Members | Partnership Members | Partnership Members | Partnership Members | `PUBLIC` |
| `game_answers` | **ENABLED** | Partnership Members | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | `PUBLIC` |
| `drive_items` | **ENABLED** | Partnership Members | Partnership Members | Partnership Members | Partnership Members | `PUBLIC` |
| `drive_item_reactions` | **ENABLED** | Partnership Members | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | `PUBLIC` |
| `favorites` | **ENABLED** | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | `PUBLIC` |
| `user_devices` | **ENABLED** | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | `PUBLIC` |
| `user_roles` | **ENABLED** | Self (`user_id = current_user_id()`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |
| `roles` | **ENABLED** | Public (`true`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |
| `permissions` | **ENABLED** | Public (`true`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |
| `roles_permissions` | **ENABLED** | Public (`true`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |
| `emojis` | **ENABLED** | Public (`true`) | Authenticated Users | Denied (Default) | Denied (Default) | `PUBLIC` |
| `drive_file_types` | **ENABLED** | Public (`true`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |
| `auth_sessions` | **ENABLED** | Denied (`USING (false)`) | Denied (`CHECK (false)`) | Denied (`USING (false)`) | Denied (`USING (false)`) | `authenticated` (Bypassed by `service_role`) |
| `request_nonces` | **ENABLED** | Denied (`USING (false)`) | Denied (`CHECK (false)`) | Denied (`USING (false)`) | Denied (`USING (false)`) | `authenticated` (Bypassed by `service_role`) |
| `logs_api_access` | **ENABLED** | Denied (`USING (false)`) | Denied (`CHECK (false)`) | Denied (`USING (false)`) | Denied (`USING (false)`) | `authenticated` (Bypassed by `service_role`) |
| `logs_api_errors` | **ENABLED** | Denied (`USING (false)`) | Denied (`CHECK (false)`) | Denied (`USING (false)`) | Denied (`USING (false)`) | `authenticated` (Bypassed by `service_role`) |
| `logs_security_events` | **ENABLED** | Denied (`USING (false)`) | Denied (`CHECK (false)`) | Denied (`USING (false)`) | Denied (`USING (false)`) | `authenticated` (Bypassed by `service_role`) |
| `logs_auth_failures` | **ENABLED** | Service Role Only | Service Role Only | Service Role Only | Service Role Only | `service_role` |
| `logs_notifications` | **ENABLED** | Self (`user_id = current_user_id()`) | Denied (Default) | Denied (Default) | Denied (Default) | `PUBLIC` |

---

## Detailed Policy Categorization & Analysis

### 1. User & Profile Access Controls

#### `users`
- **Policies:**
  - `users_select_authenticated` (SELECT): `USING (auth.role() = 'authenticated')`
  - `users_insert_self` (INSERT): `WITH CHECK ((SELECT auth.uid()) = auth_id)`
  - `users_insert_service_role` (INSERT): `TO service_role WITH CHECK (true)`
  - `users_update_self` (UPDATE): `USING (id = public.current_user_id())`
- **Assessment:** **OVERLY BROAD SELECT POLICY**. Allows any logged-in user to query all rows of `public.users` (id, email, auth_id, timestamps).

#### `user_profiles`
- **Policies:**
  - `profiles_select_authenticated` (SELECT): `USING (auth.role() = 'authenticated')`
  - `profiles_insert_self` (INSERT): `WITH CHECK (user_id = public.current_user_id())`
  - `profiles_update_self` (UPDATE): `USING (user_id = public.current_user_id())`
- **Assessment:** **OVERLY BROAD SELECT POLICY**. Allows any logged-in user to read all display names, bios, profile picture URLs, and unique `partnership_code` values for all users.

---

### 2. Shared Relationship & Partnership Boundaries

#### `partnerships`
- **Policies:**
  - `partnerships_manage_own` (FOR ALL): `USING ((user_id_1 = public.current_user_id()) OR (user_id_2 = public.current_user_id()))`
- **Assessment:** Access is restricted to `user_id_1` or `user_id_2`.

#### `drive_items` & `bucket_items` & `game_questions` & `missyou`
- **Policies:**
  - Uses `USING (public.is_in_partnership(partnership_id))`
- **Helper Function `is_in_partnership` Code:**
  ```sql
  SELECT EXISTS (
    SELECT 1 FROM public.partnerships 
    WHERE id = p_partnership_id 
    AND (user_id_1 = public.current_user_id() OR user_id_2 = public.current_user_id())
  );
  ```
- **Assessment:** **STALE / UNVALIDATED RELATIONSHIP CHECK**. `is_in_partnership` checks membership in a `partnerships` row **without checking `status = 'accepted'`**. Unaccepted or pending requests allow data access.

#### `moods`
- **Policies:**
  - `moods_related_access` (SELECT): `USING ((user_id = public.current_user_id()) OR public.is_partner_of(user_id))`
  - `moods_manage_own` (INSERT), `moods_update_own` (UPDATE), `moods_delete_own` (DELETE): `user_id = public.current_user_id()`
- **Assessment:** `is_partner_of` also checks `partnerships` without enforcing `status = 'accepted'`.

#### `game_answers` & `drive_item_reactions`
- **Policies:**
  - READ: Partnership members (via subquery on parent `game_questions` / `drive_items`).
  - WRITE/UPDATE/DELETE: Restricted to row owner (`user_id = public.current_user_id()`).
- **Assessment:** Granular ownership properly enforced on write operations.

---

### 3. Application Architecture & Access Boundary Mapping

```
+-------------------------------------------------------+
|                 Flutter Application                   |
|  (Authenticated JWT via Anon Client Key)             |
+---------------------------+---------------------------+
                            |
                            | REST / PostgREST (RLS Enforced)
                            v
+-------------------------------------------------------+
|                Supabase Data API / RLS                |
|  - Validates auth.uid() & current_user_id()          |
|  - Blocks auth_sessions, request_nonces, logs_*       |
|  - Evaluates table policies & security invoker views  |
+-------------------------------------------------------+

+-------------------------------------------------------+
|                 Node.js Express Backend               |
|  (Privileged Admin Client via Service Role Key)        |
+---------------------------+---------------------------+
                            |
                            | Direct DB Connection / Service Role
                            v
+-------------------------------------------------------+
|              Supabase Database Engine                 |
|  - Bypasses RLS for backend sessions & audit logs     |
|  - Calls SECURITY DEFINER functions                   |
+-------------------------------------------------------+
```

1. **Flutter Client Layer:**
   - Directly queries `v_active_partnership`, `v_drive_dashboard`, `moods`, `missyou`, `bucket_items`, `game_questions`, `game_answers`, `drive_items`, `favorites`, `drive_item_reactions`.
   - All Flutter direct requests pass through Supabase PostgREST with user JWT context, evaluating RLS policies.

2. **Backend Server Layer:**
   - Operates with `service_role` key to manage `auth_sessions`, `request_nonces`, API audit logs (`logs_api_access`, `logs_api_errors`, `logs_security_events`, `logs_auth_failures`), and execute SECURITY DEFINER procedures (`debug_wipe_user_data`, `get_partnership_names`).
   - Bypasses RLS by design for platform security middleware.

---

## Critical Findings & Vulnerabilities

### Finding 1: User Enumeration & Global Profile Leakage
- **Severity:** HIGH
- **Where:** `users.sql` (`users_select_authenticated`), `user_profiles.sql` (`profiles_select_authenticated`).
- **Impact:** Any registered user can execute `SELECT * FROM users` or `SELECT * FROM user_profiles` and retrieve emails, UUIDs, display names, and `partnership_code`s of all platform users.
- **Root Cause:** Policy checks `auth.role() = 'authenticated'` without restricting rows to self or partner.

### Finding 2: Unaccepted ('Pending') Partnership Data Access
- **Severity:** HIGH
- **Where:** Helper functions `public.is_in_partnership()` and `public.is_partner_of()`.
- **Impact:** When User A sends a partnership request to User B, a `partnerships` row is created with `status = 'pending'`. Because `is_in_partnership` does not check `status = 'accepted'`, User A or User B can access or upload files (`drive_items`), bucket list items, and mood records before the invite is accepted or even if rejected.
- **Root Cause:** Missing `AND status = 'accepted'` filter in helper function SQL definitions.

### Finding 3: Lack of `WITH CHECK` on Shared Resource Mutation
- **Severity:** MEDIUM
- **Where:** `drive_items.sql` (`drive_items_related`), `bucket_items.sql` (`bucket_items_partnership_access`), `game_questions.sql` (`game_questions_related`).
- **Impact:** Policies use `FOR ALL ... USING (is_in_partnership(partnership_id))` without explicit `WITH CHECK` clauses. While PostgreSQL evaluates `USING` expression on insert/update as fallback, explicit `WITH CHECK` is recommended to prevent parameter ambiguity during updates.

---

## Implementation Status

- **RLS Activation on All Tables:** **100% IMPLEMENTED** (25/25 tables)
- **Backend Infrastructure Protection:** **100% IMPLEMENTED** (`auth_sessions`, `logs_*` closed to users)
- **Security Invoker Views:** **100% IMPLEMENTED** (`v_active_partnership`, `v_drive_dashboard`)
- **Strict Relationship Validation (`status = 'accepted'`):** **NOT IMPLEMENTED** (Needs fix in helper functions)
- **Strict User Profile Isolation:** **NOT IMPLEMENTED** (Global select allowed for authenticated users)

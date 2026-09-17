# Supabase Row Level Security (RLS) Policy Analysis

## Overview

This document presents a comprehensive audit and analysis of the **Row Level Security (RLS)** policies configured across all 25 public database tables in the JustUS platform.

The analysis evaluates table-level access controls, user ownership enforcement, partner data sharing rules, backend privilege boundaries, and security vulnerabilities identified in policy logic.

---

## RLS Enforcement Status Matrix

Row Level Security is **ENABLED** on all 25 tables in the `public` schema.

| Table Name | RLS Status | SELECT Policy | INSERT Policy | UPDATE Policy | DELETE Policy | Target Roles |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- |
| `users` | **ENABLED** | Self (`auth_id = auth.uid()`) | Self (`auth.uid() = auth_id`) / Service Role | Self (`id = current_user_id()`) | Denied (Default) | `authenticated`, `service_role` |
| `user_profiles` | **ENABLED** | Self + accepted partner | Self (`user_id = current_user_id()`) | Self (`user_id = current_user_id()`) | Denied (Default) | `authenticated` |
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
  - `users_select_self` (SELECT): `TO authenticated USING (auth_id = (SELECT auth.uid()))`
  - `users_insert_self` (INSERT): `WITH CHECK ((SELECT auth.uid()) = auth_id)`
  - `users_insert_service_role` (INSERT): `TO service_role WITH CHECK (true)`
  - `users_update_self` (UPDATE): `USING (id = public.current_user_id())`
- **Assessment:** **SELF-SCOPED SELECT POLICY**. An authenticated user can read only their own row; `service_role` retains full access through its RLS bypass. No other user's email/UUID is reachable by direct query.

#### `user_profiles`
- **Policies:**
  - `profiles_select_self_or_partner` (SELECT): `TO authenticated USING (user_id = public.current_user_id() OR private.is_related_user(user_id))`
  - `profiles_insert_self` (INSERT): `WITH CHECK (user_id = public.current_user_id())`
  - `profiles_update_self` (UPDATE): `USING (user_id = public.current_user_id())`
- **Assessment:** **SELF + ACCEPTED PARTNER**. `private.is_related_user` is a `SECURITY DEFINER`, non-exposed helper that returns true only when the caller and the target share a partnership whose `status = 'accepted'`. `partnership_code`, bios and pictures of unrelated users (and of *pending* invitees) are no longer reachable through table SELECT.

#### Pending invitation identity
- Pending requests still need the counterpart's display name in the partners screen, but neither `users` nor `user_profiles` exposes pending invitees.
- Instead, `public.get_pending_invitations()` (SECURITY DEFINER, granted to `authenticated` only, revoked from `PUBLIC`/`anon`) returns the minimum identity fields (`invitation_id`, `status`, `created_at`, `partner_id`, `partner_display_name`, `is_received`) for rows where the caller is `user_id_1` or `user_id_2` and `status = 'pending'`. The function is scoped by `public.current_user_id()`, never returns an unrelated user's row, and does not expose the counterpart's email.

---

### 2. Shared Relationship & Partnership Boundaries

#### `partnerships`
- **Policies:**
  - `partnerships_manage_own` (FOR ALL): `USING ((user_id_1 = public.current_user_id()) OR (user_id_2 = public.current_user_id()))`
- **Assessment:** Access is restricted to `user_id_1` or `user_id_2`.

#### `drive_items` & `bucket_items` & `game_questions` & `missyou`
- **Policies:**
  - `drive_items_related`, `bucket_items_partnership_access`, `game_questions_related`, `missyou_related` (all `FOR ALL`, `TO PUBLIC`): `USING (public.is_in_partnership(partnership_id))` **with explicit `WITH CHECK (public.is_in_partnership(partnership_id))`** — writes (INSERT/UPDATE) are validated against the caller's accepted partnerships at the DB layer, so a row can never be created in — or moved into — a pending/rejected partnership.
- **Helper Function `is_in_partnership` Code:**
  ```sql
  SELECT EXISTS (
    SELECT 1 FROM public.partnerships
    WHERE id = p_partnership_id
    AND status = 'accepted'
    AND (user_id_1 = public.current_user_id() OR user_id_2 = public.current_user_id())
  );
  ```
- **Assessment:** **ACCEPTED-ONLY RELATIONSHIP CHECK**. `is_in_partnership` requires the `partnerships` row to both include the caller and have `status = 'accepted'`. Pending or rejected requests no longer grant any access.

#### `moods`
- **Policies:**
  - `moods_related_access` (SELECT): `USING ((user_id = public.current_user_id()) OR public.is_partner_of(user_id))`
  - `moods_manage_own` (INSERT), `moods_update_own` (UPDATE), `moods_delete_own` (DELETE): `user_id = public.current_user_id()`
- **Assessment:** `is_partner_of` filters by `status = 'accepted'` as well, so only an accepted partner's mood rows are readable.

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
   - Directly queries `v_active_partnership`, `v_drive_dashboard`, `moods`, `missyou`, `bucket_items`, `game_questions`, `game_answers`, `drive_items`, `favorites`, `drive_item_reactions`, and calls the `get_pending_invitations` RPC for pending-request identity.
   - All Flutter direct requests pass through Supabase PostgREST with user JWT context, evaluating RLS policies.

2. **Backend Server Layer:**
   - Operates with `service_role` key to manage `auth_sessions`, `request_nonces`, API audit logs (`logs_api_access`, `logs_api_errors`, `logs_security_events`, `logs_auth_failures`), and execute SECURITY DEFINER procedures (`debug_wipe_user_data`, `get_partnership_names`).
   - Bypasses RLS by design for platform security middleware.

---

## Implementation Status

- **RLS Activation on All Tables:** **100% IMPLEMENTED** (25/25 tables)
- **Backend Infrastructure Protection:** **100% IMPLEMENTED** (`auth_sessions`, `logs_*` closed to users)
- **Security Invoker Views:** **100% IMPLEMENTED** (`v_active_partnership`, `v_drive_dashboard`)
- **Strict Relationship Validation (`status = 'accepted'`):** **IMPLEMENTED** (`is_in_partnership`, `is_partner_of`, and `private.is_related_user` all require `status = 'accepted'`)
- **Explicit `WITH CHECK` on Shared-Table Mutation:** **IMPLEMENTED** (`drive_items_related`, `bucket_items_partnership_access`, `game_questions_related`, `missyou_related` all carry `WITH CHECK (is_in_partnership(partnership_id))`; INSERT/UPDATE outside the caller's accepted partnership is rejected at the DB layer)
- **Strict User & Profile Isolation:** **IMPLEMENTED** (`users` self-only; `user_profiles` self + accepted partner via `private.is_related_user`; pending invitation identity exposed only through the scoped `get_pending_invitations` RPC)

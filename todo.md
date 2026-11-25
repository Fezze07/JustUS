# JustUS — Fixing Phase · Master Todo List

> **Purpose**: the live worklist for verified defects. Everything already closed is archived in [`docs/fixing-phase-log.md`](docs/fixing-phase-log.md) (→ Outcome by phase, → Item index, → Decisions of record).
> **This file is tracked and committed with each fix.** Rules for working an item: `.agents/skills/fix-workflow/SKILL.md`.
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target `file:line`, the exact defect, the concrete fix and acceptance criteria.
> **Audit source**: [`.agents/codebase-audit-2026-11-04.md`](.agents/codebase-audit-2026-11-04.md). Every item below was re-verified against the live tree on 2026-11-04 (branch `dev`); nothing here is copied from a doc without checking the code.
>
> **Finding-ID prefixes**: `17.x` media delivery, `18.x` retention/backend safety, `21.x` schema/RLS/DB invariants, `22.x` docs/dead code, `23.x` regression tests.
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

**Baseline re-verified 2026-11-03** (`flutter test` → **386 pass** in `Flutter/test` · `flutter analyze` → clean · `npx jest --runInBand` in `Backend` → **258 pass / 22 suites** · `npm run lint` in `Backend` → 0 errors, 3 pre-existing warnings). SQL tests were not run locally (no `psql`/`DATABASE_URL`); live Supabase state is marked `Unverified — needs linked DB query`.

---

## Phase 0 — Ground truth & safety net

- [ ] **0.1 Re-run the baseline before touching anything**
  - Commands: `cd Flutter && flutter analyze && flutter test`; `cd Backend && npx jest --runInBand && npm run lint`.
  - Expected today: 386 Flutter pass, analyze clean, 258 Jest pass / 22 suites, 0 lint errors.
  - Acceptance: the numbers match this header; any drift is recorded before the first fix.

- [ ] **0.2 Confirm the migration/apply path before any SQL item**
  - `supabase/schemas/**` is the source of truth; there are no tracked migrations. Applying a schema change means `npx supabase@3.3.0 db query --remote --yes --file <script>.sql` (fix-workflow §1.9).
  - Acceptance: the linked project is reachable, or every Phase 21 item is explicitly left `Unverified` with the query that still needs to run.

---

## Phase 21 — Schema, RLS & DB invariants (🟡 MEDIUM / 🟢 LOW)

### 21.1 Add the documented `users.auth_id` FK (🟡 MEDIUM) ✅
- **Sources**: `docs/supabase/schema/doc.md:37`.
- **Files**: `supabase/schemas/public/tables/users.sql:1-10`, `supabase/schemas/public/functions/user_create_from_auth.sql:12-14`.
- **Defect**: the column is `uuid` with only a UNIQUE constraint; the docs claim `users_auth_id_fkey ... ON DELETE CASCADE`. Deleting an auth user leaves the public row and couple data; a later signup with the same email hits `users_email_key` inside the trigger.
- **Fix**: after cleaning orphans, add `FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE` (or an `AFTER DELETE` trigger if the auth schema cannot be referenced).
- **Acceptance**: deleting an auth user removes the public row and cascaded app data; the same email can register again.
- **Status: ✅ FIXED (2026-11-24, on `dev`)** — added the direct FK instead of an `AFTER DELETE` trigger because `auth.users` is referenceable, in `supabase/schemas/public/tables/users.sql:8`; the profile, partnership, mood, drive and device tables already cascade from `public.users` (audit logs are `SET NULL`), so one delete clears the app data and frees the email · **Verification**: applied to the linked project; `npx supabase@3.0.0 db query --remote` returned `users_auth_id_fkey FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE`; the cancellation test fixture now seeds the referenced `auth.users` rows before `public.users` (`supabase/test/rls_partnership_cancellation.test.sql:84-110`), confirming the constraint is enforced · **Residual**: `game_questions.user_id_a` / `user_id_b` still lack `ON DELETE` (S20), so a question row outside the user's partnership can still block the delete; no cascade assertion exists yet (23.4 open). SQL tests were not executed locally (no `psql`/`DATABASE_URL`).

### 21.2 Enforce cooldown and expiry in the cancellation trigger (🟡 MEDIUM) ✅
- **Sources**: `docs/features/partnership/doc.md:61` (24 h cooldown, 7-day expiry).
- **Files**: `supabase/schemas/public/functions/partnership_guard_status.sql:51-58`, `supabase/schemas/public/functions/partnership_request_cancel.sql:27-35`, `supabase/schemas/public/tables/partnerships.sql:49-56`.
- **Defect**: the RPC enforces `cancel_declined_at > now() - 24h` and writes `now() + 7 days`, but the trigger's `accepted → cancelled` branch only checks membership, requester and a non-null expiry. A direct PATCH can bypass the cooldown and set a 100-year expiry. Impact: a declined requester can re-spam immediately and freeze the pair in `cancelled` indefinitely.
- **Fix**: move the cooldown check and a `now() < cancel_expires_at <= now() + 7 days` bound into the trigger branch.
- **Acceptance**: a direct update within 24 h of a decline raises `42501`; a 100-year expiry raises `42501`; the RPC still sets exactly 7 days.
- **Status: ✅ FIXED (2026-11-24, on `dev`)** — duplicated the RPC's rules in the trigger's `accepted → cancelled` branch (`supabase/schemas/public/functions/partnership_guard_status.sql:58-66`): the 24 h decline cooldown (`API-VALIDATION-013`) and `now() < cancel_expires_at <= now() + interval '7 days'` (`API-VALIDATION-014`), because a direct PATCH bypasses the RPC; `partnership_request_cancel()` still writes exactly 7 days (`partnership_request_cancel.sql:34`) · **Verification**: applied to the linked project; `npx supabase@3.0.0 db query --remote` confirmed both validation markers and the 7-day bound in the live function body; assertions D1b (`supabase/test/rls_partnership_cancellation.test.sql:705`) and E7 (`:930`) cover the cooldown and the out-of-range expiry · **Residual**: the RPC and trigger now duplicate the cooldown/expiry rules, so a future edit must change both; SQL tests were not executed locally (no `psql`/`DATABASE_URL`).

### 21.3 Enforce one accepted partnership in the trigger (🟡 MEDIUM) ✅
- **Files**: `supabase/schemas/public/functions/partnership_accept.sql:21-29`, `supabase/schemas/public/functions/partnership_guard_status.sql:43-59`, `supabase/schemas/public/tables/partnerships.sql:49-53`.
- **Defect**: the RPC checks for another `accepted`/`cancelled` partnership, but the trigger's `pending → accepted` branch does not. Two direct PATCHes create two accepted rows; `v_active_partnership` returns two, `maybeSingle()` throws, and `mood_set` picks an arbitrary partnership.
- **Fix**: add the same `EXISTS` single-partnership check to the trigger branch.
- **Acceptance**: with two pending rows, the second direct accept raises `42501`; the RPC still accepts exactly one.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — mirrored the RPC's `EXISTS` guard in the trigger's `pending → accepted` branch (`supabase/schemas/public/functions/partnership_guard_status.sql:48-57`), because a direct `PATCH` bypasses `partnership_accept`; the caller must still be `user_id_2` (`-008`) and may hold no other `accepted` / `cancelled` row (`-012`) · **Verification**: applied the function to the linked project; `pg_get_functiondef` shows the `p2.status IN ('accepted', 'cancelled')` guard and the `API-VALIDATION-012` message; a rolled-back remote transaction with two pending rows for one recipient let the first direct `PATCH` through and returned `42501` on the second, while `partnership_accept` still accepted a single pending row; the duplicate accepted/cancelled check returned no rows; assertion I1b added in `supabase/test/rls_partnership_cancellation.test.sql:1366-1406` · **Residual**: the rule is duplicated in the RPC and the trigger, so a future edit must change both; the `cancelled → accepted` branch has no equivalent check, but the linked project holds no user with more than one `accepted` / `cancelled` row, so a revert cannot create a second active pairing from the current data. No new item.

### 21.4 Persist the chosen username on signup (🟡 MEDIUM) ✅
- **Sources**: `docs/features/authentication/login-registration/doc.md:85`.
- **Files**: `supabase/schemas/public/functions/user_create_from_auth.sql:16-22`, `Flutter/lib/features/auth/auth_state.dart:370-372`.
- **Defect**: Flutter sends `{'username': name}` in `signUp` metadata, but the trigger inserts `split_part(NEW.email, '@', 1)` and ignores `raw_user_meta_data`. A user who registers as "Alice" appears as the email local part.
- **Fix**: `COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'username'), ''), split_part(NEW.email, '@', 1))`.
- **Acceptance**: registering with a name different from the email prefix stores that name; both auth docs state the same rule.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — the trigger now stores `COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'username'), ''), split_part(NEW.email, '@', 1))` as `display_name` (`supabase/schemas/public/functions/user_create_from_auth.sql:16-22`), so the `{'username': name}` metadata the Flutter client already sends wins over the email local part, and blank or missing metadata still falls back · **Verification**: applied to the linked project; `pg_get_functiondef` shows the metadata read and the fallback; the new `supabase/test/user_signup_provisioning.test.sql` passed against the linked project (trimmed username stored, blank and missing metadata fall back) and left no fixture rows · **Residual**: the metadata is user-editable, but it only seeds a cosmetic display name (the profile editor already lets the user change it), never an authorization decision; profiles created before this fix keep their old name. SQL tests were not executed locally (no `psql`/`DATABASE_URL`); the new test ran remotely.

### 21.5 Regenerate the pgdelta manifest (🟡 MEDIUM) ✅
- **Files**: `supabase/schemas/.pgdelta-export.json`, `scripts/generate_pgdelta_manifest.js`.
- **Defect**: manifest lists 68 files; the directory has 76. It still lists the deleted `public/functions/partnership_get_names.sql` and omits nine functions, including the cancellation RPCs and `device_purge_dead_sessions`. A diff can fail or generate `DROP FUNCTION` for live features.
- **Fix**: remove the stale entry, regenerate the export, and add a files-vs-directory check.
- **Acceptance**: 0 missing / 0 unlisted; `supabase db diff` is empty against the applied schema. **Unverified — needs linked DB query**: the applied remote schema.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — added `scripts/generate_pgdelta_manifest.js`, which rebuilds `files` from `supabase/schemas/**/*.sql`, drops stale entries and appends new ones to the end of their `loadOrder` group; `--check` exits 1 on drift. Ran it (78 files, 10 added, 1 removed: `partnership_get_names.sql`) and wired it into `.husky/pre-commit` (auto-fix + stage) and `scripts/test-all.sh`; the fix-workflow hook description now matches · **Verification**: `node scripts/generate_pgdelta_manifest.js --check` → up to date; a probe SQL file was reported missing by `--check`, added by the generator, then removed cleanly; `node --check` and `bash -n` pass; assertion: 78 files on disk = 78 in `files` = 78 in `loadOrder`, no duplicates; `supabase db schema declarative generate --remote --output-dir` lists every local file (the only extras are the CLI's `adp_wipes.sql` helper and the Supabase-managed `hypopg` / `index_advisor` extensions) · **Residual**: the hook needs Node on PATH and scans the working tree, so a partially staged schema file enters the manifest before the file itself is staged; `supabase db diff` was not run because it diffs the migrations baseline, which this repo does not track.

### 21.6 Add retention indexes (🟢 LOW) ✅
- `supabase/schemas/public/tables/request_nonces.sql`, the five log tables — no index on `request_nonces(expires_at)` or `created_at` for the swept log tables. Add btree indexes. Acceptance: `EXPLAIN` shows index scans; a seeded 100k-row sweep completes within the statement timeout.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — added `idx_request_nonces_expires_at` plus `idx_logs_api_access_created_at`, `idx_logs_api_errors_created_at`, `idx_logs_security_events_created_at` and `idx_logs_notifications_created_at` in the matching table files; `logs_auth_failures` already had `logs_auth_failures_created_idx (created_at DESC)`, so it was left unchanged · **Verification**: applied to the linked project; a rolled-back probe seeded 100k recent + 1k expired rows per table, and `EXPLAIN (FORMAT JSON) DELETE …` chose the new index (`Index Scan`) on all five; the 1k-row `logs_api_access` sweep deleted in 13.5 ms, and `supabase/test/retention_cleanup_old_logs.test.sql` passed · **Residual**: each index adds write cost to log/nonce inserts, and the planner may still seq-scan a small table until it grows. No local SQL run (no `psql`/`DATABASE_URL`); the probe ran remotely.

### 21.7 Drop dead catalog tables and drive-file metadata (🟢 LOW) ✅
- `supabase/schemas/public/tables/permissions.sql`, `roles_permissions.sql`, `drive_file_types.sql`, `drive_items.sql:12`, `views/v_drive_dashboard.sql:9-11,21`, `supabase/test/rls_policy_matrix.test.sql:120,184`, `supabase/test/rls_anon_blocked.test.sql:99-103,223-226` - capabilities are hardcoded in JS; the three catalogs are referenced only by SQL test fixtures, never by runtime code; `drive_file_types` is never written and the view's `ft` columns are ignored. Drop the three tables, `drive_items.file_type_id`, and the `ft` select/join; keep `roles`/`user_roles`, and update the two RLS test fixtures. Acceptance: repo-wide grep finds no runtime references; both RLS SQL tests are updated and still pass; `v_drive_dashboard` still returns the fields the client consumes.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — dropped `permissions`, `roles_permissions`, `drive_file_types`, `drive_items.file_type_id` with its FK and index, and the view's `ft` select/join, because capabilities are hardcoded in `Backend/features/auth/authorization.service.js` and no runtime code reads the catalogs; `roles`/`user_roles` stay · **Verification**: applied to the linked project (`public` tables 26 → 23, `to_regclass` null for all three, `file_type_id` column count 0); `v_drive_dashboard` returns `id,partnership_id,name,original_name,type,size,created_at,updated_at,is_favorite,reactions,metadata` and still serves the Flutter model; `rls_policy_matrix.test.sql` and `rls_anon_blocked.test.sql` both passed remotely with the 3-catalog allowlist; `node scripts/generate_pgdelta_manifest.js --check` → up to date (75 files); repo-wide grep finds no runtime reference outside `todo.md` and the historical audit · **Residual**: the 7 `permissions` and 13 `roles_permissions` rows were dropped with the tables (no runtime consumer); both RLS fixtures now seed `auth.users` before `public.users` (required since 21.1) and the anon test asserts fixture-scoped counts so it runs on the populated project. No new item.

### 21.8 Fix the auth redirect allow-list (🟢 LOW) ✅
- `supabase/config.toml:158-162`, `Flutter/lib/features/auth/auth_state.dart:88-101` — the exact allow-list has only `http://127.0.0.1:3000` and `https://127.0.0.1:3000`; the client sends `justus://auth/callback` and the server `/auth/callback`. Add the exact mobile and server callback URLs; correct the `https` localhost typo. Acceptance: GoTrue accepts each client redirect and a mobile confirmation link opens `justus://auth/callback`.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — replaced the mistyped `https://127.0.0.1:3000` entry with the three URLs `AuthState._emailRedirectTo` actually produces: `justus://auth/callback` (mobile), `https://justus-dev.serverfede.eu/auth/callback` (debug web/desktop) and `https://justus.serverfede.eu/auth/callback` (release web/desktop); `site_url` already allows `http://127.0.0.1:3000` exactly, so no separate localhost entry is kept. Pushed only `auth.additional_redirect_urls` to the linked project with a minimal `config push`, because the full local `config.toml` would also have changed ten unrelated auth/db/storage properties · **Verification**: `supabase config diff` now reports no drift on `auth.additional_redirect_urls` (0 updates for the minimal config; before the push the remote lacked only the dev callback); the linked GoTrue list is `["justus://auth/callback","https://justus.serverfede.eu/auth/callback","https://justus-dev.serverfede.eu/auth/callback"]`; `AndroidManifest.xml` declares the `justus://auth/callback` scheme and the `https://justus.serverfede.eu/auth/callback` app link, and `ApiConfig` supplies both server origins · **Residual**: iOS has no `CFBundleURLTypes` for the `justus` scheme, so the same confirmation link still dead-ends on iOS — tracked as 21.11; a custom `JUSTUS_DEV_SERVER_ORIGIN` / `JUSTUS_PROD_SERVER_ORIGIN` still needs its own callback added to the allow-list.

### 21.9 Correct the Supabase docs contradictions (🟢 LOW) ✅
- `docs/supabase/database-logic/doc.md:178` claims the pending-invitations RPC exposes email (it returns `partner_display_name` only); `:277` claims `logs_auth_failures` cascades on user delete (it is `ON DELETE SET NULL`) and omits `logs_notifications`; `docs/supabase/rls/doc.md:138,161,169` names `auth_sessions` instead of `session_bindings`/`auth.sessions`. Correct all five claims. Acceptance: docs match `pg_get_function_result` and the FK definitions.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — updated `docs/supabase/database-logic/doc.md` (`:178` to list `partner_display_name` only, `:298` to list `logs_notifications` as cascading and `logs_auth_failures` as `ON DELETE SET NULL`) and `docs/supabase/rls/doc.md` (`:135,158,166` from `auth_sessions` to `session_bindings`) · **Verification**: `rg -n "auth_sessions" docs/supabase/rls/doc.md` → 0 matches; cross-checked against `logs_auth_failures.sql:15` and `logs_notifications.sql:8` · **Residual**: none.

### 21.10 Resolve the missing seed file (🟢 LOW)
- `supabase/config.toml:67-72` — seeding is enabled with `sql_paths = ["./seed.sql"]`, but `supabase/seed.sql` does not exist. Add the seed file or disable the `[db.seed]` entry. Acceptance: a fresh `db reset` completes and the intended catalog rows exist, or seeding is explicitly disabled.

### 21.11 Register the `justus://` URL scheme on iOS (🟡 MEDIUM) ✅
- **Files**: `Flutter/ios/Runner/Info.plist`, `Flutter/android/app/src/main/AndroidManifest.xml:32-45`.
- **Defect**: Android declares the `justus://auth/callback` intent filter and the HTTPS App Link, but iOS has no `CFBundleURLTypes` entry for the `justus` scheme. `AuthState._emailRedirectTo` returns `justus://auth/callback` on iOS, so a confirmation or password-recovery link cannot open the app there and dead-ends in the browser.
- **Fix**: add a `CFBundleURLTypes` entry with `CFBundleURLSchemes = ["justus"]` and verify the confirmation link opens the app.
- **Acceptance**: a confirmation email opened on an iOS device launches JustUS through `justus://auth/callback`.
- **Status: ✅ FIXED (2026-11-25, on `dev`)** — added `CFBundleURLTypes` (`CFBundleTypeRole = Editor`, `CFBundleURLName = $(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleURLSchemes = ["justus"]`) to `Flutter/ios/Runner/Info.plist:25-36` · **Verification**: XML well-formedness verified via PowerShell `[xml](Get-Content Flutter/ios/Runner/Info.plist)`; on-device iOS launch not run (Windows host, no macOS/iOS device) · **Residual**: confirm `justus://auth/callback` opens the app on an iOS device/simulator.

---

## Phase 22 — Docs & dead-code hygiene (🟢 LOW; all open)

### 22.1 Correct the feature docs (🟢 LOW)
- **Sources**: the claims below are the source; the code is the truth.
- **Files/claims**:
  1. `docs/features/shared-drive/doc.md:28,241,348` — `/api/v1/media/download-signed` → `/api/v1/media/file`.
  2. `docs/features/bucket-list/doc.md:28` — "There is no `updated_at` column" contradicts the table and lines 85/209/212; delete the sentence and describe the trigger.
  3. `docs/app/architecture/doc.md:73` — "eleven providers"; `main.dart:130-146` creates ten.
  4. `docs/app/architecture/doc.md:524` — `UpdateService` is "desktop only"; it runs on every non-web platform.
  5. `docs/features/profile-settings/doc.md:129,283` — `debugWipeData()` lives on `UserRepository`; `ProfileState` exposes `wipeAppData()`.
  6. `docs/features/profile-settings/doc.md:186` — `app_version` is marked "NO" cleared on logout; `StorageService.clearAll()` clears it.
- **Fix**: update each claim to the current code/schema; do not keep history.
- **Acceptance**: a grep finds no `download-signed`, no "no `updated_at`", no "eleven providers", no "desktop only", no `ProfileState.debugWipeData`, and the app_version row says `YES`.

### 22.2 Correct the backend/Supabase docs (🟢 LOW)
- **Files/claims**:
  1. `docs/backend/infrastructure/doc.md:19,84` — "138 modules"; `all_imports.js` has 133 getters.
  2. `docs/supabase/schema/doc.md:9,16` — `supabase/schema/remote_schema.sql` does not exist; the declarative schema is the source of truth.
  3. `docs/backend/api-architecture/doc.md:164` — `/app-version` reads `data/versions/app_version.json`, not an `app_versions` table.
  4. `docs/backend/error-handling/doc.md:68` — `ErrorHandler._toAppError` does not exist; the method is `toAppError`.
- **Fix**: correct the counts, remove the dead path, describe the JSON file, fix the method name.
- **Acceptance**: `Test-Path supabase\schema\remote_schema.sql` is false and the doc no longer claims it; the getter count matches `Select-String -Pattern "^\\s*get \\w+\\(\\)"`; the version doc matches `versionService.js`.

### 22.3 Delete the dead notification helper (🟢 LOW)
- `Backend/features/notifications/notification.service.js:155-163,168` - `getReceiverInstallationId` has no callers. Delete the helper and its export. (The 40 never-destructured `all_imports.js` getters are generated by `tool/generate_imports.js`; regeneration re-adds them, so they are deliberately not tracked as dead code.) Acceptance: grep returns no references; Jest/eslint green.

### 22.4 Delete the unused `LanguageHelper` statics (🟢 LOW)
- `Flutter/lib/core/localization/language_helper.dart:91-102` — `languageForLocale` and `LanguageHelper.isSupported` have no callers in `Flutter/lib`, `Flutter/test`, `Backend`, `supabase`, `docs` or scripts. Delete both. Acceptance: repo-wide grep returns only the generated `AppLocalizations.isSupported`; analyze clean.

---

## Phase 23 — Regression tests (🟠 HIGH / 🟡 MEDIUM)

The current suites are green with every finding present; these tests are the safety net, not a re-test of the acceptance lines above. Archived item IDs (17.x, 18.x, 19.x, 20.x) resolve in `docs/fixing-phase-log.md` § Item index.

- [ ] **23.1 Media auth + resolver tests (🟠 HIGH)** — cover 17.1/17.2: post-bind header map contains `Authorization` + `X-Device-Fingerprint`; `/media/file` resolves `drive_items.name`, `metadata.thumbnail` and `user_profiles.profile_pic_url`; unrelated-user and crafted-key requests are rejected. Acceptance: the tests fail if the fingerprint header or either resolver branch is removed.
- [ ] **23.2 Retention pagination + five-table prune tests (🟠 HIGH)** — cover 18.1/18.2: 1001-row pagination keeps the last referenced object; the sweep issues DELETEs for `logs_auth_failures`, `logs_notifications`, `logs_api_access`, `logs_api_errors`, `logs_security_events`. Acceptance: both tests are falsifiable (removing a page or a table breaks them).
- [ ] **23.3 Cross-account logout state test (🟡 MEDIUM)** — cover 19.3/19.4/19.5: A's partnership cache, sent/received invitations, `PartnerState` and an in-flight `ProfileState.loadProfile()` are all empty after logout and before B's first frame. Acceptance: the test fails if any teardown line is removed.
- [ ] **23.4 SQL trigger invariant tests (🟡 MEDIUM)** — cover 21.1/21.2/21.3: auth-user delete cascades; direct PATCH within the cooldown or with an out-of-range expiry raises `42501`; a second direct accept raises `42501`. 21.2's cooldown and expiry assertions exist as D1b/E7 in `supabase/test/rls_partnership_cancellation.test.sql`; the cascade and second-accept assertions remain. Acceptance: each assertion fails against the current SQL and passes after the fix.

---

## Finding-to-section index

| Audit area | Todo sections |
| :--- | :--- |
| Schema, RLS & DB invariants | 21.1–21.10 |
| Docs & dead-code hygiene | 22.1–22.4 |
| Regression tests | 23.1–23.4 |

---

## Suggested fix order (batch plan)

> Update it as findings are fixed; re-verify each item's "Acceptance" line before ticking. **Commit this file with the fix.**

1. **Sprint A — regression safety net for retention**: 23.2 (covers archived 18.1/18.2). The sweep code is fixed; this test guards against a future unpaginated read or a dropped table.
2. **Sprint B — media regression tests**: 23.1 (covers archived 17.1/17.2). The header and resolver are fixed; this test keeps both branches from regressing.
3. **Sprint C — auth/session regression test**: 23.3 (covers archived 19.3/19.4/19.5). The teardown is fixed; this test keeps cross-account state from returning.
4. **Sprint D — enforce DB invariants**: 21.1 ✅ → 21.2 ✅ → 21.3 ✅ → 21.4 ✅ → 21.5 ✅ (+23.4). Each SQL item must be applied to the linked project before it is ticked.
5. **Ongoing — low-severity sweep**: Phase 22 plus the remaining 21.9–21.11 rows. Safe to batch by file, one commit per item.

---

## Known non-bugs & deliberate decisions

- **Shared media rate-limit bucket (40/user/min for reads, uploads and deletes)** — deliberate, recorded in `docs/audits/media-delete-audit.md` §F-5. Do not "fix" without a product decision.
- **15 MB pre-compression upload cap** — deliberate (phase 5.4).
- **Fingerprint survives logout** — deliberate (phase 10.1); `docs/app/storage-and-caching/doc.md:51,207` is correct.
- **Notification preference is device-level across accounts** — documented in `storage_service.dart:446-452`; distinct from the background-delivery bug archived as 19.7.
- **Homepage does not use `TabScreenMixin`; Profile is not wired to realtime** — documented in `docs/app/architecture/doc.md:460-464` and `docs/app/state-management/doc.md:140`.
- **`debug_` table/function prefix** — deliberate (phase 10.17).
- **Nonce fail-open, `session_is_live` fail-open, orphan-sweep read-failure skip** — accepted decisions #36, #37, #45 in `docs/fixing-phase-log.md`.

---

## Not confirmed (do not track as fixes until reproduced)

S1 remote `signedOut` handling · S2 `PartnerScreen` cold entry · S3 duplicate invitation RPC · S4 device-level notification preference · S5 `loadSingleItem` empty list · S6 mood recent chips · S7 first drive tile highlight · S8 bucket `ChoiceChip` design drift · S9 302 forwards `Authorization` to R2 · S10 legacy token without `session_id` · S11 cancellation cleanup race · S12 timeout double-response · S13 idempotency caches errors · S14 custom rate-limit window · S15 logger stdout before sanitization · S16 pre-relationship moods · S17 crafted `drive_items` key (closed by 17.2) · S18 missing `seed.sql` (tracked as 21.10) · S19 hosted SQL test privileges · S20 `game_questions` FKs without `ON DELETE`.

Full evidence for these is in `.agents/codebase-audit-2026-11-04.md` § Not Confirmed / Suspicions.

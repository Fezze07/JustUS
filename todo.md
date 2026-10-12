# JustUS — Fixing Phase · Master Todo List

> **Purpose**: the live worklist for verified defects. Everything already closed is archived in [`docs/fixing-phase-log.md`](docs/fixing-phase-log.md) (§ Outcome by phase, § Item index, § Decisions of record, § Tests added).
> **This file is local-only and never committed** (`.gitignore: /todo.md`). Rules for working an item: `.agents/skills/fix-workflow/SKILL.md`.
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target `file:line`, the exact defect, the concrete fix and acceptance criteria.
>
> **Finding-ID prefixes** (from the docs): `F-SC` storage/caching, `F-RT`/`R-` realtime, `F-SM` state management, `F-PN` push notifications, `F-DS` design system, `F-N` navigation, `F-BL` bucket list, `F-A` architecture.
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

**Suite totals re-verified 2026-10-10** (`flutter test` → 300 pass in `Flutter/test` · `flutter analyze` → clean · `npx jest --runInBand` in `Backend` → **167 pass / 15 suites** (re-verified 2026-10-12) · `npm run lint` in `Backend` → 0 errors, 10 pre-existing warnings · `scripts/run-sql-tests.sh` → 11 SQL files selected, **0 executed** locally (no `psql`/`DATABASE_URL`); `supabase/test/prune_user_devices_dead_sessions.test.sql` + `rpc_execute_grants.test.sql` were run instead via `npx supabase@2.120.0 db query --linked` — the new prune test passed, the grants test exposes a pre-existing `drive_change_probe` anon-grant drift, see 11.6).

---

## Phase 10 — Verified defects found in the docs sweep (added 2026-09-28)

Every item below was **re-verified against the code** before it was written here — not taken from the doc on trust. Source: a full sweep of the findings sections in `docs/app/**`, `docs/features/**`, `docs/backend/**`, `docs/supabase/**` and `docs/audits/**`.

### 10.12 🟡 `login()` registers the FCM token without the `supportsFcm` guard
- **Sources**: `docs/app/notifications/doc.md:399` (F-PN5).
- **Files**: `Flutter/lib/features/auth/auth_state.dart:308-315` (login Step 4) vs `:152` (init) and `:235` (register, `if (!DeviceTokenService.supportsFcm) return;`).
- **Defect**: verified the guard exists on the two other call sites but not in `login()`. On a platform where FCM is unsupported (macOS, Linux) `getDeviceToken()` yields no usable token, so login attempts to register a null/placeholder token and the backend rejects it with a 400 that is caught and only logged — a guaranteed noisy failure on every desktop login.
- **Fix**: apply the same `supportsFcm` early return used at `:235`, and share one `_registerDeviceToken()` helper across all three call sites so the guard cannot drift again.
- **Acceptance**: on a platform without FCM support, `login()` performs no device-token request; a unit test asserts zero calls when `supportsFcm` is false.
- **Status: ✅ FIXED (2026-10-12, on `dev`)** — the missing guard was confirmed (`login()` called `getDeviceToken()`/`updateDeviceToken()` unguarded) and the corrected impact (shared 20-char sentinel colliding on the globally-unique `device_token`) is the one fixed. Extracted one `_registerDeviceToken()` helper (`auth_state.dart:263-280`) that enforces `supportsFcm` + rejects the `UNKNOWN_DEVICE_TOKEN` placeholder, and routed `init()`, `login()` and `_syncDeviceLocale()` through it so the guard cannot drift again; added an `auth.schemas.js` refinement rejecting the placeholder at the trust boundary. Confirmed the upsert's `onConflict: "device_token"` target is correct and left it unchanged: the global `UNIQUE(device_token)` is intended for real FCM tokens (one device → one active push target) and the placeholder was the only collision. · **Verification**: `flutter test test/login_device_token_guard_test.dart` → 2 pass (registers on FCM, skips without); `npx jest test/auth.routes.test.js` → 16 pass · **Residual**: the finding is removed from `notifications/doc.md`, leaving the `F-PN5` ID gap (matches the pre-existing `F-PN8` gap; no renumber, per repo precedent).
- **Real defect (replaces the old impact)**: the schema accepts a shared sentinel string, and the upsert conflicts on the globally-unique `device_token` column (`Backend/features/auth` → `user_devices_device_token_key`). Every macOS/Linux user therefore upserts the **same** row, silently re-pointing one global registration between unrelated accounts as they log in and out. Whoever registers last owns the device's push target; earlier users stop receiving notifications and the row's `user_id` no longer matches its owner.
- **Fix (updated)**: (a) keep the `supportsFcm` early return in `login()`; (b) reject the sentinel explicitly — `z.string().min(16).max(512).refine(t => t !== 'UNKNOWN_DEVICE_TOKEN')`, or better, have `DeviceTokenService.getDeviceToken()` return `null` and skip registration entirely instead of inventing a placeholder; (c) confirm the upsert's conflict target is `(user_id, device_token)` rather than `device_token` alone.
- **Acceptance (updated)**: on a platform without FCM support, `login()` performs no device-token request; a unit test asserts zero calls when `supportsFcm` is false; and two different users on two FCM-less platforms produce two distinct `user_devices` rows, neither of which is named `'UNKNOWN_DEVICE_TOKEN'`.

### 10.13 🟡 The optimistic rejection filter can never match
- **Sources**: `docs/features/partnership/doc.md:246` (finding 1).
- **Files**: `Flutter/lib/features/partnership/partner_state.dart:88-93` — `receivedRequests.where((u) => u.id != partnershipId)`.
- **Defect**: verified. `receivedRequests` holds user objects, so `u.id` is the requesting partner's **user id**, while `partnershipId` is the partnership primary key. The predicate compares two different id spaces and never removes anything, so a rejected request stays visible in the pending list until the next fetch.
- **Fix**: filter on the request's partnership id (`u.partnershipId != partnershipId`, or whatever field the model actually carries — check the model before editing), and add a unit test that rejects a request and asserts the list shrinks.
- **Acceptance**: `rejectPartner(1)` on a list of one request empties `receivedRequests` immediately.
- **Status: ✅ RESOLVED via 12.6 (2026-10-12, on `dev`)** — the id-space mismatch was confirmed, but the whole path is dead code, so the repair 10.13 proposed would have changed nothing observable. The orphaned branch was deleted together with the rest of the unused `pending_received` contract (see 12.6): no `PartnerState.receivedRequests`/`acceptPartner`/`rejectPartner` remains.

### 10.14 🟡 `ProfileState.loadProfile()` returns before reading the cache when already loading
- **Sources**: `docs/app/architecture/doc.md:459,469` (F9), `docs/app/navigation/doc.md:161`.
- **Files**: `Flutter/lib/features/settings/profile_state.dart:43-45` — `Future<void> loadProfile({bool force = false}) async { if (isLoading) return;`.
- **Defect**: verified. The guard sits before the cache read, so a second concurrent caller returns immediately with whatever state exists — empty on a cold start. `docs/app/navigation/doc.md:161` pairs this with a second defect: the tab keeps a resident `ProfileScreen` while the home menu pushes a **separate** `ProfileScreen` route, so two `State` objects share one `ProfileState` and the second one's load is the one that gets skipped.
- **Fix**: let the cache read happen for every caller, and guard only the network fetch (e.g. an in-flight future the second caller can await) — which also removes the duplicate-screen mismatch.
- **Acceptance**: two concurrent `loadProfile()` calls both end with a populated state; the profile screen is not mounted twice.
- **Status: ⚠️ PARTIAL (scope trimmed 2026-09-29)** — the `isLoading` guard at `profile_state.dart:43-45` is confirmed and the first half stands unchanged. The second half is **stale**: `ProfileScreen` is instantiated in exactly one place (`Flutter/lib/features/home/screens/main_shell.dart:122`); the only other match repo-wide is the class declaration in `profile_screen.dart:17`. There is no second mount, so the duplicate-screen mismatch described in `docs/app/navigation/doc.md:161` no longer describes the code, and no part of this fix depends on it. The doc row is folded into 9.6.

### 10.15 🟡 The drive incremental cursor is a strict `>`, so equal timestamps are skipped
- **Sources**: `docs/app/realtime/doc.md:402` (R-5), `docs/app/storage-and-caching/doc.md:162`.
- **Files**: `Flutter/lib/features/drive/drive_repository.dart:35` — `query.gt('updated_at', lastSyncTimestamp)`.
- **Defect**: verified `gt`, not `gte`. A row whose `updated_at` equals the stored checkpoint is skipped forever, so an edit that lands in the same millisecond as the previous sync is invisible to incremental fetch. Deletions are already covered by `drive_change_probe` (4.4), so this is the update-side residue only.
- **Fix**: use `gte` and rely on the probe/`updated_at` trigger for idempotency, or store `(updated_at, id)` and compare the pair. Decide against the trigger's `updated_at` bump semantics first.
- **Acceptance**: an item updated at exactly the checkpoint timestamp appears in the next incremental sync.
- **Status: 🟢 OPEN**

### 10.16 🟠 There is no backend mailer: an invitation creates a row and sends nothing
- **Sources**: `docs/audits/email.md:9,11-13,70,76-78`, `docs/features/partnership/doc.md:246,153-157` (finding 1, H2/H5).
- **Files**: `Backend/package.json` (dependencies are `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`, `@supabase/supabase-js`, `axios`, `dotenv`, `express`, `firebase-admin`, `helmet`, `zod` — **no mailer SDK**), `Backend/features/auth/auth.controller.js:164-182` (`invitePartnerController`), `supabase/schemas/public/functions/request_partnership.sql`.
- **Defect**: the backend has no mailer SDK, but Supabase Auth is configured with custom SMTP (Resend) for Auth emails (confirm sign-up, invite user via Supabase Auth, reset password, password changed, etc.). The custom partner invite endpoint (`POST /api/v1/auth/invite`) creates a pending `partnerships` row via `request_partnership` RPC but does **not** dispatch an email; code sharing is manual/out-of-band. The original item incorrectly stated "no email service are available" — Supabase Auth SMTP is available, but this specific flow doesn't use it.
- **Fix**: clarify in docs that Supabase Auth SMTP exists, but the custom invite flow does not send email (intentional for the current UX). Correct `docs/audits/email.md` and `docs/features/partnership/doc.md` to reflect this; no code changes needed.
- **Acceptance**: docs accurately state Supabase Auth SMTP is used for Auth events only; the partnership invite flow sends no email and the UI/code contract is documented as manual code sharing.
- **Status: ✅ RESOLVED (2026-10-12, on `dev`)** — docs clarified; no code change required. The phantom `partnership_invitations`/`notifications` tables claim is not present in these docs' current text; the clarification matches the actual implementation.

### 10.17 🟡 The production wipe endpoint calls a `debug_`-prefixed SECURITY DEFINER function
- **Sources**: `docs/supabase/database-logic/doc.md:74-83`, `docs/backend/api-architecture/doc.md:135-136`.
- **Files**: `supabase/schemas/public/functions/debug_wipe_user_data.sql`, `Backend/features/user/user.controller.js:38,51`.
- **Defect**: verified. A destructive, `SECURITY DEFINER` function is exposed through `POST /api/v1/users/wipe` under a name that marks it as debug tooling, so it is excluded from code review, from privilege audits and from any guardrail on production RPCs.
- **Fix**: rename to `wipe_user_data` (or `app_wipe_user_data`) with the same signature, keep one thin wrapper if the RPC name is referenced by grants, and re-apply to the linked remote database (`fix-workflow` §1.9). Also settle the related open question: whether a wipe should delete the `partnerships` row (9.6).
- **Acceptance**: no `debug_`-prefixed function is reachable from a production route; the renamed function is applied to the remote project and both docs agree on the wipe's effect on `partnerships`.
- **Status: 🟢 OPEN**

### 10.18 🟡 RPC exception messages are hardcoded Italian
- **Sources**: `docs/app/localization/doc.md:123`.
- **Files**: `supabase/schemas/public/functions/request_partnership.sql` — raises `'Utente non autenticato o ID non valido'`; `supabase/schemas/public/functions/send_missyou.sql` — raises `'No active partnership found'`.
- **Defect**: verified. Postgres raise messages are user-facing and arrive verbatim, so an English-locale user sees Italian (or, for `send_missyou`, English) regardless of the app language. The messages are also mixed-language across functions, and the localization doc's status table claims 100% implemented against a body that says 95%.
- **Fix**: return a stable machine-readable code plus a localized message resolved by the client (the app already has `ErrorCodes`), keeping the server text as a developer-facing fallback.
- **Acceptance**: an RPC error surfaces through the app's localized error path; no raw Postgres message reaches the UI in any locale.
- **Status: 🟢 OPEN**

### 10.19 🟡 Rejecting a partnership request bypasses the RPC that accepting uses
- **Sources**: `docs/features/partnership/doc.md:255` (finding 2).
- **Files**: `Flutter/lib/features/partnership/partnership_repository.dart` (accept calls the RPC; reject issues a direct table DELETE).
- **Defect**: documented CONFIDENCE MEDIUM. Accept goes through `accept_partnership` (validation, `ON DELETE` bookkeeping, notifications in the trigger); reject deletes the row directly, so the two paths have different encapsulation, different audit behaviour and — paired with 10.13 — a UI that never updates. The doc itself flags the asymmetry as "may or may not be intended".
- **Fix**: decide the intent, then either add a `reject_partnership` RPC that mirrors accept, or document the deliberate asymmetry. Verify against the SQL before choosing.
- **Acceptance**: both directions go through the same encapsulation, or the doc states the asymmetry and its reason.
- **Status: 🟢 OPEN**

---

### 10.20 🟡 A `hasChanges` failure rejects `loadWithChangeDetection` and skips the refresh (F-SM4)
- **Sources**: `docs/app/state-management/doc.md:220` (F-SM4, CONFIDENCE HIGH); promoted out of the triaged table below on 2026-10-03 while working 8.3.
- **Files**: `Flutter/lib/shared/utils/state/base_state.dart:50-59` (`:52`), with the `hasChanges` callbacks supplied by `bucket_state.dart:81-86`, `mood_state.dart`, `game_state.dart`, `drive_state.dart` and `base_repository.dart:79-108`.
- **Defect**: `loadWithChangeDetection` awaits `loadFromCache()` and then `hasChanges()` with **no `try`/`catch`**, while the network call below it is wrapped in `.catchError(...)` (`:55-57`). `hasChanges` does real network work — `BucketState._hasBucketChanges` chains `getActivePartnership()` then `hasNewBucketItems()` (bucket_state.dart:82,86), either of which can throw — so any offline/DB error there makes the returned future **reject** instead of degrading to cache-only, and `fetchFromNetwork` is never reached. Measured directly while working 8.3 (temporary probe, since removed): with a `hasChanges` that throws, the caller's `await` throws (`rejected=true`) and `fetchFromNetwork` is never invoked (`networkCalled=false`). That is the triaged row's "verify whether F-SM4's unhandled async error is observable" — **it is**, at the API boundary, and `HomepageScreen._loadData`'s `Future.wait` (homepage_screen.dart:72-77) is the likely first user-visible path because one rejecting member fails the whole wait.
- **Fix**: wrap the `hasChanges()` await in the same treatment as the fetch — on failure, route to `ErrorHandler.handle` and fall through to cache-only, i.e. treat an unknown change state as "assume changed and refetch" or "stay on cache", whichever the states' UX implies. `BucketState.init`'s `finally` already clears its guard (bucket_state.dart:70-72), so a re-init retries.
- **Acceptance**: a throwing `hasChanges` does not reject the returned future, the error reaches `ErrorHandler`, and the chosen fallback (refetch or cache-only) is asserted per state. Add the regression case to `Flutter/test/base_state_test.dart`, which now owns this file's coverage.
- **Status: 🟢 OPEN** — verified by probe, not yet fixed. The doc's own F-SM4 text was corrected in the same pass: it described the defect as "silently skips the refresh" and pointed at `bucket_state.dart:47-57` / `:37-38`, which are the dispose-flush lines, not `init`. Note the deliberate asymmetry is documented: F-SM3 (fire-and-forget by design) is an accepted trade-off, F-SM4 is not.

---

### 10.21 🟠 Structured log records don't match the log-table columns, so DB persistence always fails
- **Sources**: found while re-verifying 10.9 (no doc finding — the doc describes *record* fields as if they were columns). Ground truth: `supabase/schemas/public/tables/logs_*.sql` (source of truth, confirmed identical to the linked project via `information_schema` on 2026-10-11).
- **Files**: `Backend/core/logger.js` — `buildBaseLogRecord` (`:208-220`), `logAccess` (`:93-98`), `logError` (`:114-119`), `logSecurity` (`:131-136`), `logAuthFailure` (`:148-153`); callers `Backend/middleware/requestLogger.js:6-16`, `Backend/middleware/authMiddleware.js:111-118`, `Backend/features/auth/authRisk.service.js:60-67,123-127`, `Backend/middleware/rateLimit.js:179-187`, `Backend/features/notifications/notification.service.js:36`.
- **Defect**: with `SUPABASE_LOG_TO_DB=true`, every structured insert except `logs_notifications` is rejected because the record contains keys that are not columns of the target table (PostgREST PGRST204), and `persistLog` swallows the failure (an error line only), so **nothing is ever persisted**:
  - `logAccess` → `logs_api_access` (`id, request_id uuid, method, path, status_code, duration_ms, created_at, device_id`): record adds `user_id`, `auth_user_id`, `ip_address`, `user_agent` — not columns → fails.
  - `logError` / `logAppError→default` → `logs_api_errors` (`id, request_id uuid, path, method, error_json, created_at, device_id`): `buildBaseLogRecord` sends `error_code`, `error_message`, `user_id`, `endpoint`, `severity`, `ip_address`, `payload`, `stack` — none are columns (`endpoint` should map onto `path`/`method`, `payload` onto `error_json`) → fails.
  - `logAppError→AUTH` → `logs_auth_failures` (has `error_code, error_message, path, user_id, ip_address, reason, severity, payload, stack`): extra `endpoint` and `email` are not columns → fails; only the direct `authMiddleware.js:111` call, whose record matches the columns exactly, would succeed.
  - `logAppError→SEC` and every direct `logSecurity` caller → `logs_security_events` (`id, request_id uuid, type, path, error_json, created_at, device_id`): all send `user_id`, `ip_address`, `retry_after_seconds`/`strike_level`, and the logAppError route also `error_code`, `endpoint`, etc. — not columns, and `type` is the only populated column besides `path` → fails.
  - `logNotification` → `logs_notifications` (`type, status, user_id`): record shape matches → the only insert that works.
- **Fix**: option (a), recommended: rewrite each record to exactly the target table's columns (`path`/`method` instead of `endpoint`, `error_json` for the sanitized payload, drop `email` from `logAuthFailure`, cast `request_id` to uuid where the column is uuid) and update the `docs/backend/error-handling/doc.md` logging table to describe the DB columns; option (b), reshape the tables to the richer record model and apply to the linked DB, conflicts with the retention RPC `cleanup_old_logs` and the RLS policies that already read `path`/`method`/`error_json`.
- **Acceptance**: with `SUPABASE_LOG_TO_DB=true`, an insert per function succeeds against the linked DB (or a column probe proves every record key is a column of its target table); a logger unit test pins each insert payload against the table column list so future drift fails CI.
- **Status: 🟢 OPEN**

### Triaged from the docs sweep, not yet verified — not items

Recorded so the sweep is not lost. Each still needs a code check before it becomes a defect; several are likely accepted behaviour that only needs a doc line.

| Claim | Source | Why not an item yet |
| :--- | :--- | :--- |
| `BaseState` frame-coalescing (F-SM1, F-SM2) and fire-and-forget `loadWithChangeDetection` (F-SM3) | `state-management/doc.md:217-219` | Documented design trade-offs; F-SM4 was promoted out of this row to **10.20** on 2026-10-03, the other three stay as accepted behaviour |
| `DriveState._singleItem` mirrored copy (F-SM10) | `state-management/doc.md:225` | Verify the two write paths can actually disagree |
| PII in SharedPreferences (`user_profile`, `partner_profile`: email, authId, partnershipCode) (F-SC18) | `storage-and-caching/doc.md:288` | Platform-standard risk; needs an accepted-risk decision, not a fix |
| iOS duplicate foreground alert, badge hardcoded to 1, unknown `notificationKey` empty body, `getNotificationAppLaunchDetails`, server/client locale fallback (F-PN1, F-PN4, F-PN6, F-PN7, F-PN9) | `notifications/doc.md:364-440` | All LOW/INFO; F-PN1 and F-PN4 are explicitly unverified on device |
| Checkpoint covering undelivered events; optimistic `EMPTY` checkpoint (R-2, R-3) | `realtime/doc.md:394,398` | Rated LOW by the doc; R-3 is described as harmless |
| Bucket deletes invisible to the `updated_at` cursor; duplicate protection absent; offline add has no queue | `bucket-list/doc.md:307,110,112` | Covered by realtime/polling; absence of an offline queue is architectural |
| Mood timeline truncation on full refetch | `storage-and-caching/doc.md:71` | `mood_state.dart:112` shows correct pagination on the cached path; the full-refetch path (`:198`) needs a read before claiming loss |
| Videos and legacy images load full-size files in the drive grid | `shared-drive/doc.md:325` | Performance finding; verify the download path before iteming |
| `username` / `partner_display_name` survive an account wipe (F-SC17) | `storage-and-caching/doc.md:274` | Adjacent to decision 6 (theme/language survive); needs a decision, not a fix |
| `StorageService.resetForTest()` and other dead helpers; `sweepStalMultipartUploads` typo | `storage-and-caching/doc.md:262`, `infrastructure/doc.md:58` | Cosmetic dead code; batch with the next Phase 7 sweep |
| Firebase client keys are git-tracked; `.env.test` tracking stated both ways in the same audit; iOS plist link points at the macOS path | `audits/secrets.md:42-56,15/65,47` | Confirm `.gitignore` coverage, then fix the audit's own contradictions |
| `debug_wipe_user_data` name | `database-logic/doc.md:74-83` | Promoted to **10.17** — verified |
| Splash `_checkAuth()` has no try/catch | `navigation/doc.md:70` | **False** — moved to 9.6 as a stale row |
| No widget/route tests, no golden tests, no DS visual tests | `navigation/doc.md:326`, `design-system/doc.md:349,354` | Test coverage → **Phase 8** |

---

## Phase 11 — Security & privilege (added 2026-09-29)

Source: full-codebase scan, `docs/audits/2026-09-full-codebase-scan.md` §2–§3. All eight items were re-read in the working tree during the scan; every quoted line is verbatim. Phase 11 is one root-cause cluster in `partnerships.sql` — split the `FOR ALL` policy and 11.1–11.3 fix together.

### 11.1 🔴 An accepted partnership can be forged with a single INSERT
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.1; no prior doc finding — new.
- **Files**: `supabase/schemas/public/tables/partnerships.sql:5,27-31,33`.
- **Defect**: `partnerships_manage_own` is `FOR ALL` with `WITH CHECK (((user_id_1 = current_user_id()) OR (user_id_2 = current_user_id())))`. A client inserting `user_id_1 = <self>, user_id_2 = <victim>` satisfies the `OR` through the first column, and because `status` is omitted it takes the table default `'accepted'` (`:5`). The `partnership_code` check lives only inside `request_partnership` (`request_partnership.sql:30-33`), which a direct PostgREST insert never calls — so no code is needed, only the victim's sequential `users.id`. Any signed-in user can attach themselves to any account as an accepted partner, gaining the partnership-scoped read/write on that couple's drive, bucket, moods, miss-you, favourites and game answers.
- **Fix**: replace the single `FOR ALL` policy with per-command policies. For `INSERT`, a `WITH CHECK` that requires `user_id_1 = current_user_id()` and `user_id_2 <> current_user_id()` and `'pending' = status` — never trust a client-supplied `status`. For `SELECT`/`UPDATE`/`DELETE`, keep the two-member `OR` but scope them (11.2, 11.3). Consider removing `INSERT` from the `anon` grant at `:33` while doing this. Apply to the linked remote project (`fix-workflow` §1.9).
- **Acceptance**: as user A, `POST /rest/v1/partnerships` with `{"user_id_1": <A>, "user_id_2": <B>}` returns `401`/`403` and no row is created; with a `status` field it is rejected regardless of value. A user can still create a request only through `request_partnership`.
- **Status: 🟢 OPEN**

### 11.2 🔴 An accepted partnership can be re-pointed to a third party
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.2.
- **Files**: `supabase/schemas/public/tables/partnerships.sql:27-31`, trigger list at `:22-25`.
- **Defect**: `FOR ALL` includes `UPDATE`, and `WITH CHECK` is evaluated against the **new** row. An existing accepted pair `(A, B)` updates cleanly to `(A, C)`: the predicate passes on `user_id_1 = A` and nothing pins the previous `user_id_2`. The only trigger is `set_current_timestamp_updated_at` — nothing guards the membership columns. Member A can silently re-bind the partnership to an unrelated user, cutting B off and granting C the couple's data.
- **Fix**: either a `BEFORE UPDATE` trigger that rejects any change to `user_id_1`/`user_id_2` while a row is `accepted`, or drop `UPDATE` from the policy and route membership changes through a purpose-built RPC. Prefer the trigger: it also protects the RPC path.
- **Acceptance**: as member A of an accepted pair, `PATCH /rest/v1/partnerships?id=eq.<id>` changing `user_id_2` fails with a `PGRST` error and the row is unchanged.
- **Status: 🟢 OPEN**

### 11.3 🔴 Either member can DELETE the couple's shared history
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.3.
- **Files**: `supabase/schemas/public/tables/partnerships.sql:11-12,27-31`; `drive_items.sql:15`; `Flutter/lib/features/partnership/partnership_repository.dart:111-115`.
- **Defect**: `FOR ALL` includes `DELETE` and `USING` passes for either member. `user_id_1` and `user_id_2` both carry `ON DELETE CASCADE` (`:11-12`) and `drive_items.partnership_id` cascades too, so one member's `DELETE` destroys drive items, bucket items, moods, miss-you records, favourites, reactions and game data for **both** people. The "pending only" restriction exists solely client-side — `partnership_repository.dart:111-115` appends `.eq('status', 'pending')` to the request — and the server-side policy imposes no such condition, so the restriction is not actually enforced.
- **Fix**: restrict `DELETE` to rows the caller did not create and whose `status = 'pending'` (`user_id_1 = current_user_id() AND status = 'pending'`), or remove `DELETE` from the policy entirely and add a `reject_partnership` RPC (which also answers 10.19). Removing `DELETE` from the `anon` grant at `:33` is a free hardening step.
- **Acceptance**: as member A of an accepted pair, `DELETE /rest/v1/partnerships?id=eq.<id>` is refused and the couple's data is intact; a pending row the caller created can still be deleted.
- **Status: 🟢 OPEN**

### 11.4 🟠 `users_update_self` does not pin `auth_id` or `email`
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.4.
- **Files**: `supabase/schemas/public/tables/users.sql:3,6,7,37-41`; `supabase/schemas/public/functions/current_user_id.sql:7`.
- **Defect**: the `WITH CHECK` constrains only `id`, leaving `auth_id` and `email` writable. `auth_id` is `UNIQUE` (`:7`) so it cannot be pointed at another account directly, but a client can rewrite its own to an arbitrary uuid or `NULL`. `current_user_id()` resolves through `SELECT id FROM users WHERE auth_id = auth.uid()` (`current_user_id.sql:7`), so the row becomes unreachable: every RLS predicate calling `current_user_id()` starts returning `NULL` and the user is locked out with no self-service recovery. `email` can also be changed without re-verification. Noted for completeness: `users.sql:43` grants `DELETE` but no `DELETE` policy exists, so under RLS that grant is inert — do not "fix" it.
- **Fix**: add `auth_id = (SELECT auth.uid() AS uid)` and `email = <the value the `USING` clause read>` to the `WITH CHECK`, or split the policy so `auth_id`/`email` are immutable from the client and changed only by `handle_new_auth_user` or a verified flow.
- **Acceptance**: a client that `PATCH`es its own `users` row setting `auth_id` to a different uuid, or to `null`, is rejected and the row is unchanged; a legitimate `handle_new_auth_user` insert still works.
- **Status: 🟢 OPEN**

### 11.5 🟠 `anon` / `PUBLIC` hold EXECUTE on four partner-revealing functions
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.5. Contrast case: `get_pending_invitations.sql:39`, `get_game_stats.sql:23`.
- **Files**: `get_accepted_partner.sql:22`, `generate_unique_partnership_code.sql:23`, `accept_partnership.sql:18`, `cleanup_old_logs.sql:22`.
- **Defect**: four functions are granted to `anon` or `PUBLIC` while the comparable relationship functions explicitly `REVOKE ALL … FROM PUBLIC, "anon"`, so the inconsistency is unintentional. Not rated critical because all four are `SECURITY INVOKER` and RLS neutralises them for `anon` — `current_user_id()` is `NULL`, so `partnerships_manage_own` and `profiles_select_self_or_partner` yield nothing, `accept_partnership` matches zero rows, and the log tables' policies are `TO "authenticated"` with `USING (false)` or `FOR SELECT` only. The real residual is that `anon` can still **invoke** them: `cleanup_old_logs` runs four `DELETE` statements plus `make_interval` on every request (a resource-consumption vector, deleting nothing), and `generate_unique_partnership_code`'s `WHILE NOT done` loop cannot see any `user_profiles` row under `anon`, so it returns a code that may already be taken — silently defeating its uniqueness contract.
- **Fix**: align all four with the `get_pending_invitations.sql:39` pattern — `REVOKE ALL … FROM PUBLIC, "anon"` — and confirm each call site is `authenticated` or `service_role` before narrowing. For `generate_unique_partnership_code`, make the uniqueness check authoritative regardless of the caller's RLS visibility (or restrict the function to `service_role`, since it is only needed server-side).
- **Acceptance**: `SELECT proacl FROM pg_proc WHERE proname IN ('get_accepted_partner','generate_unique_partnership_code','accept_partnership','cleanup_old_logs')` shows no `anon` and no `PUBLIC` entry; the app's invite, accept and partner-resolution flows still pass.
- **Status: 🟢 OPEN**
- **Verified 2026-09-30 while hardening the SQL suite** — the RLS-neutralising claim above was confirmed empirically rather than by inspection, for both `anon` and an `authenticated` caller: `logs_api_access` / `logs_api_errors` / `logs_security_events` carry `backend_only_*` policies with `USING (false)`, and `logs_notifications` is `FOR SELECT` only, so all four `DELETE`s in `cleanup_old_logs` match zero rows. Severity stays 🟠 and the finding is still worth fixing — it is a defence-in-depth item, not a live data-loss path. Regression guard now in place: `supabase/test/rpc_execute_grants.test.sql` §C keeps `cleanup_old_logs(integer)` on an explicit anon-reachable allowlist (annotated as the known defect), and §E asserts the RLS backstop for `anon`, `authenticated` and `service_role` and fails loudly with a "revoke it from PUBLIC" message if that backstop is ever relaxed. Removing the grant means deleting the allowlist entry too — §C fails on both sides of the change so neither drift is silent.

### 11.6 🟠 `debug_wipe_user_data` is SECURITY DEFINER and its effective ACL is order-dependent
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.6; extends **10.17**; resolves the ACL half of **9.6**.
- **Files**: `supabase/schemas/public/functions/debug_wipe_user_data.sql:1-7,65,67`; `supabase/schemas/public/default_privileges.sql:7,9`.
- **Defect**: the function is `SECURITY DEFINER`, so it runs as its owner and **bypasses RLS on every table it touches**, and it takes `p_user_id` with no authorization check of its own. Its own grants look correct — `anon` is not named and `PUBLIC` is revoked at `:67`. The risk is `default_privileges.sql:9`, which grants `EXECUTE ON FUNCTIONS` to `anon` for every function `postgres` creates *after* it takes effect; `REVOKE … FROM PUBLIC` does not revoke a grant held by the named role `anon`. Whether `anon` ends up with `EXECUTE` therefore depends on the order the schema files were applied in. If it does, an unauthenticated caller can destroy any user's data.
- **Unverified — needs the linked DB**: `SELECT proacl FROM pg_proc WHERE proname = 'debug_wipe_user_data';` and `\df+ public.debug_wipe_user_data` on the linked Supabase project. Do not infer this from the schema files.
- **Verified 2026-10-10 (partial — mechanism confirmed, acting function is `drive_change_probe`)**: while fixing 9.9 the grant-pinning test `rpc_execute_grants.test.sql` §C failed against the linked DB: `public.drive_change_probe()` is anon-reachable on the live project (`proacl` = `{postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}`) even though its schema file `drive_change_probe.sql` explicitly `REVOKE ALL … FROM PUBLIC` and grants only `authenticated, postgres, service_role` — the exact `default_privileges.sql:9` ordering hazard this item describes. The function is `SECURITY INVOKER` + RLS-gated (`drive_items` via `is_in_partnership`), so anon reads nothing, but the grant should still be narrowed with 11.5/11.6. Check `debug_wipe_user_data`'s actual `proacl` the same way when that item is worked.
- **Fix**: add an explicit `REVOKE ALL ON FUNCTION "public"."debug_wipe_user_data"(integer) FROM PUBLIC, "anon";` after the existing `GRANT`, matching `get_pending_invitations.sql:39`, and re-apply to the remote project. Do the rename from 10.17 in the same pass so the migration is applied once.
- **Acceptance**: the `pg_proc.proacl` query above returns an ACL naming only `postgres` and `service_role`; an `anon` `rpc('debug_wipe_user_data', …)` call returns a permission error.
- **Status: 🟢 OPEN**

### 11.7 🟠 `override_sender_id` forges a pending invite attributed to a victim
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §2.7.
- **Files**: `supabase/schemas/public/functions/request_partnership.sql:4,8,16-20,26,43-45`.
- **Defect**: the function is `SECURITY INVOKER` (`:8`), so its `INSERT` **is** RLS-checked and cannot forge a request for an arbitrary unrelated sender — that variant is correctly rejected. What it does allow: the caller chooses both arguments. Passing `override_sender_id = <victim>` together with the attacker's **own** email and `partnership_code` makes `v_partner_id` resolve to the attacker, producing the row `(victim, attacker)`, which satisfies the policy's `OR` through `user_id_2`. Line 44 hard-codes `status = 'pending'`, so this is an invite forgery, not an accepted partnership (that is 11.1). The spoofed sender also bypasses the `status IN ('pending','accepted')` guard at `:26`, so a victim who is already partnered accumulates phantom rows.
- **Fix**: delete the `override_sender_id` parameter (`:4`, `:16-20`) — no application code calls it, and RLS already supplies the real guarantee. `SECURITY DEFINER` with an internal `current_user_id()` is the alternative if a server-side caller ever needs it.
- **Acceptance**: `rpc('request_partnership', { partner_email, partner_code, override_sender_id })` no longer compiles against the deployed signature; a caller cannot create a `partnerships` row naming a third party as `user_id_1`.
- **Status: 🟢 OPEN**

### 11.8 🔴 Unpaired senders bypass the notification receiver check
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.1.
- **Files**: `Backend/features/notifications/notification.service.js:383-403` (`:398`); `notify.schemas.js:6`.
- **Defect**: `if (partnerId && Number(receiverId) !== Number(partnerId))` — the guard is conditional on the sender having a partner. When `getPartnerId` returns falsy the condition short-circuits and the body-supplied `receiverId` is returned unvalidated, because `notify.schemas.js:6` accepts it as given. Any signed-in user without a partner can direct push notifications at any user id in the system. Signature and capability checks still apply, so this needs a valid signed request from an authenticated session — but that is a low bar for a spam / harassment / wake-up primitive against a known numeric id.
- **Fix**: fail closed when no partner exists (throw `AUTH_FAIL_004`), and resolve the receiver from the partnership rather than from the body. If arbitrary-receiver sends are a real product need, make them an explicit, separately-authorised path rather than an accident of the guard.
- **Acceptance**: an authenticated partnerless user posting a valid `receiverId` for another user receives `403` and no `logs_notifications` row is written.
- **Status: 🟢 OPEN**

### 11.9 🔴 `consumeNonce` discards the database's uniqueness result (supersedes 10.8)
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.2; supersedes **10.8**.
- **Files**: `Backend/core/infra/nonceStore.js:3,9-36` (`:20` discarded result, `:26-33` unreachable, `:35`).
- **Defect**: `@supabase/supabase-js` **resolves** `{ data, error }` and does not throw on a `23505`. Line 20 discards the resolved value, so the `catch` at `:26` never runs for a constraint violation, `return false` at `:31` is dead code, and `:35` returns `true` for a nonce the database already refused. Against any **cold** node the in-memory map at `:3` is empty, so `:13` passes and the whole path succeeds. Replay protection is memory-only; the `request_nonces` table provides none, and the atomicity 10.8 asked for cannot be obtained while the result is discarded.
- **Fix**: capture the resolved value and treat `error.code === '23505'` as a replay; make the DB insert the authoritative check rather than a side effect. Insert **before** touching the in-memory map, and only short-circuit on the DB conflict, so the two stores cannot disagree. Consider `INSERT … ON CONFLICT DO NOTHING` with a returned row count.
- **Acceptance**: a test calls `consumeNonce` twice with the same nonce against a fresh module instance (cleared memory) and the second call returns `false`; the same test passes with two Node processes.
- **Status: ✅ FIXED (2026-10-11, on `dev`)** — `consumeNonce` now captures the resolved `{ error }` from the `request_nonces` insert (`nonceStore.js:18`) and treats `error.code === "23505"` as a replay (`:24-26`), replacing the dead `catch`/`return false` that `@supabase/supabase-js` never reached. The DB insert is now the **authoritative** check and runs **before** the in-memory map is written; the map is set only after the insert is accepted (`:31`), so the two stores cannot disagree (previously the map was written first and claimed a nonce the DB refused). Kept a `try/catch` as a memory-only fail-open fallback for non-`23505` DB errors (unreachable DB), preserving the prior semantics outside the replay path; dropped the dead "duplicate-message substring" check. Promoted the `test.failing` case "A replay is refused by the database when the in-process nonce cache misses" (`Backend/test/security-integration.test.js:384`) to a plain `test` — it mocks the DB resolving `23505` for a nonce unknown to the process memory map, exercising exactly the cold-node replay path the bug admitted: before the fix the middleware returned `200`, now `429 SEC-BLOCK-001`. Docs aligned with the real guarantee: `docs/backend/security/doc.md` §3 Request Flow rewritten (insert-first, `23505` = replay, memory map set only after acceptance) and the "primary key constraint" claim corrected to the actual `UNIQUE (nonce)` (`request_nonces_nonce_key`) in §3 and the Nonce Deduplication matrix row; `docs/audits/distributed-state.md` §1 + matrix row flip **PARTIALLY SAFE WITH CONCURRENCY RISK → SAFE** and remediation item 2 is marked implemented; the stale "Redis/Memory" claim in `docs/features/authentication/session-token-security/doc.md:346` is corrected. · **Verification**: `npx jest test/security-integration.test.js --runInBand` → 11 pass — the DB-replay case is now a *real* pass (under `test.failing` it passed only because the assertion failed, i.e. the bug reproduced); full `npx jest --runInBand` → 159 pass / 13 suites; `npm run lint` → 0 errors (10 pre-existing warnings, none in touched files). · **Residual**: a DB outage degrades replay protection to memory-only and fails open (documented); the "two Node processes" half of the acceptance was simulated in Jest with the mock shape PostgREST resolves (`{ error: { code: "23505" } }`) rather than exercised against a live database — the DB `UNIQUE (nonce)` constraint is the only thing that can flip the outcome, and no schema change was needed (the constraint already existed).

### 11.10 🔴 Server-side session expiry is never checked (found 2026-09-30, while hardening 8.1)
- **Sources**: found while writing the revoked/expired-session cases for `Backend/test/security-integration.test.js`.
- **Files**: `Backend/middleware/authMiddleware.js:170` (the `select`), `:166-177` (`fetchSessionBinding`).
- **Defect**: the session lookup selects `revoked_at` but **not** `expires_at`, and nothing downstream compares the session's expiry. So a session closed server-side stays usable for as long as its JWT is still valid — bounded only by `MAX_ACCESS_TOKEN_LIFETIME_SEC` (900s), not by the session's own lifetime. Any logout/rotation path that closes the session row without revoking it leaves a live credential behind. Revocation *is* enforced, which is why this went unnoticed: the revoked case behaves correctly.
- **Fix**: add `expires_at` to the select and reject when `new Date(session.expires_at) <= new Date()` (treat a null expiry as expired, not as valid), alongside the existing `revoked_at` check.
- **Acceptance**: promote the `test.failing("FAIL: Expired server-side session is rejected")` case in `Backend/test/security-integration.test.js` to a plain `test` — it currently uses `test.failing` precisely so the suite stays green while this is open, and it will turn red the moment the middleware starts checking `expires_at`. Its sibling control case (live session) already returns 200, so the assertion is known to be reachable.
- **Status: 🟢 OPEN**

### 11.11 🟡 `notify.routes.js` has an unreachable route and a shared rate-limit bucket (found 2026-09-30, while hardening 8.1)
- **Sources**: found while fixing `Backend/test/notify.routes.test.js`.
- **Files**: `Backend/features/notifications/notify.routes.js:23-41`.
- **Defect**: `router.post("/:type")` is registered **before** `router.post("/partner")`, so `POST /api/v1/notify/partner` always matches `/:type` (with `type === "partner"`) and the dedicated `/partner` route is **dead code**. Both use the same limiter and schema, so there is no behavioural difference today — but the dead route implies a distinction that does not exist, and `paramsSchema` accepts any optional string, so nothing rejects a genuinely unknown `:type`. Separately, `limited(notifyRateLimit)` runs **before** `validated(...)`, so even schema-rejected requests consume rate-limit quota.
- **Fix**: register `/partner` before `/:type`, and tighten `paramsSchema` to an enum of the real notification types. Decide deliberately whether quota should be charged for requests that fail validation.
- **Acceptance**: `POST /api/v1/notify/nonexistent` is rejected; the route table has no unreachable entry. Test-side note (**resolved 2026-10-01**): the "not resettable" clause is obsolete — `middleware/rateLimit.js:154` now exports `resetRateLimitState()` and every rate-limited suite resets it in `beforeEach`, so buckets no longer leak across tests (see 8.10). The unique `x-test-profile-id` per test is kept as belt-and-braces, not as a requirement. The route defects above are still open.
- **Status: 🟢 OPEN**

### 11.12 🟠 Three authenticated mutating routes are unsigned, including the destructive one
- **Sources**: found while re-auditing `Backend/test/security-integration.test.js` after 11.9/11.11. The bypass is already named as a general risk in `docs/backend/security/doc.md:52` ("Requests on routes not wrapped with `signed(...)` helper skip HMAC verification completely") — but no item records *which* routes those are.
- **Files**: `Backend/features/user/user.routes.js:23-30` (`POST /users/wipe`), `Backend/features/notifications/notify.routes.js:23-31,32-40` (`POST /notify/:type` plus the dead `POST /notify/partner` — see 11.11), `Backend/features/auth/auth.routes.js:90-98` (`POST /auth/invite`). Client side: `Flutter/lib/core/network/api_service.dart:357` (`requireSignature` defaults to `false`), `:439,444` (invite), `:503-513` (notify), `:531` (wipe).
- **Defect**: every route registers a middleware chain, but only some chains contain `signed(...)`. Signed: `ai-question` (`ai.routes.js:39`), `auth-device-token` (`auth.routes.js:55`), `media-upload-url` / `media-complete` / `media-delete` (`media.routes.js:38,50,72`). Unsigned while authenticated **and** state-changing: `/auth/invite`, `/notify/*`, `/users/wipe`. Both sides of the contract agree — the client sets `requireSignature: true` on exactly the same five calls (`:468,474,481,492` and device-token) — so this is a consistent choice rather than drift; what is missing is any record that it was deliberate. The pre-auth routes (`/auth/login-risk-check`, `/auth/login-attempt`) are unsigned by necessity and are already covered by 9.5. Consequence: for these three a valid access token is sufficient proof of origin, so the HMAC layer's stated purpose (device/app authenticity, `docs/backend/security/doc.md` §12) is not applied and there is no nonce — an intercepted request can be re-sent indefinitely. `wipe` is the sharpest case: the most destructive operation the API exposes, irreversible (10.17, 12.3), and on the weakest origin proof of any authenticated mutation.
- **Fix**: decide the signing boundary and write it down. Either (a) extend signing to the three — `signed("user-wipe")`, `signed("notify-send")`, `signed("auth-invite")` plus `requireSignature: true` at the three client call sites, shipped as **one** change on both sides — or (b) record the boundary as a decision of record and add a test asserting the exact signed/unsigned route list so a future route cannot silently join the wrong set. Prefer (a) for `wipe`; (b) alone leaves the destructive endpoint on the weakest control. Ordering interaction: signing buys nothing as *replay* protection while 11.9 is open, so land 11.9 first or ship this explicitly as defence-in-depth rather than as the replay fix. Also confirm whether `auth-session-sync` (`auth.routes.js:79-88`) is meant to use `freshNonce(...)` instead of `signed(...)`.
- **Acceptance**: a table-driven test over the registered route table fails when any route's signed/unsigned state changes without the decision record being updated. If (a): an unsigned `POST /api/v1/users/wipe` is rejected and the Flutter `wipeUserData` flow still succeeds (that pair is the test — a signed-only server with an unsigned client silently breaks account deletion).
- **Status: 🟠 OPEN**

---

## Phase 12 — Data integrity, media & routing (added 2026-09-29)

Source: `docs/audits/2026-09-full-codebase-scan.md` §3.4–3.7, §5.2. 12.1 is the root cause of 12.2 and of several orphan findings — fix it first and re-measure the bucket.

### 12.1 🔴 The media data contract does not match the schema
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.4. `docs/features/shared-drive/doc.md:67` documents the **backend** side, so this is a code-vs-schema divergence, not a doc error.
- **Files**: `Backend/features/media/mediaWorkflow.service.js:75-87` (`:79-82`); `Backend/features/media/media.controller.js:65-69,83,90-94`; `Backend/core/jobs/retentionJob.js:141`. Schema: `supabase/schemas/public/tables/drive_items.sql:1-16` (`name` `:4`, `original_name` `:5`, `partnership_id` `:11`; no `user_id`, `partner_id` or `filename`).
- **Defect**: three call sites write or read columns that do not exist. PostgREST resolves an unknown column as `42703`, surfaced by `assertDbSuccess` (`mediaWorkflow.service.js:75`) and the explicit check at `media.controller.js:71`. Upload completion, download authorization, deletion and the retention sweep all fail at the database boundary, so the client's optimistic delete never reconciles.
- **Fix**: **migrate the backend to the schema** — use `name` (for the display name) and `partnership_id` in the insert, and read `name`/`partnership_id` in the delete path. Record the decision: do **not** add `filename`/`user_id`/`partner_id` to the schema, because `name` and `partnership_id` are already referenced by `v_drive_dashboard` and the Flutter model, so that direction duplicates state and needs a data migration. Derive the delete authorisation from `partnership_id` + `is_in_partnership()` rather than from per-row ownership columns, which do not exist by design. Update `docs/features/shared-drive/doc.md` to match.
- **Acceptance**: `POST /media/complete` inserts a row and returns the item; `POST /media/delete` authorises and deletes it; `retentionJob.fetchReferencedKeys()` returns a non-empty set against a seeded row. No `42703` appears in the logs.
- **Status: 🟢 OPEN**

### 12.2 🔴 The R2 orphan sweep throws on every run
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.5. Fixed by 12.1; listed separately because it has its own test and is the documented safety net for 12.3/12.4.
- **Files**: `Backend/core/jobs/retentionJob.js:136-150` (`:141` bad select, `:144` re-throw).
- **Defect**: `filename` does not exist on `drive_items`, so `:141` returns a `42703` error object and `:144` re-throws it, aborting the sweep before any R2 object is examined. The job is scheduled every 6 h and has never reclaimed anything. Because it is the documented safety net for aborted upload completions, media deletion and profile-picture replacement, all of those paths now accumulate R2 objects without bound.
- **Fix**: resolve through 12.1, then add a unit test that seeds one `drive_items` row and asserts `fetchReferencedKeys()` contains its key. Add a guard so a sweep failure is logged per-source (`retention.r2_orphan.failed`) instead of throwing out of the job, and make sure the scheduled runner cannot report success on a thrown sweep.
- **Acceptance**: with one seeded row, `fetchReferencedKeys()` returns a set containing that row's key; a deliberately failing query logs `retention.r2_orphan.failed` and the multipart sweep still runs.
- **Status: 🟢 OPEN**

### 12.3 🟠 The wipe destroys the partner's data and leaves the partnership row
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §5.2; resolves the open question in **9.6**; extends **10.17**.
- **Files**: `supabase/schemas/public/functions/debug_wipe_user_data.sql:13-61`; `docs/features/partnership/doc.md:282`; `docs/features/profile-settings/doc.md:217,228` (correct).
- **Defect**: the function resolves `v_partnership_id` at `:13-15` and then deletes rows for **both** members — `drive_items`, `bucket_items`, `game_questions`, `game_answers`, `missyou`, `favorites`, `drive_item_reactions`, `moods` — and nulls both `profile_pic_url` values (`:20-56`). Calling it for user A therefore wipes user B's data as well. It contains no `DELETE FROM public.partnerships`, so both accounts stay partnered with all their data gone. `docs/features/partnership/doc.md:282` states the opposite (that the row is deleted by cascade); the doc inverts the implementation.
- **Fix**: first settle the product decision — is this a per-user wipe or a per-couple wipe? — and record it as a decision of record. If per-couple, say so in the function name and docs. If per-user, scope every `DELETE` to `p_user_id` and decide explicitly what happens to the partnership row. Then correct `partnership/doc.md:282`. R2 objects are not covered by any of this; pair with 12.2.
- **Acceptance**: the decision is written down; the function's deletes match it; `partnership/doc.md` and `profile-settings/doc.md` agree; a test asserts the expected blast radius for both a partnered and an unpaired user.
- **Status: 🟢 OPEN**

### 12.4 🟠 Every named route resolves to `SplashScreen`
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.6.
- **Files**: `Flutter/lib/main.dart:141-150`.
- **Defect**: the comment at `:143-145` states the intent was to `return null` for a deep link, but `:146-149` returns a `MaterialPageRoute` that builds `const SplashScreen()` for **every** `settings.name`. Nothing pushed by name renders — including the re-authentication redirect and the localization route — so those land on the splash screen, which runs its own auth check and can loop. `home:` at `:141` is also `SplashScreen`, so the two paths are indistinguishable.
- **Fix**: return `null` for unrecognised names as the comment intends, and add an explicit `routes:` table for the names the app actually pushes. Do not remove the OAuth callback handling — Supabase consumes `/callback?code=…` before Flutter routes it, which is what the comment is protecting.
- **Acceptance**: `Navigator.pushNamed(context, '/localization')` and the re-auth redirect both render their real destinations; a deep link with an unknown name does not throw and does not render a second splash.
- **Status: 🟢 OPEN**

### 12.5 🟠 The mood checkpoint is written from the device clock
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §3.7; `docs/app/storage-and-caching/doc.md:71`, `docs/app/realtime/doc.md:394,398` (adjacent F-SC/R rows).
- **Files**: `Flutter/lib/features/mood/mood_state.dart:259`; `Flutter/lib/features/mood/mood_repository.dart:26,34-36,143-145`.
- **Defect**: both the row's `created_at` (`:26`) and the stored checkpoint (`mood_state.dart:259`) come from `DateTime.now()` on the **device**, while the incremental fetches order by `created_at` and read from the checkpoint. A device whose clock runs ahead stores a future checkpoint, after which every incremental query asks for `created_at > <future>` and no server row qualifies — the user permanently stops receiving mood updates, including their partner's. There is no clamp and no self-heal, because the checkpoint is written unconditionally. The same skew misorders the timeline.
- **Fix**: let the server own `created_at` (have `set_mood` return the persisted row and read `created_at` from it) and derive the checkpoint from the newest row actually returned rather than from the local clock. Add a forward-skew guard: if a response's newest `created_at` is behind the stored checkpoint, log and reset rather than trusting the local value.
- **Acceptance**: with the device clock set 24 h ahead, a mood set and a partner mood both appear after the next sync, and the stored checkpoint equals the newest returned `created_at`.
- **Status: 🟢 OPEN**

### 12.6 🟡 The orphaned `PartnerState` rejection branch is dead code
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md`; supersedes **10.13**.
- **Files**: `Flutter/lib/features/partnership/partner_state.dart:88-93`; `supabase/schemas/public/views/v_active_partnership.sql:1,23`; `supabase/schemas/public/functions/get_pending_invitations.sql:34-36`.
- **Defect**: the predicate 10.13 identified (comparing a partner **user id** against a **partnership id**) is real, but the whole path is unreachable. `v_active_partnership` is `security_invoker=true` and filters `AND (p.status::text = 'accepted'::text)`, so it never yields a `pending_received` value, and `get_pending_invitations` filters `p.status = 'pending'` returning only the **caller's own** rows. `receivedRequests` therefore stays empty and `acceptPartner`/`rejectPartner` have no call sites. Fixing the comparison, as 10.13 proposed, would change nothing observable.
- **Fix**: delete the orphaned branch and the `pending_received` contract rather than repairing it, then confirm 10.19 (reject bypassing the RPC) is resolved by the same removal — a `reject_partnership` RPC is only worth adding if a real caller needs it.
- **Acceptance**: no `pending_received` symbol remains in `Flutter/lib`; `grep -r "receivedRequests"` returns only the declaration; the invite list still renders incoming requests through the path that actually populates it.
- **Status: ✅ FIXED (2026-10-12, on `dev`)** — deleted the orphaned `PartnerState.acceptPartner`/`rejectPartner` methods (no call sites), the `receivedRequests`/`sentRequests` getters, and the whole `pending_received`/`pending_sent` jsonb contract that `v_active_partnership` never returns (`PartnershipResponse.pendingRequests`, the `PendingRequests` model, its `fromJson` parsing and `copyWith` param). · **Verification**: `flutter analyze` clean; `grep -rn "pending_received" Flutter/lib` and `grep -rn "receivedRequests" Flutter/lib` both return nothing; `flutter test test/partner_state_test.dart test/partnership_scope_test.dart` pass; the live invite path (`AuthState.receivedInvitations` → `InvitationTile`) is untouched. · **Residual**: this does **not** resolve 10.19 as the item predicted — `PartnershipRepository.rejectPartnerRequest` still has a real caller, `AuthState.rejectInvitation` (auth_state.dart:591), so the accept=RPC / reject=direct-DELETE asymmetry stands and 10.19 stays open. The acceptance expected `grep receivedRequests` to return "only the declaration"; the getter was itself dead, so it was removed too (grep returns nothing).

---

## Phase 13 — Test safety net, docs & the verification backlog (added 2026-09-29)

Source: `docs/audits/2026-09-full-codebase-scan.md` §4–§6. 13.1–13.4 restore the safety net the earlier phases need; 13.5 stops the docs from asserting a working sweep that does not exist; **13.6 is the executable form of the ~60 unverified doc drifts**; **13.7 is the executable form of the specialist-pass findings that were not re-read** and must be worked before any of them become fixes.

### 13.1 🔴 `test/` and `scripts/` are git-ignored, so a clone ships no tests
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §4.1. Verified with `git ls-files test scripts` (empty) and `git check-ignore -v`.
- **Files**: `.gitignore:7-9,17-18`; `Flutter/.gitignore:47`.
- **Defect**: `.gitignore:8-9` ignore `/test` and `/scripts`; `git ls-files test scripts` returns nothing, so neither the suite nor the runner is tracked. `.env.test` is caught by `.env.*` at `:17` (only `!.env.example` excepted, `:18`) and `Flutter/.env` by `Flutter/.gitignore:47`. The working copy has tests; the repository does not. Anyone who clones cannot run a single test, cannot run the SQL assertions, and cannot run `npm run validate`.
- **Fix**: remove the `/test` and `/scripts` lines and commit both directories. For `.env.test`, commit it with **placeholder values only** — never live credentials — or add a `!.env.test` exception plus a committed `.env.test.example` and document the copy step. Same decision for `Flutter/.env`. Before committing, check nothing currently in those directories contains a real key; the audit flagged that `.env.test` tracking is stated both ways in `docs/audits/secrets.md:15,65`.
- **Acceptance**: from a fresh clone, `npm run validate` starts the suite; `git ls-files test scripts` is non-empty; a grep of the committed `.env.test` finds no key matching the shape used in `docs/audits/secrets.md:27-33`.
- **Status: ✅ FIXED (2026-10-01, on `dev`)** — the `/test` and `/scripts` ignore lines are gone; `scripts/` (5 files) and the suite are tracked, and `.gitignore:15` now excepts `.env.test`, committed in `83c9d41` with placeholders only (see 8.10) · **Verification**: `git ls-files scripts` returns 5 files; `git check-ignore -v test scripts .env.test` returns nothing; all four secrets listed at `docs/audits/secrets.md:25-28` differ from the live `.env` values (13–21 chars vs 64–219, placeholder patterns) · **Residual**: `Flutter/.env` is still ignored, correctly — `Flutter/.env.example` exists and carries the placeholders, so nothing is missing there. Root `npm run validate` (`bash ./scripts/test-all.sh`) was **not** run in this pass; `cd Backend && npm test` was (144 pass), and the load-bearing nature of the env file was proven directly by moving it aside and observing `Tests: 0 total`. 13.2/13.3 are unaffected and remain open.

### 13.2 🟠 The documented root entry points are a stub and a dangling path
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §4.2, §4.3.
- **Files**: `package.json:10,13`.
- **Defect**: `package.json:10` is the npm-init default — `"test": "echo \"Error: no test specified\" && exit 1"` — so `npm test` always fails with a non-zero exit. `package.json:13` points `validate` at `bash ./scripts/test-all.sh`, a path inside the git-ignored `scripts/` (13.1), so in a fresh clone it fails with "No such file". The script itself is substantial and real (≈104 lines, 12 gates), so the workflow is not missing — it is simply not reachable by anyone but the original author.
- **Fix**: point `test` at the real suite and `validate` at the committed script. Once 13.1 lands, both resolve; the change here is only the two lines.
- **Acceptance**: `npm test` and `npm run validate` both succeed from a fresh clone, or fail for a real reason rather than "no test specified".
- **Status: 🟢 OPEN**

### 13.3 🟠 `test-all.sh` hard-codes a Windows launcher, so the suite is not portable
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §4.4.
- **Files**: `scripts/test-all.sh:10,27,34,35,37,47,52,54,56,61,71,80,104`.
- **Defect**: the comment at `:34` says `cmd.exe //c` is used "to ensure we use the Windows Dart executable correctly in all environments". It does the opposite — twelve call sites invoke every gate (lint, madge, `npm run check`, jest, jscpd, `flutter analyze`, `flutter test`, the two import generators, the compose lifecycle) through a Windows-only launcher, so under WSL bash or any non-Windows host the script cannot run. Lines 52, 54, 56, 61, 71, 80 and 104 chain `&& echo "✅ …"`, so a launcher failure trips the `||` branch and exits; the two `docker` lines (`:10`, `:27`) end `|| true` and are best-effort by design. Because the script is untracked (13.1), no CI system could have exercised it.
- **Unverified — needs `bash ./scripts/test-all.sh` run on this machine** to record the exact current failure mode per gate.
- **Fix**: detect the platform once at the top and invoke natively (or replace the shell driver with a Node entry point, which the project already uses for other tooling). Keep the `|| true` best-effort semantics on the compose teardown/startup lines and keep the hard-fail guards on the check gates — those are deliberate and correct.
- **Acceptance**: the script runs its full gate list on Windows, WSL bash and Linux, and a deliberately failing gate still exits non-zero with the `❌` message on every platform.
- **Status: 🟢 OPEN**

### 13.4 🟠 Two audit documents assert the dead orphan sweep is working
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §5.1. Depends on **12.1**/**12.2** for the truth; this item fixes the false assurance, not the sweep.
- **Files**: `docs/audits/data-retention.md:20,110`; `docs/audits/media-delete-audit.md:25-28,34`.
- **Defect**: both documents describe the sweep against `drive_items.filename` — the column that does not exist (12.1) — and rate it `ACTIVE & NECESSARY`, with `data-retention.md:110` stating it "guarantee[s] no unbounded orphan accumulation". Per 12.2 the sweep throws on every run. These are the documents a maintainer consults before touching media storage, and `media-delete-audit.md:25-28` additionally rationalises the DB-first delete ordering on the premise that an orphaned object "is reclaimed by the safety net below" — a premise that is false, which removes the justification for that ordering.
- **Fix**: correct the column reference and the effectiveness rating. Until 12.1/12.2 land, state plainly that the sweep is non-functional and that orphans are unbounded — do not leave a "guarantee" in place that no code backs. Re-check the DB-first rationale once the sweep works again.
- **Acceptance**: neither document names `drive_items.filename`; no `ACTIVE` / `guarantee` claim about orphan bounding survives without a test that proves it.
- **Status: 🟢 OPEN**

### 13.5 🟢 `partnership/doc.md:282` inverts the wipe's effect on the partnership row
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §5.2; resolves the disputed row in **9.6**; pairs with **12.3**.
- **Files**: `docs/features/partnership/doc.md:282`; `docs/features/profile-settings/doc.md:217,228` (correct); `supabase/schemas/public/functions/debug_wipe_user_data.sql:20-56`.
- **Defect**: the doc claims the wipe deletes the `partnerships` row "via database foreign key cascading (`ON DELETE CASCADE`)". The function contains no such delete — that row is what supplies `v_partnership_id` at `:15`, and it survives. `profile-settings/doc.md` is the correct one; `9.6` had this recorded as unresolved and it is now settled.
- **Fix**: correct `partnership/doc.md:282` to match the implementation, and land the 12.3 decision in the same edit so the doc states the intended blast radius rather than the current one.
- **Acceptance**: both docs describe the same effect, and the description matches the function body.
- **Status: 🟢 OPEN**

### 13.6 🟢 Batched documentation drift (~60 rows) — full evidence in the audit doc
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §6 and §9 (`Docs vs code` pass); this is the **batched** form of that pass, per the decision taken when the scan was planned.
- **Files**: `docs/**/*.md` — the full per-row evidence table is in the scan's `## Coverage` section and the specialist-pass notes; this item deliberately carries no per-row list so the 20 real defects in Phases 11–12 stay visible in this file.
- **Defect**: ~60 individually-minor rows across `docs/**` describe code that has since changed — `Implementation Status` tables still saying `NOT IMPLEMENTED` / `STUB` / `PARTIALLY BROKEN` for features that exist, dead component lists, error-code tables in the underscore form the code stopped using in 9.6, `requestTimeoutMs` documented as both 15 000 ms and 30 000 ms, `docs/audits/email.md:30` naming `partnership_invitations` and `notifications` tables that do not exist in the schema, and the localisation status table claiming 100 % against a body that says 95 %. Individually cosmetic; collectively they are why 10.16 and 10.18 could not be closed by reading the docs.
- **Fix**: sweep every `Implementation Status` / findings section in `docs/**` against the code — delete rows for removed components, flip fixed rows to IMPLEMENTED, remove findings for closed bugs, renumber and fix cross-references. This subsumes the remainder of 9.6. Work it as one mechanical pass, not row-by-row, and re-verify each row before editing (`fix-workflow` §1).
- **Acceptance**: no `docs/**` row claims `NOT IMPLEMENTED` / `STUB` / `BROKEN` / `PARTIALLY BROKEN` for code that exists; verifiable by grep plus spot-check. **13.4 and 13.5 are carved out of this batch** because they have functional consequences and are tracked individually.
- **Status: 🟢 OPEN**

### 13.7 🔴 Verification backlog — the specialist-pass findings not yet re-read
- **Sources**: `docs/audits/2026-09-full-codebase-scan.md` §6 (35 rows, with cited locations and reported severities).
- **Files**: as cited per row in the audit doc — `Backend/features/auth/authMiddleware*`, `notification.service.js:220-221`, `media.controller.js:90-104`, `user.controller.js`, `notify.routes.js`, `partner_state.dart`, `auth_state.dart`, `base_state.dart`, the realtime service, `drive_repository.dart`, `cleanup_old_logs.sql`, `.github/workflows`, `Backend/package.json`, `pubspec.yaml`, `.vscode/tasks.json`.
- **Defect**: the scan's auth, R2/media, FCM/push, client-state and realtime passes produced 35 further findings. They are consistent with the code read during the scan, but **their cited lines were not individually re-read in the final pass** — they are reported findings, not verified ones. They are recorded here so the work is not lost and so nothing is promoted to a fix on a second-hand line number. The most consequential rows, in order: the `/media/complete` orphan path; `PartnerState` never cleared on logout (a cross-account leak); a failed wipe leaving realtime suppressed permanently because `resume()` has zero callers; `metadata.thumbnail` being unvalidated (cross-user R2 deletion); `fetchSessionBinding` swallowing DB errors so session binding silently disables itself; `sanitizeRequest` rewriting the body before signature verification; the missing `favorites` / `drive_item_reactions` cursors and publications; and CI running zero tests.
- **Fix**: work the audit doc's §6 table row by row. For each: re-read the cited line, confirm the defect, then **promote it to a Phase 11/12/13 item** with the full `Sources / Files / Defect / Fix / Acceptance` shape — or record it in `## Known non-bugs & deliberate decisions` if it turns out to be intentional, or close it as stale if the code no longer exists. Do not fix anything directly from this item. Several rows will need runtime confirmation (FCM delivery, R2 object counts, device behaviour) and must carry an `Unverified` label until then.
- **Acceptance**: every row in the audit doc's §6 table is either promoted to a numbered item, recorded as a deliberate decision, or closed as stale with a reason; no row remains "reported but unchecked".
- **Status: 🟢 OPEN**

---

## Phase 14 — Post-AI-removal dead code & simplification sweep (added 2026-10-09)

Source: full-repo sweep run after the AI question flow was removed (`3145a9a`, `79ac039`, `32b0943`, `eed7481`). Every item below was re-verified by symbol-level grep in the working tree on 2026-10-09 (definition vs. every occurrence in `Backend/`, `Flutter/lib`, `Flutter/test`, `scripts/`, `supabase/`), not taken from a report on trust. **Deliberately not duplicated**: `DriveState.clearMediaCache` → 10.2 · unreachable `/localization`, `/change-password`, `/login` redirects → 12.4 · `PartnerState.acceptPartner`/`rejectPartner`/`receivedRequests` → 12.6 · root `package.json` `test` placeholder → 13.2 · `test-all.sh` portability → 13.3 · generic doc drift → 13.6.

**Verified clean — nothing to remove here**: all 12 `Backend/middleware/*` files have live call sites; every `routeHelpers` chain segment (`signed`/`freshNonce`/`capability`/`validated`/`limited`/`withIdempotency`) is used; no AI symbol survives in `Backend/`, `Flutter/lib`, `scripts/`, `.github/` or any env file; every remaining `.env.example` key is consumed; the only workflow (`codeql.yml`) has no AI jobs; no orphaned test files or test helpers; `untranslated_messages.txt` is `{}`.

### 14.1 🟢 Six dead Backend exports and one orphaned validation schema
- **Sources**: no doc finding — found by the 2026-10-09 sweep.
- **Files**: `Backend/features/user/user.schemas.js` (whole file — `userActionSchema`); `Backend/config/apiRoutes.js:4,31` (`CALLBACK_ROUTES`); `Backend/utils/misc/controllerUtils.js:11,18` (`asyncHandlerWithCallback`); `Backend/utils/http/responseUtils.js:9,13` (`notFound`); `Backend/utils/auth/rateLimitPresets.js:13,19` (`createIpOnlyRateLimit`); `Backend/features/notifications/notification.service.js:356,421,434,436` (`sendNotificationToUsers`, `getReceiverDeviceToken`).
- **Defect**: each symbol has **zero call sites** outside its own defining file and the generated barrel `all_imports.js` (`rg -w` over the whole repo). `userActionSchema` never had a consumer since the initial commit — `user.routes.js` registers `POST /users/wipe` with no `validated(...)` segment, and the file survives only because `tool/generate_imports.js` rescans `features/**`. `asyncHandlerWithCallback`'s only consumer was the deleted `ai.controller.js`, and its doc comment still cites the deleted circuit breaker. `CALLBACK_ROUTES` is dead while `routes/authCallbacks.js:30` hardcodes `/invite-callback`. `createIpOnlyRateLimit` is an unused alias of `createIpUserRateLimit`, which every route file imports directly. The two notification exports are dead while the module's only real external surface is `dispatchNotification`.
- **Fix**: delete the six exports (the whole file for `user.schemas.js`), regenerate `all_imports.js` with `Backend/tool/generate_imports.js`, then run the suite. Whether `/users/wipe` should gain `validated(...)` is a separate decision (adjacent to 11.12) — do **not** fold it into this deletion.
- **Acceptance**: `rg -w "userActionSchema|CALLBACK_ROUTES|asyncHandlerWithCallback|createIpOnlyRateLimit|sendNotificationToUsers|getReceiverDeviceToken"` returns nothing outside git history; `npx jest --runInBand`, `npm run lint` and the madge check are green; the barrel shrinks accordingly.
- **Status: 🟢 OPEN**

### 14.2 🟢 Stale AI config and comments in Backend tests, middleware and tooling
- **Sources**: no doc finding — found by the 2026-10-09 sweep.
- **Files**: `Backend/jest.config.js:8-10`; `Backend/test/authorization.test.js:11`; `Backend/test/env-integrity.test.js:11`; `Backend/middleware/rateLimit.js:153`; `Backend/tool/generate_imports.js:4`.
- **Defect**: `jest.config.js` still carries `testPathIgnorePatterns`/`coveragePathIgnorePatterns` for `<rootDir>/test/mock-ai/` and a comment calling it "a standalone helper service" — the directory was deleted in `32b0943` (`Test-Path Backend\test\mock-ai` → False), so the patterns can never match. `authorization.test.js:11` describes its subject as the path to "the media/AI APIs" — the AI APIs no longer exist. `env-integrity.test.js:11` asserts the barrel has **138** entries; the actual count after the AI getters were removed is **125**, so the test documents a number it does not check. `rateLimit.js:153` says the reset "mirror[s] resetCircuitState/resetQuotaState" — both functions were deleted in `3145a9a`. `generate_imports.js` `TARGET_DIRS` still lists a `controllers` directory that does not exist.
- **Fix**: drop the two jest ignore entries and their comment; correct or delete the three stale comments (recount the barrel rather than hardcoding 125 — or make `env-integrity.test.js` assert the count dynamically); remove `controllers` from `TARGET_DIRS`.
- **Acceptance**: `rg -n "mock-ai|resetCircuitState|resetQuotaState|media/AI" Backend` returns nothing; `npx jest` green including `env-integrity`.
- **Status: 🟢 OPEN**

### 14.3 🟢 `API_V1_PATHS` carries 14 unused keys
- **Sources**: no doc finding — found by the 2026-10-09 sweep.
- **Files**: `Backend/config/apiRoutes.js:9-26`; readers: `Backend/features/auth/authRisk.service.js:62,125`.
- **Defect**: of the 16 keys, only `authLoginAttempt` and `authSessionBind` are ever read. The other 14 (`root`, `ping`, `authBase`, `mediaBase`, `notifyBase`, `usersBase`, `appVersion`, `authLoginRiskCheck`, `authInvite`, `authDeviceToken`, `authDeviceTokenRevoke`, `mediaFile`, `mediaDelete`, `userWipe`) have zero `API_V1_PATHS.<key>` readers — routes mount on literals and Flutter builds its own URLs from `core/network/api_routes.dart`. The table is a client-parity contract nobody consumes, so it silently rots (note `authDeviceTokenRevoke` was added by 9.2 and is equally unread).
- **Fix**: trim the table to the two keys `authRisk.service` reads, or delete it and inline those two paths — and record in a one-line comment why path constants do (not) exist, so the next route does not re-grow the table.
- **Acceptance**: `rg -n "API_V1_PATHS\." Backend` shows only real readers; jest and lint green.
- **Status: 🟢 OPEN**

### 14.4 🟢 Dead docker-compose plumbing in `scripts/test-all.sh` and an orphaned compose file
- **Sources**: no doc finding — the dead code was left behind when `32b0943` removed the mock-AI readiness block.
- **Files**: `scripts/test-all.sh:15-16,29,39-43,62,64-66`; `scripts/docker-compose.test.yml` (whole file); `README.md:123`.
- **Defect**: `has()` (`:62`) and `compose()` (`:64-66`) have **zero call sites** — their only consumers (`has docker`/`has curl` and the mock-ai `compose up`) were deleted in `32b0943`. `COMPOSE_FILE` (`:29`), `COMPOSE_ARG` + the `wslpath` conversion (`:39-43`) and the header comment (`:15-16`, "Windows paths are converted for docker compose") are read only by that dead code. `scripts/docker-compose.test.yml`'s `backend-tests` service (`node:20-alpine`) is invoked by nothing in the repo (`rg "backend-tests"` → only the compose file itself). `README.md:123` claims `npm run validate` "can run the backend Jest suite in a `node:20-alpine` container (skipped automatically when Docker is unavailable)" — false: the backend phase runs `npx jest` on the host (`test-all.sh:126`) and no gate starts docker.
- **Fix**: delete `has()`, `compose()`, the `COMPOSE_*` variables, the `wslpath` block and the header lines; decide the compose file's fate deliberately — remove it, or wire it back up as an explicit opt-in gate — and correct `README.md:123` to describe what the script actually runs. Do this **together with 13.3** (both edit `test-all.sh`), but the defects are distinct: 13.3 is the `cmd.exe //c` dispatch, this is dead docker code.
- **Acceptance**: `rg -n "compose|COMPOSE|docker|wslpath" scripts/test-all.sh` shows only lines that execute; `README.md:123` matches observed behaviour; `bash ./scripts/test-all.sh` still passes its gates.
- **Status: 🟢 OPEN**

### 14.5 🟢 Orphaned Supabase function `get_partnership_names` and the last AI env reference
- **Sources**: `docs/supabase/database-logic/doc.md:95` ("No current application caller… the removed AI question flow was its last consumer").
- **Files**: `supabase/schemas/public/functions/get_partnership_names.sql` (whole file); `supabase/test/rpc_execute_grants.test.sql:122`; `supabase/config.toml:99-100`.
- **Defect**: `rg -n "get_partnership_names"` outside the schema file and docs → only the grants test that asserts it. Zero references in `Backend/` and `Flutter/`. It is granted only to `postgres`/`service_role` (`:41`), so it is inert dead schema still kept alive by a test assertion. Separately, `config.toml:99-100` still carries `# OpenAI API Key … openai_api_key = "env(OPENAI_API_KEY)"` — `OPENAI_API_KEY` is defined in no `.env*` file and no workflow; it is default Supabase CLI template residue and the last AI-specific env reference in the repository.
- **Fix**: delete the function file and its line in `rpc_execute_grants.test.sql`, apply the schema change to the linked remote project (`fix-workflow` §1.9); remove or comment out the `openai_api_key` key (it is harmless template config — removing it is hygiene, not a functional fix, so say so in the commit).
- **Acceptance**: `rg "get_partnership_names|OPENAI_API_KEY" .` returns nothing outside `docs/` history and `report.md`; `scripts/run-sql-tests.sh` green against the linked DB.
- **Status: 🟢 OPEN**

### 14.6 🟢 Root `package.json` stale metadata
- **Sources**: no doc finding — found by the 2026-10-09 sweep. The `test` placeholder is **already tracked by 13.2** — not repeated here.
- **Files**: `package.json:5` (`"main": "index.js"`), `package.json:7` (`"directories": {"test": "test"}`).
- **Defect**: neither path exists at the repo root (`Test-Path .\index.js` → False, `Test-Path .\test` → False). Cosmetic metadata drift that misleads tooling and readers.
- **Fix**: delete both fields (or point `main` at the real entry if some tool consumes it — verify with `rg "require.*index.js"` at root first).
- **Acceptance**: every field in root `package.json` resolves to a path that exists.
- **Status: 🟢 OPEN**

### 14.7 🟢 Two fully dead Flutter files, one unused widget pair and six marker classes
- **Sources**: no doc finding — found by the 2026-10-09 sweep (symbol-level grep, because `import_hygiene_test.dart` forbids direct imports and makes naive file-level checks useless).
- **Files**: `Flutter/lib/shared/design_system/vp_circle_button.dart` (whole file); `Flutter/lib/features/mood/widgets/emoji_picker_widget.dart` (whole file); `Flutter/lib/shared/design_system/vp_widgets.dart:546,619` (`VPSegmentedControl<T>`, `VPSegmentedControlOption<T>`); marker classes `AuthModels` (`auth_models.dart:5`), `BucketModels`, `DriveModels`, `MoodModels`, `PartnershipModels`, `VersionModels`.
- **Defect**: `VPCircleButton` occurs only on its own declaration lines — 0 uses in `lib/` or `test/` (still exported by `design_system.dart:6` and `all_imports.dart:118`). `EmojiPickerWidget`/`EmojiButton` have 0 uses outside their file; the live `EmojiPickerSheet` (`mood_screen.dart`) has its own inline emoji grid and never touches this file. `VPSegmentedControl` + its option class have 0 external refs while every other `VP*` widget in `vp_widgets.dart` is used. The six marker classes are identical one-liners (`abstract class XModels {}`) never referenced anywhere.
- **Fix**: delete both files and the marker classes, remove `VPSegmentedControl`/`VPSegmentedControlOption`, drop `vp_circle_button.dart` from the `design_system.dart` barrel, regenerate `all_imports.dart`, run `flutter analyze` + `flutter test`.
- **Acceptance**: `rg -w "VPCircleButton|EmojiPickerWidget|EmojiButton|VPSegmentedControl|AuthModels|BucketModels|DriveModels|MoodModels|PartnershipModels|VersionModels" Flutter/lib Flutter/test` returns nothing; suite green.
- **Status: 🟢 OPEN**

### 14.8 🟢 Dead Flutter methods and getters (11 symbols across 9 files)
- **Sources**: no doc finding — found by the 2026-10-09 sweep. **Deliberately excluded** (owned elsewhere): `DriveState.clearMediaCache` → 10.2 · `PartnerState.acceptPartner`/`rejectPartner`/`receivedRequests` → 12.6 · the unreachable screens → 12.4.
- **Files** (symbol occurs exactly once in `lib/`+`test/` = its own definition, or has no production caller):
  - `PartnerState.sendPartnerRequest` (`partner_state.dart:52`) + `PartnershipRepository.sendPartnerRequest` (`partnership_repository.dart:84`) — production UI uses `AuthState.invitePartner`/`acceptInvitation`/`rejectInvitation` (`partner_invite_dialog.dart:90`, `partner_screen.dart:354,379`); the only caller is `test/partner_state_test.dart`.
  - `StorageService.saveToken` (`core/local_storage/storage_service.dart:210`) — real code uses `saveAccessToken`/`saveRefreshToken`.
  - `CompressionService.compressAudio` (`core/media/compression_service.dart:68`) — image/video/thumbnail paths are used, audio is not.
  - `DriveState.getSignedUrl` (`drive_state.dart:281`), `MoodState.loadPartnerMoodFromCache` (`mood_state.dart:149`), `ProfileState.setLocalProfileImage` (`profile_state.dart:108`), `MediaPickerService.pickImageFromSource` (`shared/utils/ui/media_picker_service.dart:10`), `LanguageProvider.currentLanguage` (`core/localization/language_provider.dart:12`).
  - `PartnershipModels.hasAcceptedPartner` (`partnership_models.dart:38`) / `isPending` (`:154`); `SupabaseQueryExtensions.maybeEq` (`shared/utils/extensions/supabase_query_extensions.dart:12` — sibling `maybeFilterIn` **is** used); `ApiRoutes.root`/`ping`/`inviteCallbackPath` (`core/network/api_routes.dart:6,7,11` — the other 12 constants are consumed).
- **Defect**: each is reachable from no production path, so it misleads readers about the active API surface and inflates the barrel. The `sendPartnerRequest` pair is the notable one: it is a *second* invitation path superseded by `AuthState`, kept alive only by its own test — and it overlaps **12.6**, which owns the accept/reject half of the same orphaned flow.
- **Fix**: re-verify each symbol with a bare-name grep immediately before deleting (`fix-workflow` §1); for `sendPartnerRequest`, delete state + repository method **with** 12.6 in one pass and either move `partner_state_test.dart`'s two cases onto `AuthState.invitePartner` or delete them — do not leave a test asserting a removed method.
- **Acceptance**: each listed symbol returns 0 hits in `Flutter/lib`+`Flutter/test` outside history; `flutter analyze` clean; `flutter test` green (no test references a deleted member).
- **Status: 🟢 OPEN**

### 14.9 🟢 ~43 orphan l10n keys in `intl_en.arb` / `intl_it.arb`
- **Sources**: no doc finding — found by the 2026-10-09 sweep (every ARB value key compared against its usage in `lib/` + `test/`, excluding `generated/`, then each candidate re-checked by bare-name grep).
- **Files**: `Flutter/lib/core/localization/intl_en.arb`, `intl_it.arb` (+ regenerate `generated/app_localizations*.dart`).
- **Clusters** (full candidate list, re-verify each before deleting): `example`, `italianLanguage`, `englishLanguage` (language names come from `LanguageHelper`/`flagEmoji`); `common_add`, `common_more`; `auth_passwordHint`, `auth_captchaFailed`, `auth_loginNoUserData`, `auth_registerUserNotCreated`, `auth_tooManyLoginAttempts`; `home_quickActions`, `home_moodTitle/Subtitle`, `home_gamesTitle/Subtitle`, `home_photosTitle/Subtitle`, `home_nudgeSubtitle`; the whole `settings_darkModeTitle/Subtitle`, `settings_appearanceSection`, `settings_themeLight/Dark` group (the theme UI uses a different key set); `profile_displayNameSubtitle`, `partner_requestButton` (pairs with 12.6/14.8); `drive_subtitle/uploadComplete/deleted/uploadInProgress`; `bucket_emptyAll/enterText/addError/updateError`; `mood_emojiHint`, `mood_updated`; and the `error_*` fallbacks `unknownApi`, `noDataReturned`, `malformedResponse`, `networkUnavailable`, `operationTimedOut`, `sessionExpiredLoginAgain`, `requestTimeout`, `connection` — `ErrorCodes.userMessage` (`error_codes.dart:67-128`) never returns them.
- **Defect**: 43 of 314 keys have no reader, so translations drift invisibly and every future string audit re-finds them. **Do not delete `game_generatingQuestion`** despite the AI-sounding name — it is live (`game_screen.dart:274`) with reworded "Fetching the question." text.
- **Fix**: re-verify each candidate by bare-name grep, delete from both ARBs together (never one locale), regenerate localizations, run `flutter gen-l10n` (or the project's generator) and the suite. Keep `untranslated_messages.txt` at `{}`.
- **Acceptance**: a scripted ARB-key-vs-usage diff reports 0 orphans for both locales; `flutter analyze` clean; the suite green; IT/EN key sets still identical.
- **Status: 🟢 OPEN**

### 14.10 🟡 Three capabilities are granted and resolved but enforced nowhere
- **Sources**: no doc finding — found by the 2026-10-09 sweep.
- **Files**: `Backend/features/auth/authorization.service.js:5,9,14-19,19` (role→capability grants); the only `capability(...)` call sites: `Backend/features/media/media.routes.js` (3×, always `"can_media_upload"`); ad-hoc check `Backend/features/media/mediaWorkflow.service.js:23` (`can_upload_large`); tests `Backend/test/authorization.test.js:71,80-83`.
- **Defect**: `can_profile_update`, `can_moderate_content` and `can_system_access` are granted to roles, resolved by `resolveCapabilities` and asserted by tests, but **no route ever calls `capability(...)` with them** — the enforcement layer for three quarters of the capability system does not exist. Either the definitions are dead weight or the enforcement was never written; today they only create the appearance of a permission gate (and `can_system_access` looks alarming in a grants table while checking nothing). The pairing test comment ("media/AI APIs") is stale — tracked in 14.2.
- **Fix**: decide per capability — enforce it on the route(s) it was designed for, or delete it from the grants, from `resolveCapabilities` and from the tests. Record the decision (a capability that exists but gates nothing is worse than none, because auditors read the grants table).
- **Acceptance**: every capability in `authorization.service.js` is checked by at least one `capability(...)` call site, or is gone from grants + tests; `authorization.test.js` reflects the chosen set.
- **Status: 🟢 OPEN**

### 14.11 🟡 Dead backend error codes paired with unreachable Flutter handlers and strings
- **Sources**: no doc finding — found by the 2026-10-09 sweep.
- **Files**: `Backend/core/errors/AppError.js` (`ERROR_CODES` table); `Flutter/lib/core/error_handling/error_codes.dart:14,28,34,39` + switch at `:67-128` and `isSessionIssue` at `:135`; `intl_en.arb` / `intl_it.arb` (`error_authFail003`, `error_dbTimeout001`, `error_apiFail001`, `error_secPermission001`).
- **Defect**: `rg` over `Backend/` excluding `AppError.js` shows `AUTH_FAIL_003`, `API_FAIL_001`, `DB_TIMEOUT_001`, `SEC_PERMISSION_001` and `SYS_INTERNAL_001` are never thrown as an `errorKey`, so the matching Flutter constants, switch cases and localized strings are unreachable. Note `AUTH_FAIL_003` ("Session revoked") is suspicious rather than plainly dead: 731885d added session revocation on password change (9.3), so the code may represent **missing backend mapping** — revocation currently surfaces under a different key. `SEC_PERMISSION_001` duplicates the message `SEC_AUTH_001` already uses (`corsUtils.js:32`).
- **Fix**: decide per code — wire it where the behaviour exists (candidate: revoked-session rejection → `AUTH_FAIL_003`) or delete it from `ERROR_CODES`, from `error_codes.dart` and from both ARBs. Add a cross-side test that iterates the backend's `ERROR_CODES` keys and fails when one has no Flutter handler, or vice versa, so the two lists cannot drift again.
- **Acceptance**: every `ERROR_CODES` entry is thrown by some backend path **or** removed from both sides; the drift test passes.
- **Status: 🟢 OPEN**

### 14.12 🟢 AI-removal documentation drift (postdates the 13.6 batch)
- **Sources**: found by the 2026-10-09 sweep. 13.6's batch was written 2026-09-28, **before** the AI removal, so these rows are new, not a duplicate of it. `README.md:123` is tracked in **14.4**, not repeated here.
- **Files**: `docs/audits/distributed-state.md:67-111` (whole sections on `quotaService.js`, `circuitBreaker.js`, `env.aiDailyTokenLimit`, OpenRouter multi-instance risk, with `file:///` links to files deleted in `3145a9a` — 10.6/10.7 already point here as moot, but the audit text itself still reads as live guidance); `docs/audits/dead-code-and-outdated-docs.md:21,23` (claims `Backend/config/aiConfig.js` and `test/mock-ai/server.js` are live — both deleted); `docs/audits/secrets.md:26,34,37,63,121` (`OPENROUTER_API_KEY` listed as a present secret to rotate and as `.env.test` content that no longer exists); and **this file** — `todo.md` (11.12's Defect text) still lists `ai-question` (`ai.routes.js:39`) among the signed routes of record.
- **Defect**: three audit documents instruct a maintainer to rotate, read or fear infrastructure that no longer exists, and the 11.12 route list — the table meant to drive a signing-boundary test — names a deleted route, so copying it would enshrine a wrong route set.
- **Fix**: one mechanical pass: strip/quarantine the AI sections in `distributed-state.md` (keep a one-line "removed 2026-10-09" tombstone so 10.6/10.7's pointers keep resolving), correct `dead-code-and-outdated-docs.md` and `secrets.md`, and fix `todo.md`'s route list (drop `ai-question`, re-verify the remaining five against `git show 3145a9a`). Do **not** touch `docs/fixing-phase-log.md` — its AI mentions are historical entries by design.
- **Acceptance**: `rg -ni "openrouter|aiConfig|circuitBreaker|quotaService|mock-ai|ai.routes" docs README.md todo.md` returns only tombstones, historical log entries and 10.6/10.7's SUPERSEDED notes.
- **Status: 🟢 OPEN**

---

## Open finding IDs

| ID(s) | Item | Source finding |
| :--- | :--- | :--- |
| Log record↔schema mismatch | 10.21 | revealed by 10.9 (no doc finding; `supabase/schemas/…/logs_*.sql` vs `logger.js`) |
| F9 profile load guard | 10.14 | `architecture` F9 |
| R-5 drive cursor boundary | 10.15 | `realtime` R-5 |
| Mailer absence | 10.16 | `audits/email`, `partnership` finding 2 |
| `debug_wipe_user_data` | 10.17, 11.6, 12.3 | `database-logic` § `debug_wipe_user_data` |
| RPC error localization | 10.18 | `localization` § Alignment Audit |
| Partnership reject path + optimistic filter | 10.13 ✅ resolved via 12.6, 10.19 | `partnership` findings 1, 3 |
| **Forged / re-pointed / deleted partnership** | **11.1, 11.2, 11.3** | scan §2.1–2.3 — `partnerships.sql:27-31` |
| **Writable `auth_id` / `email`** | **11.4** | scan §2.4 — `users.sql:37-41` |
| **Over-broad function grants** | **11.5** | scan §2.5 — four `GRANT … anon/PUBLIC` |
| **Invite forgery via `override_sender_id`** | **11.7** | scan §2.7 — `request_partnership.sql:16-17` |
| **Notification receiver bypass** | **11.8** | scan §3.1 — `notification.service.js:398` |
| **Unsigned authenticated mutations (invite / notify / wipe)** | **11.12** | sweep §1 — `user.routes.js:23-30`, `security/doc.md:52` |
| **Media column contract mismatch** | **12.1, 12.2** | scan §3.4–3.5 — `drive_items.sql` vs media + retention |
| **Named routes → `SplashScreen`** | **12.4** | scan §3.6 — `main.dart:141-150` |
| **Mood checkpoint from device clock** | **12.5** | scan §3.7 — `mood_state.dart:259` |
| **Test safety net is not in git** | **13.2, 13.3** (13.1 ✅ fixed 2026-10-01) | scan §4.2–4.4 — `package.json`, `test-all.sh` |
| **Docs assert a dead safety net** | **13.4, 13.5** | scan §5.1–5.2 — `data-retention.md`, `media-delete-audit.md`, `partnership/doc.md` |
| **~60 doc drifts (batched)** | **13.6** | scan §6/§9 `Docs vs code` pass |
| **35 reported findings, not yet re-read** | **13.7** | scan §6 table |
| F-SC / F-SM / F-RT / F-DS leftovers | 8.4, 8.6, 8.8 (8.1, 8.2, 8.3, 8.5, 8.7 ✅) | see `docs/fixing-phase-log.md` § Item index |
| **Post-AI-removal dead code & simplification** | **14.1–14.12** | 2026-10-09 sweep (no doc finding) — dead exports, stale config, orphaned schema/function, dead Flutter files/methods/strings, AI doc drift |

---

## Suggested fix order (batch plan)

Added 2026-09-29. Phases 11–13 are independent of 8–10, so either track can run first; within a track the order below is forced by shared root causes.

1. **Sprint N (restore the safety net) — 13.1 → 13.2 → 13.3.** Commit `test/` and `scripts/` first, because every later acceptance criterion wants a runnable suite. Then fix the two `package.json` entry points, then make `test-all.sh` portable. Nothing else in Phases 11–13 can be verified without this.
2. **Sprint O (partnerships, one change) — 11.1 → 11.2 → 11.3.** One root cause: the `FOR ALL` policy in `partnerships.sql:27-31`. Splitting it fixes all three and must be done in a single schema change, applied once to the linked project. Ship 11.7 in the same migration — the `override_sender_id` parameter is part of the same trust boundary.
3. **Sprint P (media root cause) — 12.1 → 12.2 → 12.3.** Migrate the backend to `name`/`partnership_id`, which revives the orphan sweep, then re-measure the R2 bucket before and after so the accumulated garbage is known. The wipe's blast radius (12.3) is a product decision and should be taken before the code moves.
4. **Sprint Q (auth/notification) — 11.8 → 11.9 → 11.4 → 11.5 → 11.6 → 11.7 → 11.12.** 11.8 and 11.9 are the two live-code exploits; the rest are hardening. 11.6 needs the live ACL check first, and 11.7 pairs with Sprint O. 11.12 goes last deliberately — its replay-protection value is zero until 11.9 lands, so it ships alongside that fix as defence-in-depth, never instead of it.
5. **Sprint R (client correctness) — 12.4 → 12.5 → 12.6.** Independent of the backend work and safe to run in parallel.
6. **Sprint S (docs) — 13.4 → 13.5 → 13.6.** 13.4 and 13.5 are the two rows that assert something false about behaviour; 13.6 is the mechanical remainder. 13.4 must not land before 12.1/12.2 are re-measured, or it will assert a working sweep again.
7. **Sprint T (verification backlog) — 13.7.** Promotes the audit doc's §6 rows into numbered items. Run it whenever capacity allows; several rows will be needed to close 8.x and 10.x.
8. **Ongoing** — Phase 8 tests folded into every sprint; 8.8 (CI wiring) can only be completed once 13.1–13.3 land, since CI cannot call a script the repository does not contain.

> Keep this file local. Update it as findings are fixed; re-verify each item's "Acceptance" line before ticking. **Never commit this file.**
# Full-Stack Codebase Audit — 2026-11-04

## Executive Summary

Read-only audit of the four layers that make up JustUS: the Flutter client (`Flutter/lib`), the Node/Express backend (`Backend/`), the Supabase Postgres schema (`supabase/`), and the reverse-engineering documentation (`docs/`). The audit targeted dead code, wrong or partial implementations, and defects visible to a real user or exploitable by a real client.

**Baseline (2026-11-03, branch `dev`)** — `flutter analyze` clean · `flutter test` 386 pass · backend Jest 258 pass / 22 suites · ESLint 0 errors. The suites were green with every defect below present, so none of them is covered by an existing regression test.

**Result: 1 critical, 6 high, 20 medium, 25 low findings; 20 suspicions explicitly separated.**

The critical finding is a data-loss path: the R2 orphan sweep reads at most 1000 database rows, so on a large account it treats live media beyond page one as garbage and deletes it. The high findings are: media requests losing the device fingerprint after session binding, the media resolver not knowing about avatars or thumbnails, two audit tables never expiring PII, session binding returning a secret the database never stored, login lockout expiring before its block, and the static partnership cache surviving a logout into the next account.

Every finding carries `file:line` evidence and a concrete fix with an observable acceptance criterion. The executable list lives in `todo.md`; this document is the evidence record.

## Baseline

| Check | Command | Result |
| :--- | :--- | :--- |
| Flutter static analysis | `cd Flutter && flutter analyze` | Clean |
| Flutter tests | `cd Flutter && flutter test` | 386 pass |
| Backend tests | `cd Backend && npx jest --runInBand` | 258 pass / 22 suites |
| Backend lint | `cd Backend && npm run lint` | 0 errors (3 pre-existing warnings) |
| SQL tests | `scripts/run-sql-tests.sh` | Not run — no local `psql`/`DATABASE_URL`; hosted state unverified |

**Unverifiable surfaces:** live Supabase state (RLS enforcement, FK existence, grants, table sizes, whether the stale pgdelta manifest already caused a drop), R2 behavior, FCM delivery, device builds. Findings that depend on live state are marked `Unverified — needs linked DB query`.

---

## Findings Matrix Summary

| ID | Sev | Category | Finding | Location |
| :--- | :--- | :--- | :--- | :--- |
| 18.1 | 🔴 CRITICAL | Data loss | R2 orphan sweep trusts a 1000-row reference set and deletes live objects | `Backend/core/jobs/retentionJob.js:203-257`, `supabase/config.toml:18` |
| 17.1 | 🟠 HIGH | Media/auth contract | Image/video requests omit `X-Device-Fingerprint` after binding | `Flutter/lib/core/network/api_service.dart:40-47`, `Backend/features/auth/session.utils.js:13-21` |
| 17.2 | 🟠 HIGH | Media resolver | `/media/file` resolves only `drive_items.name`; avatars and thumbnails 404 | `Backend/features/media/mediaWorkflow.service.js:119-136` |
| 18.2 | 🟠 HIGH | Retention/PII | `logs_auth_failures` and `logs_notifications` are never expired | `Backend/core/jobs/retentionJob.js:64-67`, `supabase/schemas/public/functions/logs_cleanup.sql:15-18` |
| 19.1 | 🟠 HIGH | Session binding | `trackSession` ignores DB errors and returns an unpersisted binding secret | `Backend/features/auth/authRisk.service.js:104-132` |
| 19.2 | 🟠 HIGH | Auth lockout | Login lockout state expires before the 30-minute block ends | `Backend/features/auth/authRisk.service.js:21-34,76-86` |
| 19.3 | 🟠 HIGH | Cross-account leak | Static partnership cache survives logout; next account inherits the partner | `Flutter/lib/features/partnership/partnership_repository.dart:9-34`, `Flutter/lib/features/auth/auth_state.dart:775-793` |
| 17.3 | 🟡 MEDIUM | Data integrity | Duplicate `drive_items.name` rows make a file permanently unresolvable | `Backend/features/media/mediaWorkflow.service.js:93-130`, `supabase/schemas/public/tables/drive_items.sql:1-16` |
| 17.4 | 🟡 MEDIUM | Data lifecycle | Client-controlled `folder` escapes `uploads/`/`profile/`, so objects survive wipe and orphan sweep | `Backend/features/media/media.schemas.js:8`, `Backend/features/media/r2.service.js:82-87` |
| 18.3 | 🟡 MEDIUM | Retention | Multipart sweep handles only page one and stops on the first abort error | `Backend/core/jobs/retentionJob.js:135-167` |
| 18.4 | 🟡 MEDIUM | Memory leak | Expired login-attempt and idempotency entries are only removed when re-read | `Backend/features/auth/authRisk.service.js:9,21-34`, `Backend/core/infra/idempotencyStore.js:1-29` |
| 18.5 | 🟡 MEDIUM | Error masking | DB read errors become 403/404; wipe can silently skip partner R2 prefixes | `Backend/utils/misc/partnershipUtils.js:3-60`, `Backend/middleware/authMiddleware.js:150-162` |
| 18.6 | 🟡 MEDIUM | HTTP contract | Malformed JSON and oversized bodies return 500 `SYS_FAIL_001` instead of 400/413 | `Backend/middleware/errorHandler.js:16-26`, `Backend/app.js:25-35` |
| 19.4 | 🟡 MEDIUM | Logout teardown | Logout aborts when GoTrue `signOut()` throws and leaves received invites/PartnerState | `Flutter/lib/features/auth/auth_state.dart:775-793`, `Flutter/lib/features/partnership/partner_state.dart:13-17` |
| 19.5 | 🟡 MEDIUM | State race | `ProfileState.clear()` cannot stop an in-flight `loadProfile()` | `Flutter/lib/features/settings/profile_state.dart:41-55,174-182` |
| 19.6 | 🟡 MEDIUM | Auth UX/security | Transient auth failures are reported as wrong passwords and create lockout strikes | `Flutter/lib/features/auth/auth_state.dart:291-303,478-486` |
| 19.7 | 🟡 MEDIUM | Notifications | The notification toggle is bypassed by FCM's OS-rendered background notification | `Flutter/lib/main.dart:14-17`, `Backend/features/notifications/notification.utils.js:166-197` |
| 19.8 | 🟡 MEDIUM | Invite contract | The authoritative invite RPC matches email case-sensitively | `supabase/schemas/public/functions/partnership_request.sql:30-37` |
| 19.9 | 🟡 MEDIUM | Config | Relative FCM service-account paths resolve under `Backend/config/` | `Backend/config/fcm-key.js:10-24`, `.env.test:30` |
| 20.1 | 🟡 MEDIUM | Optimistic state | Bucket `_pendingChanges` overrides are never cleared | `Flutter/lib/features/bucket_list/screens/bucket_list_screen.dart:184-186,310-321` |
| 20.2 | 🟡 MEDIUM | Reactions | Changing a drive reaction violates `UNIQUE (user_id, item_id)` | `supabase/schemas/public/tables/drive_item_reactions.sql:7`, `Flutter/lib/features/drive/drive_repository.dart:177-194` |
| 20.3 | 🟡 MEDIUM | Dead controls | Drive filter chips and SELECT do nothing | `Flutter/lib/features/drive/screens/drive_screen.dart:94-130` |
| 21.1 | 🟡 MEDIUM | Data integrity | `public.users.auth_id` has no FK to `auth.users` despite the documented cascade | `supabase/schemas/public/tables/users.sql:1-10`, `docs/supabase/schema/doc.md:37` |
| 21.2 | 🟡 MEDIUM | DB invariants | Cancellation cooldown and 7-day expiry are enforced only by the RPC, not the trigger | `supabase/schemas/public/functions/partnership_guard_status.sql:51-58` |
| 21.3 | 🟡 MEDIUM | DB invariants | A recipient can accept two pending invitations by direct UPDATE | `supabase/schemas/public/functions/partnership_guard_status.sql:43-49` |
| 21.4 | 🟡 MEDIUM | Signup | The auth trigger discards the username the client sends | `supabase/schemas/public/functions/user_create_from_auth.sql:17-18` |
| 21.5 | 🟡 MEDIUM | Schema tooling | `.pgdelta-export.json` lists a deleted file and omits nine existing functions | `supabase/schemas/.pgdelta-export.json` |
| 17.5 | 🟢 LOW | Resource leak | Compression thumbnails/artifacts are never deleted | `Flutter/lib/core/media/compression_service.dart:10-51` |
| 17.6 | 🟢 LOW | Dead code | `fetchReactions` and its two models have no callers | `Flutter/lib/features/drive/drive_repository.dart:161-175` |
| 18.7 | 🟢 LOW | Middleware | Query validation/sanitization write-back is a silent no-op on Express 5 | `Backend/middleware/validateRequest.js:24-28`, `Backend/middleware/sanitizeRequest.js:28-30` |
| 18.8 | 🟢 LOW | CORS | Empty `ALLOWED_ORIGINS` allows every origin | `Backend/utils/http/corsUtils.js:37-38` |
| 18.9 | 🟢 LOW | Error contract | Capability denial uses `SEC_AUTH_001` instead of `AUTH_PERMISSION_001` | `Backend/middleware/authorizeCapabilities.js:10-15` |
| 18.10 | 🟢 LOW | Dead config | `R2_ACCOUNT_ID` is loaded but never consumed | `Backend/config/env.js:59`, `.env.example:24` |
| 19.10 | 🟢 LOW | Lifecycle | Login/Register `TextEditingController`s are never disposed | `Flutter/lib/features/auth/screens/login_screen.dart:19-22` |
| 19.11 | 🟢 LOW | UI text | Register password hint renders replacement glyphs | `Flutter/lib/features/auth/screens/register_screen.dart:56` |
| 19.12 | 🟢 LOW | Dead code | `AuthState.user` is permanently null; token getters are unused | `Flutter/lib/features/auth/auth_state.dart:69,75-76,790` |
| 20.4 | 🟢 LOW | Crash | Bucket checkbox tap can throw after a realtime delete | `Flutter/lib/features/bucket_list/screens/bucket_list_screen.dart:309-313` |
| 20.5 | 🟢 LOW | Formatting | Bucket dates render raw ISO strings | `Flutter/lib/features/bucket_list/screens/bucket_list_screen.dart:395-397` |
| 20.6 | 🟢 LOW | Localization | Mood timeline is hardcoded to Italian | `Flutter/lib/features/mood/screens/mood_screen.dart:317` |
| 20.7 | 🟢 LOW | UI | Favorites empty-state title is invisible | `Flutter/lib/features/drive/screens/favorites_screen.dart:64-68` |
| 20.8 | 🟢 LOW | Dead controls | Game "View all" and notification bell do nothing | `Flutter/lib/features/games/screens/game_screen.dart:48,102-106` |
| 20.9 | 🟢 LOW | UI | Avatar picker offers unsupported Audio/PDF options | `Flutter/lib/shared/utils/ui/media_picker_service.dart:85-110` |
| 20.10 | 🟢 LOW | Stale cache | App version label is cached forever | `Flutter/lib/features/settings/screens/profile_screen.dart:58-63` |
| 21.6 | 🟢 LOW | Performance | Retention sweeps have no supporting indexes | `supabase/schemas/public/tables/request_nonces.sql`, log tables |
| 21.7 | 🟢 LOW | Dead schema | `permissions`, `roles_permissions`, `drive_file_types` and `drive_items.file_type_id` are unused by the app (only SQL fixtures reference the catalogs) | `supabase/schemas/public/tables/*` |
| 21.8 | 🟢 LOW | Auth config | Redirect allow-list omits the mobile and server callbacks | `supabase/config.toml:158-162` |
| 21.9 | 🟢 LOW | Docs | Supabase docs contradict the schema in two places | `docs/supabase/database-logic/doc.md:178,277` |
| 21.10 | 🟢 LOW | Config | `config.toml` points seeding at a missing `seed.sql` | `supabase/config.toml:67-72` |
| 22.1 | 🟢 LOW | Docs | Feature docs describe routes/columns/state that no longer exist | `docs/features/**` |
| 22.2 | 🟢 LOW | Docs | Backend/Supabase docs describe removed files, tables and provider counts | `docs/backend/**`, `docs/supabase/**` |
| 22.3 | 🟢 LOW | Dead code | Dead notification helper | `Backend/features/notifications/notification.service.js:155-163` |
| 22.4 | 🟢 LOW | Dead code | Unused `LanguageHelper` statics | `Flutter/lib/core/localization/language_helper.dart:91-102` |

---

## Detailed Investigation

### 18.1 — R2 orphan sweep deletes live objects after the first 1000 rows (CRITICAL)

**Files:** `Backend/core/jobs/retentionJob.js:203-257`, `supabase/config.toml:18`

`fetchReferencedKeys()` builds the set of R2 keys that must survive:

```js
const driveRows = await read(
  "drive_items",
  adminSupabase
    .from("drive_items")
    .select("name, metadata")
    .not("name", "is", null)
);
...
const profileRows = await read(
  "user_profiles",
  adminSupabase
    .from("user_profiles")
    .select("profile_pic_url")
    .not("profile_pic_url", "is", null)
);
```

Neither query paginates. `supabase/config.toml:18` sets `max_rows = 1000`, so PostgREST silently truncates each result to 1000 rows. `sweepStaleOrphanObjects()` then lists every object under `uploads/` and `profile/` and deletes any object older than 24 h whose key is not in `referenced`:

```js
if (!referenced.has(object.key) && age < cutoff) {
  orphans.push(object.key);
}
```

**Trigger:** the sweep runs on an installation with more than 1000 `drive_items` rows, or more than 1000 profiles with pictures. **Impact:** every referenced key that falls beyond the first page is treated as garbage; live photos, videos, thumbnails and avatars are permanently deleted from R2. This is silent and irreversible.

**Fix:** add a `readAllPages(query)` helper in `retentionJob.js` that orders by `id`, calls `.range(from, from + 999)` until a short page, and aggregates. Use it for both reads. Keep the existing `null`-on-read-failure skip: a failed page must abort the whole sweep rather than produce a partial reference set.

**Acceptance:** a unit test seeds 1001 drive rows where the last row references `uploads/u/keep.jpg`, marks that object older than the cutoff, runs the sweep, and asserts the object is not deleted and both pages were requested. Same for profile pictures.

**Unverified — needs linked DB query:** the actual row counts and whether PostgREST returns exactly 1000 or errors. The defect is proven from the config value, independent of row counts.

---

### 17.1 — Media requests drop the device fingerprint after session binding (HIGH)

**Files:** `Flutter/lib/core/network/api_service.dart:40-47`, `Flutter/lib/shared/widgets/protected_network_image.dart:33`, `Flutter/lib/core/media/media_cache_manager.dart:69-84`, `Backend/features/auth/session.utils.js:13-21`, `Backend/middleware/authMiddleware.js:47-60`

`ApiService.authHeaders` is the only header map used by image/video loaders:

```dart
static Map<String, String> get authHeaders {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) return const {};
  return {'Authorization': 'Bearer $token'};
}
```

After `POST /auth/session-bind`, `session_bindings.device_fingerprint_hash` is set. `validateSessionBinding` then requires the request header:

```js
if (!clientContext.deviceFingerprint ||
    sessionBinding.device_fingerprint_hash !== clientContext.deviceFingerprintHash) {
  throw new AppError({ errorKey: "AUTH_FAIL_006" });
}
```

`buildClientContext` reads `req.get("x-device-fingerprint")`; image/video loaders never send it. `ProtectedNetworkImage` passes only `authHeaders`; `_R2FileService` passes no headers at all; `DriveGridItem` uses `CachedNetworkImage` with no headers. **Trigger:** any media load after the first successful bind. **Impact:** avatars, drive tiles, favorites tiles and video playback all fail with 401 `AUTH_FAIL_006` (or `AUTH_FAIL_002` for the unauthenticated cache path), which is the exact post-login experience for every user.

**Fix:** include the cached fingerprint in `authHeaders` (`_cachedDeviceFingerprint` already exists and is populated by `_buildHeaders`), and make every media loader send `ApiService.authHeaders`. For the bare-key path in `_R2FileService`, pass the headers through to `super.get`. Do not add an async header builder unless a request can genuinely run before the first API call; if that is possible, resolve the fingerprint once in `ApiService` initialization.

**Acceptance:** after a bind, `GET /api/v1/media/file?filename=...` with `Authorization` + `X-Device-Fingerprint` returns 302; the same request without the fingerprint returns 401 `AUTH_FAIL_006`. A Flutter widget test asserts `ProtectedNetworkImage.httpHeaders` contains both headers.

---

### 17.2 — Avatars and thumbnails are not resolvable by `/media/file` (HIGH)

**Files:** `Backend/features/media/mediaWorkflow.service.js:119-136`, `Flutter/lib/core/media/media_service.dart:102-127`, `Flutter/lib/features/drive/drive_models.dart:93-95`

The download path authorizes a key only through `drive_items.name`:

```js
const { data: media, error } = await adminSupabase
  .from("drive_items")
  .select("partnership_id")
  .eq("name", filename)
  .single();

if (error || !media) {
  throw new AppError({ errorKey: "DB_NOT_FOUND_001", ... });
}
```

But the app stores two other kinds of R2 keys:

- Profile pictures are written to `user_profiles.profile_pic_url` (`mediaWorkflow.service.js:74-87`).
- Grid thumbnails are written only to `drive_items.metadata.thumbnail` (`media_service.dart:122-126`; read by `DriveItem.contentThumb`, `drive_models.dart:93-95`).

Both grids ask the resolver for those keys. `.eq("name", ...)` finds no row, so the endpoint returns `DB_NOT_FOUND_001`. **Trigger:** opening any profile or any drive grid with a generated thumbnail. **Impact:** every avatar and every image/video tile is a broken-image placeholder; the phase-16 thumbnail flow is unusable.

**Fix:** resolve in this order, stopping at the first match:

1. `drive_items` where `name = filename` **or** `metadata->>thumbnail = filename`.
2. `user_profiles` where `profile_pic_url = filename`.

Then authorize the row: drive rows through `isPartnershipMember(partnership_id, userId)`; profile rows through the owner (`user_profiles.user_id = userId`) or an accepted partner. Reject any key that does not start with `uploads/<userId>/`, `users/<userId>/` or `profile/<userId>/` before signing it — this also closes the suspected direct-insert path in 21.11. Use `.limit(1).maybeSingle()` rather than `.single()` so a duplicate row cannot turn a valid file into a 404 (see 17.3).

**Acceptance:** the owner and the accepted partner get 302 for a profile key and for a `_thumb.jpg` key; an unrelated user gets 403/404; a crafted `drive_items` row pointing at another user's key is rejected. Backend tests cover all four cases.

---

### 18.2 — Two actively written audit tables never expire (HIGH)

**Files:** `Backend/core/jobs/retentionJob.js:64-67`, `supabase/schemas/public/functions/logs_cleanup.sql:15-18`, `Backend/core/logger.js:256-290`

The scheduled Node sweep covers three tables:

```js
const tables = ["logs_security_events", "logs_api_access", "logs_api_errors"];
```

The SQL function covers four, and still omits `logs_auth_failures`:

```sql
DELETE FROM public.logs_api_access ...
DELETE FROM public.logs_api_errors ...
DELETE FROM public.logs_security_events ...
DELETE FROM public.logs_notifications ...
```

Both omitted tables are actively written: `logAuthFailure()` inserts into `logs_auth_failures` (IP, path, reason, payload) and `logNotification()` inserts into `logs_notifications`. The Node job does not call `logs_cleanup()`, so `logs_notifications` is only pruned if an operator runs the SQL function by hand. **Impact:** failed-auth PII (IP addresses, paths, error context) and notification history accumulate without bound; the tables grow until storage or query time becomes a problem.

**Fix:** add `"logs_auth_failures"` and `"logs_notifications"` to the Node `tables` array; add `DELETE FROM public.logs_auth_failures` to `logs_cleanup.sql`. Update `docs/audits/data-retention.md`, the retention SQL test and the Jest table assertion.

**Acceptance:** one sweep issues a cutoff DELETE for all five tables; a 91-day row in each is gone and an 89-day row remains. Both the Jest suite and the SQL assertions fail if a table is dropped from either list.

---

### 19.1 — `trackSession` returns a binding secret the database never stored (HIGH)

**Files:** `Backend/features/auth/authRisk.service.js:104-132`, `Backend/features/auth/auth.controller.js:152-171`

```js
await adminSupabase.from("session_bindings").upsert(payload, { onConflict: "session_id" });
...
return { anomalies, bindingSecret, clientContext };
} catch {
  return { anomalies: [], bindingSecret, clientContext };
}
```

The upsert result is discarded, so a Supabase error (RLS, FK, network, missing column) does not throw. The catch-all then returns the freshly generated `bindingSecret` anyway. The controller responds `200` with that secret. **Trigger:** any failure while persisting the binding. **Impact:** the client signs subsequent requests with a secret the server never stored; `requireSignedRequest` rejects them with `SEC_AUTH_002`, and the client retries/recovery loops. Session binding is silently disabled for that session.

**Fix:** wrap the upsert in `assertDbSuccess(..., "DB_WRITE_001")`; reject a missing `sessionId` before generating the secret; let RPC errors from `revokeStaleDeviceSession` propagate (or log them but still fail the bind if the current row was not written). Only return `bindingSecret` after the row is confirmed.

**Acceptance:** a stubbed upsert error returns 500 `DB-WRITE-001` with no `bindingSecret`; a successful bind stores a row whose `binding_secret` equals the returned value and verifies a signed request.

---

### 19.2 — The lockout ends before its scheduled block (HIGH)

**Files:** `Backend/features/auth/authRisk.service.js:21-34,76-86`

```js
const fresh = {
  failures: 0,
  strikeLevel: 0,
  blockedUntil: 0,
  expiresAt: now + 15 * 60_000,
};
```

`getAttemptState()` replaces the state when `existing.expiresAt <= now`, and `expiresAt` is never extended after creation. The third strike sets `blockedUntil = now + 30 min`, but the state was created 15 minutes earlier, so at minute 15 the entry is discarded and the 30-minute block evaporates. The same applies to the 10-minute block set late in the 15-minute window. **Trigger:** repeated failures spread across the window. **Impact:** the documented 10/30-minute lockout can end after 0–15 minutes, so brute-force protection is weaker than advertised.

**Fix:** every time the state is touched, set `expiresAt = Math.max(now + 15 * 60_000, state.blockedUntil)`. Only reset when no block is active.

**Acceptance:** fake-timer tests prove a 10-minute block set at minute 14 lasts to minute 24 and a 30-minute block set at minute 14:59 lasts 30 minutes; a success after the block clears the state.

---

### 19.3 — Logout leaves the static partnership cache alive (HIGH)

**Files:** `Flutter/lib/features/partnership/partnership_repository.dart:9-34`, `Flutter/lib/features/auth/auth_state.dart:775-793`

```dart
static Future<Map<String, dynamic>?>? _activePartnershipFuture;
static int? _activePartnershipUserId;

Future<Map<String, dynamic>?> getActivePartnership() async {
  if (_activePartnershipFuture != null) {
    return _activePartnershipFuture;   // returns before the user-id check
  }
  ...
  if (_activePartnershipUserId != null && currentUid != null && _activePartnershipUserId != currentUid) {
```

The user-id mismatch check is unreachable while a cached future exists. `AuthState.logout()` clears storage and calls `onClearFeatureStates`, but never calls `PartnershipRepository.clearPartnershipCache()`. **Trigger:** account A logs out and account B logs in in the same process. **Impact:** B's first `getActivePartnership()` returns A's partnership; B is routed to MainShell/PartnerScreen with A's partner id and display name, and `PartnerState` shows A's partner and cancellation until something forces a refetch. This is a cross-account data exposure on shared devices.

**Fix:** call `PartnershipRepository.clearPartnershipCache()` at the start of `logout()`; move the user-id check before the cached-future early return (or key the cache by user id). Add `PartnerState.clear()` to the same teardown (see 19.4).

**Acceptance:** seed A's cache, log out, set B's user id, call `getActivePartnership()`, and assert it queries the server, returns B's row, and contains no A partner id/name in state or storage.

---

### Medium findings

#### 17.3 — Duplicate `drive_items.name` rows permanently 404 a file
`registerCompletedUpload` always inserts; `drive_items.name` has no UNIQUE constraint. A retried `/complete` creates a second row with the same name, after which `getSignedDownloadUrl`'s `.single()` fails and every download of that key returns `DB_NOT_FOUND_001`. **Fix:** add a UNIQUE constraint on `name` and make completion an upsert, or at minimum use `.limit(1).maybeSingle()` and deduplicate on read. **Acceptance:** two `/complete` calls leave one row (or a deterministic conflict) and `/media/file` still returns 302.

#### 17.4 — A signed client can choose an arbitrary upload folder
`presignSchema` accepts `folder` (1–32 chars) and `buildObjectKey` interpolates it after stripping unsafe characters. A client can presign `folder: "custom"`, producing `custom/<uid>/...`, which is outside the `uploads/` and `profile/` roots used by the orphan sweep and by `deleteUserR2Objects`. **Impact:** those objects survive account wipe and retention. **Fix:** derive the folder server-side from `kind`/`type` or allowlist only `uploads` and `profile`; reject anything else at the schema boundary. **Acceptance:** `folder: "custom"` is rejected or rewritten under `uploads/`; a wipe removes every object under both allowed roots.

#### 18.3 — Multipart sweep ignores pagination and stops on the first error
`ListMultipartUploadsCommand` is called once with no marker; `IsTruncated`, `NextKeyMarker` and `NextUploadIdMarker` are ignored. All aborts share one try block, so one failed abort skips the rest. **Impact:** uploads beyond the first 1000 are never aborted and one bad upload blocks cleanup of the others. **Fix:** loop on `IsTruncated` with the markers and catch each abort separately. **Acceptance:** a two-page mock aborts both stale uploads; one rejected abort still attempts the later ones.

#### 18.4 — Expired in-memory maps are never swept
`loginAttempts` and the idempotency `responses` map remove an entry only when the same key is read again. Unique emails/IPs and unique idempotency keys therefore accumulate until restart. **Fix:** add `.unref()` interval sweeps deleting `expiresAt <= now`, matching the existing rate-limit sweeper. **Acceptance:** seeded expired entries are removed, live entries survive, and Jest exits without the timer holding it open.

#### 18.5 — DB read errors are masked as 403/404
`getPartnerId`, `getCancellationPartnerId` and `getPartnershipById` discard Supabase `error` and return `null`; `authMiddleware` interprets that as "no partner" and returns `AUTH_FAIL_005`/`API_VALIDATION_012`. During account wipe, the same null result makes `deleteUserR2Objects` skip the partner's prefixes. **Impact:** outages look like authorization failures, and a wipe can silently leave partner media in R2. **Fix:** use `assertDbSuccess(..., "DB_READ_001")` in all three helpers and let the error propagate; do not swallow the lookup during wipe. **Acceptance:** a mocked read error returns `DB-READ-001`; a wipe test asserts all four prefixes are attempted or the endpoint returns a retryable 500.

#### 18.6 — Body-parser errors become 500
`errorHandler` only recognizes `AppError`; `AppError.from` ignores `err.status`. Express body-parser emits `entity.parse.failed` (400) and `entity.too.large` (413), which fall through to `SYS_FAIL_001`/500 and are logged as server errors. **Fix:** map `entity.parse.failed` to `API_VALIDATION_001` and `entity.too.large` to a dedicated 413 code before the generic fallback. **Acceptance:** supertest proves malformed JSON returns 400 `API-VALIDATION-001` and an oversized body returns 413, never 500.

#### 19.4 — Logout aborts on a GoTrue failure and leaves state behind
`AuthState.logout()` calls `await _authRepo.signOut()` outside a try block. If GoTrue is offline or returns a retryable failure, the exception aborts before `CacheService.clearAll()`, `StorageService.clearAll()`, the field resets and navigation; the user stays logged in. `_receivedInvitations` is never reset, and `onClearFeatureStates` clears six states but not `PartnerState` (which holds `_partnershipInfo` and `_cancellation`). **Fix:** wrap `signOut()` in try/catch like `_revokeInstallationId()`; always run the remaining teardown; reset `_sentInvitations` and `_receivedInvitations`; add `PartnerState.clear()` and wire it into `onClearFeatureStates`. **Acceptance:** a throwing fake auth repository still reaches `/login` with tokens and caches cleared; a test that populates both invitation lists and `PartnerState`, logs out, and asserts all are empty before the next account's first frame.

#### 19.5 — `ProfileState.clear()` cannot stop an in-flight load
`loadProfile()` deduplicates on `_inFlightLoad`; `clear()` nulls the fields but does not invalidate the future. If logout/wipe happens while a slow fetch is in flight, the old account's profile and partner profile are written after `clear()`, and the one-minute throttle keeps them visible to the next account. **Fix:** add a generation counter incremented by `clear()`; discard state and storage writes from a stale generation. **Acceptance:** start `loadProfile()`, `clear()`, complete the fetch, and assert state/storage stay empty while the next load still queries the server.

#### 19.6 — Transient auth failures are treated as wrong credentials and create strikes
`login()` catches every `AuthException` and maps it to `AUTH_FAIL_CRED`, then calls `_reportFailedLogin(..., 'invalid_credentials')`. `AuthRetryableFetchException` (offline, GoTrue 5xx/429) is a subclass of `AuthException`, so a network outage is shown as "wrong password" and feeds the lockout engine. **Fix:** catch `AuthRetryableFetchException` before `AuthException` and map it to `AppError.network()` without a strike; apply the same distinction in `changePassword()`. **Acceptance:** a fake throwing `AuthRetryableFetchException` produces a network error and zero `reportFailedLogin` calls, while a real wrong-password `AuthApiException` still produces the current-password message.

#### 19.7 — The notification toggle does not stop background notifications
The backend always sends an FCM `notification` block and an APNs `alert`. When the app is backgrounded or terminated, the OS renders that block directly; `_firebaseMessagingBackgroundHandler` returns immediately when `message.notification != null` (`main.dart:14-17`), so `StorageService.getNotificationsEnabled()` is never consulted. The toggle is stored only on the device, so the server cannot filter recipients either. **Impact:** a user who disabled notifications still receives banners and sounds. **Fix:** persist the preference server-side (`user_devices.notifications_enabled`, default `true`), update it from the toggle through the existing installation-registration path, and filter recipient devices in `getReceiverInstallationIds`/`notification.service.js`. This is preferred over data-only messages because iOS does not guarantee background delivery for data-only payloads. **Acceptance:** with the toggle off, a backgrounded and a terminated device receive no notification; the server-side query excludes the disabled installation id.

#### 19.8 — Invite matching is case-sensitive in the authoritative RPC
The controller pre-check uses `ilike("email", email.trim())`, but `partnership_request` compares `u.email = partner_email`. A mixed-case or space-padded address passes the pre-check and then fails `API-VALIDATION-005`. **Fix:** compare `lower(btrim(u.email)) = lower(btrim(partner_email))` in the RPC and trim the client input. **Acceptance:** `Partner@Example.com` invites the stored `partner@example.com`; a genuinely wrong address still returns `API-VALIDATION-005`.

#### 19.9 — Relative FCM service-account paths resolve under `Backend/config/`
`require(serviceAccountPath)` resolves relative paths against `Backend/config/fcm-key.js`, so `.env.test`'s `./test-data/fcm-service-account.json` becomes `Backend/config/test-data/...`. In production a relative `FCM_SERVICE_ACCOUNT_PATH` fails the same way; initialization logs an error and push silently stops. **Fix:** `path.resolve(__dirname, "..", serviceAccountPath)` for relative paths, preserving absolute ones. **Acceptance:** a temp account file under `Backend/test-data` loads; absolute paths still work.

#### 20.1 — Bucket optimistic overrides are never cleared
`_pendingChanges` is removed only when the user toggles the row back to the server value. Realtime updates and a fresh `loadData` never clear it, so a partner's later toggle is masked forever and a failed write still looks successful. **Fix:** move the optimistic toggle into `BucketState.toggleDone` with rollback on error (following `DriveState.toggleFavorite`), then delete `_pendingChanges` from the screen. **Acceptance:** with two sessions, A marks done and B undoes; A shows undone without leaving the screen; an offline toggle reverts with an error.

#### 20.2 — A reaction can never be changed
The table has `UNIQUE (user_id, item_id)`, but `addReaction` always inserts. Choosing a second emoji raises Postgres `23505`; the UI shows an error and the original reaction remains. **Fix:** use `.upsert({...}, onConflict: 'user_id,item_id')` and replace the local reaction instead of appending. **Acceptance:** reacting 😀 then 😂 succeeds; after refresh the detail shows only 😂 and no `23505`.

#### 20.3 — Drive filter chips and SELECT are inert
`VPFilterChip` has no `onTap`; "All" is hardcoded active. The header's SELECT button has `onPressed: () {}`. **Impact:** users tap filters and get no change; SELECT advertises a selection mode that does not exist. **Fix:** add one filter enum + filtered getter for the in-memory items and wire the chips; delete SELECT (no selection mode exists). **Acceptance:** Photos/Videos/Likes/All change the grid; SELECT is absent or functional; `flutter analyze` clean.

#### 21.1 — `public.users.auth_id` has no FK to `auth.users`
`users.sql` declares `auth_id uuid` with only a UNIQUE constraint; `docs/supabase/schema/doc.md:37` claims `users_auth_id_fkey ... ON DELETE CASCADE`. Deleting an auth user leaves the public row and all couple data; a later signup with the same email hits `users_email_key` inside the auth trigger. **Fix:** after cleaning orphans, add `FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE` (or an `AFTER DELETE` trigger if the auth schema cannot be referenced from a migration). **Acceptance:** deleting an auth user removes the public row and cascaded app data; the same email can register again. **Unverified — needs linked DB query:** current orphan count and whether the FK already exists remotely.

#### 21.2 — The cancellation trigger accepts any expiry and ignores the cooldown
`partnership_request_cancel` enforces `cancel_declined_at > now() - 24h` and writes `now() + 7 days`, but `partnership_guard_status`'s `accepted → cancelled` branch only checks that the caller is a member, `cancel_requested_by` is the caller, and `cancel_expires_at` is non-null. A direct PATCH can therefore bypass the 24-hour cooldown and set a 100-year expiry. **Impact:** a declined requester can re-spam immediately and freeze the pair in `cancelled` indefinitely. **Fix:** move the cooldown check and a `now() < cancel_expires_at <= now() + 7 days` bound into the trigger branch. **Acceptance:** a direct update within 24 hours of a decline raises `42501`; a 100-year expiry raises `42501`; the RPC still sets exactly 7 days.

#### 21.3 — Direct UPDATE can accept two pending invitations
`partnership_accept` checks for another `accepted`/`cancelled` partnership before accepting, but the trigger's `pending → accepted` branch only checks that the caller is `user_id_2`. Two direct PATCHes create two accepted rows; `v_active_partnership` then returns two rows, `maybeSingle()` throws, and `mood_set` picks an arbitrary partnership. **Fix:** add the same `EXISTS` single-partnership check to the trigger branch. **Acceptance:** with two pending rows, the second direct accept raises `42501`; the RPC still accepts exactly one. **Unverified — needs linked DB query:** whether the current remote trigger already includes the check.

#### 21.4 — Signup discards the username the client sends
Flutter sends `{'username': name}` in `signUp` metadata (`auth_state.dart:370-372`), but `user_create_from_auth()` inserts `split_part(NEW.email, '@', 1)` as `display_name` and ignores `raw_user_meta_data`. A user who registers as "Alice" appears as the email local part. **Fix:** `COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'username'), ''), split_part(NEW.email, '@', 1))`. **Acceptance:** registering with a name different from the email prefix stores that name; both auth docs state the same rule.

#### 21.5 — The declarative pgdelta manifest is stale
The manifest lists 68 files; the directory contains 76. It still lists the deleted `public/functions/partnership_get_names.sql` and omits nine existing functions, including `partnership_cancel_accept`, `partnership_cancel_revert`, `partnership_expire_cancellations`, `device_purge_dead_sessions` and `drive_change_probe`. **Impact:** a pgdelta diff can fail on the missing file or generate `DROP FUNCTION` statements for live features. **Fix:** remove the stale entry, regenerate the export from the current schema, and add a files-vs-directory check. **Acceptance:** the comparison reports 0 missing and 0 unlisted; `supabase db diff` is empty against the applied schema. **Unverified — needs linked DB query:** the applied remote schema.

---

### Low findings

| ID | Evidence | Defect | Fix |
| :--- | :--- | :--- | :--- |
| 17.5 | `compression_service.dart:10-51`, `media_service.dart:164-204` | `compressImage`, `createThumbnail` and video frame extraction write temp files that are never deleted; repeated uploads consume app storage until the OS reclaims it. | Delete generated files in a `finally`, comparing paths first because the service returns the original on failure. |
| 17.6 | `drive_repository.dart:161-175`, `drive_models.dart:123-157` | `fetchReactions`, `DriveItemReaction` and `DriveItemReactionsListResponse` have no callers; the nested `emojis(emoji_char)` parse does not match `fromJson`. | Delete all three; revive only if a reaction list UI is built. |
| 18.7 | `validateRequest.js:24-28`, `sanitizeRequest.js:28-30`, Express 5.2.1 `request.js:217` | `req.query = parsed.data` assigns to a prototype getter with no setter. In non-strict CommonJS this is silently ignored, so coercion/defaults/stripping and query sanitization never reach handlers. | Shadow the getter with `Object.defineProperty(req, "query", { value: parsed.data, configurable: true })`, or pass validated query data through a dedicated property. |
| 18.8 | `corsUtils.js:37-38`, `env.js:48` | `if (allowedOrigins.length === 0) return true;` — an unset `ALLOWED_ORIGINS` allows every origin. | Return `false` for an empty list, or require the variable in production; keep the development private-origin branch. |
| 18.9 | `authorizeCapabilities.js:10-15` | Missing capabilities return `SEC_AUTH_001`, although `AUTH_PERMISSION_001` exists and is used elsewhere; clients cannot distinguish permission failure from binding failure. | Switch to `AUTH_PERMISSION_001` and update the pinned integration assertion. |
| 18.10 | `env.js:59`, `.env.example:24`, `.env.test:33` | `r2AccountId` is loaded but has no consumer. | Delete the field and both template entries. |
| 19.10 | `login_screen.dart:19-22`, `register_screen.dart:19-23` | Controllers are never disposed; listeners survive repeated navigation. | Add `dispose()` overrides disposing all controllers, matching `ChangePasswordScreen`. |
| 19.11 | `register_screen.dart:56` | Hint is ten U+FFFD replacement glyphs instead of bullets. | Use the same bullet string as `LoginScreen` or a shared localization key. |
| 19.12 | `auth_state.dart:69,75-76,790` | `AuthState.user` is permanently null; `accessToken`/`refreshToken` getters have no consumers. | Delete the field and both getters; keep the private token fields used internally. |
| 20.4 | `bucket_list_screen.dart:309-313` | `firstWhere` has no `orElse`; a realtime delete between build and tap throws `StateError`. | Use `firstOrNull` and return when absent. |
| 20.5 | `bucket_list_screen.dart:395-397` | `item.createdAt.split('T').first` prints `2026-11-04` in both locales. | Parse with `AppDateUtils.tryParse(...).toLocal()` and format with `MaterialLocalizations.formatMediumDate`. |
| 20.6 | `mood_screen.dart:317` | `DateFormat('d MMMM', 'it')` ignores the app locale; English users see Italian months. | Use `Localizations.localeOf(context).toLanguageTag()`. |
| 20.7 | `favorites_screen.dart:64-68` | Title color is `palette.canvas` on a `palette.canvas` scaffold, so the empty-state title is invisible. | Remove the override or use `contentPrimary`. |
| 20.8 | `game_screen.dart:48,102-106,178-213` | "View all" has `onActionTap: null`; the bell has no destination while showing an unread dot. | Delete both controls or wire them to real screens; do not keep a dead affordance. |
| 20.9 | `media_picker_service.dart:85-110`, `profile_screen.dart:65-75` | The avatar sheet offers Audio and Documents; the avatar upload then rejects the MIME type with `API-VALIDATION-001`. | Add an `imagesOnly`/allowlist parameter and pass it from `_pickProfilePhoto`; Drive keeps all four. |
| 20.10 | `profile_screen.dart:58-63`, `storage_service.dart:362-373` | `app_version` is reused forever after the first install, so Settings shows the old version while the update checker uses the new build. | Read `PackageInfo` every time and use the stored value only as a fallback, or key the cache by build number. |
| 21.6 | `request_nonces.sql`, log tables | No index on `request_nonces(expires_at)` or `created_at` for the swept log tables; every retention run scans. | Add btree indexes on `request_nonces(expires_at)` and `created_at` for all five log tables. |
| 21.7 | `permissions.sql`, `roles_permissions.sql`, `drive_file_types.sql`, `drive_items.sql:12`, `v_drive_dashboard.sql:9-11`, `supabase/test/rls_*` | Capabilities are hardcoded in JS; the three catalogs are referenced only by SQL test fixtures, never by runtime code; `drive_file_types` is never written and the view's `ft` columns are ignored by the client. | Drop the three tables, `drive_items.file_type_id`, and the `ft` select/join; keep `roles`/`user_roles`, and update the two RLS test fixtures. |
| 21.8 | `config.toml:158-162`, `auth_state.dart:88-101` | The exact allow-list has only `http://127.0.0.1:3000` and `https://127.0.0.1:3000`; the client sends `justus://auth/callback` and the server `/auth/callback`. | Add the exact mobile and server callback URLs; correct the `https` localhost typo. |
| 21.9 | `database-logic/doc.md:178,277`, `rls/doc.md:138,161,169` | Docs claim the pending-invitations RPC exposes email (it returns `partner_display_name` only) and that deleting a user cascades to `logs_auth_failures` (it is `ON DELETE SET NULL`); `auth_sessions` is named instead of `session_bindings`/`auth.sessions`. | Correct the two database-logic lines and replace `auth_sessions` with the real table names. |
| 21.10 | `config.toml:67-72` | Seeding is enabled with `sql_paths = ["./seed.sql"]`, but `supabase/seed.sql` does not exist. | Add the seed file or disable the `[db.seed]` entry. |
| 22.1 | `shared-drive/doc.md:28,241,348`; `bucket-list/doc.md:28`; `architecture/doc.md:73,524`; `profile-settings/doc.md:129,283,186` | `/media/download-signed` is documented but the route is `/media/file`; bucket doc says there is no `updated_at` while the table and later sections use it; "eleven providers" but `main.dart` creates ten; `UpdateService` is documented as desktop-only but runs on all non-web; `ProfileState.debugWipeData` actually lives on `UserRepository`/`wipeAppData`; `app_version` is documented as not cleared on logout but `clearAll()` clears it. | Update each claim to the current code/schema. |
| 22.2 | `infrastructure/doc.md:19,84`; `schema/doc.md:9,16`; `api-architecture/doc.md:164`; `error-handling/doc.md:68` | "138 modules" but `all_imports.js` has 133 getters; `supabase/schema/remote_schema.sql` does not exist; `/app-version` is documented as querying an `app_versions` table but `versionService.js` reads `data/versions/app_version.json`; `ErrorHandler._toAppError` does not exist (it is `toAppError`). | Correct the counts, remove the dead path, describe the JSON file, fix the method name. |
| 22.3 | `notification.service.js:155-163,168` | `getReceiverInstallationId` has no callers. (The 40 never-destructured `all_imports.js` getters are generated by `tool/generate_imports.js` and are not tracked as dead code — regeneration re-adds them.) | Delete the helper and its export. |
| 22.4 | `language_helper.dart:91-102` | `languageForLocale` and `LanguageHelper.isSupported` have no callers in `Flutter/lib`, `Flutter/test`, `Backend`, `supabase`, `docs` or scripts. | Delete both statics. |

---

## Not Confirmed / Suspicions

These are real code smells or plausible defects, but the trigger or user-visible symptom could not be proven statically. They are **not** tracked as fix items until reproduced.

| # | Suspicion | Evidence | Why unconfirmed |
| :--- | :--- | :--- | :--- |
| S1 | Remote `signedOut` events are ignored by the auth listener, so a session revoked on another device leaves local state until a later 401 | `auth_state.dart:176-198` | No standalone trigger/symptom proven; the 401 path eventually calls `logout()` |
| S2 | `PartnerScreen` entered cold may show stale/no cancellation until refresh | `partner_screen.dart:29-33` | Normal post-auth navigation usually fetches first; cold-entry route unverified |
| S3 | `fetchSentInvitations()` and `fetchReceivedInvitations()` each call the same RPC, doubling requests | `auth_state.dart:561-568` | Performance only; no user-visible failure |
| S4 | Notification preference is device-level, so account B inherits A's disabled setting | `storage_service.dart:446-452` | Documented as deliberate device-level retention |
| S5 | `DriveState.loadSingleItem` throws on an empty list (`orElse: () => _driveItems.first`) | `drive_state.dart:272-279` | No current caller passes an id with an empty list |
| S6 | Mood recent-emoji chips are not tappable | `mood_screen.dart:286-305` | May be intentional display-only |
| S7 | First drive tile is permanently highlighted (`isHighlighted = index == 0`) | `drive_screen.dart:250` | Possibly intentional "latest" emphasis |
| S8 | Bucket category `ChoiceChip` bypasses the design system | `bucket_list_screen.dart:68` | Visual-review item, no functional defect |
| S9 | The 302 to R2 may forward the Supabase `Authorization` header across hosts | `media.controller.js:35-40`, `protected_network_image.dart:31-33` | Depends on the HTTP client's redirect behavior; not tested |
| S10 | A verified token without `session_id` builds a non-UUID key against a `uuid` column | `authMiddleware.js:172-181` | Normal Supabase tokens carry `session_id`; reachability unconfirmed |
| S11 | Cancellation cleanup deletes `uploads/<uid>/` after the partnership row is gone, so a new upload in the window could be lost | `partnership.service.js:5-15,57-64` | Race not reproduced |
| S12 | Timeout middleware can double-respond after a late handler | `timeoutMiddleware.js:3-13` | No repro; `headersSent` guards may cover it |
| S13 | Idempotency middleware caches 4xx/5xx responses for 24 h | `idempotencyMiddleware.js:21-28` | Flutter uses a fresh UUID per attempt, so impact is latent |
| S14 | Per-user rate-limit rule ignores a custom `windowMs` | `rateLimitPresets.js:3-8` | No current caller passes a custom window |
| S15 | `logAuthFailure` writes the raw record to stdout before sanitization | `logger.js:256-257,323-327` | No current production caller passes `req.body` |
| S16 | Pre-relationship `moods` (`partnership_id IS NULL`) are visible to a new partner | `moods.sql:35-38`, `mood_repository.dart:31-55` | Product rule undecided; RLS doc treats it as intended |
| S17 | A client-crafted `drive_items` row can point at another user's R2 key | `drive_items.sql:38`, `mediaWorkflow.service.js:119-136` | Key is random and no enumeration path found; 17.2's ownership check closes it |
| S18 | `supabase/seed.sql` is missing though seeding is enabled | `config.toml:67-72` | CLI behavior on a missing seed file is environment-dependent |
| S19 | The hosted SQL test inserts into `auth.users`/`auth.sessions` and may lack privileges | `supabase/test/prune_user_devices_dead_sessions.test.sql:17` | Hosted role behavior unverified |
| S20 | `game_questions.user_id_a/user_id_b` have no `ON DELETE` clause | `game_questions.sql:11-12` | No in-app user-deletion path exists |

---

## Known Non-Bugs & Deliberate Decisions

- **Shared media rate-limit bucket (40/user/min for reads, uploads and deletes)** — deliberate, recorded in `docs/audits/media-delete-audit.md` §F-5. Do not "fix" without a product decision.
- **15 MB pre-compression upload cap** — deliberate (phase 5.4).
- **Fingerprint survives logout** — deliberate (phase 10.1); `docs/app/storage-and-caching/doc.md:51,207` is correct.
- **Notification preference is device-level across accounts** — documented in `storage_service.dart:446-452`; distinct from the background-delivery bug in 19.7.
- **Homepage does not use `TabScreenMixin`; Profile is not wired to realtime** — documented in `docs/app/architecture/doc.md:460-464` and `docs/app/state-management/doc.md:140`.
- **`debug_` table/function prefix** — deliberate (phase 10.17).
- **Nonce fail-open, `session_is_live` fail-open, orphan-sweep read-failure skip** — accepted decisions #36, #37, #45 in `docs/fixing-phase-log.md`.

---

## Recommended Cleanup Action Plan

1. **Stop the data loss first (18.1).** Paginate the orphan-sweep reads and add the 1001-row test before touching anything else. This is the only finding that destroys user data without a trigger the user controls.
2. **Restore media delivery (17.1, 17.2, 17.3).** Ship the fingerprint header, the resolver union and the duplicate-name guard together: fixing only one leaves avatars or thumbnails broken, and the acceptance tests overlap.
3. **Close the auth/session leaks (19.1, 19.2, 19.3, 19.4, 19.5).** These share the session/teardown path; one regression test can cover the cross-account state and the fail-closed bind.
4. **Expire PII (18.2, 18.3, 18.4, 18.5, 18.6).** Retention and error-masking changes are backend-only and independent of the client work.
5. **Enforce DB invariants (21.1–21.5).** Apply SQL to the linked project per the fix workflow; each item needs a direct-PATCH assertion, not only an RPC test.
6. **Fix feature surfaces (20.1–20.3).** Bucket overrides, reactions and drive filters are independent; each has a two-session or two-emoji acceptance test.
7. **Sweep the low-severity UI/config/dead-code items (Phase 22 and the 17.5–21.10 rows).** These are safe to batch by file.
8. **Add the regression tests (23.1–23.4) while the fixes are fresh.** The current suites passed with every finding present; without these tests the next refactor re-introduces them.

---

## Coverage

| Pass | Surfaces examined | Result |
| :--- | :--- | :--- |
| 0 Baseline | `flutter analyze`, `flutter test`, backend Jest, ESLint, SQL runner | Green: 386 Flutter, 258 backend, 0 lint errors; SQL tests not runnable locally |
| 1 Docs vs code | `docs/**` (app, features, backend, supabase), `README.md` | 22.1, 22.2, 21.9, plus the `app_version` table drift; feature docs otherwise re-verified |
| 2 Dead code | `getReceiverInstallationId`, `fetchReactions`, `DriveItemReaction*`, `AuthState.user`, `accessToken`, `refreshToken`, `languageForLocale`, `LanguageHelper.isSupported`, `R2_ACCOUNT_ID`, `permissions`, `roles_permissions`, `drive_file_types`, `file_type_id` | 17.6, 18.10, 19.12, 21.7, 22.3, 22.4; all proven by repo-wide grep (the schema catalogs are referenced only by SQL test fixtures) |
| 3 Data layer | 76 schema files, RLS policies, triggers, functions, grants, `config.toml`, `.pgdelta-export.json`, SQL tests | 18.1, 18.2, 21.1–21.10; live RLS/FK state unverified |
| 4 Backend services | `features/auth`, `media`, `notifications`, `partnership`, `user`; `middleware/**`; `config/**`; `core/**`; `utils/**`; `services/**`; routes | 17.1–17.4, 18.1–18.10, 19.1–19.9; route table and error codes checked on both sides |
| 5 Client state & UI | `features/auth`, `home`, `partnership`, `settings`, `drive`, `mood`, `games`, `bucket_list`; `core/**`; `shared/**` | 19.3–19.7, 19.10–19.12, 20.1–20.10; lifecycle, realtime and optimistic paths traced |
| 6 Cross-layer contracts | Flutter route/header/payload ↔ Express route/schema ↔ Postgres table/RPC | 17.1, 17.2, 17.3, 19.8, 21.4; signed-route table and response codes re-checked |
| 7 Tests & tooling | Jest suites, Flutter tests, SQL assertions, test helpers | The green baseline did not cover any finding; 23.1–23.4 added |
| 8 Triage | All sub-agent scope reports | 52 items after merging duplicates (media resolver, fingerprint, trackSession, lockout, retention, invite case, docs drift, logout state); 20 suspicions separated |

### Cross-agent merges

- **Media resolver** — Flutter drive agent + backend features agent + this re-verification → 17.2.
- **Device fingerprint** — Flutter core + backend features + backend middleware → 17.1.
- **`trackSession` fail-open** — backend features + backend middleware → 19.1.
- **Login lockout** — backend features + backend middleware → 19.2.
- **Log retention** — backend middleware + Supabase → 18.2.
- **Invite case sensitivity** — backend features + Supabase → 19.8.
- **Docs drift** — docs agent + backend features + Supabase → 22.1/22.2/21.9.

---

**Tracking:** `todo.md`, Phases 17–23. This document records evidence only; status lives in `todo.md` and, once closed, in `docs/fixing-phase-log.md`.

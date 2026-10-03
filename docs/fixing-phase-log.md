# Fixing Phase Log

**What this is**: the permanent record of the closed fixing work on `dev` — every item, the decisions of record and the tests added. Nothing open is tracked here (that lives in `todo.md`).

**Relationship to `todo.md`**: `todo.md` is the *live worklist* (untracked, never committed, see `.agents/skills/fix-workflow/SKILL.md`). This file is the *closed history*: what was found, what was decided, and where the reasoning now lives. When `todo.md` is retired, this file plus `git log` are what remain.

**How it was produced**: a layered scan of the codebase (docs-vs-code drift, dead code, RLS/data layer, backend services, client state, cross-layer contracts, test gaps) that produced one item per independently-fixable defect, each with `file:line` evidence, a concrete fix and an observable acceptance criterion. Items were fixed one at a time, each with its own commit.

---

## Outcome by phase

| Phase | Theme | Items | Outcome |
| :--- | :--- | :--- | :--- |
| 1 | Auth & session integrity | 1.1–1.6 | All fixed. Session ownership consolidated on the Supabase SDK; the backend refresh proxy was deleted |
| 2 | Security: RLS + backend | 2.1–2.4, 2.6, 2.8 | All fixed. Policies tightened with explicit `WITH CHECK`; Turnstile moved to Supabase Auth Managed mode; server origins made configurable |
| 3 | Feature-blocking bugs | 3.1–3.10 | All fixed. Change-password, forgot-password, app-update flow, miss-you debounce, camera picker, profile editing, account wipe (R2 orphan) |
| 4 | Sync, caching & realtime | 4.1–4.11 | All fixed. Lossless realtime buffers, `updated_at` triggers, deletion detection, per-partnership namespacing, epoch-gated clears |
| 5 | Data retention & media leaks | 5.1–5.6 | 5 fixed, 5.4 closed as *not a defect* (the 15 MB pre-compression cap is intended). R2 orphan sweep, thumbnails, audio/PDF |
| 6 | Design system, navigation, theming | 6.1–6.8 | All fixed. Tokenized theme, DS adoption, single routing strategy, notification taps, theme persistence, light theme |
| 7 | Dead code & docs hygiene | 7.1–7.9 | All fixed. 7.7 closed as *already clean* (stale item). README rebuilt against the code |
| 8 | Testing gaps | 8.1–8.7, 8.9, 8.10 | 9 fixed. Still open — 8.8 CI wiring, carried in `todo.md`. Auth-refresh retry, runnable SQL assertions for RLS and retention, `BaseState` helpers, the realtime pipeline, optimistic rollback, the force-update flow, and two suite-hardening sweeps |

---

## Item index

`Outcome`: **Fixed** = code changed · **Clean** = the item was stale, nothing to do · **By design** = not a defect.

| ID | Item | Outcome | Date |
| :--- | :--- | :--- | :--- |
| 1.1 | Token refresh desync — retry carries the stale token | Fixed (`refreshSession()` + `tokenRefreshed` listener) | 2026-09-17 |
| 1.2 | Request-binding secret: silent failure + no recovery | Fixed (recovery attempt, fail-closed, `LOCAL-BINDING-001`) | 2026-09-17 |
| 1.3 | Session expiry leaves the user on a stale screen | Fixed (`401` → reauth dialog → `/login`) | 2026-09-17 |
| 1.4 | Reauth dialog fires on ordinary login failures | Fixed (`authFailCred` for credential errors) | 2026-09-17 |
| 1.5 | Access-token lifetime policy mismatch | Fixed (1 h cap, fail-fast env, `.env.example` = 3600) | 2026-09-17 |
| 1.6 | Dual token-refresh race | Fixed (SDK is the single source of truth; `/auth/refresh` retired) | 2026-09-17 |
| 2.1 | RLS: user enumeration & global profile leakage | Fixed | 2026-09-17 |
| 2.2 | RLS: unaccepted partnerships grant data access | Fixed (accepted-only scope) | 2026-09-17 |
| 2.3 | RLS: missing explicit `WITH CHECK` on shared-table policies | Fixed | 2026-09-17 |
| 2.8 | `WITH CHECK` sweep on the remaining write policies | Fixed | 2026-09-17 |
| 2.4 | Turnstile verification is dead code | Fixed (Managed mode via Supabase Auth; service + keys deleted) | 2026-09-17 |
| 2.6 | Server origins hardcoded in the client | Fixed (`--dart-define` overrides) | 2026-09-18 |
| 3.1 | `ChangePasswordScreen` is a pure UI stub | Fixed (re-auth → `updateUser`) | 2026-09-18 |
| 3.2 | App update / APK flow half-wired | Fixed | 2026-09-18 |
| 3.3 | Miss-you button lacks tap debounce | Fixed | 2026-09-18 |
| 3.4 | Game question status update depends on the client | Fixed | 2026-09-18 |
| 3.5 | Forgot-password button is a no-op | Fixed (reset flow) | 2026-09-18 |
| 3.6 | Register → auto-login branch unreachable | Fixed | 2026-09-19 |
| 3.7 | Profile photo picker has no camera option | Fixed | 2026-09-19 |
| 3.8 | Display name & bio editing have no UI | Fixed | 2026-09-19 |
| 3.9 | Mood: dead analytics button + unused `note` field | Fixed | 2026-09-19 |
| 3.10 | Account wipe incomplete (R2 orphan) | Fixed | 2026-09-18 |
| 4.1 | F-RT1 — game debounce drops intermediate events | Fixed (lossless buffer) | 2026-09-20 |
| 4.2 | F-RT2 — mood debounce keeps only last `changedUserId` | Fixed (lossless buffer) | 2026-09-20 |
| 4.3 | Checkpoint update-blindness (game answers, bucket toggle) | Fixed (`updated_at` triggers) | 2026-09-22 |
| 4.4 | Drive deletions invisible to incremental sync | Fixed (`drive_change_probe` revalidation) | 2026-09-22 |
| 4.5 | Cross-partnership checkpoint contamination | Fixed (per-partnership namespacing) | 2026-09-22 |
| 4.6 | Logout wipes the persisted language preference | Fixed (preference survives) | 2026-09-22 |
| 4.7 | Wipe does not clear checkpoints nor media file cache | Fixed | 2026-09-22 |
| 4.8 | Concurrency bugs in cache writes / optimistic rollback | Fixed (serialized writes, full rollback) | 2026-09-22 |
| 4.9 | Feature states not cleared on logout | Fixed (`onClearFeatureStates` hook) | 2026-09-23 |
| 4.10 | Checkpoint writes race logout/wipe clears | Fixed (epoch gating) | 2026-09-23 |
| 4.11 | Realtime follow-ons (F-RT3…F-RT10) | Fixed (idempotency keys, version guards, dedup keys) | 2026-09-20 → 09-23 |
| 5.1 | Log retention conflict (Postgres 30 d vs Node 90 d) | Fixed (aligned to 90 d) | 2026-09-23 |
| 5.2 | R2 orphan on drive-item deletion | Fixed (delete + orphan sweep job) | 2026-09-23 |
| 5.3 | R2 orphan on failed upload completion | Fixed (swept by the 5.2 job) | 2026-09-23 |
| 5.4 | Pre-compression 15 MB fast-fail | **By design** — the cap is intentional | 2026-09-24 |
| 5.5 | Missing thumbnail / video-poster generation | Fixed (client-side image thumbnails) | 2026-09-24 |
| 5.6 | Audio/PDF uploads unreachable from UI | Fixed (pickers exposed) | 2026-09-24 |
| 6.1 | Homepage bypasses the design system | Fixed | 2026-09-24 |
| 6.2 | Design system — components | Fixed (catalog + usage map) | 2026-09-24 |
| 6.3 | Design system — theme and styling | Fixed (token files) | 2026-09-25 |
| 6.4 | Design system — global state and UX | Fixed (single snackbar/dialog) | 2026-09-26 |
| 6.5 | Design system — light theme | Fixed (palette + selector) | 2026-09-26 |
| 6.6 | Navigation — routing and navigation structure | Fixed (single `onGenerateRoute` strategy) | 2026-09-28 |
| 6.7 | Navigation — notifications, realtime events, auth flow | Fixed (notification taps, runtime unpair, post-auth routing) | 2026-09-28 |
| 6.8 | Theme persistence | Fixed (mode survives restart + logout) | 2026-09-26 |
| 7.1 | Remove unused `multer` dependency | Fixed (`npm uninstall`, 11 packages) | 2026-09-28 |
| 7.2 | Fix stale README | Fixed (rebuilt against the code; Ollama → OpenRouter) | 2026-09-28 |
| 7.3 | Remove dead query extensions | Fixed (`maybeGt`, `toSingle`) | 2026-09-28 |
| 7.4 | `can_send_email` capability | Fixed (grant removed; no mailer exists) | 2026-09-28 |
| 7.5 | Dead storage keys | Fixed (`profile_pic_version` given its missing consumer; `_keyDriveThumbCache` deleted) | 2026-09-28 |
| 7.6 | Remove dead `_missYouRefreshTimer` | Fixed (during the realtime refactor) | 2026-09-20 |
| 7.7 | Remove dead mood `note` property | **Clean** — no such property existed; stale item | 2026-09-28 |
| 7.8 | Clean up dead navigation | Fixed (shadowed fields removed from `GameState`) | 2026-09-28 |
| 7.9 | `HomepageState._isLoading` never used | Fixed (it was the debounce guard, shadowing `BaseState`) | 2026-09-28 |
| 8.1 | Auth refresh-retry flow untested | Fixed (real `401` rotation, fail-closed signed calls) | 2026-09-29 → 09-30 |
| 8.2 | RLS policies asserted by nothing | Fixed (SQL suites, superuser pre-flight) | 2026-10-03 |
| 8.3 | `BaseState` helpers and `hasChanges` untested | Fixed (mutation-verified unit suite) | 2026-10-03 |
| 8.4 | Realtime pipeline and two handlers untested | Fixed (pipeline plus per-handler suites) | 2026-10-03 |
| 8.5 | Optimistic rollback and cache-write ordering untested | Fixed (full rollback, `CacheWriteQueue`, both flush triggers) | 2026-10-03 |
| 8.6 | Version and force-update flow untested | Fixed (injectable `VersionRepository` seam) | 2026-10-03 |
| 8.7 | `cleanup_old_logs(p_days)` boundary unasserted | Fixed (parameterized and default-90 sweeps) | 2026-09-30 |
| 8.9 | Test-suite hardening sweep (Flutter + Backend) | Fixed (non-vacuous scans, shared mocks, tracked `scripts/`) | 2026-09-30 |
| 8.10 | Backend suite could pass for the wrong reasons | Fixed (`resetRateLimitState()`, tracked `.env.test`) | 2026-10-01 |

---

## Decisions of record

Non-obvious choices that were made during the phase. Each one now lives in its owning doc; do not "fix" them back without reading the doc.

1. **The Supabase SDK owns the session.** The client refreshes via `auth.refreshSession()`; the Node backend exposes no refresh endpoint (the `POST /api/v1/auth/refresh` proxy was deleted in 1.6). gotrue serializes concurrent refreshes per refresh token, so the 401-retry path and the SDK's auto-refresh spend the one-time token once. → `docs/features/authentication/session-token-security/doc.md` § Refresh Flow.
2. **The token-lifetime cap is a drift guard, not a policy.** `MAX_ACCESS_TOKEN_LIFETIME_SEC` has no default and fails fast at startup; it must be ≥ the Supabase Auth JWT expiry (both 3600 today). → same doc, § Token Lifetime & Policy Enforcement.
3. **Turnstile runs in Managed mode in the app and is validated by Supabase Auth.** The single-use `captchaToken` cannot also be consumed by the backend, so no backend verification exists by design; the backend only does risk assessment (strikes / IP / device locks). → `docs/features/authentication/login-registration/doc.md` § Turnstile.
4. **Partnership-scoped cache keys are an invariant.** Feature caches are `base:<partnership_id>`, checkpoints `chk_x:<partnership_id>`; a partnership transition purges base/old/new scopes. Depends on `partnerships.id` never being reused. → `docs/app/storage-and-caching/doc.md` § Cross-partnership checkpoint namespacing.
5. **Checkpoint writes are epoch-gated.** A checkpoint computed by a fetch is discarded if a `clear()` (logout, wipe, partnership switch) landed while the fetch was in flight, so a stale snapshot cannot resurrect purged data. → same doc, § How checkpoints work.
6. **Theme and language preferences deliberately survive logout and wipe.** They are user preferences, not account data. → `docs/features/authentication/account-lifecycle/doc.md` § Local Storage Cleanup, `docs/app/theming/doc.md`.
7. **The 15 MB upload cap is a pre-compression hard limit, by design.** It rejects large *source* files before compression; it is not a bug. → `docs/features/shared-drive/doc.md` § 15 MB Size Limit.
8. **Profile photos are cache-versioned.** Uploads bump `profile_pic_version`; reads go through `ApiService.versionedMediaUrl(url, version)` and the superseded file is evicted from `MediaCacheManager`. Partner avatars stay unversioned. → `docs/app/storage-and-caching/doc.md`, `docs/features/profile-settings/doc.md`.
9. **One signing secret, recovered on demand.** A signed request with no `request_binding_secret` triggers one deduplicated `/auth/session-sync` retry (30 s cooldown) and otherwise fails closed — a signed call is never sent unsigned. → `docs/features/authentication/session-token-security/doc.md` § Binding Secret & HMAC Request Signing.
10. **A force update is mandatory whatever the local build.** `mandatory = forceUpdate || localBuild < minBuild`, so `forceUpdate` alone blocks dismissal even above `minBuild`. Non-dismissibility needs **both** `barrierDismissible: false` and `PopScope(canPop: false)`: a barrier tap pops through `Navigator.maybePop`, which `PopScope` also blocks, so either flag alone lets the other regress unnoticed. → `docs/features/miss-you/doc.md` § Force Update Dialog Behavior.
11. **Change detection is cursor-based, not payload-diff-based.** No client-side field comparison exists; the tested contract is that an unchanged server timestamp costs zero fetches and zero checkpoint writes. A "payload with no changed field produces no refetch" guarantee does not exist and must not be reintroduced. → `docs/app/storage-and-caching/doc.md` § Tests.
12. **Source-scan tests must fail loudly, never vacuously.** A scan that resolves no files, or accepts a fallback constant when a lookup misses, reports success over nothing; the scan-based tests share `test_helpers/source_scan.dart`, which resolves `lib/` at runtime, throws on an empty file list and strips comments. → `docs/app/architecture/doc.md` § Tests.

---

## Tests added during the phase

| Test | Item |
| :--- | :--- |
| `Flutter/test/bucket_realtime_race_test.dart` | 4.3 |
| `Flutter/test/drive_sync_test.dart` | 4.4 |
| `Flutter/test/partnership_scope_test.dart` | 4.5 |
| `Flutter/test/missyou_idempotent_test.dart` | 4.11 |
| `Flutter/test/mark_seen_realtime_test.dart` | 4.11 |
| `Flutter/test/profile_state_test.dart` | 7.5 |
| `supabase/test/rls_user_isolation.test.sql` | 8.2 |
| `supabase/test/rls_accepted_partnership_only.test.sql` | 8.2 |
| `supabase/test/rls_self_scoped_with_check.test.sql` | 8.2 |
| `supabase/test/rls_shared_table_with_check.test.sql` | 8.2 |
| `supabase/test/rls_anon_blocked.test.sql` | 8.2 |
| `supabase/test/rls_policy_matrix.test.sql` | 8.2 |
| `supabase/test/rpc_execute_grants.test.sql` | 8.2 |
| `supabase/test/updated_at_triggers.test.sql` | 8.2 |
| `supabase/test/bucket_items_category_check.test.sql` | 8.2 |
| `supabase/test/retention_cleanup_old_logs.test.sql` | 8.2 |
| `Flutter/test/base_state_test.dart` | 8.3 |
| `Flutter/test/realtime_sync_service_test.dart` | 8.4 |
| `Flutter/test/bucket_realtime_handler_test.dart` | 8.4 |
| `Flutter/test/miss_you_realtime_handler_test.dart` | 8.4 |
| `Flutter/test/cache_write_queue_test.dart` | 8.5 |
| `Flutter/test/version_update_test.dart` | 8.6 |
| `Flutter/test/test_helpers/source_scan.dart` | 8.9 |
| `Flutter/test/test_helpers/mock_secure_storage.dart` | 8.9 |
| `Flutter/test/test_helpers/settle_helpers.dart` | 8.9 |
| `Backend/test/request-signing.test.js` | 8.10 |
| `Backend/test/crypto-utils.test.js` | 8.10 |
| `Backend/test/token-utils.test.js` | 8.10 |
| `Backend/test/ai-utils.test.js` | 8.10 |
| `Backend/test/api-routing.test.js` | 8.10 |
| `Backend/test/authorization.test.js` | 8.10 |
| `Backend/test/setupEnv.js` | 8.10 |
| `Backend/test/support/mockSupabase.js` | 8.10 |

---
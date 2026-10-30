# Fixing Phase Log

**What this is**: the permanent record of the closed fixing work on `dev` — every item and the decisions of record. Nothing open is tracked here (that lives in `todo.md`).

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
| 9 | Findings that were never planned | 9.1–9.9 | All fixed. Failed-login reporting plus route idempotency, token and session revocation on logout and password change, server-side password policy, a distinct-email risk cap, a docs reconciliation sweep, and the `user_devices` retention and session-linked prune |
| 10 | Verified defects found in the docs sweep | 10.1–10.5, 10.8–10.21 | 18 fixed, 10.17 closed as *not a defect* (the `debug_` prefix is deliberate). Fingerprint survives logout, media cache cleared on logout, per-process state documented for a single-instance deployment, nonce replay closed by the database `UNIQUE` constraint, log area-split and record fixes, an FCM-less login registers no push identifier, an inclusive drive cursor, a `partnership_reject` RPC, machine-readable RPC error codes, and log records projected onto their table columns |
| 11 | Security & privilege | 11.1–11.13 | All fixed. No client INSERT policy on `partnerships`; immutable membership and identity columns; `DELETE` limited to pending rows; `anon`/`PUBLIC` EXECUTE revoked and ACLs pinned in each function file; notification receivers resolved from the partnership; a DB-authoritative nonce check; server-side session-expiry validation; a signed-route boundary pinned by a route-table test; and an invite-recipient guard |
| 12 | Data integrity, media & routing | 12.1–12.7 | All fixed. Backend migrated to the real `drive_items` contract; the R2 orphan sweep guarded per source; the debug wipe scoped to the accepted couple; named routes resolved by an explicit table; the mood checkpoint taken from the server; the dead `pending_received` path deleted; and cancellation acceptance keyed by profile id |

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
| 8.7 | `logs_cleanup(p_days)` boundary unasserted | Fixed (parameterized and default-90 sweeps) | 2026-09-30 |
| 8.9 | Test-suite hardening sweep (Flutter + Backend) | Fixed (non-vacuous scans, shared mocks, tracked `scripts/`) | 2026-09-30 |
| 8.10 | Backend suite could pass for the wrong reasons | Fixed (`resetRateLimitState()`, tracked `.env.test`) | 2026-10-01 |
| 9.1 | Failed logins are never reported — strikes inert | Fixed (best-effort report from `login()`, idempotent route) | 2026-10-04 |
| 9.2 | Device tokens are never revoked on logout | Fixed (hard row delete via `device-token-revoke`) | 2026-10-04 |
| 9.3 | Password change leaves other sessions valid | Fixed (`signOut(scope: others)`) | 2026-10-04 |
| 9.4 | Password complexity enforced only on the client | Fixed (GoTrue policy aligned in `config.toml`) | 2026-10-09 |
| 9.5 | Risk-check endpoints are unsigned | Fixed (design kept; distinct-email IP cap added) | 2026-10-09 |
| 9.6 | Documentation reconciliation sweep | Fixed (stale status rows and findings corrected) | 2026-10-09 |
| 9.7 | Stale `user_devices` rows survive a failed revoke | Fixed (30-day retention sweep) | 2026-10-09 |
| 9.8 | Push rows of password-revoked sessions survive | Fixed (`device-token-revoke-all` on password change) | 2026-10-10 |
| 9.9 | Failed-logout `user_devices` rows linger 30 days | Fixed (session-linked prune RPC) | 2026-10-10 |
| 10.1 | Logout destroys the device fingerprint | Fixed (preserved in `clearAll()`) | 2026-10-10 |
| 10.2 | Media file cache is not cleared on logout | Fixed (`emptyAppMediaCaches()` in logout) | 2026-10-10 |
| 10.3 | Rate limiting and strike bans live in process memory | Fixed (single-instance constraint documented) | 2026-10-11 |
| 10.4 | Login strikes never accumulate across instances | Fixed (per-instance constraint documented) | 2026-10-11 |
| 10.5 | Idempotency cache is per-process | Fixed (per-instance guarantee documented) | 2026-10-11 |
| 10.8 | Nonce store can accept a nonce on two instances | Fixed (atomic DB reservation; superseded by 11.9) | 2026-10-11 |
| 10.9 | `logAppError` splits error codes on the wrong separator | Fixed (`split("-")`) | 2026-10-11 |
| 10.10 | Non-production responses expose `details` and `stack` | Fixed (explicit `ENABLE_ERROR_DETAILS` flag) | 2026-10-12 |
| 10.11 | Invalid-token cleanup deletes rows globally | Fixed (`user_id`-scoped delete) | 2026-10-12 |
| 10.12 | `login()` registers the FCM token without the `supportsFcm` guard | Fixed (one shared registration helper; later replaced by installation IDs) | 2026-10-12 |
| 10.13 | The optimistic rejection filter can never match | Fixed (via 12.6 — the dead path was deleted) | 2026-10-12 |
| 10.14 | `ProfileState.loadProfile()` returns before reading the cache when loading | Fixed (in-flight load coalescing) | 2026-10-12 |
| 10.16 | No backend mailer: an invitation sends no email | Fixed (docs clarification; no code change) | 2026-10-12 |
| 10.15 | The drive cursor is a strict `>`, skipping equal timestamps | Fixed (inclusive `gte` bound) | 2026-10-14 |
| 10.17 | The `debug_`-prefixed wipe RPC is deliberate dev-only tooling | **By design** — the prefix names a debug tool, not a production RPC | 2026-10-14 |
| 10.18 | RPC exception messages are hardcoded Italian | Fixed (`API-VALIDATION-00x` codes resolved client-side) | 2026-10-14 |
| 10.19 | Rejecting a partnership request bypasses the accepting RPC | Fixed (`partnership_reject` RPC) | 2026-10-20 |
| 10.20 | A `hasChanges` failure rejects `loadWithChangeDetection` (F-SM4) | Fixed (error caught; refetch triggered) | 2026-10-20 |
| 10.21 | Structured log records don't match the log-table columns | Fixed (records projected onto their table's columns) | 2026-10-21 |
| 11.9 | `consumeNonce` discards the database's uniqueness result | Fixed (DB-first nonce check; `23505` is a replay) | 2026-10-11 |
| 11.1 | An accepted partnership can be forged with a single INSERT | Fixed (no INSERT policy; per-command policies plus a status guard) | 2026-10-21 |
| 11.2 | An accepted partnership can be re-pointed to a third party | Fixed (membership columns immutable via trigger) | 2026-10-22 |
| 11.3 | Either member can DELETE the couple's shared history | Fixed (`DELETE` restricted to pending rows) | 2026-10-23 |
| 11.4 | `users_update_self` does not pin `auth_id` or `email` | Fixed (identity columns pinned by a trigger) | 2026-10-28 |
| 11.5 | `anon` / `PUBLIC` hold EXECUTE on four partner-revealing functions | Fixed (`anon`/`PUBLIC` EXECUTE revoked) | 2026-10-28 |
| 11.6 | `debug_wipe_user_data` effective ACL is order-dependent | Fixed (ACL pinned in the function file) | 2026-10-28 |
| 11.7 | `override_sender_id` forges a pending invite attributed to a victim | Fixed (via 11.1 — the EXECUTE grant that enabled the forgery was revoked) | 2026-10-28 |
| 11.8 | Unpaired senders bypass the notification receiver check | Fixed (fail closed; receiver resolved from the partnership) | 2026-10-28 |
| 11.10 | Server-side session expiry is never checked | Fixed (`session_is_live` checked server-side) | 2026-10-28 |
| 11.11 | `notify.routes.js` has an unreachable route and a shared rate-limit bucket | Fixed (dead route deleted; `limited()` stays before `validated()`) | 2026-10-28 |
| 11.12 | Three authenticated mutating routes are unsigned | Fixed (all three signed; signed-route table pinned by a test) | 2026-10-28 |
| 11.13 | A partnership request can be addressed to an already-paired user | Fixed (recipient guard; `API-VALIDATION-004` reused) | 2026-10-28 |
| 12.6 | Orphaned `PartnerState` rejection branch is dead code | Fixed (dead `pending_received` path deleted) | 2026-10-12 |
| 12.1 | The media data contract does not match the schema | Fixed (backend migrated to `name`/`partnership_id`) | 2026-10-29 |
| 12.2 | The R2 orphan sweep throws on every run | Fixed (per-source guard; aborts before deletion) | 2026-10-29 |
| 12.3 | The wipe destroys the partner's data and keeps the row | Fixed (`debug_wipe_couple_data` scoped to the accepted couple) | 2026-10-29 |
| 12.4 | Every named route resolves to `SplashScreen` | Fixed (explicit route table; unknown names return `null`) | 2026-10-29 |
| 12.5 | The mood checkpoint is written from the device clock | Fixed (`mood_set` returns the server-stamped row) | 2026-10-29 |
| 12.7 | Cancellation acceptance passes the auth UUID | Fixed (`req.user.profileId`; missing error codes added) | 2026-10-29 |

---

## Decisions of record

Non-obvious constraints that still bind the code. Each one now lives in its owning doc; do not "fix" them back without reading the doc.

1. **The Supabase SDK owns the session.** The client refreshes via `auth.refreshSession()`; the Node backend exposes no refresh endpoint (the `POST /api/v1/auth/refresh` proxy was deleted in 1.6). gotrue serializes concurrent refreshes per refresh token, so the 401-retry path and the SDK's auto-refresh spend the one-time token once. → `docs/features/authentication/session-token-security/doc.md` § Refresh Flow.
2. **The token-lifetime cap is a drift guard, not a policy.** `MAX_ACCESS_TOKEN_LIFETIME_SEC` has no default and fails fast at startup; it must be ≥ the Supabase Auth JWT expiry (both 3600 today). → same doc, § Token Lifetime & Policy Enforcement.
3. **Turnstile runs in Managed mode in the app and is validated by Supabase Auth.** The single-use `captchaToken` cannot also be consumed by the backend, so no backend verification exists by design; the backend only does risk assessment (strikes / IP / device locks). → `docs/features/authentication/login-registration/doc.md` § Turnstile.
4. **Partnership-scoped cache keys are an invariant.** Feature caches are `base:<partnership_id>`, checkpoints `chk_x:<partnership_id>`; a partnership transition purges base/old/new scopes. Depends on `partnerships.id` never being reused. → `docs/app/storage-and-caching/doc.md` § Cross-partnership checkpoint namespacing.
5. **Checkpoint writes are epoch-gated.** A checkpoint computed by a fetch is discarded if a `clear()` (logout, wipe, partnership switch) landed while the fetch was in flight, so a stale snapshot cannot resurrect purged data. → same doc, § How checkpoints work.
6. **Theme and language preferences deliberately survive logout and wipe.** They are user preferences, not account data. → `docs/features/authentication/account-lifecycle/doc.md` § Local Storage Cleanup, `docs/app/theming/doc.md`.
7. **The 15 MB upload cap is a pre-compression hard limit, by design.** It rejects large *source* files before compression; it is not a bug. → `docs/features/shared-drive/doc.md` § 15 MB Size Limit.
8. **Own profile photos are cache-versioned; partner avatars are not.** The locally stored `profile_pic_version` is the own avatar's cache key; the partner's avatar has no local version to key on. → `docs/app/storage-and-caching/doc.md`, `docs/features/profile-settings/doc.md`.
9. **One signing secret, recovered on demand.** A signed request with no `request_binding_secret` triggers one deduplicated `/auth/session-sync` retry (30 s cooldown) and otherwise fails closed — a signed call is never sent unsigned. → `docs/features/authentication/session-token-security/doc.md` § Binding Secret & HMAC Request Signing.
10. **A force update is mandatory whatever the local build.** `mandatory = forceUpdate || localBuild < minBuild`, so `forceUpdate` alone blocks dismissal even above `minBuild`. Non-dismissibility needs **both** `barrierDismissible: false` and `PopScope(canPop: false)`: a barrier tap pops through `Navigator.maybePop`, which `PopScope` also blocks, so either flag alone lets the other regress unnoticed. → `docs/features/miss-you/doc.md` § Force Update Dialog Behavior.
11. **Change detection is cursor-based, not payload-diff-based.** No client-side field comparison exists; the tested contract is that an unchanged server timestamp costs zero fetches and zero checkpoint writes. A "payload with no changed field produces no refetch" guarantee does not exist and must not be reintroduced. → `docs/app/storage-and-caching/doc.md` § Tests.
12. **Source-scan tests must fail loudly, never vacuously.** A scan that resolves no files, or accepts a fallback constant when a lookup misses, reports success over nothing; the scan-based tests share `test_helpers/source_scan.dart`, which resolves `lib/` at runtime, throws on an empty file list and strips comments. → `docs/app/architecture/doc.md` § Tests.
13. **A logged-out device token is deleted, not marked inactive.** `user_devices` has no revocation column and delivery reads every row for the user, so removing the row *is* the deactivation; the audit FKs to `user_devices(id)` are `ON DELETE SET NULL`, so the history survives. → `docs/features/authentication/account-lifecycle/doc.md` § Token Revocation.
14. **Only the current session survives a password change — `signOut(scope: others)`, never `global`.** `global` would also sign out the device that changed the password, and `others` fires no `signedOut` event, so the revoke cannot re-enter the logout teardown. → `docs/features/authentication/account-lifecycle/doc.md` § Other-Session Revocation.
15. **A password change also revokes every other device's push registration immediately.** The 30-day age sweep is a backstop only: the change exists to cut off a possibly-stolen device, so FCM must stop within the request, not 30 days later. → `docs/app/notifications/doc.md` § Backend other-device revocation.
16. **`user_devices.session_id` deliberately carries no foreign key.** An `auth.sessions` row is gone before the sweep runs, and an `ON DELETE SET NULL` FK would null the very pointer the prune reads; the session-linked prune runs as a `service_role` RPC instead. → `docs/features/authentication/account-lifecycle/doc.md` § Notification Cleanup.
17. **Password complexity is enforced by the native GoTrue config, not an Auth hook.** Same guarantee with no extra code to drift; the tracked `supabase/config.toml` records the intended policy and `config diff` is the guard, not the deployment mechanism. → `docs/features/authentication/login-registration/doc.md` § Password Validation.
18. **The device fingerprint is a device attribute and survives logout and wipe.** It is not user data; the backend strike key is `sha256(email)+sha256(deviceFingerprint)+ip`, so minting a new UUID per logout silently reset the lockout schedule. → `docs/app/storage-and-caching/doc.md` § Logout Behavior.
19. **No shared store (Redis/KeyDB): the backend is single-instance by design.** Rate-limit buckets, login strikes and idempotency keys are per process and cleared by a restart; the accepted exposure is documented per mechanism rather than fixed, and nonce replay is closed separately by the database `UNIQUE` constraint. → `docs/backend/security/doc.md` § Multi-Instance Vulnerability Analysis Matrix.
20. **Error diagnostics are gated on an explicit `ENABLE_ERROR_DETAILS` flag, not `NODE_ENV`.** The gate covers the message as well as `details`/`stack`, because a copied `err.message` carried the same disclosure class in any non-production container. → `docs/backend/error-handling/doc.md` § End-to-End Error Flow Map.
21. **Partner emails exist only for accounts that do not exist yet.** A pairing request (`POST /auth/invite`, email + 6-char code) never sends an email — the recipient must already have an account, so the request is delivered in-app plus push. The one partnership-related email is the Supabase Auth **"Invite user"** template, sent by `POST /auth/invite-user` (`admin.auth.admin.inviteUserByEmail`, signed + rate-limited 5/user, 10/IP), which is **account-only**: it writes no `partnerships` row, so pairing still needs the invitee's code afterwards. An address that already has an account gets `409 API-VALIDATION-002` (GoTrue `email_exists`/`user_already_exists`); an invited-but-unconfirmed address is re-invited. → `docs/features/partnership/doc.md` § Email Policy, `docs/audits/email.md`.
22. **A device that cannot produce a push identifier is never registered.** The platform guard and the schema check live in one shared registration path, so startup, login and locale sync cannot drift apart; a shared placeholder on the globally-unique registration column would re-point one device's push target between unrelated accounts. (The FCM token was later replaced by a Firebase Installation ID; the guard moved with it.) → `docs/app/notifications/doc.md` § Platform Support, § Installation ID Registration.
23. **A concurrent profile load joins the load already in flight.** `loadProfile()` hands the running load to a second caller instead of skipping it, and a forced caller chains a fresh load after it, so no caller is left with empty state. → `docs/app/architecture/doc.md` § State-scoped observations.
24. **The drive cursor is inclusive (`gte`), not strict.** The merge replaces rows by id, so re-fetching the boundary rows is idempotent, and the `updated_at` trigger writes `NOW()` (transaction start), which makes equal timestamps reachable. → `docs/app/storage-and-caching/doc.md` § Per-checkpoint analysis.
25. **The `debug_` prefix on the wipe RPC is deliberate.** The RPC is `service_role`-only and reachable only from the `kDebugMode` debug tile, so renaming it would advertise a debug-only tool as a production RPC; the developer-only scope is documented instead. → `docs/supabase/database-logic/doc.md` § `debug_wipe_couple_data(p_user_id integer)`.
26. **An RPC error travels as `CODE: text` and the client resolves it.** Every raise carries a stable app error code, the backend keeps the code and the client maps it through `ErrorCodes` to the ARB string; the Postgres text is a developer-facing note and never reaches a release UI. → `docs/app/localization/doc.md` § Alignment Audit & Findings.
27. **A failing change check means "assume changed and refetch".** The `hasChanges()` await is wrapped in `try`/`catch`; the error goes to `ErrorHandler.handle`, the fallback is `changed = true` and the network fetch still runs, so the caller's future never rejects. → `docs/app/state-management/doc.md` § loadWithChangeDetection.
28. **A log record is projected onto exactly the columns of its target table.** One extra key makes Postgres reject the whole row, so each logger function writes only its table's columns and nests the rest in `error_json`; `request_id` is a `uuid` column, so a client-supplied `X-Request-Id` is accepted only when it parses as a uuid. → `docs/backend/error-handling/doc.md` § Backend Logging Infrastructure & Supabase Tables.
29. **A `partnerships` row can never be created by a client.** There is no INSERT policy at all — not even a `status = 'pending'` one — so the backend calling `partnership_request` as `service_role` is the only creator and the table's `'accepted'` default is unreachable through PostgREST. → `docs/supabase/rls/doc.md` § Detailed Policy Categorization & Analysis (`partnerships`).
30. **Partnership membership is immutable on every row and for every caller.** The `partnership_guard_status` trigger rejects any change to `user_id_1` / `user_id_2` instead of carving out an accepted-only or service-role path, because no flow legitimately writes those columns; the unconditional rule is smaller and stronger than a conditional one. → `docs/supabase/rls/doc.md` § Detailed Policy Categorization & Analysis (`partnerships`).
31. **A member may delete only a `pending` partnership row.** The `DELETE` policy carries `status = 'pending'`, so neither member can cascade away the couple's shared history; withdrawing a request stays available to either member. → `docs/supabase/rls/doc.md` § Detailed Policy Categorization & Analysis (`partnerships`).
32. **Identity columns are pinned by a trigger, not a `WITH CHECK`.** A policy cannot read the old row (and a same-table subquery recurses), so `users_guard_identity` rejects client changes to `auth_id` / `email` while `postgres` / `service_role` keep the provisioning and verified-flow path. → `docs/supabase/schema/doc.md` § Database Triggers & Automation.
33. **Every function pins its own ACL in its schema file.** `default_privileges.sql` grants `anon` EXECUTE to functions `postgres` creates after it takes effect, and `REVOKE … FROM PUBLIC` does not remove that named grant, so each function file must revoke `PUBLIC` and `anon` explicitly; apply order is not a security control. → `docs/supabase/database-logic/doc.md` § Non-Obvious Database-Side Behaviors.
34. **`override_sender_id` stays as a backend-only parameter.** The forgery needed client EXECUTE, which 11.1 revoked; the backend supplies the sender from the JWT-verified profile, so removing the parameter would either reopen client execution or duplicate the RPC's validation in Node. → `docs/features/partnership/doc.md` § Security & Authorization Boundaries.
35. **A notification receiver comes from the partnership, never from the body.** A sender without an accepted partner fails closed with `AUTH_FAIL_004` instead of having a body `receiverId` honoured, which closes the partnerless spam / wake-up primitive. → `docs/app/notifications/doc.md` § Backend Dispatch.
36. **The database insert is the authoritative nonce check.** `consumeNonce` inserts into `request_nonces` before writing the in-memory map and treats `23505` as a replay; the map is only a cache of nonces this process has already accepted. → `docs/backend/security/doc.md` § 3. Nonce Store & Replay Prevention.
37. **The `session_is_live` check fails open on an RPC error.** GoTrue already rejects a deleted session and enforces `not_after` at refresh, so the database check is defence in depth; a database outage must not take authentication down. → `docs/backend/security/doc.md` § 4. JWT Verification & Session Binding.
38. **The limiter runs before validation on purpose.** Malformed requests still consume a rate-limit slot, so a typo flood is throttled instead of free; the unreachable `/notify/:type` route was deleted rather than reordered because no client calls it. → `docs/backend/api-architecture/doc.md` § 3. Push Notification Endpoints.
39. **All authenticated mutations are signed, and the boundary is a test.** `/users/wipe`, `/notify/partner` and `/auth/invite` carry `signed(...)` and the client sets `requireSignature: true`; a wipe sends an explicit `{}` because the client hashes the empty string while `express.json()` hands the server `{}`. `signing-boundary.test.js` walks the router so a new route cannot silently join the wrong set. → `docs/backend/security/doc.md` § 1. HMAC-SHA256 Request Signing.
40. **Several `pending` invitations to one recipient are allowed; an `accepted` or `cancelled` row blocks a new request.** Receiving multiple invitations is legitimate, while a recipient who already holds an `accepted` or `cancelled` row could never accept another. → `docs/features/partnership/doc.md` § Transition & Invariant Rules (Recipient Availability).
41. **The debug wipe is per-couple, not per-user.** `debug_wipe_couple_data(p_user_id)` resolves the caller's `accepted` partnership, deletes the couple's shared rows and both members' user-scoped rows, and keeps the `partnerships` row so the debug pair stays connected ("Reset everything except account"). A caller with no accepted partnership clears only their own user-scoped rows; `pending`/`cancelled` rows are not a couple and are left untouched. The `debug_` prefix is still deliberate (decision 25). → `docs/features/profile-settings/doc.md` § Edge Cases, `docs/supabase/database-logic/doc.md` § `debug_wipe_couple_data(p_user_id integer)`.
42. **The mood timestamp and checkpoint come from the server, never the device clock.** `mood_set` returns the inserted `public.moods` row and the client reads `created_at` from it; the `kMoods` checkpoint is the newest `created_at` actually returned. The optimistic entry keeps the previous server timestamp until the response arrives, so an in-flight checkpoint write cannot ingest a future device value, and `_updateMoodsCheckpoint` logs and resets a stored checkpoint that is ahead of the newest returned row (legacy device-clock checkpoints). The guard only runs on a fetch: a legacy future checkpoint can still suppress a cold-start fetch until an update or realtime event triggers one. → `docs/features/mood/doc.md` § Timestamps & Ordering, `docs/supabase/database-logic/doc.md` § `mood_set(p_emoji_char text)`.
43. **The cancellation-accept endpoint identifies the actor by internal profile id, not the auth UUID.** `partnerships.user_id_1`/`user_id_2` and `partnership_cancel_accept(p_actor_id integer)` use `users.id`, so the controller must pass `req.user.profileId`; the Supabase UUID in `req.user.id` belongs only to auth/session concerns. → `docs/backend/api-architecture/doc.md` § `POST /api/v1/partnership/cancel/accept`, `docs/features/partnership/doc.md` § Acceptance.
44. **The backend was migrated to the `drive_items` schema, not the schema to the backend.** `name` (R2 key) and `partnership_id` already back `v_drive_dashboard` and the Flutter model, so adding `filename` / `user_id` / `partner_id` columns would duplicate state and require a data migration. → `docs/features/shared-drive/doc.md` § Architecture & Component Mapping.
45. **An R2 orphan-sweep read failure aborts the run before any deletion.** Treating an unread key source as empty would mark live objects as orphans; the sweep logs `retention.r2_orphan.failed` per source and skips the delete pass instead. → `docs/backend/infrastructure/doc.md` § Background Maintenance & Retention Jobs.

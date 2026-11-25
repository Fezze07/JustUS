# JustUS — Pre-First-Couple Readiness Audit

**Audit date:** 2026-11-24
**Branch:** `dev`
**Scope:** Current repository state, changes since the 2026-11-04 full-stack audit, validation tooling, Android release configuration, and read-only metadata/advisor checks on the linked Supabase project.

No application code or database objects were changed. Supabase access in this audit used read-only catalog queries and advisors only. The three attempted explore agents failed before starting (`400 The requested model is not supported`), so the review and evidence collection were completed directly. The existing worklist in `todo.md` remains the single source of status; this report records current behavior and new evidence only.

## Executive Summary

The unit/static suites that could run passed: Flutter analysis and all 439 Flutter tests; backend lint and all 305 Jest tests; backend syntax and circular-dependency checks. The repository-wide `npm run validate` command did not start because this Windows PowerShell environment has no `bash`. SQL tests were not run locally because neither Bash nor `psql` is installed. A local Android debug build did not complete with JDK 26; the supported JDK 21 build and a signed production artifact remain unverified.

The linked Supabase project has RLS enabled on all 26 public tables, and the live `users.auth_id` cascade and cancellation cooldown/expiry trigger rules match the recorded fixes. The live partnership trigger still lacks the separate one-accepted-partnership guard already tracked as 21.3. Supabase advisors also report leaked-password protection disabled and an unindexed partnership cancellation foreign key.

**Readiness decision: do not invite the first real couple yet.** First close the release-signing and leaked-password-protection items, make the full test suite an enforced CI gate, and complete the staged two-account/provider/device checks in Phase 0 of `todo.md`. The game-question race is a confirmed medium-priority correctness issue.

## Phase 0 — Ground Truth

### Component map

| Component | Entry point / configuration | Public surface and principal contracts |
| :--- | :--- | :--- |
| Flutter client | `Flutter/lib/main.dart`; `Flutter/pubspec.yaml`; `.env` loaded at startup | Supabase Auth/PostgREST/Realtime plus the backend origin selected by `ApiConfig` (`JUSTUS_DEV_SERVER_ORIGIN` / `JUSTUS_PROD_SERVER_ORIGIN`) |
| Node backend | `Backend/index.js` → `Backend/app.js`; env selection in `Backend/config/loadEnv.js`; root `.env.example` | `/api/v1` routes for auth/session, media, notifications, app version, user wipe and partnership cancellation; `/auth` callback/invite pages |
| Supabase | `supabase/config.toml`; declarative SQL under `supabase/schemas/**` | Public tables/RPCs exposed to the Flutter client under RLS; backend uses privileged operations for server-side workflows |
| External services | R2, Resend, Firebase/FCM, hosted Supabase Auth | Media object lifecycle, invite email delivery, push notifications, user identity and database |
| CI | `.github/workflows/codeql.yml` | CodeQL analysis and a Flutter debug APK build; no backend/Flutter/SQL test job is configured |

The Flutter route constants match the backend's mounted feature routes for the audited auth, media, notification, user, partnership and app-version surfaces. The newly added `game_pick_question(integer, text[])` RPC exists in the linked database and is callable by `authenticated`; it is `SECURITY INVOKER`.

### Client/API and data contracts

| Client surface | Client route → backend mount |
| :--- | :--- |
| Authentication/session | `/api/v1/auth/installation-id`, `/installation-id-revoke`, `/installation-id-revoke-all`, `/login-risk-check`, `/login-attempt`, `/session-bind`, `/invite`, `/invite-user` → `/api/v1/auth` |
| Media | `/api/v1/media/upload-url`, `/complete`, `/file`, `/delete` → `/api/v1/media` |
| Notifications | `/api/v1/notify/partner` → `/api/v1/notify` |
| Partnership | `/api/v1/partnership/cancel/accept` → `/api/v1/partnership` |
| User/version | `/api/v1/users/wipe`, `/api/v1/app-version` → `/api/v1/users`, `/api/v1/app-version` |
| Browser auth callbacks | `/auth/callback`; backend also mounts `/auth/invite` and `/auth/invite-callback` |

Flutter also uses Supabase directly for Auth, RLS-protected PostgREST, Realtime and RPC. The audited game-create path reads `game_question_bank` through `game_pick_question`, then inserts into `game_questions`; membership is checked by the RPC, and table RLS is enabled. Partnership cancellation reads/writes `public.partnerships`, with `partnership_guard_status()` enforcing the live cooldown/expiry transitions. Backend env values load from the repository-root env file; Flutter server origins come from `ApiConfig` compile-time defines, while its `.env` is a packaged client configuration asset.

### Test entry points and observed results

| Check | Command / result |
| :--- | :--- |
| Flutter static analysis | `cd Flutter; flutter analyze` — clean |
| Flutter tests | `cd Flutter; flutter test` — 439 passed |
| Backend lint + Jest | `cd Backend; npm test` — 27 suites, 305 tests passed; 0 lint errors, 4 warnings |
| Backend syntax | `cd Backend; npm run check` — passed |
| Circular dependencies | `cd Backend; npm run madge:circular` — no cycles |
| Duplication | `npm run scan:duplicates` — exit 0; jscpd reported clones |
| Unified validation | `npm run validate` — failed before any check: `bash` is not recognized in PowerShell |
| Supabase SQL tests | Not run locally: no Bash or `psql`; not run against the hosted project because the scripts use fixed test fixtures |
| Android debug build | `flutter build apk --debug` failed during JDK image transformation under installed JDK 26; `:app:compileFlutterBuildDebug` succeeded when invoked directly. No JDK 21 was available for a supported-toolchain retry. |

### Contracts, environment and unverifiable surfaces

- Backend env files are resolved from the repository root by `Backend/config/loadEnv.js`: `.env` normally, `.env.test` for test mode, or `JUSTUS_ENV_FILE` when exported in the process.
- The Flutter client selects development or production backend origins by build mode and permits `--dart-define` overrides. Its `.env` is a packaged asset and is not committed.
- `supabase/config.toml` targets PostgreSQL 17 and enables the local seed file `./seed.sql`; the file is absent, an existing item (21.10).
- The hosted project could be inspected for catalog state and advisor notices, but this did not execute RLS assertions as real authenticated users.
- **Unverified — needs staging credentials/devices:** R2 privacy and full upload/download/delete, Resend delivery, FCM foreground/background delivery and preference behavior, Supabase registration/redirect configuration, Android installation/update with a production signer, and iOS build/install behavior.
- Current branch is `dev`. The only workflow is CodeQL, triggered for `main`; GitHub branch-protection/required-check settings were not available to this repository scan.

## Findings Matrix

| ID | Priority | Finding | Evidence |
| :--- | :--- | :--- | :--- |
| 24.1 | 🟡 MEDIUM | Concurrent game-question creation can leave multiple active rows | `Flutter/lib/features/games/game_repository.dart:87-91,118-123,186-191`; `supabase/schemas/public/tables/game_questions.sql:9-12` |
| 24.2 | 🟠 HIGH | Android release silently falls back to debug signing | `Flutter/android/app/build.gradle.kts:11-12,53-57`; `.gitignore:26`; `README.md:177` |
| 24.3 | 🟡 MEDIUM | Partnership route and shell consult inconsistent state sources | `Flutter/lib/features/auth/auth_state.dart:351-363`; `Flutter/lib/shared/utils/auth/auth_navigation_utils.dart:29-43`; `Flutter/lib/features/partnership/partner_state.dart:92-105`; `Flutter/lib/features/home/screens/main_shell.dart:130-147` |
| 21.11 | 🟢 LOW | Cancellation-requester foreign key has no supporting index | `supabase/schemas/public/tables/partnerships.sql:16,27`; linked performance advisor |

The actionable fixes and their acceptance criteria are in the matching sections of `todo.md`. Phase 0.3–0.5 are explicit pre-use verification gates, not claims that the external services are already defective.

## Detailed Findings

### 24.1 — Concurrent game-question creation is not atomic

`GameRepository.fetchNewGameQuestion()` first reads for an active question and returns only if it finds one:

```dart
final existing = await _fetchActiveQuestionFor(ctx);
if (existing != null) return existing;
```

It then selects a catalogue row and inserts a new `game_questions` row in a later request (`game_repository.dart:87-123`). The retry button is available in the no-question state (`game_screen.dart:345`), and the `_isFetchingQuestion` guard in `GameState` (`game_state.dart:241-243`) only serializes calls in one client process. The active-question reader filters out `both_answered` rows, orders newest first, and returns only one row (`game_repository.dart:186-191`). The table defines a primary key and foreign keys, but no uniqueness rule for one active question per partnership (`game_questions.sql:9-12`).

**Trigger and impact:** both partners press “try again” while no active question exists. Their independent reads can both return empty and their writes create different pending rows. The app reads only the newest active row, so before Realtime converges clients (or while one is offline), an answer to the other row can become detached from the visible game and history.

The race is proven by the non-atomic client/database path and absence of an active-row uniqueness rule, but the two-client symptom was not reproduced against staging. **Unverified — needs** two authenticated test clients.

**Fix:** make “return active question or create one” a single transactional RPC, with a partnership-level lock or equivalent uniqueness guarantee. Return the row that won the race to both clients.

**Acceptance:** a concurrency test releases two requests for the same partnership together; both responses identify the same question and the database contains exactly one active question.

### 24.2 — Android release uses a debug key when release secrets are absent

`Flutter/android/app/build.gradle.kts:11-12` loads `key.properties` only if present; lines 53-57 select the release config when it exists and the debug config otherwise:

```kotlin
if (keystorePropertiesFile.exists()) {
    signingConfig = signingConfigs.getByName("release")
} else {
    signingConfig = signingConfigs.getByName("debug")
}
```

The file is git-ignored (`.gitignore:26`). The README says the APK is distributed via GitHub Releases and users install updates from that release (`README.md:177`).

**Trigger and impact:** a clean checkout or CI release build has no `key.properties`. It still produces a release-signed APK with that runner's debug key. A subsequent build with a different debug keystore cannot update the installed app, and the artifact does not use a stable production signing identity.

**Fix:** fail the release task unless a protected production keystore is explicitly configured; retain debug signing only for debug builds.

**Acceptance:** release without signing secrets fails clearly; consecutive configured releases have the expected identical certificate, and Android installs the second over the first.

### 24.3 — Partnership routing can disagree with the main shell

`AuthState.login()` reads the active partnership after authentication and sets its partner fields only when `getPartnership()` returns a partner; the surrounding `catch (_) {}` discards thrown errors and still lets login complete (`auth_state.dart:351-364`). `AuthNavigationUtils.determinePostAuthRouteName()` then fetches into `PartnerState` and chooses `MainShell` if either `AuthState.hasPartner` **or** `PartnerState.partner != null` (`auth_navigation_utils.dart:29-43`). But `MainShell.build()` redirects to `PartnerScreen` whenever `AuthState.hasPartner` is false (`main_shell.dart:130-147`). `PartnerState._applyPartnership()` updates its own state and storage without updating `AuthState` (`partner_state.dart:92-105`).

**Trigger and impact:** the login-time partnership read fails transiently, but the route-time retry succeeds. The route helper chooses the main shell using `PartnerState`; the shell rejects that same user using the still-empty `AuthState`. A real partnered user is sent back to partner selection and cannot reach shared features until the auth state is reconciled.

**Fix:** resolve membership into one canonical state before selecting the post-auth route, and make both route selection and the shell use that same resolved state. A failed membership lookup must not be interpreted as proof that no partnership exists.

The divergent state sources and redirect guard are confirmed in the current code, but the complete failure-then-success navigation sequence was not reproduced. **Unverified — needs** a focused Flutter regression test.

**Acceptance:** a test makes the login-time lookup fail and the route-time lookup succeed; `AuthState` and `PartnerState` then agree on the partnership, the post-auth route settles in `MainShell`, and the shell does not redirect to `PartnerScreen`.

### 21.11 — Cancellation requester foreign key is unindexed

`partnerships.sql:16` declares `FOREIGN KEY (cancel_requested_by) REFERENCES public.users(id) ON DELETE CASCADE`. The only declared index in the file is `idx_partnerships_user2_id` on `user_id_2` at line 27. The linked project's performance advisor specifically reported `partnerships_cancel_requested_by_fkey` as unindexed.

**Trigger and impact:** user deletion or requester-filtered cleanup can scan `partnerships` as the table grows. The live advisor classifies this as informational performance risk, not a current correctness failure.

**Fix:** add a btree index on `cancel_requested_by` to the declarative schema and apply it to the linked project.

**Acceptance:** remote index exists and the advisor no longer reports the unindexed foreign key.

## Existing Findings Rechecked, Not Duplicated

- The linked project reports `users_auth_id_fkey` as `FOREIGN KEY (auth_id) REFERENCES auth.users(id) ON DELETE CASCADE`, confirming 21.1 is applied remotely.
- The live `partnership_guard_status()` contains the 24-hour cooldown and seven-day expiry bound for cancellation, confirming 21.2 is present. Its `pending → accepted` branch still only checks that the caller is the invited partner and does not check for another accepted partnership; existing item 21.3 remains open.
- All 26 public base tables returned `relrowsecurity = true` in the live catalog query. Per-policy authorization and application behavior still require executable tests.
- Supabase security advisors warned that the authenticated role can execute two `SECURITY DEFINER` partnership read RPCs. The live definitions restrict rows through `user_current_id()` (`users.auth_id = auth.uid()`) and partnership membership; grants revoke `PUBLIC` and `anon`. The warning alone did not establish a cross-user read, so these functions are recorded as deliberate rather than a new vulnerability.
- Existing open worklist items 21.4–21.10, 22.1–22.4 and 23.1–23.4 were not duplicated here. Their status remains in `todo.md`.

## Coverage

| Pass | Surfaces examined | Result |
| :--- | :--- | :--- |
| 0 Baseline/inventory | Entry points, env loaders, package manifests, Supabase config, workflows, test scripts | Component map and test results recorded above; Android, provider and hosted SQL execution remain unverified |
| 1 Docs vs code | README validation/update claims, package scripts, current API routes/config, existing audit backlog | open documentation drift stays in 21.9/22.1/22.2 |
| 2 Dead code/unused surface | Repo-wide search for `getReceiverInstallationId`, `languageForLocale`, and `LanguageHelper.isSupported` | Existing 22.3/22.4 remain; no new dead-code item added |
| 3 Data layer | Live public-table RLS flags/policies, foreign-key metadata, partnership triggers/functions, Supabase security/performance advisors | RLS enabled on 26 tables; 21.3 remains open; 24.3 and 21.11 found |
| 4 Backend services | Express middleware/route mounts, auth/media route contracts, env loading; lint/Jest/syntax | Commands pass; no new backend behavior defect confirmed in this delta pass |
| 5 Client state/UI | Game state/repository/screen; auth-to-route-to-shell membership state; full Flutter analyzer/tests | 24.1 and 24.3 found; existing tests do not exercise concurrent game creation or mismatched auth/partnership state |
| 6 Cross-layer contracts | Flutter API route constants vs Express mounts; game RPC call vs live signature/grants; auth route helper vs shell guard; release artifact/update docs | 24.3 found: route and shell use different membership state; game creation is not atomic; Android signing issue 24.2 found |
| 8 Triage | Current findings merged with existing `todo.md` IDs | Seven new items; external pre-use gates are tracked in Phase 0; existing backlog retained without duplication |

## Recommended Order

1. Enable leaked-password protection and remove the Android release debug-signing fallback (24.2).
2. Reconcile partnership state before post-auth routing and add the failure/retry regression test (24.3s).
3. Make game-question creation atomic and add the concurrent two-client regression test (24.1).
4. Apply the cancellation foreign-key index (21.11).

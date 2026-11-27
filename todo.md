# JustUS — Fixing Phase · Master Todo List

> **Purpose**: the live worklist for verified defects. Everything already closed is archived in [`docs/fixing-phase-log.md`](docs/fixing-phase-log.md) (→ Outcome by phase, → Item index, → Decisions of record).
> **This file is tracked and committed with each fix.** Rules for working an item: `.agents/skills/fix-workflow/SKILL.md`.
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target `file:line`, the exact defect, the concrete fix and acceptance criteria.
> **Finding-ID prefixes**: `17.x` media delivery, `18.x` retention/backend safety, `21.x` schema/RLS/DB invariants, `22.x` docs/dead code, `23.x` regression tests, `24.x` first-use correctness/security, `25.x` validation and CI.
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

**Latest audit baseline (2026-11-24, branch `dev`)**: Flutter analysis clean and **439 tests passed**; `Backend/npm test` **305 passed / 27 suites**, lint 0 errors / 4 warnings; backend syntax and circular-dependency checks passed; duplication scan exited 0 (with reported clones). `npm run validate` could not start in this Windows PowerShell environment because `bash` is unavailable. SQL scripts were not run locally (no `bash` or `psql`); read-only checks against the linked Supabase project are documented in the audit. The Android debug build did not complete with the installed JDK 26; a build on the CI's JDK 21 and a signed release build remain unverified.

---

## Phase 0 — Ground truth & safety net

- [ ] **0.1 Re-run the baseline before touching anything**
  - Commands: `cd Flutter && flutter analyze && flutter test`; `cd Backend && npm test && npm run check && npm run madge:circular`; root `npm run scan:duplicates`.
  - Latest observed: 439 Flutter tests pass and analysis is clean; 305 backend tests / 27 suites pass, lint has 0 errors / 4 warnings; syntax, circular-dependency and duplication commands exit 0.
  - `npm run validate` currently stops before checks on this Windows host because it invokes `bash`; SQL tests were not run locally.
  - Acceptance: the baseline is reproducible in the chosen CI environment, including SQL tests, and any runner limitations are resolved or documented.

- [ ] **0.2 Confirm the migration/apply path before any SQL item**
  - `supabase/schemas/**` is the source of truth; there are no tracked migrations. Applying a schema change means `npx supabase@3.4.0 db query --remote --yes --file <script>.sql` (fix-workflow §1.9).
  - Acceptance: the linked project is reachable, or every Phase 21 item is explicitly left `Unverified` with the query that still needs to run.

---
## Phase 25 — Auth, Logout & Session Lifecycle

### 25.1 Prevent MainShell from redirecting to PartnerScreen after logout (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-26, on `dev`) — `MainShell.build()` now redirects only when `isLoggedIn && !hasPartner`, and the post-frame callback revalidates both flags (and `mounted`) before navigating, so a stale callback cannot redirect a logged-out user (`Flutter/lib/features/home/screens/main_shell.dart:130-137`). · **Verification**: `flutter analyze` clean; `flutter test` 454 pass, including the 3 new tests in `Flutter/test/main_shell_partner_redirect_test.dart` (the logout and stale-callback tests both fail against the pre-fix code). · **Residual**: 25.2 (logout navigation still depends on the caller's `BuildContext` lifecycle) remains open and out of scope.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/home/screens/main_shell.dart:130-147, Flutter/lib/features/auth/auth_state.dart (isLoggedIn, hasPartner, logout()), Flutter/lib/shared/utils/auth/logout_utils.dart:39-48, Flutter/lib/features/settings/screens/profile_screen.dart (_logout()), Flutter/test/logout_unconditional_test.dart.
- **Defect**: MainShell.build() redirects to PartnerScreen whenever hasPartner == false, regardless of whether the user is still authenticated. During logout, both isLoggedIn and hasPartner become false, potentially causing a redirect that conflicts with the navigation to LoginScreen. A previously scheduled post-frame callback can also execute after the authentication state changes.
- **Fix**: redirect only when isLoggedIn && !hasPartner. Recheck both conditions inside the post-frame callback before navigating, so a stale callback cannot redirect a logged-out user.
- **Acceptance**: a widget test performs logout from ProfileScreen inside the real MainShell and verifies that the final destination is LoginScreen, never PartnerScreen. Another test verifies that an authenticated user who loses their partner is redirected to PartnerScreen. A previously scheduled redirect must not override logout navigation.

### 25.2 Keep logout navigation independent of caller lifecycle (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-26, on `dev`) — `LogoutUtils.performLogout()` now reads `AuthState` from the caller, awaits `logout()`, then replaces the stack with `AppRoutes.login` through `ErrorHandler.navigatorKey.currentState`; the caller's `context.mounted` gate was removed, so navigation still runs if the initiating screen is disposed mid-teardown (`Flutter/lib/shared/utils/auth/logout_utils.dart:37-47`). · **Verification**: `flutter analyze` clean; `flutter test` 455 pass, including the new `Flutter/test/logout_navigation_lifecycle_test.dart` (fails against the pre-fix code because the disposed caller skipped navigation) and the updated `Flutter/test/logout_unconditional_test.dart`. · **Residual**: if the root navigator is not attached (`navigatorKey.currentState == null`), the redirect is skipped; session-expiry navigation still uses the separate reauth dialog. 25.3–25.5 remain open.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/shared/utils/auth/logout_utils.dart:39-48, Flutter/lib/features/auth/auth_state.dart (logout()), Flutter/lib/features/home/screens/main_shell.dart:130-147, Flutter/lib/main.dart (MaterialApp.navigatorKey), Flutter/test/logout_unconditional_test.dart.
- **Defect**: logout navigation depends on the lifecycle of the BuildContext that initiated it. If the calling screen is disposed during the asynchronous teardown, performLogout() returns without navigating to LoginScreen. This can leave the final navigation destination dependent on competing redirects.
- **Fix**: after authState.logout() completes, navigate through ErrorHandler.navigatorKey.currentState using pushNamedAndRemoveUntil(AppRoutes.login, (route) => false). Do not depend on the original BuildContext or its mounted state after the teardown.
- **Acceptance**: a widget test starts logout, disposes the calling screen while AuthState.logout() is still running, then completes the teardown and verifies that LoginScreen is always the final destination. No previous route remains in the navigation stack.

### 25.3 Prevent PartnerScreen from loading private data without an active session (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-27, on `dev`) — `PartnerScreen` skips its initial and pull-to-refresh loads when `AuthState.isLoggedIn` is false (`Flutter/lib/features/partnership/screens/partner_screen.dart:29-38,86-90`). The state layer enforces the same rule through `BaseState.hasActiveSession()` — the stored identity `BaseRepository.withUser` already trusts — and re-checks it after every await before applying a result or starting the next request (`Flutter/lib/shared/utils/state/base_state.dart:46-50`, `Flutter/lib/features/partnership/partner_state.dart:27-60`, `Flutter/lib/features/settings/profile_state.dart:61-95`), so a logout mid-flight stops `fetchCancellation()` and drops late partnership/profile data; `AuthState._fetchInvitations()` now guards on `isLoggedIn || _isLoggingOut` before and after the RPC (`Flutter/lib/features/auth/auth_state.dart:617-622`). The `ProfileState` generation check is unchanged. · **Verification**: `flutter analyze` clean; `flutter test` 459 pass (was 455), including the new no-session and session-lost-mid-load tests in `partner_state_test.dart`, the no-session test in `profile_state_test.dart` and the signed-out-screen test in `partner_screen_test.dart`. · **Residual**: the state-layer guard reads the stored user id, not the live Supabase session, so a token invalidated without a local `logout()` is caught only once storage is cleared; writes already in progress inside `_applyPartnership` are not cancelled. Generation-based invalidation for `PartnerState.clear()` and the failed-lookup short-circuit remain in 25.4.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/partnership/screens/partner_screen.dart:25-30 (initial loading), Flutter/lib/features/partnership/partner_state.dart (fetchPartnership, fetchCancellation), Flutter/lib/features/settings/profile_state.dart (loadProfile, _loadProfile, clear), Flutter/lib/features/auth/auth_state.dart (fetchInvitations, _fetchInvitations, logout), Flutter/lib/features/partnership/partnership_repository.dart (getPartnership, getCancellation), supabase/schemas/public/functions/partnership_get_pending_invitations.sql (RPC restricted to authenticated users), Flutter/test/partner_screen_test.dart.
- **Defect**: PartnerScreen starts private-data loading regardless of authentication state. Even after logout, ProfileState and PartnerState can initiate Supabase partnership reads without a valid session. During the logout transition, fetchInvitations() can also run while _userId has not yet been cleared, despite the Supabase session already being invalidated. Pending operations may additionally complete after the session is lost.
- **Fix**: prevent PartnerScreen from starting initial or refresh requests when AuthState.isLoggedIn is false. Add authentication guards to the relevant state-level loading methods so other callers cannot bypass them. Recheck session validity during asynchronous loading, stop subsequent requests after session loss and discard stale results. Preserve the existing cache-generation protection in ProfileState.clear().
- **Acceptance**: opening PartnerScreen without an authenticated session starts no private Supabase requests. Simulating logout during initialization prevents further requests and prevents late responses from repopulating cleared state. Existing authenticated PartnerScreen flows continue to load correctly.

### 25.4 Prevent stale PartnerState requests from restoring cleared data (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-27, on `dev`) — `fetchPartnership()` and `refreshFromRealtime()` now return right after a non-`Success` `getPartnership()` (the error is still surfaced through `handleResult`, so a failed lookup is never mistaken for "no partner") and no longer call `getCancellation()` (`Flutter/lib/features/partnership/partner_state.dart:29-57`). A `_generation` counter mirrors `ProfileState`: `clear()` increments it (`:22-27`), each fetch snapshots it and checks after every await before applying results, persisting, chaining `fetchCancellation()` or teleporting (`:29-69`), so a response that lands after `clear()` cannot repopulate `_partnershipInfo`/`_cancellation` or rewrite the cached partner. · **Verification**: `flutter analyze` clean; `flutter test` 462 pass (was 459), including the new failed-lookup, pending-response-after-`clear()` and pending-realtime-refresh-after-`clear()` tests in `Flutter/test/partner_state_test.dart`. · **Residual**: `acceptCancellation()`/`requestCancellation()`/`revertCancellation()` do not snapshot the generation themselves; they rely on the guarded fetch calls, so after `clear()` with a still-active session their follow-up reload is a fresh, legitimate read rather than stale data.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/partnership/partner_state.dart:18-58,70-105, Flutter/lib/shared/utils/state/base_state.dart:67-86 (handleResult), Flutter/lib/features/settings/profile_state.dart:41-111,182-192 (generation-based invalidation reference), Flutter/test/partner_state_test.dart.
- **Defect**: fetchPartnership() and refreshFromRealtime() call fetchCancellation() even when getPartnership() returns an error, causing unnecessary requests after the initial lookup has already failed. Additionally, clear() only resets in-memory fields. A pending request can therefore complete afterwards, repopulate _partnershipInfo or _cancellation, and write stale partnership data back to local storage.
- **Fix**: stop the loading sequence when getPartnership() does not return Success, without treating a failed lookup as an empty partnership. Introduce a generation counter, following ProfileState, and invalidate it in clear(). Check the generation after asynchronous operations and before applying results or persisting data, so obsolete requests cannot restore cleared state.
- **Acceptance**: a test makes getPartnership() fail and verifies that getCancellation() is never called. Another starts a pending partnership request, calls clear(), completes the request and verifies that _partnershipInfo, _cancellation and persisted partner data remain cleared. Apply the same invalidation guarantees to realtime refreshes. Existing partnership and cancellation tests continue to pass.

### 25.5 Prevent RealtimeSync from reconnecting or polling after signedOut (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-27, on `dev`) — `RealtimeSyncConnection` now handles `AuthChangeEvent.signedOut` as an immediate disconnect via `handleSignedOut()` (`Flutter/lib/core/realtime/realtime_connection.dart:66-88`): it sets `_signedOut = true`, increments `_generation`, cancels pending lifecycle debounce and reconnect timers, deactivates polling fallback, and unsubscribes the active channel. `scheduleReconnect()`, `activatePollingFallback()`, its periodic timer, and `subscribe()` (pre- and post-`await unsubscribe()`) all short-circuit while `_signedOut` is true (`:132-245`), and the bumped `_generation` drops stale channel status callbacks (`:264-268`). `RealtimeSyncService.configure()` treats `wasSignedOut && userId != null` as a change, calls `handleSignedIn()` on non-null `userId`, and calls `handleSignedOut()` when `userId == null` (`Flutter/lib/core/realtime/realtime_sync_service.dart:151-187`); `docs/app/realtime/doc.md` and `docs/app/architecture/doc.md` updated. · **Verification**: `flutter analyze` clean; `flutter test test/realtime_sync_service_test.dart` 13 pass; `flutter test` 465 pass (was 462), including the 3 new `signedOut` lifecycle tests in `Flutter/test/realtime_sync_service_test.dart:365-438`. · **Residual**: `didChangeAppLifecycleState(resumed)` still checks `_session.userId != null` before `schedule()`, though `flush()` → `scheduleReconnect()` is blocked by `_signedOut`; `subscribe()` catch blocks (`:303-310`) also rely on `scheduleReconnect()`'s `_signedOut` guard. 25.6 remains open.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/core/realtime/realtime_connection.dart:49-67,107-116,164-190,193-209,225-263,281-295, Flutter/lib/core/realtime/realtime_sync_service.dart:151-187, Flutter/test/realtime_sync_service_test.dart:340-364.
- **Defect**: signedOut can schedule another subscription attempt before configure(userId: null) updates the session. If the failure counter reaches the fallback threshold, this event can also activate polling and immediately trigger _refreshAll(). An already-running subscribe() can pass its post-await unsubscribe() check because the old user ID is still present. unsubscribe() cancels the reconnect timer but does not stop polling or invalidate pending subscription work.
- **Fix**: handle signedOut as an immediate disconnect: cancel pending debounce and reconnect timers, deactivate polling fallback, invalidate pending subscription attempts and remove the active channel. Prevent reconnects, subscriptions, channel-status callbacks and polling from starting further work while signed out. Re-enable them only when a subsequent authenticated configure() supplies a non-null user ID.
- **Acceptance**: a test emits signedOut while the previous user ID is still configured, before calling configure(userId: null). It verifies immediate channel removal and, after advancing timers beyond the reconnect and polling intervals, no new subscriptions, reconnect attempts or polling refreshes. Also verify that an in-flight subscription cannot create a channel after signedOut, and that a subsequent authenticated configuration can reconnect normally.

### 25.6 Prefill the login email after signup confirmation (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-27, on `dev`) — `AuthState.register()` now persists the registered email via `StorageService.savePendingSignupEmail()` (`Flutter/lib/core/local_storage/storage_service.dart:382-400`, `Flutter/lib/features/auth/auth_state.dart:495`). Both cold-start (`init()`, `:158-163`) and warm-start (`onAuthStateChange` `signedIn` when `!isLoggedIn && !_isSigningIn`, `:204-217`) route through `_completeSignupConfirmation()` (`:911-938`), which revokes the temporary Supabase session, clears the stored pending email, sets `_pendingLoginEmail`, and queues the localized `auth_emailConfirmed` toast via `setMessage()` → `AuthMessageHost`. `LoginScreen` consumes `consumePendingLoginEmail()` once in `initState` and via its `AuthState` listener (`Flutter/lib/features/auth/screens/login_screen.dart:25-38`), leaving the password field empty; `docs/features/authentication/login-registration/doc.md` updated. · **Verification**: `flutter analyze` clean; `flutter test` 470 pass (was 465), including `Flutter/test/signup_confirmation_prefill_test.dart`. · **Residual**: none.
- **Sources**: docs/features/authentication/login-registration/doc.md — mandatory email confirmation flow; current-code review.
- **Files**: Flutter/lib/features/auth/auth_state.dart:88-95,172-190, Flutter/lib/features/auth/screens/register_screen.dart:21-28,133-154, Flutter/lib/features/auth/screens/login_screen.dart:20-27,45-53, Flutter/lib/main.dart:191-207 (AuthMessageHost), Flutter/lib/shared/utils/state/base_state.dart:36-48,118-156.
- **Defect**: after the confirmation link reopens the app, the confirmed email is not passed to the login form and no success feedback is displayed. Users must manually enter the same email they used during registration.
- **Fix**: capture the confirmed email from the signup confirmation callback/session and expose it as pending data for LoginScreen. Prefill its email controller and display a localized success toast using the existing AuthState.setMessage() and AuthMessageHost mechanism. Consume the pending email and message once, avoiding repeated notifications or unintended prefilling on later visits.
- **Acceptance**: completing signup confirmation on the same device reopens the app on LoginScreen, with the registered email already filled in and a single success toast. The password remains empty. The behavior works whether the app was already running or had to be launched again, and does not trigger on unrelated auth events.

## Phase 26 — Change Splash Screen Behavior

### 26.1 Add the shared couple emoji to Supabase schema (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Agreed feature requirements.
- **Files**: `supabase/schemas/public/tables/partnerships.sql`, `supabase/schemas/public/views/v_active_partnership.sql`.
- **Defect**: `public.partnerships` does not store a shared couple emoji, and `v_active_partnership` does not expose one.
- **Fix**: Add `couple_emojis TEXT NOT NULL DEFAULT '❤️'` to `public.partnerships`, ensure existing rows receive the default, and expose the column through `v_active_partnership`. Apply the change using the repository's documented Supabase schema workflow; do not introduce a migrations directory.
- **Acceptance**: Existing and newly created partnerships return `❤️` by default, and the active partnership view exposes `couple_emojis`.

### 26.2 Add couple emoji support to the partnership model and repository (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/partnership/partnership_models.dart`, `Flutter/lib/features/partnership/partnership_repository.dart`.
- **Defect**: `PartnershipResponse` does not read the shared emoji, and `PartnershipRepository` has no method to update it.
- **Fix**: Add the `coupleEmojis` model field, parse `couple_emojis` from Supabase, and implement a repository method to update it on the current partnership. Preserve the existing repository error-handling and cache-invalidation conventions.
- **Acceptance**: The model correctly reads the value returned by Supabase, and the repository can update it without changing unrelated partnership fields.

### 26.3 Add partnership-scoped local storage for the couple emoji (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current storage architecture.
- **Files**: `Flutter/lib/core/local_storage/storage_service.dart`.
- **Defect**: The shared emoji is not available locally before remote data is loaded.
- **Fix**: Add methods to save, retrieve, and clear the emoji together with its `partnershipId`. A cached emoji must only be returned for the matching partnership. Ensure `StorageService.clearAll()` also removes it on logout.
- **Acceptance**: The emoji can be retrieved without a network request, an old partnership's emoji cannot appear in a new pairing, and logout clears the cache.

### 26.4 Add couple emoji state management to ProfileState (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/settings/profile_state.dart`.
- **Defect**: `ProfileState` manages the anniversary date but does not expose or update the shared couple emoji.
- **Fix**: Add a `coupleEmojis` property, load it from local storage and partnership data, and provide an update method that uses `PartnershipRepository` and refreshes the local cache after a successful update.
- **Acceptance**: Both the cached and remotely loaded values are reflected in the state, successful changes notify listeners, and failed updates do not overwrite the current value.

### 26.5 Synchronize couple emoji changes through Realtime (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current Realtime implementation.
- **Files**: `Flutter/lib/core/realtime/realtime_sync_service.dart`, `Flutter/lib/core/realtime/refetch_realtime_handler.dart`, `Flutter/lib/features/settings/profile_state.dart`, `Flutter/lib/core/local_storage/storage_service.dart`.
- **Defect**: Partnership events refresh `PartnerState` and `AuthState`, but do not refresh the shared emoji in `ProfileState`.
- **Fix**: Extend the existing partnership event flow to refresh only partnership metadata, update `ProfileState`, and persist the received emoji locally. Do not clear the cached emoji when a cancellation is merely requested or is still reversible; clear it only after the partnership is definitively deleted or ended.
- **Acceptance**: An emoji changed on one device appears on the other through Realtime. A reversible cancellation preserves the cached value, while a confirmed partnership deletion clears it.

### 26.6 Make the existing emoji picker reusable (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart`, `Flutter/lib/features/mood/screens/mood_screen.dart`.
- **Defect**: `EmojiPickerSheet` is coupled directly to `MoodState`, so it cannot be reused by other features.
- **Fix**: Refactor the existing picker to accept a selection callback, an optional initial emoji, and a configurable title. Keep mood-specific behavior in the mood screen rather than inside the reusable picker.
- **Acceptance**: The picker can return a selected emoji without directly modifying `MoodState`, and the existing mood selection flow continues to work.

### 26.7 Replace the Drive reaction picker with the reusable emoji picker (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/drive/screens/drive_item_screen.dart`.
- **Defect**: Drive reactions use a separate bottom sheet with a hardcoded list of eight emojis.
- **Fix**: Replace the custom reaction bottom sheet with the reusable emoji picker from 26.6. Pass the selected emoji to the existing Drive reaction flow.
- **Acceptance**: Drive reactions use the shared picker and continue to save and display reactions correctly.

### 26.8 Add the couple emoji setting to ProfileScreen (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Agreed feature requirements.
- **Files**: `Flutter/lib/features/settings/screens/profile_screen.dart`, `Flutter/lib/core/localization/intl_*.arb`.
- **Defect**: Partners have no interface for changing their shared emoji.
- **Fix**: Add an `Emoji della coppia` setting under the existing `Connessione` section. Open the reusable picker and save the selected emoji through `ProfileState`. Add the required translations.
- **Acceptance**: Both partners can open the setting, select an emoji, and update the same partnership value.

### 26.9 Display the shared emoji between the avatars (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Agreed feature requirements.
- **Files**: `Flutter/lib/features/home/screens/homepage_screen.dart`, `Flutter/lib/features/settings/screens/profile_screen.dart`.
- **Defect**: The HomeScreen uses a fixed link icon between the avatars, while ProfileScreen uses a fixed heart icon.
- **Fix**: Replace both static connectors with the current `coupleEmojis` value from `ProfileState`. Keep the existing layout and styling around the avatars.
- **Acceptance**: Both screens display the same shared emoji and update automatically when `ProfileState` changes.

### 26.10 Display the cached couple emoji on the splash screen (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Agreed feature requirements.
- **Files**: `Flutter/lib/features/auth/screens/splash_screen.dart`, `Flutter/lib/core/local_storage/storage_service.dart`.
- **Defect**: The splash screen always displays a hardcoded heart.
- **Fix**: Load the cached emoji locally and display it instead of the hardcoded value. Use `❤️` when no matching cached value exists. Do not wait for Supabase or delay authentication routing to retrieve the emoji.
- **Acceptance**: The splash screen displays the last cached emoji immediately, works offline, and falls back to `❤️` when no valid cache exists.

### 26.11 Update documentation for the shared couple emoji (🟢 LOW)
- [ ] **Status: ⬜ TODO**
- **Sources**: Updated implementation from Phase 26.
- **Files**: `docs/features/partnership/doc.md`, `docs/features/profile-settings/doc.md`, `docs/features/mood/doc.md`, `docs/features/shared-drive/doc.md`, `docs/app/architecture/doc.md`.
- **Defect**: Existing documentation does not describe the shared emoji, its editing flow, local cache, or reuse of the emoji picker.
- **Fix**: Update the relevant feature and architecture documentation to describe the database field, state ownership, picker reuse, Realtime synchronization, splash behavior, and cache lifecycle.
- **Acceptance**: Documentation matches the implemented behavior and does not describe the old fixed icons or separate Drive picker.

### 26.12 Add regression tests for the shared couple emoji flow (🟡 MEDIUM)
- [ ] **Status: ⬜ TODO**
- **Sources**: Phase 26 implementation.
- **Files**: `Flutter/test/`.
- **Defect**: The new shared emoji flow has no regression coverage across its persistence and UI lifecycle.
- **Fix**: Add focused tests covering model parsing, repository updates, local cache scoping, ProfileState updates, Realtime synchronization, picker selection, and splash fallback.
- **Acceptance**: Tests verify that both partners receive the same emoji, cached values survive app restarts, reversible cancellation does not clear the value, confirmed partnership deletion and logout clear it, and a new partnership falls back to `❤️`.

## Phase 27 — Adjust drive bugs and non-correct behavior

### 27.1 Add video selection to the Drive picker (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `MediaPickerService.showPickerSheet()` offers image capture, image gallery, audio and PDF selection, but does not offer video selection. The downstream video upload and playback pipelines already exist.
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/shared/utils/ui/media_picker_service.dart`, `Flutter/lib/features/drive/screens/drive_screen.dart`, `Flutter/lib/core/localization/intl_it.arb`, `Flutter/lib/core/localization/intl_en.arb`, `Flutter/test/media_picker_service_test.dart`.
- **Defect**: Users cannot select existing videos from the Drive picker despite the application already supporting video uploads and playback.
- **Fix**: Add a video selection option using `ImagePicker.pickVideo()` with `ImageSource.gallery`. Preserve the existing image, audio and PDF options and keep `imagesOnly: true` restricted to images for profile-picture selection. Add the corresponding Italian and English translations.
- **Acceptance**: Videos can be selected from the Drive picker and passed to the existing upload flow. All existing picker options continue working, and the profile-picture picker remains image-only.

### 27.2 Resolve missing MIME types correctly (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `DriveScreen._uploadFile()` substitutes `image/jpeg` whenever `XFile.mimeType` is null, regardless of the actual file format.
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/drive/screens/drive_screen.dart`, `Flutter/lib/features/drive/drive_state.dart`, `Flutter/lib/shared/utils/ui/media_picker_service.dart`, `Flutter/lib/core/media/media_service.dart`, relevant media upload tests.
- **Defect**: Files without MIME metadata can be incorrectly classified as images, causing videos and other supported formats to enter the wrong upload path.
- **Fix**: Remove the unconditional `image/jpeg` fallback. Resolve missing MIME types from the actual file extension using a shared mapping, preserving the existing supported image, video, audio and PDF formats. Reject unsupported or unrecognized formats instead of silently treating them as images.
- **Acceptance**: Missing MIME metadata is resolved correctly for supported formats. Videos reach `MediaType.video`, and unknown formats never default to `image/jpeg`.

### 27.3 Align video upload metadata with LightCompressor output (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `MediaService.uploadMedia()` derives the MIME type and upload filename from the original file before compression, while `CompressionService.compressVideo()` can return a generated `.mp4` file.
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/core/media/media_service.dart`, `Flutter/lib/core/media/compression_service.dart`, relevant media upload tests.
- **Defect**: When LightCompressor produces an MP4 from an input with another extension, the uploaded content can have a different format from the MIME type and extension used for its R2 object.
- **Fix**: Determine the effective MIME type and upload filename extension from the actual file returned by compression. Keep the original filename separately in metadata. When compression falls back to the original file, preserve its actual format and extension.
- **Acceptance**: The uploaded file's actual format, R2 object extension and `Content-Type` always agree, both when compression succeeds and when it falls back to the original file. Original filename metadata remains preserved.

-- Raw
CORREZIONI DOPO FULL TEST MANUALE:

-- arriva la mail dell'invito, ma se nella mail clicco sul sito justus.serverfede.eu non mi da nulla, infatti da come come errore " CANNOT GET /" non mostrando nulla. servirebbe una pagina statica con delle info (a cui in seguito inseriremo privacy, policy e altre cose)

-- batch presigned URL generation: Replace the two /media/upload-url requests with one /media/upload-urls request that generates URLs for both the original photo and thumbnail.

-- improve upload logging: Add distinct logs for compression, original photo upload, thumbnail upload, metadata registration and notification. Include duration, file size and upload ID.

-- optimize RealtimeSync: Avoid refreshing all application states after every reconnection. Refresh only what is necessary and prevent redundant subscriptions or refreshes.

-- decouple notifications: Move partner notification dispatch into the backend's media completion flow, using reliable background processing.

-- in drive screen posso solo selezionare foto o video o like, no audio o pdf.

-- posso reagire alle foto solo con un set di 8 emoji predefinite, io vorrei lo stesso emoji picker personalizzabile del mood, possiamo riutilizzare lo stesso.

-- non c'è la possibilità di scaricare gli item dal drive

-- gli oggetti all'interno di cloudflare vengono divisi per userid, non per partnershipId, quindi ogni utente ha il proprio spazio privato, questo non serve, lo spazio deve essere di copia, così tutto è più ordinato.

-- quando provo ad aprire un pdf/audio dall'app non vedo nulla, la sola scritta "file"

-- un file audio viene catalogato come pdf e la miniatura corretta

-- non c'è nessun resize image prima del caricamento, questo deve essere implementato soppratutto per le foto profilo.

## Phase 28 — Realtime Synchronization

**### 28.1 Enable limited Realtime synchronization for unpaired users (🟡 MEDIUM)**
- [ ] **Status: 🔴 OPEN** — Confirmed: `RealtimeSyncService.configure()` currently prevents subscriptions when `partnershipId` is null. Authenticated users without an active partnership therefore cannot receive partnership events, and their pending invitation lists remain stale.
- **Sources**: `Flutter/lib/core/realtime/realtime_sync_service.dart:34-45,67-90,151-204`, `Flutter/lib/core/realtime/realtime_sync_scope.dart:57-69`, `Flutter/lib/core/realtime/realtime_sync_session.dart:84-130`, `Flutter/lib/core/realtime/realtime_connection.dart:107-184,194-245`, `Flutter/lib/features/auth/auth_state.dart:583-617`, `Flutter/lib/features/partnership/partner_state.dart:25-45`, `Flutter/lib/features/partnership/screens/partner_screen.dart:25-35,78-96,255-300`, `supabase/schemas/_cluster/publications.sql:15-17`, `supabase/schemas/public/tables/partnerships.sql:34-50`.
- **Files**: `Flutter/lib/core/realtime/realtime_sync_service.dart`, `Flutter/lib/core/realtime/realtime_connection.dart`, `Flutter/lib/core/realtime/realtime_sync_scope.dart`, `Flutter/lib/core/realtime/realtime_sync_session.dart`, `Flutter/lib/core/realtime/realtime_table_binding.dart`, `Flutter/lib/core/realtime/realtime_handler.dart`, `Flutter/lib/core/realtime/refetch_realtime_handler.dart`, `Flutter/lib/features/auth/auth_state.dart`, `Flutter/lib/features/partnership/partner_state.dart`, `Flutter/lib/features/partnership/partnership_repository.dart`, `Flutter/lib/features/partnership/screens/partner_screen.dart`, `Flutter/test/realtime_sync_service_test.dart`, `Flutter/test/partner_screen_test.dart`, `Flutter/test/partner_state_test.dart`, `supabase/schemas/_cluster/publications.sql`, `supabase/schemas/public/tables/partnerships.sql`, `docs/app/realtime/doc.md`, `docs/features/partnership/doc.md`.
- **Defect**:
  - `RealtimeSyncService.configure()` unsubscribes and defers subscription whenever `partnershipId` is null. This leaves authenticated unpaired users without Realtime synchronization.
  - The existing partnership handler only refreshes `PartnerState` and partnership identity in `AuthState`. It never calls `AuthState.fetchInvitations()`, so `sentInvitations` and `receivedInvitations` remain unchanged after remote requests.
  - `PartnerScreen` renders its invitation lists directly from those collections, requiring a manual refresh to display incoming, accepted or rejected requests.
- **Fix**: Implement the limited Realtime configuration within the existing architecture, without introducing another `RealtimeSyncService`, `RealtimeSyncConnection`, independent channel or subscription manager.
  - Introduce explicit subscription modes:
    - `UNAUTHENTICATED`: no active channel when `userId == null`.
    - `UNPAIRED`: authenticated user without an active partnership; subscribe exclusively to `public.partnerships`.
    - `PAIRED`: authenticated user with an active partnership; preserve the existing nine-table configuration.
  - Make the existing `RealtimeTableBinding` configuration selectable by mode. Reuse the current `RefetchRealtimeHandler`, `RealtimeHandler`, session filtering, deduplication and debounce infrastructure.
  - In `UNPAIRED` mode, relevant partnership INSERT, UPDATE and DELETE events must trigger a debounced refresh of:
    - `AuthState.fetchInvitations()` for sent and received requests.
    - `PartnerState.refreshFromRealtime()` for partnership and cancellation state.
    - `AuthState.refreshPartnershipFromRealtime()` for partnership identity reconciliation.
  - Ensure `AuthState.fetchInvitations()` safely handles overlapping requests. Realtime refreshes must not allow older responses to overwrite newer invitation lists after a request has been sent, accepted, rejected or withdrawn.
  - Preserve the existing `isRelevantPartnership()` filtering for INSERT and UPDATE events. Handle DELETE payloads containing only the primary key, including when `partnershipId` is null. Since such payloads cannot identify the original members, use them only to trigger a scoped refresh; never expose or infer deleted row contents.
  - Keep the existing authenticated Supabase client, JWT and RLS policies. The limited configuration restricts subscribed tables and client-side processing; it does not introduce a new privilege level.
  - Do not add unnecessary database permissions or publication entries. `public.partnerships` is already included in `supabase_realtime` and has an existing member-scoped SELECT policy.
  - Preserve the current paired-mode bindings and handlers. The full mode transition and connection lifecycle hardening are handled in 28.2.
- **Acceptance**:
  - An unauthenticated user never establishes a Realtime channel.
  - An authenticated unpaired user maintains exactly one active channel with only the `public.partnerships` binding.
  - A paired user continues using the existing nine-table configuration.
  - Sending a request automatically updates the sender's pending sent list and the recipient's pending received list.
  - Rejecting or withdrawing a request automatically removes it from the affected pending lists.
  - Repeated or simultaneous partnership events are deduplicated and coalesced without causing duplicate or stale invitation entries.
  - PK-only DELETE events trigger the necessary scoped refresh without requiring a locally known partnership ID.
  - Realtime refreshes do not fetch couple-specific data in `UNPAIRED` mode.
  - Manual pull-to-refresh continues working and no longer becomes necessary for ordinary invitation updates.
  - Existing paired-mode Realtime and invitation-flow tests continue passing.

**### 28.2 Handle automatic transitions between Unpaired and Paired Realtime modes (🟡 MEDIUM)**
- [ ] **Status: 🔴 OPEN** — Depends on 28.1. The existing Realtime connection must automatically switch between limited and full synchronization when the user's partnership status changes.
- **Sources**: `Flutter/lib/core/realtime/realtime_sync_scope.dart`, `Flutter/lib/core/realtime/realtime_sync_service.dart`, `Flutter/lib/core/realtime/realtime_connection.dart`, `Flutter/lib/features/auth/auth_state.dart`, `Flutter/lib/features/partnership/partner_state.dart`, `Flutter/lib/features/partnership/partnership_repository.dart`.
- **Files**: `Flutter/lib/core/realtime/realtime_sync_scope.dart`, `Flutter/lib/core/realtime/realtime_sync_service.dart`, `Flutter/lib/core/realtime/realtime_connection.dart`, `Flutter/lib/core/realtime/realtime_sync_session.dart`, `Flutter/lib/features/auth/auth_state.dart`, `Flutter/lib/features/partnership/partner_state.dart`, `Flutter/lib/features/partnership/partnership_repository.dart`, `Flutter/lib/features/settings/profile_state.dart`, `Flutter/test/realtime_sync_service_test.dart`, `Flutter/test/partner_state_test.dart`.
- **Defect**:
  - The current configuration does not dynamically switch between limited and full Realtime synchronization.
  - Temporary or incomplete partnership state can cause incorrect configuration decisions.
  - Configuration changes during an active subscription may be ignored, leaving an obsolete channel active.
- **Fix**:
  - Automatically switch the existing Realtime service between `UNPAIRED` and `PAIRED` after verifying the partnership through the authoritative active-partnership query.
  - Activate `PAIRED` only when an accepted partnership with a valid `partnershipId` is confirmed. Never rely solely on `partnerId` or cached IDs.
  - Return to `UNPAIRED` when the server confirms that no active partnership exists.
  - Ensure acceptance, removal and cancellation transitions trigger the appropriate configuration change.
  - Serialize subscription changes so the latest requested configuration always wins, without creating overlapping channels or ignoring changes during an ongoing subscription.
  - Make reconnects, lifecycle resume and polling fallback preserve the current mode.
  - Refresh or clear `ProfileState.partnerProfile` when the active partner changes or is removed.
  - Ignore obsolete callbacks and refresh operations from previous configurations.
- **Acceptance**:
  - Accepting a partnership automatically activates the full nine-table configuration on both devices.
  - Removing or cancelling an active partnership restores the limited `partnerships`-only configuration.
  - Incomplete or stale partnership data never activates `PAIRED`.
  - Only one Realtime channel remains active during and after transitions.
  - Reconnect and lifecycle recovery preserve the correct configuration.
  - Existing partnership and cancellation behavior remains functional.

**### 28.3 Add regression tests and update Realtime documentation (🟡 MEDIUM)**
- [ ] **Status: 🔴 OPEN** — Depends on 28.1 and 28.2. The new Realtime modes and their transitions need focused regression coverage and updated documentation.
- **Sources**: `Flutter/test/realtime_sync_service_test.dart`, `Flutter/test/partner_screen_test.dart`, `Flutter/test/partner_state_test.dart`, `docs/app/realtime/doc.md`, `docs/app/architecture/doc.md`, `docs/app/state-management/doc.md`, `docs/features/partnership/doc.md`.
- **Files**: `Flutter/test/realtime_sync_service_test.dart`, `Flutter/test/partner_screen_test.dart`, `Flutter/test/partner_state_test.dart`, `Flutter/test/partnership_scope_test.dart`, `Flutter/test/partnership_cancellation_test.dart`, `docs/app/realtime/doc.md`, `docs/app/architecture/doc.md`, `docs/app/state-management/doc.md`, `docs/features/partnership/doc.md`.
- **Defect**:
  - Existing tests do not cover the complete `UNAUTHENTICATED`, `UNPAIRED` and `PAIRED` subscription behavior or their transitions.
  - Realtime documentation describes only the previous paired-mode configuration and must reflect the new architecture.
- **Fix**:
  - Add focused regression tests covering:
    - Correct bindings for all three subscription modes.
    - Automatic invitation-list updates on both devices after sending, accepting, rejecting or withdrawing a request.
    - Automatic transitions between `UNPAIRED` and `PAIRED` after partnership acceptance or removal.
    - Correct behavior during reconnect, lifecycle resume and logout.
    - Prevention of duplicate channels and stale state after mode changes.
  - Update the four documentation files to describe the subscription modes, their bindings, transition conditions and mode-aware refresh behavior.
  - Remove outdated statements claiming that authenticated users without an active partnership have no Realtime subscription.
  - Run the relevant Flutter tests and fix any regressions introduced by the implementation.
- **Acceptance**:
  - Focused tests cover the three modes and their main transitions.
  - Invitation updates work automatically on both devices.
  - Existing paired-mode synchronization and partnership cancellation tests continue passing.
  - Documentation matches the implemented behavior.
  - Relevant Flutter tests pass.

**### 28.4 Prevent redundant Realtime configuration calls (🟢 LOW)**
- [ ] **Status: 🔴 OPEN** — `RealtimeSyncScope` schedules `configure()` after every `AuthState` or `PartnerState` notification, even when the effective identity parameters remain unchanged.
- **Sources**: `Flutter/lib/core/realtime/realtime_sync_scope.dart:58-81`, `Flutter/lib/core/realtime/realtime_sync_service.dart:143-160`, `Flutter/lib/core/realtime/realtime_connection.dart:68-76`.
- **Files**: `Flutter/lib/core/realtime/realtime_sync_scope.dart`, `Flutter/lib/core/realtime/realtime_sync_service.dart`, `Flutter/lib/core/realtime/realtime_connection.dart`, `Flutter/test/realtime_sync_service_test.dart`.
- **Defect**:
  - `Consumer2<AuthState, PartnerState>` schedules `configure()` after every notification, including unrelated state updates.
  - Although `configure()` correctly avoids recreating the channel when IDs are unchanged, it resets reconnect and failure counters before returning.
  - Repeated calls therefore cannot directly cause unnecessary subscriptions, but can interfere with exponential backoff and polling-fallback activation.
- **Fix**:
  - Prevent `RealtimeSyncScope` from scheduling `configure()` when `userId`, `partnerId` and `partnershipId` have not changed.
  - Move `resetRetryCounters()` after the identity-change check so retry state is reset only after a genuine configuration change.
  - Keep `configure()` idempotent as a safeguard, without modifying connection or session state on unchanged parameters.
- **Acceptance**:
  - Unrelated `AuthState` and `PartnerState` notifications do not trigger redundant configuration calls.
  - Repeated calls with identical IDs do not reset retry counters, recreate channels, unsubscribe or schedule reconnections.
  - Genuine identity changes still trigger the required Realtime reconfiguration.
  - Existing retry, polling-fallback and Realtime synchronization behavior remains unchanged.

### 28.5 Fix realtime propagation of anniversary date and partner name (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code:
  - `partnerships` events trigger a refetch of `PartnerState` and `AuthState`, but not `ProfileState`. However, `ProfileState` owns `_anniversaryDate`, which is updated only by `loadProfile()`. The homepage and profile screen read this value from `ProfileState`, so the other device retains the old date.
  - The homepage reads `AuthState.partnerDisplayName` through `context.read<AuthState>()` inside a `Selector<ProfileState>`. The selector does not include the partner name, so changes to `AuthState` alone do not rebuild the widget. `ProfileScreen` correctly uses `context.watch<AuthState>()`.
  - Existing Realtime tests cover partnership DELETE events, but not anniversary UPDATE propagation or homepage name rebuilding.
- **Sources**:
  - `RealtimeSyncService` partnership and user-profile handlers.
  - `ProfileState.loadProfile()` and `_anniversaryDate`.
  - `HomepageScreen._buildProfileSection()` and `ProfileScreen.build()`.
- **Files**:
  - `Flutter/lib/core/realtime/realtime_sync_service.dart`
  - `Flutter/lib/features/settings/profile_state.dart`
  - `Flutter/lib/features/home/screens/homepage_screen.dart`
  - `Flutter/test/realtime_sync_service_test.dart`
  - Add a focused homepage realtime widget test under `Flutter/test/`.
- **Defect**: Partnership updates do not refresh the anniversary value stored in `ProfileState`. Separately, the homepage does not subscribe to `AuthState` changes, leaving the partner's displayed name stale even when the realtime handler successfully updates it.
- **Fix**:
  - Refresh the anniversary value in `ProfileState` when a relevant `partnerships` UPDATE arrives. Prefer a targeted refresh rather than unnecessarily reloading unrelated profile data.
  - Make the homepage observe `AuthState.partnerDisplayName`, including it in the selector or using an equivalent reactive provider subscription.
  - Preserve the existing realtime flow for profile images and display names.
- **Acceptance**:
  - Changing the anniversary on either device updates the date and days-together counter on the other device without manually refreshing or reopening the screen.
  - Changing the display name updates the partner's name on the homepage and profile screen in realtime.
  - Tests verify the partnership UPDATE refresh path and homepage rebuild after an `AuthState` name change, without requiring an unrelated `ProfileState` mutation.

### 28.6 Keep Realtime connected while a partnership cancellation is pending (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code:
  - `v_active_partnership` returns only `accepted` rows. When a cancellation is requested, `getPartnership()` therefore returns no active partner.
  - `AuthState.syncPartnership()` clears `_partnerId`, `_partnershipId` and `_partnerDisplayName` when no accepted partner is returned.
  - `PartnerState` retains the cancelled partnership's `partnershipId` and `partnerId` inside `PartnershipCancellation`.
  - `RealtimeSyncScope` resolves the Realtime identity only from `AuthState` and `PartnerState.partnershipInfo`, ignoring `PartnerState.cancellation`. It consequently calls `configure()` with a null partnership ID, causing `RealtimeSyncService` to unsubscribe.
  - The partner's subsequent `partnership_cancel_revert` changes the database row back to `accepted`, but the requester is no longer subscribed and cannot receive the UPDATE. The reported recovery after restarting the app is consistent with this behavior.
  - Existing tests cover cancellation and deletion separately, but not the complete decline-and-restore flow across Realtime.
- **Sources**:
  - `v_active_partnership` filters for `status = 'accepted'`.
  - `AuthState.syncPartnership()` clears the active partnership identity.
  - `RealtimeSyncScope` resolves the subscription identity.
  - `RealtimeSyncService.configure()` unsubscribes when the partnership ID is null.
  - `partnership_cancel_revert.sql` restores the row to `accepted`.
- **Files**:
  - `Flutter/lib/core/realtime/realtime_sync_scope.dart`
  - `Flutter/lib/core/realtime/realtime_sync_service.dart`
  - `Flutter/lib/features/auth/auth_state.dart`
  - `Flutter/lib/features/partnership/partner_state.dart`
  - `Flutter/lib/features/partnership/partnership_models.dart`
  - `supabase/schemas/public/views/v_active_partnership.sql`
  - `supabase/schemas/public/functions/partnership_cancel_revert.sql`
  - `Flutter/test/partner_state_test.dart`
  - `Flutter/test/realtime_sync_service_test.dart`
- **Defect**: Realtime loses the partnership subscription while a cancellation is pending, precisely when it is still needed to receive the partner's decision.
- **Fix**: Keep the Realtime subscription bound to the pending cancellation by falling back to `PartnerState.cancellation.partnershipId` and `partnerId` when no active partnership is available. Restore the normal active-partnership identity after a decline, while preserving the existing deletion flow when cancellation is accepted.
- **Acceptance**:
  - When either user requests cancellation, both devices remain subscribed to the cancelled partnership.
  - When the other user declines, the requester receives the UPDATE, restores `AuthState` and `PartnerState`, and returns to the normal app state without restarting the app.
  - When cancellation is accepted, the DELETE event is still received and both users correctly transition to the no-partnership state.
  - Tests cover the full request → decline → realtime restoration flow and the request → accept → deletion flow.

### 28.7 Prevent unnecessary Realtime reconnections when opening system pickers (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code and user-provided logs: `RealtimeSyncConnection.didChangeAppLifecycleState()` schedules a reconnect on every `resumed` event, including transitions from `inactive` where the existing Realtime channel was never disconnected. `flush()` then requests a full refresh after subscription.
- **Sources**: Current-code review; user-provided Android lifecycle and Realtime logs.
- **Files**: `Flutter/lib/core/realtime/realtime_connection.dart`, `Flutter/test/realtime_sync_service_test.dart`.
- **Defect**: Opening or closing Android system pickers (photo, video, audio and PDF) triggers `inactive → resumed`. The app unnecessarily removes and recreates its Realtime channel, then executes `_refreshAll()`, refetching multiple feature states despite no actual background suspension or connection loss.
- **Fix**: Track whether the app actually entered a background lifecycle state. Only schedule the resume reconnection when returning from `paused`, `hidden` or another state that caused the channel to disconnect. An `inactive → resumed` transition must preserve the existing channel without reconnecting or refreshing. Preserve the existing reconnection and refresh behavior after genuine background suspension and actual Realtime errors.
- **Acceptance**: Opening and closing system pickers does not recreate the Realtime channel or trigger `_refreshAll()`. Returning from `paused` or `hidden` reconnects and performs exactly one refresh. Genuine channel errors continue using the existing retry mechanism. Add lifecycle regression tests covering both transitions.

## Phase 29 — Partnership & Notifications

**### 29.1 Show a partner-specific message when no partner is linked (🟡 MEDIUM)**
- [ ] **Status: 🔴 OPEN** — Confirmed in the current code: `fetchPartnerProfile()` uses `DB-NOT_FOUND-001` when no partner exists. In release mode, `ErrorHandler` maps that code to the generic localized message `Risorsa non trovata`.
- **Sources**: no doc — current-code review.
- **Files**: `Flutter/lib/features/partnership/partnership_repository.dart:68-88`, `Flutter/lib/features/settings/profile_state.dart:85-108`, `Flutter/lib/features/settings/screens/profile_screen.dart:23-50`, `Flutter/lib/shared/utils/state/base_state.dart:67-86`, `Flutter/lib/core/error_handling/error_handler.dart:163-173`, `Flutter/lib/core/error_handling/error_codes.dart:26-30,106-130`, `Flutter/lib/core/localization/intl_it.arb:315-316`, `Flutter/lib/core/localization/intl_en.arb:285-286`, `Flutter/test/profile_state_test.dart`.
- **Defect**: when the user has no linked partner, `fetchPartnerProfile()` returns a generic database not-found error. `ProfileState.loadProfile()` passes it to `handleResult()`, which displays `Risorsa non trovata` in release mode. Additionally, failed partnership lookups are currently treated as if the partner did not exist.
- **Fix**: introduce a dedicated partner-not-found error code and localized messages (`Partner non trovato` / `Partner not found`). Use it only when the partnership lookup succeeds but contains no partner. Preserve the original error when the lookup itself fails. Keep the existing generic not-found message for unrelated resources.
- **Acceptance**: a successful partnership lookup with no linked partner displays `Partner non trovato` in Italian and `Partner not found` in English. A failed partnership lookup retains its actual error message. Other `DB-NOT_FOUND-001` errors continue displaying `Risorsa non trovata` / `Resource not found`.

**### 29.2 Block account-invite emails to existing JustUS users (🟡 MEDIUM)**
- [ ] **Status: 🔴 OPEN** — Confirmed in the current code: `inviteUserController()` sends the email through Resend without checking whether the recipient already has a JustUS account.
- **Sources**: `docs/features/partnership/doc.md:165-182,214-220`, `docs/audits/email.md:37-46,98-104` — the account-invite flow is intended for users without an account, but the documentation currently describes redundant emails to existing users as harmless.
- **Files**: `Flutter/lib/features/partnership/screens/partner_screen.dart:312-316,523-548`, `Flutter/lib/features/partnership/widgets/partner_invite_email_dialog.dart:6-9,75-91`, `Flutter/lib/features/partnership/widgets/partner_invite_dialog.dart:39-62,79-96` (existing-account invitation), `Flutter/lib/features/auth/auth_state.dart:566-579`, `Flutter/lib/core/network/api_service.dart:520-529`, `Backend/features/auth/auth.controller.js:227-238`, `Backend/core/errors/AppError.js:22-29` (`API-VALIDATION-002`), `Backend/test/auth.routes.test.js:647-701`, `supabase/schemas/public/tables/users.sql:1-10,23-40`, `Flutter/lib/core/error_handling/error_codes.dart:31-44,130-137`, `Flutter/lib/core/localization/intl_it.arb:317`, `Flutter/lib/core/localization/intl_en.arb:287`, `docs/features/partnership/doc.md`, `docs/audits/email.md`.
- **Defect**: `PartnerScreen` offers the account-invitation action whenever the user has no linked partner. The dialog accepts any email address, and `inviteUserController()` immediately calls `sendPartnerInviteEmail()`. Consequently, someone who already has a JustUS account can receive an email telling them to download the app and register again, instead of receiving a normal partnership request.
- **Fix**: before sending the email, check case-insensitively whether the address exists in `public.users`. If it does, reject the request with the existing `API-VALIDATION-002` error (HTTP 409), whose localized message already tells the sender that the email has a JustUS account and asks them to use the 6-character partnership code. Treat database lookup failures as `DB-READ-001` and never send the email when the check fails. Update the documentation to remove the previous decision that redundant invitations are harmless.
- **Acceptance**: an existing account's email is rejected without calling Resend and returns `API-VALIDATION-002`; the Flutter dialog displays the localized message. An email not registered in JustUS still receives exactly one invitation. A database lookup failure prevents sending and returns `DB-READ-001`. The existing email + 6-character code invitation flow continues working.

### 29.3 Fix partnership cancellation button overflow (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `ProfileScreen` builds the cancellation button with a `Row` containing an icon, fixed spacing, and an unconstrained `Text` widget. The Italian label `RICHIEDI LA CANCELLAZIONE DELLA PARTNERSHIP`, combined with `letterSpacing: 2`, exceeds the available width on narrow screens. The reported runtime error confirms a 99-pixel horizontal overflow.
- **Sources**: User-reported runtime error; current-code review.
- **Files**: `Flutter/lib/features/settings/screens/profile_screen.dart`, `Flutter/test/profile_screen_test.dart`.
- **Defect**: The cancellation button does not constrain or wrap its label, causing the `Row` to overflow horizontally on smaller screens.
- **Fix**: Constrain the label with `Flexible` or `Expanded`, allow it to wrap, and keep the icon and text centered. Preserve the existing button styling and localized label.
- **Acceptance**: The button displays without overflow on narrow and standard screen widths, remains fully visible and tappable, and still opens the confirmation dialog. Add a widget test using a narrow viewport and verify that no layout exception occurs.

### 29.4 Prevent duplicate installation-id requests when changing notification preferences (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `InstallationIdService.getInstallationId()` calls `FirebaseMessaging.instance.register()` and waits for the resulting `onRegistered` event. At the same time, `AuthState.init()` subscribes to that event and independently calls `_authRepo.updateInstallationId()`. The explicit `_registerInstallationId()` flow also calls `_authRepo.updateInstallationId()` after receiving the FID. Since `ProfileScreen` invokes this flow when the notification toggle changes, a single toggle can trigger two identical POST requests. The existing `notification_preference_sync_test.dart` covers concurrent toggle changes but does not simulate the FCM registration event.
- **Sources**: Current-code review; user-reported duplicate API requests.
- **Files**: `Flutter/lib/features/auth/auth_state.dart`, `Flutter/lib/features/auth/installation_id_service.dart`, `Flutter/lib/features/settings/screens/profile_screen.dart`, `Flutter/test/notification_preference_sync_test.dart`, `docs/app/notifications/doc.md`.
- **Defect**: Explicit FID registration and the persistent `onRegistered` listener both persist the same installation ID, causing duplicate backend requests.
- **Fix**: Ensure that an FID obtained during an explicit registration flow is persisted only once. Keep the `onRegistered` listener for independent FID changes, without allowing it to duplicate an update already handled by `_registerInstallationId()`. Preserve the existing serialization of rapid notification-toggle changes and the latest-preference behavior.
- **Acceptance**: A single notification toggle produces exactly one `POST /api/v1/auth/installation-id`. Independent FID changes still trigger registration, rapid consecutive toggles remain serialized, and the final `notifications_enabled` value matches the last switch position. Add regression tests covering both explicit registration events and independent FID changes.

## Phase 30 — Games

### 30.1 Prevent GameScreen empty-state flicker on cold start (🟢 LOW)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `GameState._noQuestionAvailable` is initialized to `false`, and `clear()` resets it to `false` as well. On a cold start with no cached question, `GameScreen` therefore initially displays `game_allCaughtUp` (`Pronti per una nuova domanda?`). When the background `fetchActiveQuestion()` returns `null`, `_noQuestionAvailable` becomes `true` and the UI switches to `game_noQuestionAvailable` (`Nessuna domanda disponibile`), causing the reported flicker.
- **Sources**: Current-code review.
- **Files**: `Flutter/lib/features/games/game_state.dart`, `Flutter/test/game_state_test.dart`.
- **Defect**: The initial empty state incorrectly assumes the couple has already completed a game, before the first active-question fetch has established the actual state.
- **Fix**: Initialize `_noQuestionAvailable` to `true` and preserve that default when clearing the game state. Set it to `false` when an active question is successfully loaded or created. Keep the existing `game_allCaughtUp` behavior after a question is completed during the current session.
- **Acceptance**: A cold start with no cached question immediately displays `Nessuna domanda disponibile`, without first displaying `Pronti per una nuova domanda?`. A remotely loaded or newly created active question replaces the empty state correctly. Completing a question during the current session still displays `Pronti per una nuova domanda?`. Add regression tests for initial state, `clear()`, and these transitions.

### 30.2 Stop replaying previously answered game questions (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `game_pick_question.sql` prioritizes locale order before checking whether a question was already played. When all questions in the preferred locale have been used, it can select a previously played question even if the fallback locale still has unused questions. When every question is used, it continues selecting old questions instead of returning `NULL`. The existing SQL test explicitly expects this replay behavior in test C.
- **Sources**: Current-code review; `supabase/test/game_pick_question.test.sql`.
- **Files**: `supabase/schemas/public/functions/game_pick_question.sql`, `supabase/test/game_pick_question.test.sql`, `docs/features/game/doc.md`.
- **Defect**: The question-selection function allows the same question to be assigned repeatedly to the same partnership, creating an endless cycle after the available catalogue has been completed.
- **Fix**: Exclude every `question_code` already used by the partnership, regardless of locale. Select only unused questions across the entire locale fallback chain, preferring the requested locale when multiple unused choices exist. Return `NULL` when no unused questions remain. Update the SQL tests and remove the documented replay fallback.
- **Acceptance**: A partnership never receives the same question code twice. Exhausting the preferred locale correctly falls back to unused questions in another supported locale. Once all available question codes have been used, the selection function returns `NULL` without creating another game.

### 30.3 Show an explicit all-questions-completed state (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `GameState` uses a single `_noQuestionAvailable` boolean for different situations. Both `fetchActiveQuestion()` returning no active question and `fetchNewGameQuestion()` returning `NULL` set this flag. `GameScreen` consequently cannot distinguish an empty question catalogue from a partnership that has completed every available question.
- **Sources**: Current-code review; agreed UI behavior.
- **Files**: `Flutter/lib/features/games/game_question_bank_repository.dart`, `Flutter/lib/features/games/game_repository.dart`, `Flutter/lib/features/games/game_state.dart`, `Flutter/lib/features/games/screens/game_screen.dart`, `Flutter/lib/core/localization/intl_it.arb`, `Flutter/lib/core/localization/intl_en.arb`, `Flutter/test/game_state_test.dart`.
- **Defect**: The UI does not represent question exhaustion separately, and can continue offering the `Nuova domanda` action even when the partnership has no unused questions.
- **Fix**: Introduce a distinct `allQuestionsCompleted` state and check question availability when loading the Game screen and after an unsuccessful new-question request. Preserve the existing empty-catalog state separately. When all questions are completed, display `Avete terminato tutte le domande, attendete nuovi aggiornamenti.` and hide the `Nuova domanda` button. Recheck availability on screen refresh so newly added questions become available without requiring an app update. Do not mark the catalogue as exhausted when the availability request fails.
- **Acceptance**: When unused questions remain, the existing `Pronti per una nuova domanda?` state and action remain available. When all questions have been completed, the new message is displayed and no further question can be requested. An actually empty catalogue retains its separate message, and newly added questions restore the normal flow after refreshing.

## Phase 31 — Mood, Bucket List & Drive

**### 31.1 Shorten the Italian Bucket List title (🟢 LOW)**
- [ ] **Status: 🔴 OPEN** — The Italian translation `La nostra lista dei desideri` is too long for the available UI space.
- **Sources**: `Flutter/lib/core/localization/intl_it.arb` (`home_bucketListTitle`, `bucket_title`), `Flutter/lib/features/home/screens/homepage_screen.dart:443`, `Flutter/lib/features/bucket_list/screens/bucket_list_screen.dart` (header).
- **Files**: `Flutter/lib/core/localization/intl_it.arb`, `Flutter/lib/core/localization/generated/app_localizations_it.dart`, `Flutter/lib/core/localization/generated/app_localizations.dart`, `docs/features/bucket-list/doc.md`.
- **Defect**:
  - The Italian title `La nostra lista dei desideri` is unnecessarily long and can compromise the layout in the Home section and Bucket List screen header.
- **Fix**:
  - Replace `La nostra lista dei desideri` with `I nostri sogni` in both `home_bucketListTitle` and `bucket_title`.
  - Regenerate the localization files using the existing localization generation workflow.
  - Keep the English translation and all other locales unchanged.
- **Acceptance**:
  - Both the Home section and Bucket List screen display `I nostri sogni` in Italian.
  - The shorter title fits the existing layouts without overflow.
  - Other languages remain unchanged.

### 31.2 Prevent invalid date labels when adding the first mood (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `MoodState.updateMood()` inserts an optimistic `MoodEntry` with `createdAt: previousTimestamp ?? ''`. When adding the first mood, `previousTimestamp` is `null`, producing an invalid empty timestamp. `EmojiPickerSheet` calls `updateMood()` using `unawaited()` and closes immediately, so this provisional entry can appear before the server returns the actual timestamp. `MoodScreen._buildTimelineItem()` displays `mood_noneSet` whenever the timestamp cannot be parsed.
- **Sources**: User-reported behavior; current-code review.
- **Files**: `Flutter/lib/features/mood/mood_state.dart`, `Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart`, `Flutter/lib/features/mood/screens/mood_screen.dart`, `Flutter/test/mood_state_test.dart`, `Flutter/test/mood_screen_test.dart`.
- **Defect**: The optimistic timeline entry has no valid date when the user adds their first mood, causing the timeline to display `Nessun mood inserito` next to an emoji that was just selected.
- **Fix**: Stop inserting an invalid provisional entry into the timeline. Keep the current mood and recent emojis optimistic, but add the timeline entry only after the repository returns the server-confirmed `MoodEntry` with its actual timestamp. Preserve the existing rollback behavior when the update fails.
- **Acceptance**: Adding the first mood never displays `Nessun mood inserito` as its date. The timeline receives the new entry with the server timestamp after a successful update, and a failed update never leaves a phantom entry. Existing mood updates and timeline pagination continue working correctly.

### 31.3 Prevent unnecessary Favorites reloads (🟢 LOW)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: `FavoritesScreen.loadData()` schedules `DriveState.loadFavorites()` on every tab activation. `DriveState.loadFavorites()` always calls `DriveRepository.fetchFavoriteDriveItems()`, even when the favorites were already loaded. Unlike the main Drive list, favorites have no dedicated local cache or change-detection gate. The existing `drive_change_probe()` only reads `drive_items` and does not detect changes in `public.favorites`, so it cannot safely validate the favorites list by itself.
- **Sources**: User-reported network logs; current-code review.
- **Files**: `Flutter/lib/features/drive/screens/favorites_screen.dart`, `Flutter/lib/features/drive/drive_state.dart`, `Flutter/lib/features/drive/drive_repository.dart`, `Flutter/lib/core/local_storage/storage_service.dart`, `Flutter/test/drive_paging_test.dart`, `Flutter/test/drive_sync_test.dart`.
- **Defect**: Returning to Favorites always triggers a full `v_drive_dashboard` request, causing an unnecessary loading cycle even when the list has not changed.
- **Fix**: Add a persistent, partnership-scoped cache for favorites and a lightweight revalidation mechanism that detects changes in `public.favorites`. Restore cached favorites immediately and fetch the list again only when changes are detected or an explicit refresh is requested. Preserve independent pagination and optimistic favorite updates. Do not rely exclusively on `drive_change_probe()` unless it is extended to cover favorite changes.
- **Acceptance**: The first Favorites visit loads and caches the list. Returning without changes displays cached content without another full favorites request. When favorites change, the list refreshes correctly. Pull-to-refresh forces a full fetch, and pagination, adding and removing favorites continue working correctly.

## Known non-bugs & deliberate decisions

- **Shared media rate-limit bucket (40/user/min for reads, uploads and deletes)** — deliberate, recorded in `docs/audits/media-delete-audit.md` §F-5. Do not "fix" without a product decision.
- **15 MB pre-compression upload cap** — deliberate (phase 5.4).
- **Fingerprint survives logout** — deliberate (phase 10.1); `docs/app/storage-and-caching/doc.md:51,207` is correct.
- **Notification preference is device-level across accounts** — documented in `storage_service.dart:446-452`; distinct from the background-delivery bug archived as 19.7.
- **Homepage does not use `TabScreenMixin`; Profile is not wired to realtime** — documented in `docs/app/architecture/doc.md:460-464` and `docs/app/state-management/doc.md:140`.
- **`debug_` table/function prefix** — deliberate (phase 10.17).
- **Nonce fail-open, `session_is_live` fail-open, orphan-sweep read-failure skip** — accepted decisions #36, #37, #45 in `docs/fixing-phase-log.md`.
- **Authenticated `SECURITY DEFINER` partnership read RPCs** — the live advisor flags `partnership_get_cancellation()` and `partnership_get_pending_invitations()`, but both functions filter through `user_current_id()` (`users.auth_id = auth.uid()`) and return only the caller's own partnership rows; anonymous execution is revoked. Do not revoke without preserving the client flow.
- **Supabase RLS status** — a read-only live catalog query found RLS enabled on all 26 public tables. This does not replace per-policy behavior tests.
- **Unused-index advisor notices** — not treated as removal tasks: low/zero usage on this project's current traffic is not proof an index is dead.

---

## Not confirmed (do not track as fixes until reproduced)

S6 mood recent chips · S7 first drive tile highlight · S9 302 forwards `Authorization` to R2 · S11 cancellation cleanup race · S12 timeout double-response · S13 idempotency caches errors · S14 custom rate-limit window · S15 logger stdout before sanitization · S16 pre-relationship moods · S17 crafted `drive_items` key (closed by 17.2)· S19 hosted SQL test privileges · S20 `game_questions` FKs without `ON DELETE`
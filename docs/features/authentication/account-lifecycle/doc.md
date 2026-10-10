# Authentication Account Lifecycle - JustUS

## Overview

This document provides a detailed reverse-engineered analysis of the **Authentication Account Lifecycle** in the JustUS application. It covers password modifications, push device token registration and hardware identification, logout protocols, local and realtime state cleanup, state machine transitions, and account wipe effects.

Key architectural boundaries:
- **Password Management**: `ChangePasswordScreen` re-authenticates the current password, then calls `supabase.auth.updateUser(password:)`; every other session of the account is then revoked with `SignOutScope.others`.
- **Push Device Identity**: Cross-platform resolution differentiating FCM push tokens (Android/iOS/Web) from persistent hardware UUID fingerprints (Windows Desktop), backed by PostgreSQL `user_devices` upserts and a logout-time revocation delete.
- **Logout Protocol**: Multi-stage cleanup — best-effort push-token revoke, `FlutterSecureStorage`, `SharedPreferences`, in-memory `ApiService` headers, and Supabase Realtime channels (`RealtimeSyncService`).
- **Account Wipe**: Debug operation clearing application domain data (`debug_wipe_user_data` procedure, `StorageService.clearAppCache()`, `CacheService.clearAll()`, `emptyAppMediaCaches()`) while maintaining active session authentication.

---

## Password Change

### Implementation Analysis

- UI Screen File: [change_password_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart)
- Route: `/change-password` declared in [main.dart:142](file:///f:/JustUS/Flutter/lib/main.dart#L142) and pushed from `ProfileScreen` ([profile_screen.dart:321](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart#L321)).
- Form Controllers: `_oldController`, `_newController`, `_confirmController`.

### Current Behavior

The change-password flow is implemented end to end, client → Supabase Auth (no backend route is involved):

1. `ChangePasswordScreen` validates required/format/confirmation locally, then calls `AuthState.changePassword(currentPassword:, newPassword:)` with a loading state on the `VPButton`.
2. `AuthState.changePassword` ([auth_state.dart:449-520](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L449-L520)) re-authenticates the current password with `signInWithPassword` (fresh Turnstile token included) before changing anything. A wrong current password maps to `ErrorCodes.authFailCurrent` and surfaces the screen's own message instead of the generic reauth dialog.
3. On success it calls `AuthRepository.changePassword` ([auth_repository.dart:96-104](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L96-L104)) → `sbClient.auth.updateUser(UserAttributes(password: …))`.
4. The write is followed by the other-session revoke (see below).
5. Failures are surfaced by `ErrorHandler`; success shows a localized snackbar and pops the screen.

The recovery flow (`ResetPasswordScreen` → `AuthState.updatePasswordNew` ([auth_state.dart:429-448](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L429-L448)) → `AuthRepository.updatePasswordWithoutCurrent` ([auth_repository.dart:71-78](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L71-L78))) writes the password without a current-password check and performs the same revokes.

### Other-Session Revocation

Both password writes end with `AuthState._revokeOtherSessions()` ([auth_state.dart:783-794](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L783-L794)), which calls `AuthRepository.revokeOtherSessions()` ([auth_repository.dart:97-99](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L97-L99)) → `sbClient.auth.signOut(scope: SignOutScope.others)`, immediately followed by `AuthState._revokeOtherDeviceTokens()` ([auth_state.dart:797-817](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L797-L817)) → `AuthRepository.revokeOtherDeviceTokens()` ([auth_repository.dart:85-89](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L85-L89)) → `POST /api/v1/auth/device-token-revoke-all`.

- **Why `others`, not `global`**: `SignOutScope.others` revokes every session of the account **except the one the request is issued with**, so the device that changed the password stays logged in and the SDK fires no `signedOut` event (the teardown in [Logout](#logout) is not triggered). `global` would have logged the current device out as well.
- **What it kills**: Supabase issues `DELETE FROM auth.sessions WHERE id != <current>`, so both the other refresh tokens *and* their already-issued access tokens stop working. GoTrue resolves the JWT's `session_id` on every request, so a deleted session is rejected at once (`session_not_found`) rather than at token expiry — the backend turns that into `AUTH-FAIL-001` (`401`), which is the app's normal "session gone" path.
- **Best-effort, by design**: the password is already changed when the revoke runs, so a failure here is logged and never turns a successful change into a failure:

| Failure | Behavior |
|---|---|
| Offline / DNS / SocketException | caught and logged; the user still gets the success feedback |
| Hanging request | cut off by a 5 s timeout (`sessionRevokeTimeout`), success feedback follows |
| `401` / `403` / `404` from Supabase | swallowed by the SDK itself (it treats these as "already gone") |
| No live session | the SDK sends nothing, so no revoke is attempted |

- **Push registrations die with the sessions**: after revoking the other sessions, the client keeps its **own** device token and asks the backend to delete every *other* `user_devices` row (`POST /api/v1/auth/device-token-revoke-all`, middleware stack `authenticated()` → `limited(authRateLimit)` → `signed("auth-device-token-revoke-all")` → `validated({ body: revokeDeviceTokenSchema })`, same rate-limit bucket as the logout revoke). The delete is scoped `user_id = me AND device_token != mine`, so the caller's own pushes keep flowing. The deleted rows are **durable**: `POST /api/v1/auth/device-token` is `authenticated()`, and the other devices' Supabase sessions are already dead, so a revoked device gets `401` and cannot re-register. The same best-effort contract applies — a failure is logged and never fails the change, and a 5 s timeout (`sessionRevokeTimeout`) bounds it.
- **Residual — push registrations survive only when the revoke-all cannot land**: if the local token is unresolvable the call is skipped outright (mirroring the logout revoke's `UNKNOWN_DEVICE_TOKEN` guard), and an offline call or a crash between the two revokes leaves the rows in place. Those rows then stop receiving pushes only when the device itself hits a `401` (and runs the [logout revoke](#logout)), or when the 30-day retention sweep ages them out.
- **Residual — the local token mirror is stale**: the re-auth `signInWithPassword` creates a *new* session on this device, and the subsequent `others` revoke deletes the older one that `AuthState._accessToken` / `StorageService` still hold. Harmless: every authenticated request and the Realtime JWT are read from the live SDK session, and the stale copy only feeds the `isLoggedIn` check.

---

## Device Token Registration

JustUS manages hardware device identities and push notification tokens across Android, iOS, Web, and Windows Desktop.

### Token Resolution by Platform

File: [device_token_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/device_token_service.dart)

```dart
static Future<String> getDeviceToken() async {
  try {
    if (supportsFcm) { // Android, iOS, Web
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) return fcmToken;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      return await getDeviceFingerprint(); // Persistent Windows UUID
    }
  } catch (e) { ... }
  return 'UNKNOWN_DEVICE_TOKEN';
}
```

1. **FCM Mobile & Web Tokens (Android / iOS / Web)**:
   - Evaluates `supportsFcm` (`Android`, `iOS`, or `Web`).
   - Fetches dynamic FCM token from `FirebaseMessaging.instance.getToken()`.
   - Listens to token refresh events via `FirebaseMessaging.instance.onTokenRefresh` stream, auto-updating the backend when FCM rotates tokens.
2. **Desktop Hardware UUID (Windows)**:
   - FCM is not supported on Windows Desktop in this application.
   - `getDeviceToken()` returns `getDeviceFingerprint()`, which reads/generates a persistent UUID stored in secure storage (`StorageService.getOrCreateDeviceFingerprint()`).
   - **Verification**: The desktop UUID is a hardware device fingerprint for session identification, **not** an FCM push notification token.

### Backend Registration & Database Persistence

- Endpoint: `POST /api/v1/auth/device-token`
- Controller: `updateDeviceToken` in [auth.controller.js:18-55](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L18-L55)
- Middleware Stack: `authenticated()`, `limited(authRateLimit)`, `signed("auth-device-token")`, `validated({ body: updateDeviceTokenSchema })`.

#### Database Upsert Specification
- Target Table: `user_devices` in PostgreSQL.
- Conflict Target: `device_token` (`onConflict: "device_token"`).
- Database Write Query:
  ```javascript
  await adminSupabase.from("user_devices").upsert(
    {
      user_id: userId,
      device_token: deviceToken,
      user_agent: clientUserAgent,
      device_type: deviceType,
      last_ip: lastIp,
      ...(locale && { locale }),
    },
    { onConflict: "device_token" }
  );
  ```

#### Multi-User Device Replacement Behavior
Because `onConflict: "device_token"` is used, if User A logs out and User B logs in on the **same physical device**:
- User B's login triggers `updateDeviceToken()`.
- The `user_devices` table row matching `device_token` is updated to set `user_id = userB.profileId`.
- This automatically transfers push notification targeting to User B.

### Token Revocation

The registration is removed again when the account logs out, so a device that is later handed to someone else cannot keep receiving the previous account's pushes.

- Endpoint: `POST /api/v1/auth/device-token-revoke`
- Controller: `revokeDeviceToken` in [auth.controller.js:56-77](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L56-L77)
- Middleware Stack: `authenticated()`, `limited(authRateLimit)`, `signed("auth-device-token-revoke")`, `validated({ body: revokeDeviceTokenSchema })`
- Database Write Query:
  ```javascript
  await adminSupabase
    .from("user_devices")
    .delete()
    .eq("device_token", deviceToken)
    .eq("user_id", userId);
  ```
- **Hard delete, not a deactivation flag**: `user_devices` has no `is_active`/`revoked_at` column and notification targeting reads every row for the user, so removing the row *is* the deactivation. Audit rows survive: `logs_api_access`, `logs_api_errors` and `logs_security_events` reference `user_devices(id)` `ON DELETE SET NULL`, so the delete nulls the pointer instead of cascading.
- **Scoped to the caller**: because `device_token` is `UNIQUE`, an unscoped delete could remove a row another account has already re-registered on this device. The `user_id` predicate makes a late logout harmless.
- Idempotent — revoking an already-removed token answers `200 { success: true }`; a DB failure raises `500 DB-WRITE-001`.
- Client side: `AuthRepository.revokeDeviceToken()` → `ApiService.revokeDeviceToken()`, issued by `AuthState._revokeDeviceToken()` (see [Logout](#logout)).

---

## Logout

The logout protocol performs a multi-layer tear-down of local credentials, storage caches, in-memory headers, and realtime WebSocket channels.

### Execution Sequence

Logout is initiated by `LogoutUtils.performLogout(context)` ([logout_utils.dart:39-48](file:///f:/JustUS/Flutter/lib/shared/utils/auth/logout_utils.dart#L39-L48)), which delegates to `AuthState.logout()` ([auth_state.dart:730-747](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L730-L747)):

```
Logout Initiated (Profile / Partner Screen)
   │
   ├── 0. Push Token Revoke (best-effort, POST /api/v1/auth/device-token-revoke)
   │        └── deletes this device's user_devices row before the session dies
   │
   ├── 1. Supabase Auth Sign-Out (sbClient.auth.signOut())
   │
   ├── 2. Checkpoint Cache Purge (CacheService.clearAll())
   │
   ├── 3. Storage & Secret Wipe (StorageService.clearAll())
   │        ├── SharedPreferences.clear()
   │        └── FlutterSecureStorage.deleteAll()
   │
   ├── 4. ApiService Header Cache Reset (ApiService.clearHeadersCache())
   │
   ├── 5. AuthState Memory Reset (_accessToken, _refreshToken, _userId, _partnerId -> null)
   │
   ├── 6. AuthState.notifyListeners()
   │        │
   │        └── Triggers RealtimeSyncScope -> RealtimeSyncService.configure(userId: null)
   │               └── RealtimeSyncConnection.unsubscribe() closes WebSocket channel
   │
   └── 7. UI Stack Replacement (Navigator.pushAndRemoveUntil -> LoginScreen)
```

#### Why the revoke runs first

`AuthState._revokeDeviceToken()` ([auth_state.dart:753-768](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L753-L768)) is the only network step of the teardown, so it has to run while the JWT, the HMAC binding secret and the device fingerprint are still in storage — the route is `authenticated()` + `signed()`. It is strictly best-effort and cannot affect the local logout:

| Failure | Behavior |
|---|---|
| No session (`isLoggedIn` false) | skipped entirely |
| Token unresolvable (`UNKNOWN_DEVICE_TOKEN`) | skipped entirely |
| Offline / DNS / SocketException | caught and logged; teardown continues |
| Hanging request | cut off by a 5 s timeout (`deviceRevokeTimeout`), teardown continues |
| `401` after a failed refresh | reported as a `401` error result, **without** firing `ApiService.onSessionExpired` — that callback *is* `logout()`, so escalating here would re-enter the teardown |

If the revoke never lands (offline logout, session already expired, app killed mid-teardown), the row stays in `user_devices` until re-registered or deleted by the periodic 30-day retention sweep (`sweepStaleUserDevices` in `retentionJob.js`), which purges rows whose `updated_at` timestamp predates 30 days (`USER_DEVICE_RETENTION_DAYS = 30`).

---

## Authentication State Lifecycle

### State Transition Graph

```
                   ┌──────────────────────────┐
                   │     UNAUTHENTICATED      │
                   └────────────┬─────────────┘
                                │ Login / Register Success
                                ▼
                   ┌──────────────────────────┐
                   │       AUTHENTICATED      │
                   └──────┬────────────▲──────┘
                          │            │
             401 Detected │            │ Token Refresh Success
                          ▼            │
                   ┌──────────────────────────┐
                   │        REFRESHING        │
                   └──────┬───────────────────┘
                          │ Refresh Failed / Both Tokens Invalid
                          ▼
                   ┌──────────────────────────┐
                   │    SESSION EXPIRED       │
                   └──────────┬───────────────┘
                               │ AuthState.logout() + reauth dialog redirect
                              ▼
                   ┌──────────────────────────┐
                   │     UNAUTHENTICATED      │
                   └──────────────────────────┘
```

### Transition Specifications

1. **Unauthenticated → Authenticated**:
   - Triggered by `AuthState.login()` or `register()`.
   - Populates `StorageService`, initializes `_accessToken`, syncs backend session via `/auth/session-sync`, registers device token, and fetches active partnership status.
2. **Authenticated → Refreshing → Authenticated**:
   - Triggered when `ApiService._safeCall` receives HTTP 401.
   - Delegates to the Supabase SDK (`auth.refreshSession()`), the single refresh path; if the SDK already refreshed the live session (different token than the failed request), the redundant call is skipped.
   - The `tokenRefreshed` listener persists the new access+refresh pair to `StorageService`; the original request is retried with `isRetry = true`. If the refresh fails, `logout()` runs and the synthetic `"401"` code is `requiresReauth`, so the reauth dialog opens and redirects to `LoginScreen` (todo# 1.3).
3. **Authenticated → Logout → Unauthenticated**:
   - User confirms logout dialog.
   - Revokes the device push token (best-effort), clears storage, invalidates session headers, unsubscribes Realtime channel, and replaces stack with `LoginScreen`.
4. **Authenticated → Account Wipe → Authenticated**:
   - Triggered via `ProfileState.wipeAppData()` ([profile_state.dart:139](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart#L139)).
   - Invokes backend `POST /api/v1/user/wipe` (executing PostgreSQL procedure `debug_wipe_user_data`).
   - Clears local caches via `StorageService.clearAppCache()` + `CacheService.clearAll()` (checkpoints) + `emptyAppMediaCaches()` (media file stores).
   - **Authentication Impact**: User session and security tokens remain completely active. Only domain data (drive files, moods, game history, miss-you counts) is erased from the database and local storage.

---

## Session Effects

- **Supabase Session**: Calling `sbClient.auth.signOut()` revokes the local Supabase session.
- **HMAC Request Signing**: `StorageService.clearAll()` deletes `request_binding_secret` from `FlutterSecureStorage`. `ApiService.clearHeadersCache()` sets `_cachedRequestBindingSecret = null`.
- **Device Fingerprint**: Cleared from `FlutterSecureStorage` during logout, forcing regeneration of a new device UUID on subsequent logins.
- **Push Registration**: `POST /api/v1/auth/device-token-revoke` deletes this device's `user_devices` row before the session is dropped, so server-initiated pushes stop for the logged-out account. Best-effort — see [Why the revoke runs first](#why-the-revoke-runs-first).

---

## Local Storage Cleanup

Concrete inventory of storage keys cleared versus surviving during `logout()`:

### Secure Storage (`FlutterSecureStorage.deleteAll()`)

| Key Name | Description | Cleared on Logout? |
|---|---|---|
| `access_token` | Supabase Bearer Token | **YES** |
| `refresh_token` | Supabase Refresh Token | **YES** |
| `user_id` | Database Integer User ID | **YES** |
| `partner_id` | Database Integer Partner ID | **YES** |
| `partnership_id` | Database Integer Partnership ID | **YES** |
| `device_fingerprint` | Client Device UUID | **YES** |
| `request_binding_secret` | HMAC Signing Secret | **YES** |

### SharedPreferences (`SharedPreferences.clear()`)

| Key Name | Description | Cleared on Logout? |
|---|---|---|
| `username` | User Display Name | **YES** |
| `partner_display_name` | Partner Display Name | **YES** |
| `miss_you` | Miss You Count | **YES** |
| `bucket_list` | Cached Bucket Items | **YES** |
| `game_question` | Cached Game Question | **YES** |
| `game_history` | Cached Game History | **YES** |
| `drive_cache` | Cached Drive Items | **YES** |
| `user_profile` | Cached User Profile JSON | **YES** |
| `partner_profile` | Cached Partner Profile JSON | **YES** |
| `profile_pic_version` | Profile Picture Cache Version | **YES** |
| `recent_emojis` | Used Emoji List | **YES** |
| `mood_me` / `mood_partner` | Mood Emojis | **YES** |
| `mood_timeline` | Mood Timeline Entries | **YES** |
| `chk_*` (All Keys) | Cache Checkpoints | **YES** (`CacheService.clearAll()`) |
| `app_language_code` | Selected App Language | **NO** — device-level preference; `StorageService.clearAll()` re-persists it after `p.clear()` (F-SC4 resolved) |

### Feature-State Cleanup on Logout

`AuthState.logout()` wipes secure storage (`FlutterSecureStorage.deleteAll()`) and SharedPreferences (`SharedPreferences.clear()`), then calls the `onClearFeatureStates` hook wired in `RealtimeSyncScope` (`realtime_sync_scope.dart:46-53`). The hook clears the eager Provider singletons — `MoodState`, `HomepageState`, `BucketState`, `GameState`, `DriveState`, `ProfileState` — so no in-memory field survives into a second account in the same process.

Two keys deliberately **survive** logout: `app_language_code` and the theme mode (`app_theme_mode`). They are user preferences, not account data, and are re-applied at the next login.

---

## Realtime Cleanup

- **Scope Management**: Managed by `RealtimeSyncScope` in [realtime_sync_scope.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_scope.dart).
- **Logout Behavior**:
  - `AuthState.logout()` resets `_userId = null` and calls `notifyListeners()`.
  - `RealtimeSyncScope` detects the update and passes `userId: null` to `RealtimeSyncService.configure()`.
  - `RealtimeSyncService.configure()` (realtime_sync_service.dart) executes `unawaited(_connection.unsubscribe())` — closing the active WebSocket channel (`justus-sync-{userId}-{gen}`) and canceling background timers.

---

## Notification Cleanup

- **Backend Row**: `logout()` deletes this device's row from `user_devices` via `POST /api/v1/auth/device-token-revoke` (`AuthState._revokeDeviceToken()`), scoped to the logged-out `user_id`. Once the row is gone the backend has no token to target for that account, so server-initiated pushes stop arriving on the device.
- **Local FCM Token**: `logout()` still does **not** call `FirebaseMessaging.instance.deleteToken()`; the FCM registration itself stays valid on the device. That is harmless for targeting — with no `user_devices` row nothing is sent — and it keeps the next login cheap, since the same token is re-registered by the upsert. The token is re-registered at app start, at login, and on `onTokenRefresh`.
- **Best-Effort**: an offline (or already-expired-session) logout skips the revoke and leaves the row behind. It self-heals on the next successful login from that device; until then a stale row can still receive pushes for a logged-out account.

---

## Error Handling

- **Logout Exceptions**: `AuthState.logout()` executes cleanup steps (`revokeDeviceToken()`, `signOut()`, `clearAll()`, `clearHeadersCache()`) sequentially without throwing errors if individual sub-tasks encounter network or storage issues, ensuring local logout completion. The revoke is additionally bounded by a 5 s timeout.
- **Password Write Exceptions**: `AuthState._revokeOtherSessions()` swallows every error (and is bounded by a 5 s timeout), so the result reported for the change itself is never influenced by the revoke. The `updateUser` failures above it are what turn into `ChangePasswordResult.failure` / `false` — and in that case no revoke is attempted at all, since the password was not written.

---

## Edge Cases

1. **Logout During Active HTTP Requests**: In-flight requests failing after `logout()` are handled by `_safeCall`. Since `StorageService` is already wiped, token refresh fails and no re-authentication state is modified.
2. **Account Wipe Operating Without Logout**: `ProfileState.wipeAppData()` executes database purging without touching session tokens or clearing `AuthState`, allowing seamless app usage post-wipe. The push registration survives the wipe, which is correct: the session stays active.
3. **Password Change on a Device with a Pre-existing Session**: the re-auth inside `changePassword` opens a *second* session for this same device, so the `others` revoke deletes the session the app was using before the change. Only its copy in `AuthState._accessToken` / `StorageService` is affected — requests and the Realtime JWT read the live SDK session, so nothing breaks, but those stored values are dead tokens until the next refresh.
4. **Password Change While Other Devices Are Logged In**: those devices lose API access immediately (their `auth.sessions` rows are gone), and their `user_devices` rows are deleted at once by the revoke-all (`POST /api/v1/auth/device-token-revoke-all`), so server-initiated pushes stop with the sessions — see [Other-Session Revocation](#other-session-revocation). If that best-effort call cannot land, they keep receiving pushes until they next hit a `401` and run the logout revoke, or until the 30-day retention sweep.
5. **No Session Available for the Revoke**: `updatePasswordNew` runs from a recovery deep link; when no live session exists (link opened in a client that never resolved it) the SDK sends no revoke, so the other sessions survive. The password change itself still succeeds.

---

## Files and Functions

### Flutter Frontend
- [change_password_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart): Password change UI form.
- [reset_password_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/reset_password_screen.dart): Post-recovery password form (`AuthState.updatePasswordNew`).
- [device_token_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/device_token_service.dart): Platform token resolution `getDeviceToken()`, `getDeviceFingerprint()`.
- [logout_utils.dart](file:///f:/JustUS/Flutter/lib/shared/utils/auth/logout_utils.dart): Logout dialog and `performLogout()` helper.
- [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart): `logout()`, `_revokeDeviceToken()`, `_revokeOtherSessions()`, `_revokeOtherDeviceTokens()`, `updateDeviceToken()`.
- [auth_repository.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart): `updateDeviceToken()`, `revokeDeviceToken()`, `revokeOtherSessions()`, `revokeOtherDeviceTokens()`.
- [storage_service.dart](file:///f:/JustUS/Flutter/lib/core/local_storage/storage_service.dart): Storage purge `clearAll()`, `clearAppCache()`.
- [cache_service.dart](file:///f:/JustUS/Flutter/lib/core/local_storage/cache_service.dart): Checkpoint cache purge `clearAll()`.
- [realtime_connection.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_connection.dart): Channel teardown `unsubscribe()`, lifecycle.
- [realtime_sync_service.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart): Facade `configure()`, `dispose()`.
- [profile_state.dart](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart): `wipeAppData()`.

### Backend Node.js
- [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js): Device token registration `updateDeviceToken()`, revocation `revokeDeviceToken()`, other-device revocation `revokeOtherDeviceTokens()`.
- [user.controller.js](file:///f:/JustUS/Backend/features/user/user.controller.js): Data wipe controller.

---

## Database Objects

- **Table `user_devices`**: PostgreSQL table storing `user_id`, `device_token`, `user_agent`, `device_type`, `last_ip`, `locale`. Primary conflict target: `device_token`. No active/revoked flag: deactivation is a row delete, and the `logs_api_access` / `logs_api_errors` / `logs_security_events` foreign keys are `ON DELETE SET NULL`.
- **Procedure `debug_wipe_user_data`**: Stored procedure executed during account wipe to erase user domain records.

---

## Implementation Status

| Feature / Lifecycle Stage | Implementation Status | Notes |
|---|---|---|
| Change Password Flow | **IMPLEMENTED** | Re-authenticates the current password, then `updateUser(password:)`; every other session is revoked with `SignOutScope.others` and every other `user_devices` row with `POST /api/v1/auth/device-token-revoke-all` (both best-effort, 5 s cap) |
| FCM Mobile Device Token Registration | **IMPLEMENTED** | `DeviceTokenService` & `POST /api/v1/auth/device-token` |
| Windows Desktop Identification | **IMPLEMENTED** | Uses persistent UUID device fingerprint (Not push) |
| Device Token Reassignment | **IMPLEMENTED** | Database `upsert` on conflict `device_token` |
| Local Storage Purge on Logout | **IMPLEMENTED** | Clears `FlutterSecureStorage` and `SharedPreferences` |
| Realtime Teardown on Logout | **IMPLEMENTED** | Unsubscribes WebSocket channel via `RealtimeSyncScope` |
| In-Memory State Provider Cleanup | **IMPLEMENTED** | `onClearFeatureStates` hook wired in `RealtimeSyncScope` resets the six provider singletons |
| Device Token Unregistration | **IMPLEMENTED** | `AuthState._revokeDeviceToken()` → `POST /api/v1/auth/device-token-revoke` (best-effort, 5 s cap) |
| Other-Device Push Registration Revocation on Password Write | **IMPLEMENTED** | `AuthState._revokeOtherDeviceTokens()` → `POST /api/v1/auth/device-token-revoke-all` (best-effort, 5 s cap) |
| Account Wipe (Debug Data Erase) | **IMPLEMENTED** | `debug_wipe_user_data` procedure |

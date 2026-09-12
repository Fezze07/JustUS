# Authentication Account Lifecycle - JustUS

## Overview

This document provides a detailed reverse-engineered analysis of the **Authentication Account Lifecycle** in the JustUS application. It covers password modifications, push device token registration and hardware identification, logout protocols, local and realtime state cleanup, state machine transitions, and account wipe effects.

Key architectural boundaries:
- **Password Management**: Client UI stub vs Supabase Auth API capabilities.
- **Push Device Identity**: Cross-platform resolution differentiating FCM push tokens (Android/iOS/Web) from persistent hardware UUID fingerprints (Windows Desktop), backed by PostgreSQL `user_devices` upserts.
- **Logout Protocol**: Multi-stage cleanup purging `FlutterSecureStorage`, `SharedPreferences`, in-memory `ApiService` headers, and Supabase Realtime channels (`RealtimeSyncService`).
- **Account Wipe**: Debug operation clearing application domain data (`debug_wipe_user_data` procedure & `StorageService.clearAppCache()`) while maintaining active session authentication.

---

## Password Change

### Implementation Analysis

- UI Screen File: [change_password_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart)
- Route: `/change-password` declared in [main.dart:142](file:///f:/JustUS/Flutter/lib/main.dart#L142) and pushed from `ProfileScreen` ([profile_screen.dart:321](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart#L321)).
- Form Controllers: `_oldController`, `_newController`, `_confirmController`.

### CRITICAL FINDING: Stub Implementation

Inspection of `ChangePasswordScreen._ChangePasswordScreenState` ([change_password_screen.dart:90-98](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart#L90-L98)) reveals that the password update functionality is a **pure UI stub**:

```dart
VPButton(
  label: context.loc.auth_updatePassword,
  onPressed: () {
    if (_formKey.currentState!.validate()) {
      // Logic to update password
      UIUtils.showSnackBar(context, context.loc.auth_passwordUpdated);
      Navigator.pop(context);
    }
  },
)
```

#### Empirical Password Change Audit Findings
1. **No API Call Execution**: Tapping "Update Password" validates the local Flutter `Form` widgets, displays a localized SnackBar ("Password updated!"), and pops the screen back to `ProfileScreen`. It **never invokes `AuthRepository.changePassword()`**, `AuthState`, backend API, or Supabase Auth.
2. **Dead Code Repository Method**: `AuthRepository.changePassword(currentPassword, newPassword)` exists in [auth_repository.dart:50-55](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L50-L55) calling `sbClient.auth.updateUser(UserAttributes(password: newPassword))`. However, this method is dead code and is never invoked anywhere in the codebase.
3. **No Current Password Verification**: The current password entered in `_oldController` is never verified against Supabase Auth.
4. **No Session Invalidation**: Because no password update request is sent to Supabase Auth, existing JWT tokens and refresh tokens remain completely active, and the account password remains unchanged in reality.

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

---

## Logout

The logout protocol performs a multi-layer tear-down of local credentials, storage caches, in-memory headers, and realtime WebSocket channels.

### Execution Sequence

Logout is initiated by `LogoutUtils.performLogout(context)` ([logout_utils.dart:39-48](file:///f:/JustUS/Flutter/lib/shared/utils/auth/logout_utils.dart#L39-L48)), which delegates to `AuthState.logout()` ([auth_state.dart:534-549](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L534-L549)):

```
Logout Initiated (Profile / Partner Screen)
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
   │               └── RealtimeSyncService._unsubscribe() closes WebSocket channel
   │
   └── 7. UI Stack Replacement (Navigator.pushAndRemoveUntil -> LoginScreen)
```

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
                              │ AuthState.logout()
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
   - Sets `_isRefreshing = true` and invokes `POST /api/v1/auth/refresh`.
   - Saves new access token to `StorageService`. Retries original request with `isRetry = true`.
3. **Authenticated → Logout → Unauthenticated**:
   - User confirms logout dialog.
   - Clears storage, invalidates session headers, unsubscribes Realtime channel, and replaces stack with `LoginScreen`.
4. **Authenticated → Account Wipe → Authenticated**:
   - Triggered via `ProfileState.wipeAppData()` ([profile_state.dart:139](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart#L139)).
   - Invokes backend `POST /api/v1/user/wipe` (executing PostgreSQL procedure `debug_wipe_user_data`).
   - Clears domain cache via `StorageService.clearAppCache()`.
   - **Authentication Impact**: User session and security tokens remain completely active. Only domain data (drive files, moods, game history, miss-you counts) is erased from the database and local storage.

---

## Session Effects

- **Supabase Session**: Calling `sbClient.auth.signOut()` revokes the local Supabase session.
- **HMAC Request Signing**: `StorageService.clearAll()` deletes `request_binding_secret` from `FlutterSecureStorage`. `ApiService.clearHeadersCache()` sets `_cachedRequestBindingSecret = null`.
- **Device Fingerprint**: Cleared from `FlutterSecureStorage` during logout, forcing regeneration of a new device UUID on subsequent logins.

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
| `game_matches` | Game Matches Count | **YES** |
| `game_question` | Cached Game Question | **YES** |
| `game_history` | Cached Game History | **YES** |
| `drive_cache` | Cached Drive Items | **YES** |
| `user_profile` | Cached User Profile JSON | **YES** |
| `partner_profile` | Cached Partner Profile JSON | **YES** |
| `profile_pic_version` | Profile Picture Timestamp | **YES** |
| `recent_emojis` | Used Emoji List | **YES** |
| `mood_me` / `mood_partner` | Mood Emojis | **YES** |
| `mood_timeline` | Mood Timeline Entries | **YES** |
| `chk_*` (All Keys) | Cache Checkpoints | **YES** (`CacheService.clearAll()`) |

### Surviving In-Memory Provider Data (BUG)

While `AuthState` and `StorageService` are completely wiped, **eager Provider singletons** created in `main.dart` (`ProfileState`, `PartnerState`, `DriveState`, `MoodState`, `BucketState`, `GameState`, `MissYouState`) are **not** reset during `logout()`. Their in-memory fields retain data from the previous account until a new user logs in and triggers fresh `loadData()` calls.

---

## Realtime Cleanup

- **Scope Management**: Managed by `RealtimeSyncScope` in [realtime_sync_scope.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_scope.dart).
- **Logout Behavior**:
  - `AuthState.logout()` resets `_userId = null` and calls `notifyListeners()`.
  - `RealtimeSyncScope` detects the update and passes `userId: null` to `RealtimeSyncService.configure()`.
  - `RealtimeSyncService.configure()` executes `unawaited(_unsubscribe())` ([realtime_sync_service.dart:138](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart#L138)), closing the active WebSocket channel (`justus-sync-{userId}-{gen}`) and canceling background timers.

---

## Notification Cleanup

- **FCM Token Status**: `logout()` does **not** call `FirebaseMessaging.instance.deleteToken()` or notify the backend to delete the token row from `user_devices`.
- **Impact**: The device token remains associated with `user_id` in PostgreSQL `user_devices` until another user logs in on the same device and updates the row.

---

## Error Handling

- **Logout Exceptions**: `AuthState.logout()` executes cleanup steps (`signOut()`, `clearAll()`, `clearHeadersCache()`) sequentially without throwing errors if individual sub-tasks encounter network or storage issues, ensuring local logout completion.

---

## Edge Cases

1. **Logout During Active HTTP Requests**: In-flight requests failing after `logout()` are handled by `_safeCall`. Since `StorageService` is already wiped, token refresh fails and no re-authentication state is modified.
2. **Account Wipe Operating Without Logout**: `ProfileState.wipeAppData()` executes database purging without touching session tokens or clearing `AuthState`, allowing seamless app usage post-wipe.

---

## Potential Bugs and Inconsistencies

### 1. CRITICAL BUG: `ChangePasswordScreen` is a Pure UI Stub
- **Finding**: In `change_password_screen.dart:92-98`, submitting the change password form displays a success SnackBar and pops the screen back.
- **Impact**: The password is **never updated** in Supabase Auth or the database. `AuthRepository.changePassword()` is dead code, and users are misled into believing their password was changed.

### 2. BUG: In-Memory Provider Contamination Across Account Switches
- **Finding**: `AuthState.logout()` clears `AuthState` and `StorageService`, but does **not** clear other global Provider states (`DriveState`, `MoodState`, `BucketState`, `GameState`, `ProfileState`).
- **Impact**: If User A logs out and User B logs in within the same Flutter process execution, User B may briefly see User A's in-memory cached state (e.g. Drive file names or Mood emojis) until background API fetches overwrite them.

### 3. BUG: Orphaned Device Tokens Receive Notifications Post-Logout
- **Finding**: `logout()` does not send a request to backend to delete or deactivate the device token in `user_devices`.
- **Impact**: Server-initiated push notifications targeting the logged-out user (e.g., partner interactions or reminders) continue to deliver to the physical device after logout until a new account logs in on that device.

---

## Files and Functions

### Flutter Frontend
- [change_password_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart): Password change UI form stub.
- [device_token_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/device_token_service.dart): Platform token resolution `getDeviceToken()`, `getDeviceFingerprint()`.
- [logout_utils.dart](file:///f:/JustUS/Flutter/lib/shared/utils/auth/logout_utils.dart): Logout dialog and `performLogout()` helper.
- [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart): `logout()`, `updateDeviceToken()`.
- [storage_service.dart](file:///f:/JustUS/Flutter/lib/core/local_storage/storage_service.dart): Storage purge `clearAll()`, `clearAppCache()`.
- [cache_service.dart](file:///f:/JustUS/Flutter/lib/core/local_storage/cache_service.dart): Checkpoint cache purge `clearAll()`.
- [realtime_sync_service.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart): Channel teardown `_unsubscribe()`, `configure()`.
- [profile_state.dart](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart): `wipeAppData()`.

### Backend Node.js
- [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js): Device token registration `updateDeviceToken()`.
- [user.controller.js](file:///f:/JustUS/Backend/features/user/user.controller.js): Data wipe controller.

---

## Database Objects

- **Table `user_devices`**: PostgreSQL table storing `user_id`, `device_token`, `user_agent`, `device_type`, `last_ip`, `locale`. Primary conflict target: `device_token`.
- **Procedure `debug_wipe_user_data`**: Stored procedure executed during account wipe to erase user domain records.

---

## Implementation Status

| Feature / Lifecycle Stage | Implementation Status | Notes |
|---|---|---|
| Change Password Flow | **BROKEN / STUB** | Form validates UI, but never calls API or Supabase Auth |
| FCM Mobile Device Token Registration | **IMPLEMENTED** | `DeviceTokenService` & `POST /api/v1/auth/device-token` |
| Windows Desktop Identification | **IMPLEMENTED** | Uses persistent UUID device fingerprint (Not push) |
| Device Token Reassignment | **IMPLEMENTED** | Database `upsert` on conflict `device_token` |
| Local Storage Purge on Logout | **IMPLEMENTED** | Clears `FlutterSecureStorage` and `SharedPreferences` |
| Realtime Teardown on Logout | **IMPLEMENTED** | Unsubscribes WebSocket channel via `RealtimeSyncScope` |
| In-Memory State Provider Cleanup | **BROKEN / DEFECTIVE** | Provider singletons retain old user data during logout |
| Device Token Unregistration | **NOT IMPLEMENTED** | Token remains in `user_devices` post-logout |
| Account Wipe (Debug Data Erase) | **IMPLEMENTED** | `debug_wipe_user_data` procedure |

# Profile & Settings

## Overview

The **Profile & Settings** feature in JustUS manages user profile attributes (avatar photo, display name, bio), system preferences (language/localization, notifications, theme), security actions (password change navigation, logout), app version display, and debug maintenance operations (account domain wipe).

This document provides a reverse-engineering technical analysis of the end-to-end implementation across the Flutter mobile app, Node.js/Express backend server, and Supabase PostgreSQL database.

---

## Functional Behavior

1. **Connected Avatar & Partner Info**: Displays linked user and partner avatars in a dual-hero avatar badge connected by a neon gradient line. Displays user and partner usernames, anniversary date badge, and user bio.
2. **Profile Image Picker & Upload**: Tapping the user avatar opens the device gallery, crops/resizes the image to max 512x512 pixels, compresses it to 80% JPEG quality, uploads it directly to Cloudflare R2 via a backend-signed PUT URL, and updates the `user_profiles` database record.
3. **Partner Code Sharing**: Displays the user's unique partnership code with a single-tap copy action to the system clipboard.
4. **Anniversary Date Selection**: Interactive date picker allowing users to set or update their partnership anniversary date.
5. **Language & Localization Management**: Navigates to `/localization` to select between supported languages (Italian and English), persisting the preference across app restarts and dynamically switching localized string lookup.
6. **Password Change Navigation**: Navigates to `/change-password` screen with current, new, and confirm password fields.
7. **Session Disconnection (Logout)**: Displays confirmation dialog and terminates the active session, clearing local tokens, cached data, and real-time WebSocket subscriptions.
8. **App Version Display & Update Check**: Displays local app version (`v{version}`) at the footer of the profile screen. Automatic update checks run on app startup (`HomepageScreen`).
9. **Account Data Wipe (Debug)**: In debug builds (`kDebugMode`), provides an operation to purge all user domain data (drive files, moods, game history, bucket items, miss-you records) from PostgreSQL and local storage without invalidating authentication tokens.

---

## User Flow

### Profile Photo Update Flow
```
User Taps Avatar → Gallery Picker (512x512) → Image Selected → Local File Path
  → CompressionService (80% JPEG) → POST /api/v1/media/upload-url (Signed R2 PUT URL)
  → HTTP PUT to Cloudflare R2 → POST /api/v1/media/complete (kind: 'profile')
  → UPDATE user_profiles SET profile_pic_url = filename
  → Local Storage & ProfileState Updated → Avatar Refreshed
```

### Language Selection Flow
```
Profile Screen → Tap Language → LocalizationScreen
  → Select Language (e.g. English) → LanguageProvider.setLanguageCode('en')
  → SharedPreferences.setString('app_language_code', 'en')
  → LanguageHelper.setAppLocale(Locale('en')) → AppLocalizations Lookup Updated
  → notifyListeners() → MaterialApp Rebuilds UI in English
```

### Account Data Wipe Flow (Debug)
```
Profile Screen (Debug) → Tap Wipe Data → Confirmation Dialog → User Confirms
  → RealtimeSyncService.suppress() → POST /api/v1/user/wipe
  → Backend Executes RPC debug_wipe_user_data(userId)
  → PostgreSQL deletes domain records (partnerships, drive, moods, bucket, games)
  → StorageService.clearAppCache() → Clear In-Memory Providers
  → RealtimeSyncService.refreshChannel() → Profile Reloaded (Empty State)
```

---

## Architecture

The Profile & Settings subsystem crosses all architectural layers:

```
[ Flutter UI (ProfileScreen / LocalizationScreen / ChangePasswordScreen) ]
                               │
                [ ProfileState / LanguageProvider / AuthState ]
                               │
            ┌──────────────────┴──────────────────┐
            ▼                                     ▼
 [ Local Storage & Cache ]              [ Repositories & Services ]
(SharedPreferences / SecureStorage)    (UserRepository / MediaService / ApiService)
                                                  │
                                                  ▼
                                      [ Node.js Express Backend ]
                                      (user.routes / mediaWorkflow.service)
                                                  │
                                                  ▼
                                      [ Supabase PostgreSQL & R2 ]
                                   (user_profiles / RPC debug_wipe_user_data)
```

---

## Frontend

### Screens & Widgets
- [`profile_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart): Main violet-punk styled screen rendering connected avatars, names, partner code, settings sections, debug utilities, logout button, and version label.
- [`localization_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/localization_screen.dart): Screen listing supported languages (`_LanguageTile`) and AI translation readiness card.
- [`change_password_screen.dart`](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart): Form with text fields for current password, new password, and confirmation password.

### Key Logic & Repositories
- [`profile_state.dart`](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart): Manages `_userProfile`, `_partnerProfile`, `_isUploading`, `_anniversaryDate`, throttling server profile fetches (1-minute window), uploading profile photos, updating bio, and calling `wipeAppData()`.
- [`user_repository.dart`](file:///f:/JustUS/Flutter/lib/features/settings/user_repository.dart): Contains API calls:
  - `fetchProfileByAuthId(authId)`: Queries `users` joined with `user_profiles`.
  - `fetchProfile()`: Queries `users` for current authenticated user.
  - `updateBio(bio)`: Updates `user_profiles.bio`.
  - `updateDisplayName(displayName)`: Updates `user_profiles.display_name`.
  - `uploadProfilePicture(file)`: Delegates upload to `MediaService`.
  - `debugWipeData()`: Invokes `ApiService.wipeUserData()`.
- [`language_provider.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_provider.dart): Manages current `Locale`, reads/writes `app_language_code` in `SharedPreferences`, updates `LanguageHelper.setAppLocale()`.
- [`language_helper.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_helper.dart): Contains fallback locale (`it`), supported languages catalog (`it`, `en`), locale resolution callbacks, and global `AppLocalizations` lookup reference (`LanguageHelper.appLoc`).
- [`update_service.dart`](file:///f:/JustUS/Flutter/lib/core/version/update_service.dart): Checks server app version against local build number (`package_info_plus`), displaying mandatory or optional update dialogs.

---

## Backend

### Controllers & Routes
- [`user.routes.js`](file:///f:/JustUS/Backend/features/user/user.routes.js): Defines `POST /api/v1/user/wipe`, guarded by authentication middleware and rate-limiting middleware (`userRateLimit`: max 5 requests per window).
- [`user.controller.js`](file:///f:/JustUS/Backend/features/user/user.controller.js): Implements `wipeUserDataController`, extracting `userId = req.user.profileId` and executing RPC `debug_wipe_user_data`.
- [`mediaWorkflow.service.js`](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js): Implements signed upload creation (`createPresignedUpload`) and registration (`registerCompletedUpload`). When `kind === 'profile'`, updates `user_profiles.profile_pic_url` directly.

---

## Supabase

### Tables
- `public.users`: Holds core account details (`id`, `email`, `auth_id`, `created_at`).
- `public.user_profiles`: Holds profile attributes (`user_id`, `display_name`, `bio`, `profile_pic_url`, `partnership_code`, `created_at`, `updated_at`).

### Stored Procedures & RPCs
- `debug_wipe_user_data(p_user_id integer)`: Administrative stored procedure executing data deletion. Configured with `SECURITY INVOKER` and restricted execution rights (`service_role` execution only via admin client).

---

## Authentication & Authorization

- **Backend Route Protection**: `POST /api/v1/user/wipe`, `POST /api/v1/media/upload-url`, and `POST /api/v1/media/complete` require valid JWT Bearer tokens verified by backend middleware (`authenticated()`).
- **HMAC Request Signing**: Media upload endpoints (`upload-url`, `complete`) require cryptographic request signatures (`X-Request-Signature`) generated with the session's `binding_secret`.
- **RPC Privileges**: Direct execution of `debug_wipe_user_data` from client Supabase SDK is revoked for `anon` and `authenticated` roles. It can only be invoked by the backend via `adminSupabase` (`service_role`).

---

## State Management

- `ProfileState`: Listens to user profile data, partner profile data, upload states, and anniversary date. Notifies listeners on profile changes.
- `LanguageProvider`: Extends `ChangeNotifier`, providing `locale` and notifying UI components when language changes.
- `AuthState`: Manages session tokens and credentials. Provides `logout()` which revokes sessions and clears local storage.

---

## Caching & Local Storage

### Local Storage Key Inventory

| Storage Level | Key | Purpose | Cleared on Logout? | Cleared on Account Wipe? |
|---|---|---|---|---|
| `FlutterSecureStorage` | `access_token` | JWT Access Token | **YES** | NO |
| `FlutterSecureStorage` | `refresh_token` | JWT Refresh Token | **YES** | NO |
| `FlutterSecureStorage` | `user_id` | DB User Integer ID | **YES** | NO |
| `FlutterSecureStorage` | `partner_id` | DB Partner Integer ID | **YES** | NO |
| `FlutterSecureStorage` | `partnership_id` | DB Partnership Integer ID | **YES** | NO |
| `FlutterSecureStorage` | `device_fingerprint` | Client Device UUID | **YES** | NO |
| `FlutterSecureStorage` | `request_binding_secret` | HMAC Signing Secret | **YES** | NO |
| `SharedPreferences` | `app_language_code` | Selected App Language Code | NO | NO |
| `SharedPreferences` | `user_profile` | Cached User Profile JSON | **YES** | **YES** |
| `SharedPreferences` | `partner_profile` | Cached Partner Profile JSON | **YES** | **YES** |
| `SharedPreferences` | `profile_pic_version` | Profile Pic Cache Timestamp | **YES** | **YES** |
| `SharedPreferences` | `username` / `partner_display_name` | Profile Names | **YES** | NO |
| `SharedPreferences` | `bucket_list`, `drive_cache`, etc. | App Feature Caches | **YES** | **YES** |

---

## Realtime / Synchronization

- **Account Wipe Suppression**: Prior to executing account wipe, `ProfileScreen` calls `RealtimeSyncService.suppress()` to prevent incoming database change events from triggering state re-syncs mid-deletion.
- **Post-Wipe Refresh**: Once wipe completes, `RealtimeSyncService.refreshChannel()` re-establishes the WebSocket sync channel.

---

## Notifications / Events

- Device token registration (`updateDeviceToken`) occurs at boot and login, passing the current device locale (`languageCode`).
- Changing device locale at runtime triggers `didChangeLocales` in `AuthState` to re-sync the locale with `user_devices`.

---

## Error Handling

- **Media Upload Failures**: Caught in `MediaService.uploadMedia()` with logging and exception rethrowing. `ProfileState` catches errors via `runSafe()`, clearing uploading status and presenting user feedback.
- **Wipe Failures**: Handled via `ResultWrapper`. If backend returns non-success, an exception is thrown and an error SnackBar is displayed without clearing local state.

---

## Validation

- **Image Picker Boundaries**: Constrained by `maxWidth: 512` and `maxHeight: 512` in `ImagePicker.pickImage()`.
- **MIME & File Size Guards**:
  - `MediaService`: Validates MIME against `['image/jpeg', 'image/png', 'image/webp', 'image/gif']`.
  - `CompressionService.isWithinSizeLimit()`: Enforces hard limit of 15 MB prior to compression.
- **Rate Limiting**: `POST /api/v1/user/wipe` is rate limited to max 5 requests per window (`userRateLimit`).

---

## Edge Cases

1. **Wipe Without Unpairing**: `debug_wipe_user_data` erases `partnerships` DB records via cascading deletes. The linked partner's database view dynamically updates, but the partner's in-memory Flutter state requires a refresh to reflect partnership severance.
2. **Offline Language Switch**: Language switching operates entirely locally via `SharedPreferences` and generated ARB assets, working seamlessly without network connectivity.

---

## Detailed Account Data Wipe Analysis

### Reconstruction of Purged vs. Surviving System Data

| System Layer | Target / Object | Status | Description |
|---|---|---|---|
| **Supabase PostgreSQL** | `partnerships` | **DELETED** | Deletes partnership record. Cascades (`ON DELETE CASCADE`) to `bucket_items`, `drive_items`, `missyou`, `game_questions`, `game_answers`. |
| **Supabase PostgreSQL** | `moods`, `drive_item_reactions`, `favorites` | **DELETED** | Deletes user-authored records. |
| **Supabase PostgreSQL** | `user_devices` | **DELETED** | Removes registered FCM device token rows. |
| **Supabase PostgreSQL** | System Logs (`logs_*`) | **DELETED** | Deletes user-associated log records. |
| **Supabase PostgreSQL** | `public.users` / `public.user_profiles` | **SURVIVES** | User account and user profile rows are **NOT** deleted. Auth credentials remain valid. |
| **Supabase Auth** | `auth.users` / `auth.sessions` | **SURVIVES** | Active auth user and JWT sessions remain active. |
| **Cloudflare R2** | Physical Storage Files (`/profile/`, `/{userId}/`) | **SURVIVES (ORPHANED)** | Files in Cloudflare R2 are **NOT** deleted by DB RPC. Objects survive as unreferenced files. |
| **Local Storage** | `SharedPreferences` (App Cache) | **DELETED** | `StorageService.clearAppCache()` removes domain keys (`bucket_list`, `drive_cache`, `mood_*`, etc.). |
| **Local Storage** | `SharedPreferences` (`username`, `partner_display_name`) | **SURVIVES** | Key strings are not included in `clearAppCache()`. |
| **Secure Storage** | `FlutterSecureStorage` | **SURVIVES** | Auth tokens (`access_token`, `user_id`, `binding_secret`, `device_fingerprint`) remain intact. |
| **Cached State** | In-Memory Providers (`GameState`, `BucketState`, `DriveState`, `MoodState`, `HomepageState`) | **CLEARED** | Explicitly cleared in UI callback (`context.read<State>().clear()`). |

---

## Files, Classes and Functions

### Frontend
- [`profile_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart)
  - `_pickProfilePhoto()`: Opens gallery picker with 512x512 limits.
  - `_showWipeConfirmation()`: Displays wipe dialog, suppresses realtime sync, invokes wipe, clears provider states.
  - `_logout()`: Invokes `LogoutUtils.showLogoutDialog()`.
- [`localization_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/localization_screen.dart)
  - `_LanguageTile`: Renders language option and calls `LanguageProvider.setLanguageCode()`.
- [`change_password_screen.dart`](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart)
  - `_ChangePasswordScreenState`: Password change form (UI stub).
- [`profile_state.dart`](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart)
  - `loadProfile()`: Throttled fetch of user and partner profile data.
  - `uploadProfilePhoto()`: Uploads image file and updates local profile version.
  - `updateBio()`: Updates user bio.
  - `wipeAppData()`: Triggers backend wipe API and clears local app cache.
- [`user_repository.dart`](file:///f:/JustUS/Flutter/lib/features/settings/user_repository.dart)
  - `fetchProfile()`, `updateBio()`, `updateDisplayName()`, `uploadProfilePicture()`, `debugWipeData()`.
- [`language_provider.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_provider.dart)
  - `loadSavedLocale()`, `setLanguageCode()`, `setLocale()`.
- [`language_helper.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_helper.dart)
  - `supportedLanguages`, `resolveLocale()`, `setAppLocale()`.
- [`update_service.dart`](file:///f:/JustUS/Flutter/lib/core/version/update_service.dart)
  - `checkVersion()`: Compares version/build info and presents update dialog.

### Backend
- [`user.routes.js`](file:///f:/JustUS/Backend/features/user/user.routes.js)
  - `POST /wipe`: Rate-limited authenticated endpoint.
- [`user.controller.js`](file:///f:/JustUS/Backend/features/user/user.controller.js)
  - `wipeUserDataController`: Calls Supabase RPC `debug_wipe_user_data`.
- [`mediaWorkflow.service.js`](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js)
  - `registerCompletedUpload`: Handles `kind === 'profile'` updates to `user_profiles.profile_pic_url`.

---

## Database Objects

- `public.users`: User accounts table.
- `public.user_profiles`: User profile metadata table (`user_id`, `display_name`, `bio`, `profile_pic_url`, `partnership_code`).
- `debug_wipe_user_data`: Stored procedure purging user domain records.

---

## Invariants

1. **Profile Picture Resolution**: Profile pictures are always uploaded with `kind = 'profile'`, storing relative R2 filenames in `user_profiles.profile_pic_url`.
2. **Language Preference Persistence**: The active locale code is strictly persisted in `SharedPreferences` under key `app_language_code`.
3. **Session Integrity During Data Wipe**: Account wipe only affects application domain data; authentication sessions and security tokens remain completely active.

---

## Known Issues & Discovered Bugs

### 1. CRITICAL BUG: `ChangePasswordScreen` is a Pure UI Stub
- **Finding**: In [`change_password_screen.dart:92-98`](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart#L92-L98), submitting the password change form shows a success SnackBar and pops the screen.
- **Impact**: The password is **never updated** in Supabase Auth or backend. Users receive false confirmation of a password change.
- **Confidence**: **HIGH**

### 2. BUG: Missing Camera Option in Profile Photo Picker
- **Finding**: In [`profile_screen.dart:47-51`](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart#L47-L51), `_pickProfilePhoto()` hardcodes `source: ImageSource.gallery`.
- **Impact**: Users cannot take a new profile photo directly using the device camera.
- **Confidence**: **HIGH**

### 3. BUG: Unreachable Display Name & Bio Editing Logic
- **Finding**: `UserRepository` defines `updateDisplayName()` and `updateBio()`, and `ProfileState` defines `updateBio()`, but `ProfileScreen` provides **no text fields or edit buttons** to edit display name or bio.
- **Impact**: Users cannot edit their display name or bio within the application UI.
- **Confidence**: **HIGH**

### 4. INCOMPLETE DELETION: Cloudflare R2 Storage Leak During Account Wipe
- **Finding**: RPC `debug_wipe_user_data` purges database rows in `drive_items` and updates `user_profiles`, but does **not** delete underlying files stored in Cloudflare R2 storage.
- **Impact**: Physical media files remain orphaned permanently in Cloudflare R2 storage post-wipe.
- **Confidence**: **HIGH**

### 5. INCOMPLETE LOCAL CLEANUP: Surviving Local Keys During Account Wipe
- **Finding**: `StorageService.clearAppCache()` leaves `username` and `partner_display_name` in `SharedPreferences`, and does not clear `FlutterSecureStorage`.
- **Impact**: User credentials and names survive the account wipe locally until manual logout.
- **Confidence**: **HIGH**

---

## Implementation Status

| Feature / Component | Status | Notes |
|---|---|---|
| Connected Avatars & Names Display | **IMPLEMENTED** | Renders user & partner info with connected gradient line |
| Profile Image Gallery Pick & 512px Resize | **IMPLEMENTED** | Gallery picker with 512x512 limits & 80% JPEG compression |
| Profile Image Camera Selection | **NOT IMPLEMENTED** | Hardcoded to `ImageSource.gallery` |
| R2 Profile Image Direct Upload | **IMPLEMENTED** | Uploads via signed PUT URL & updates `user_profiles` |
| Display Name & Bio Viewing | **IMPLEMENTED** | Displayed on profile screen |
| Display Name & Bio Editing UI | **NOT IMPLEMENTED** | Backend/repo functions exist, but no UI input fields |
| Language Selection & Persistence | **IMPLEMENTED** | `/localization` screen, `SharedPreferences`, dynamic locale |
| App Version Display | **IMPLEMENTED** | `v{info.version}` displayed via `package_info_plus` |
| Automatic Update Checker | **IMPLEMENTED** | Executed on `HomepageScreen` startup via `UpdateService` |
| Manual Update Check from Profile | **NOT IMPLEMENTED** | No manual trigger button on profile screen |
| Session Logout | **IMPLEMENTED** | Clears tokens, local storage, closes WebSocket connection |
| Password Change Navigation | **BROKEN / STUB** | UI form exists but does not call password update API |
| Account Data Wipe (Debug) | **PARTIALLY IMPLEMENTED** | Purges PostgreSQL & local app cache; leaks R2 files & local secure storage |

---

## Notes

- All analysis conducted directly from current source code files in `Flutter/`, `Backend/`, and `.agents/skills/`.

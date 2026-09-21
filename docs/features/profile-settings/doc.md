# Profile & Settings

## Overview

The **Profile & Settings** feature in JustUS manages user profile attributes (avatar photo, display name), system preferences (language/localization, notifications, theme), security actions (password change navigation, logout), app version display, and debug maintenance operations (account domain wipe).

This document provides a reverse-engineering technical analysis of the end-to-end implementation across the Flutter mobile app, Node.js/Express backend server, and Supabase PostgreSQL database.

---

## Functional Behavior

1. **Connected Avatar & Partner Info**: Displays linked user and partner avatars in a dual-hero avatar badge connected by a neon gradient line. Displays user and partner usernames and the anniversary date badge.
2. **Profile Image Picker & Upload**: Tapping the user avatar opens a camera/gallery bottom sheet (`MediaPickerService`), crops/resizes the image to max 512x512 pixels, compresses it to 80% JPEG quality, uploads it directly to Cloudflare R2 via a backend-signed PUT URL, and updates the `user_profiles` database record.
3. **Display Name Editing**: An "IDENTITY" setting group lets the user edit their display name (required, max 60 chars) through an edit dialog wired to `ProfileState.updateDisplayName`. Edits persist to `user_profiles`, update local caches, and propagate to partner devices in realtime.
4. **Partner Code Sharing**: Displays the user's unique partnership code with a single-tap copy action to the system clipboard.
5. **Anniversary Date Selection**: Interactive date picker allowing users to set or update their partnership anniversary date.
6. **Language & Localization Management**: Navigates to `/localization` to select between supported languages (Italian and English), persisting the preference across app restarts and dynamically switching localized string lookup.
7. **Password Change Navigation**: Navigates to `/change-password` screen with current, new, and confirm password fields.
8. **Session Disconnection (Logout)**: Displays confirmation dialog and terminates the active session, clearing local tokens, cached data, and real-time WebSocket subscriptions.
9. **App Version Display & Update Check**: Displays local app version (`v{version}`) at the footer of the profile screen. Automatic update checks run on app startup (`HomepageScreen`).
10. **Account Data Wipe (Debug)**: In debug builds (`kDebugMode`), provides an operation to purge all user domain data (drive files, moods, game history, bucket items, miss-you records) from PostgreSQL, Cloudflare R2, and local storage without invalidating authentication tokens.

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

### Display Name Edit Flow
```
Profile Screen → Identity Group → Tap Display name → Edit Dialog (TextField)
  → Save → ProfileState.updateDisplayName
  → UserRepository.updateDisplayName → UPDATE user_profiles SET display_name
  → ProfileState updates in-memory model + StorageService caches (user_profile, username)
  → Realtime: user_profiles UPDATE → RefetchRealtimeHandler (lib/core/realtime/refetch_realtime_handler.dart)
      → clearPartnershipCache + ProfileState.loadProfile(force: true)
      → PartnerState/AuthState.refreshFromRealtime → partner device UI + storage updated
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
  → RealtimeSyncService.suppress() → POST /api/v1/users/wipe
  → Backend Executes RPC debug_wipe_user_data(userId)
  → PostgreSQL deletes domain records (drive, moods, bucket, games, missyou)
  → Backend enumerates & deletes R2 objects under uploads/{userId}/, profile/{userId}/,
    uploads/{partnerId}/, profile/{partnerId}/ (r2.service deleteObjectsByPrefix)
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
- [`profile_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart): Main violet-punk styled screen rendering connected avatars, names, partner code, IDENTITY setting group (display name edit dialog), debug utilities, logout button, and version label.
- [`localization_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/localization_screen.dart): Screen listing supported languages (`_LanguageTile`) and AI translation readiness card.
- [`change_password_screen.dart`](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart): Form with text fields for current password, new password, and confirmation password.

### Key Logic & Repositories
- [`profile_state.dart`](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart): Manages `_userProfile`, `_partnerProfile`, `_isUploading`, `_anniversaryDate`, throttling server profile fetches (1-minute window), uploading profile photos, updating the display name, and calling `wipeAppData()`.
- [`user_repository.dart`](file:///f:/JustUS/Flutter/lib/features/settings/user_repository.dart): Contains API calls:
  - `fetchProfileByAuthId(authId)`: Queries `users` joined with `user_profiles`.
  - `fetchProfile()`: Queries `users` for current authenticated user.
  - `updateDisplayName(displayName)`: Updates `user_profiles.display_name`.
  - `uploadProfilePicture(file)`: Delegates upload to `MediaService`.
  - `debugWipeData()`: Invokes `ApiService.wipeUserData()`.
- [`language_provider.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_provider.dart): Manages current `Locale`, reads/writes `app_language_code` in `SharedPreferences`, updates `LanguageHelper.setAppLocale()`.
- [`language_helper.dart`](file:///f:/JustUS/Flutter/lib/core/localization/language_helper.dart): Contains fallback locale (`it`), supported languages catalog (`it`, `en`), locale resolution callbacks, and global `AppLocalizations` lookup reference (`LanguageHelper.appLoc`).
- [`update_service.dart`](file:///f:/JustUS/Flutter/lib/core/version/update_service.dart): Checks server app version against local build number (`package_info_plus`), displaying mandatory or optional update dialogs.

---

## Backend

### Controllers & Routes
- [`user.routes.js`](file:///f:/JustUS/Backend/features/user/user.routes.js): Defines `POST /api/v1/users/wipe`, guarded by authentication middleware and rate-limiting middleware (`userRateLimit`: max 5 requests per window).
- [`user.controller.js`](file:///f:/JustUS/Backend/features/user/user.controller.js): Implements `wipeUserDataController`, extracting `userId = req.user.profileId`, executing RPC `debug_wipe_user_data`, then deleting the R2 objects under the user's and their accepted partner's prefixes via `deleteUserR2Objects` (`uploads/{id}/`, `profile/{id}/`).
- [`mediaWorkflow.service.js`](file:///f:/JustUS/Backend/features/media/mediaWorkflow.service.js): Implements signed upload creation (`createPresignedUpload`) and registration (`registerCompletedUpload`). When `kind === 'profile'`, updates `user_profiles.profile_pic_url` directly.

---

## Supabase

### Tables
- `public.users`: Holds core account details (`id`, `email`, `auth_id`, `created_at`).
- `public.user_profiles`: Holds profile attributes (`user_id`, `display_name`, `profile_pic_url`, `partnership_code`, `created_at`, `updated_at`).

### Stored Procedures & RPCs
- `debug_wipe_user_data(p_user_id integer)`: Administrative stored procedure executing data deletion. Configured with `SECURITY DEFINER` and restricted execution rights (revoked from `PUBLIC`, granted to `postgres`/`service_role` only, invoked by the backend via `adminSupabase`).

---

## Authentication & Authorization

- **Backend Route Protection**: `POST /api/v1/users/wipe`, `POST /api/v1/media/upload-url`, `POST /api/v1/media/complete`, and `POST /api/v1/media/delete` require valid JWT Bearer tokens verified by backend middleware (`authenticated()`).
- **HMAC Request Signing**: Media endpoints (`upload-url`, `complete`, `delete`) require cryptographic request signatures (`X-Request-Signature`) generated with the session's `binding_secret`.
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

> **Deliberate retention**: the wipe intentionally does **not** clear `FlutterSecureStorage` (`access_token`, `refresh_token`, `user_id`, `partner_id`, `partnership_id`, `device_fingerprint`, `request_binding_secret`) nor the display-name keys. Authentication must remain active after the wipe (invariant 3), so tokens/session identity are always preserved; names are kept only as a cosmetic convenience for the post-wipe reload.
| `SharedPreferences` | `bucket_list`, `drive_cache`, etc. | App Feature Caches | **YES** | **YES** |

---

## Realtime / Synchronization

- **Profile Edit Propagation**: `user_profiles` is part of the `supabase_realtime` publication; `RefetchRealtimeHandler` (150 ms debounce, update-only) reacts to self/partner `UPDATE`s by clearing the partnership cache and refreshing `ProfileState.loadProfile(force: true)` + `PartnerState.refreshFromRealtime()` + `AuthState.refreshPartnershipFromRealtime()`. Display name/profile pic changes appear on the partner device without re-entering the screen.
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
- **Display Name**: Required (non-empty), trimmed, max 60 chars; empty submissions rejected in the edit dialog.
- **MIME & File Size Guards**:
  - `MediaService`: Validates MIME against `['image/jpeg', 'image/png', 'image/webp', 'image/gif']`.
  - `CompressionService.isWithinSizeLimit()`: Enforces hard limit of 15 MB prior to compression.
- **Rate Limiting**: `POST /api/v1/users/wipe` is rate limited to max 5 requests per window (`userRateLimit`).

---

## Edge Cases

1. **Wipe Keeps the Partnership**: `debug_wipe_user_data` deletes the partnership's domain rows (drive, moods, bucket, game, miss-you, reactions, favorites, logs) but does **not** delete the `partnerships` row itself — the couple stays linked and the wipe is recoverable; the partner's in-memory Flutter state refreshes via realtime.
2. **Offline Language Switch**: Language switching operates entirely locally via `SharedPreferences` and generated ARB assets, working seamlessly without network connectivity.

---

## Detailed Account Data Wipe Analysis

### Reconstruction of Purged vs. Surviving System Data

| System Layer | Target / Object | Status | Description |
|---|---|---|---|
| **Supabase PostgreSQL** | `partnerships` | **SURVIVES** | Partnership row is kept; the wipe only clears its domain rows. |
| **Supabase PostgreSQL** | `drive_items`, `bucket_items`, `missyou`, `game_questions`, `game_answers` | **DELETED** | Deleted explicitly by `debug_wipe_user_data` (not via partnership cascade). |
| **Supabase PostgreSQL** | `moods`, `drive_item_reactions`, `favorites` | **DELETED** | Deletes user-authored records. |
| **Supabase PostgreSQL** | `logs_notifications` | **DELETED** | Deletes user-associated notification log rows. |
| **Supabase PostgreSQL** | `public.users` / `public.user_profiles` | **SURVIVES** | User account and profile rows are **NOT** deleted (profile picture URL is reset to `NULL`). Auth credentials remain valid. |
| **Supabase Auth** | `auth.users` / `auth.sessions` | **SURVIVES** | Active auth user and JWT sessions remain active. |
| **Cloudflare R2** | Physical Storage Files (`uploads/{userId}/`, `profile/{userId}/`, and partner prefixes) | **DELETED** | `wipeUserDataController` enumerates objects by prefix (`r2.service` `listObjectKeys` + batched `DeleteObjectsCommand`) after the DB RPC succeeds. |
| **Local Storage** | `SharedPreferences` (App Cache) | **DELETED** | `StorageService.clearAppCache()` removes domain keys (`bucket_list`, `drive_cache`, `mood_*`, etc.). |
| **Local Storage** | `SharedPreferences` (`username`, `partner_display_name`) | **SURVIVES** | Deliberate — display names are a cosmetic convenience; tokens stay for an active session. |
| **Secure Storage** | `FlutterSecureStorage` | **SURVIVES** | Deliberate — auth tokens (`access_token`, `user_id`, `binding_secret`, `device_fingerprint`) are kept so the session remains valid after the wipe. |
| **Cached State** | In-Memory Providers (`GameState`, `BucketState`, `DriveState`, `MoodState`, `HomepageState`) | **CLEARED** | Explicitly cleared in UI callback (`context.read<State>().clear()`). |

---

## Files, Classes and Functions

### Frontend
- [`profile_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/profile_screen.dart)
  - `_pickProfilePhoto()`: Opens `MediaPickerService` bottom sheet (camera + gallery) capped at 512x512.
  - `_showTextEditDialog()`: Generic localized edit dialog (TextField, validation, max length 60).
  - `_editDisplayName()`: Opens the edit dialog and calls `ProfileState.updateDisplayName`.
  - `_showWipeConfirmation()`: Displays wipe dialog, suppresses realtime sync, invokes wipe, clears provider states.
  - `_logout()`: Invokes `LogoutUtils.showLogoutDialog()`.
- [`localization_screen.dart`](file:///f:/JustUS/Flutter/lib/features/settings/screens/localization_screen.dart)
  - `_LanguageTile`: Renders language option and calls `LanguageProvider.setLanguageCode()`.
- [`change_password_screen.dart`](file:///f:/JustUS/Flutter/lib/features/auth/screens/change_password_screen.dart)
  - `_ChangePasswordScreenState`: Password change form (UI stub).
- [`profile_state.dart`](file:///f:/JustUS/Flutter/lib/features/settings/profile_state.dart)
  - `loadProfile()`: Throttled fetch of user and partner profile data.
  - `uploadProfilePhoto()`: Uploads image file and updates local profile version.
  - `updateDisplayName()`: Updates `user_profiles.display_name`, refreshes in-memory model + `user_profile`/`username` caches.
  - `wipeAppData()`: Triggers backend wipe API and clears local app cache.
- [`user_repository.dart`](file:///f:/JustUS/Flutter/lib/features/settings/user_repository.dart)
  - `fetchProfile()`, `updateDisplayName()`, `uploadProfilePicture()`, `debugWipeData()`.
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
- `public.user_profiles`: User profile metadata table (`user_id`, `display_name`, `profile_pic_url`, `partnership_code`).
- `debug_wipe_user_data`: Stored procedure purging user domain records.

---

## Invariants

1. **Profile Picture Resolution**: Profile pictures are always uploaded with `kind = 'profile'`, storing relative R2 filenames in `user_profiles.profile_pic_url`.
2. **Language Preference Persistence**: The active locale code is strictly persisted in `SharedPreferences` under key `app_language_code`.
3. **Session Integrity During Data Wipe**: Account wipe only affects application domain data; authentication sessions and security tokens remain completely active.

---

## Known Issues & Discovered Bugs

No known bugs remain in the account-wipe flow. The R2 object cleanup and the deliberate secure-storage retention are documented above (see "Deliberate retention" under local storage, and invariant 3).

---

## Implementation Status

| Feature / Component | Status | Notes |
|---|---|---|
| Connected Avatars & Names Display | **IMPLEMENTED** | Renders user & partner info with connected gradient line |
| Profile Image Gallery Pick & 512px Resize | **IMPLEMENTED** | Gallery picker with 512x512 limits & 80% JPEG compression |
| Profile Image Camera Selection | **IMPLEMENTED** | `MediaPickerService` bottom sheet (camera + gallery) shared with the drive, profile caps pick at 512x512 |
| R2 Profile Image Direct Upload | **IMPLEMENTED** | Uploads via signed PUT URL & updates `user_profiles` |
| Display Name Viewing | **IMPLEMENTED** | Displayed on profile screen |
| Display Name Editing UI | **IMPLEMENTED** | "IDENTITY" setting group on the profile screen: edit dialog wired to `ProfileState.updateDisplayName`; partner devices see the change in realtime (`user_profiles` subscription) |
| Language Selection & Persistence | **IMPLEMENTED** | `/localization` screen, `SharedPreferences`, dynamic locale |
| App Version Display | **IMPLEMENTED** | `v{info.version}` displayed via `package_info_plus` |
| Automatic Update Checker | **IMPLEMENTED** | Executed on `HomepageScreen` startup via `UpdateService` |
| Manual Update Check from Profile | **IMPLEMENTED** | Setting tile & app version tap trigger manual update check via `UpdateService` |
| Session Logout | **IMPLEMENTED** | Clears tokens, local storage, closes WebSocket connection |
| Password Change Navigation | **IMPLEMENTED** | Wired submit form with reauthentication, loading state, localized validation & error handling |
| Account Data Wipe (Debug) | **IMPLEMENTED** | Purges PostgreSQL, R2 objects (`uploads/` + `profile/` prefixes for user & partner), & local app cache; secure storage (tokens) intentionally retained |

---

## Notes

- All analysis conducted directly from current source code files in `Flutter/`, `Backend/`, and `.agents/skills/`.

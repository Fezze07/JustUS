# Homepage & Miss You Functionality - JustUS

## Overview

This document provides a reverse-engineered analysis of the **Homepage** and **Miss You** subsystem in the JustUS application. It traces the full execution flow from user touch interaction on the Miss You pill button, through state management and Supabase PostgreSQL RPCs, over Supabase Realtime WebSocket broadcasts, to UI updates on the partner's device.

Additionally, this document covers the partner avatar display, shared counter calculation, caching mechanics, and the interaction between Miss You initialization and startup app version enforcement (`UpdateService`).

---

## Architecture & Component Mapping

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER FRONTEND LAYER                         │
│  HomepageScreen • _MissYouButton • HomepageState • MissYouRepository    │
│  RealtimeSyncService • ProfileState • UpdateService                     │
└────────────────────┬───────────────────────────────▲────────────────────┘
                     │                               │
          Supabase   │                               │ Supabase Realtime
          RPC call   │                               │ Postgres Changes
                     ▼                               │ (table: missyou)
┌────────────────────────────────────────────────────┴────────────────────┐
│                             SUPABASE LAYER                              │
│  Tables: public.missyou, public.partnerships, public.user_profiles      │
│  RPC: send_missyou                                                      │
│  RLS Policies: SELECT / INSERT restricted to active partnership members │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [homepage_screen.dart](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart): UI layout following Midnight Glass aesthetics. Renders top app bar, partner avatars, days together pill, mood display, pending bucket items, and `_MissYouButton`.
   - [homepage_state.dart](file:///f:/JustUS/Flutter/lib/features/home/homepage_state.dart): State manager maintaining `_totalMissYou`, handles cache checks (`loadWithChangeDetection`), network fetches (`fetchTotalMissYou`), and tap execution (`sendMissYou`).
   - [missyou_repository.dart](file:///f:/JustUS/Flutter/lib/features/home/missyou_repository.dart): API repository calling `sbClient.rpc('send_missyou')`, triggering push notifications (`notifyPartnerOnce`), and querying row count on `public.missyou`.
   - [realtime_sync_service.dart](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart): Subscribes to Postgres change events on `public.missyou`. On `INSERT`, invokes `_homepageState.addMissYou()`. On `DELETE`, triggers `refreshFromRealtime()`.
   - [update_service.dart](file:///f:/JustUS/Flutter/lib/core/version/update_service.dart): Checks app build version against backend `/api/v1/app-version` and displays mandatory or optional update dialogs.

2. **Backend / Database Layer**:
   - `public.missyou`: PostgreSQL table storing individual "Miss You" signals. Columns: `id` (integer, PK), `partnership_id` (integer, FK to `partnerships.id`), `created_at` (timestamptz).
   - `send_missyou` RPC: PostgreSQL stored procedure that inserts a new row into `public.missyou` bound to the caller's active partnership.
   - `versionService.js`: Express service serving latest app version metadata from server JSON configuration.

---

## End-to-End Execution Trace

### Sequence Diagram

```
User A (Sender)          HomepageState         Supabase DB         Realtime WS        User B (Partner)
      │                        │                    │                  │                      │
      │ ── Taps Miss You ─────>│                    │                  │                      │
      │                        │ ── send_missyou ──>│                  │                      │
      │                        │    (RPC call)      │                  │                      │
      │                        │                    │ ── INSERT row ──>│                      │
      │                        │                    │   into missyou   │                      │
      │                        │                    │                  │ ── Realtime Event ──>│
      │                        │                    │                  │   (table: missyou)   │
      │                        │                    │                  │                      │
      │                        │                    │                  │                      ├── _handleMissYouPayload()
      │                        │                    │                  │                      ├── addMissYou() [_totalMissYou += 1]
      │                        │                    │                  │                      └── notifyListeners() -> UI updates
```

### Detailed Component Steps

1. **User Interaction (`HomepageScreen`)**
   - File: [homepage_screen.dart:422-432](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart#L422-L432)
   - User taps the `_MissYouButton` pill in the mood section of `HomepageScreen`.
   - `GestureDetector.onTap` executes `unawaited(hpState.sendMissYou())` and displays a confirmation SnackBar (`context.loc.home_missYouSent`).

2. **State Handling (`HomepageState`)**
   - File: [homepage_state.dart:70-88](file:///f:/JustUS/Flutter/lib/features/home/homepage_state.dart#L70-L88)
   - `HomepageState.sendMissYou()` sets `_isLoading = true` and notifies listeners.
   - Invokes `MissYouRepository.sendMissYou()`.

3. **Supabase RPC Execution & Push Notification**
   - File: [missyou_repository.dart:8-16](file:///f:/JustUS/Flutter/lib/features/home/missyou_repository.dart#L8-L16)
   - Calls `sbClient.rpc('send_missyou')`.
   - The database function identifies the user's active partnership ID and inserts a new row into `public.missyou`.
   - Repository asynchronously fires a push notification request to the partner via `notifyPartnerOnce(notificationKey: 'missyou')`.

4. **Realtime Event Broadcast**
   - File: [realtime_sync_service.dart:429-440](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart#L429-L440)
   - Supabase Realtime engine detects the `INSERT` on `public.missyou` and broadcasts the payload to subscribed client channels (`justus-sync-{userId}-{gen}`).
   - On Partner User B's device, `RealtimeSyncService._handleMissYouPayload` receives the event.
   - Evaluates relevance via `_isRelevantMissYou` (verifies `eventPartnershipId == _partnershipId`).
   - Deduplicates the event key via `_markSeen` (`table:eventType:id:commitTimestamp`).
   - If event is `insert`, calls `_homepageState.addMissYou()`.

5. **Partner Device UI Update**
   - File: [homepage_state.dart:64-68](file:///f:/JustUS/Flutter/lib/features/home/homepage_state.dart#L64-L68)
   - `HomepageState.addMissYou()` increments `_totalMissYou += 1`.
   - Asynchronously persists the new total to local storage (`StorageService.saveTotalMissYou(_totalMissYou)`).
   - Calls `notifyListeners()`.
   - `_MissYouButton` re-builds seamlessly displaying the updated count badge.

---

## Miss You Button & Pulse Animation

### UI Rendering (`_MissYouButton`)

- File: [homepage_screen.dart:764-834](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart#L764-L834)
- **Visual Design**: Glassmorphic pill with rounded corners (`BorderRadius.circular(9999)`), linear gradient (`primaryContainer` + `secondary`), subtle box shadow, and a white border.
- **Content**:
  - Animated favorite heart icon (`Icons.favorite_rounded`, color: `secondary`).
  - Localized title (`context.loc.home_nudgeTitle.toUpperCase()`).
  - Badge container displaying current count (`$count`).

### Pulse Animation

- File: [homepage_screen.dart:36-45](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart#L36-L45)
- Managed by `_pulseCtrl` (`AnimationController`, vsync: `SingleTickerProviderStateMixin`, duration: `2 seconds`, `repeat(reverse: true)`).
- `_pulseAnim` interpolates scale from `1.0` to `1.1` using a `Curves.easeInOut` curve.
- Applied to heart icons via `ScaleTransition(scale: _pulseAnim)`.
- Runs continuously on the UI thread while `HomepageScreen` is mounted.

---

## Partner Avatar Rendering & Profile Linking

- File: [homepage_screen.dart:204-282](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart#L204-L282)
- **Layout**: Renders two circular avatar columns (`_AvatarColumn`) connected by a central glass node (`_GlassLinkNode`) and gradient line.
- **Data Binding**:
  - `ProfileState` selector listens for changes to user profile picture URL, partner profile picture URL, and anniversary date.
  - User avatar displays `context.loc.common_you` and user profile picture.
  - Partner avatar displays `auth.partnerDisplayName` and partner profile picture.
  - Images are loaded via `Image.network` with error fallback to a default person icon (`Icons.person_rounded`).
- **Days Together Pill**: Below avatars, if `anniversaryDate` is set, calculates days elapsed since anniversary using `AppDateUtils.daysSince(anniversary)` and displays total days together.

---

## Counter, Concurrency & Duplicate Tap Analysis

### Shared Counter Calculation

- Total count is determined by counting total rows in `public.missyou` matching the current `partnership_id` ([missyou_repository.dart:27-32](file:///f:/JustUS/Flutter/lib/features/home/missyou_repository.dart#L27-L32)):
  ```dart
  final count = await sbClient
      .from('missyou')
      .count()
      .eq('partnership_id', partnershipId);
  ```

### Duplicate Tap & Concurrency Behavior

1. **Tap Debouncing**:
   - **Finding**: In `homepage_screen.dart:422-432`, `GestureDetector` wraps `_MissYouButton`.
   - `HomepageState.sendMissYou()` sets `_isLoading = true`, but the `GestureDetector` in the UI does **not** check `_isLoading` or disable `onTap` during request execution.
   - **Impact**: Rapid multi-tapping by the user fires parallel calls to `sendMissYou()`.

2. **Concurrency & Database Execution**:
   - Each call executes `sbClient.rpc('send_missyou')`.
   - PostgreSQL executes independent `INSERT` operations into `public.missyou`.
   - Multiple rows are inserted for rapid successive taps, causing the shared counter to increment by the exact number of taps made.

3. **Ordering Behavior**:
   - Realtime events are received in commit order over WebSocket channel.
   - Event deduplication in `RealtimeSyncService._markSeen` uses a composite key: `table:eventType:id:commitTimestamp`. Since each `INSERT` creates a unique row `id` and `commitTimestamp`, all legitimate tap events are processed sequentially.

---

## Caching Strategy & Offline Behavior

### Cache Pipeline

1. **Storage Service Keys**:
   - Total count: `_keyMissYouTotal = 'miss_you'` ([storage_service.dart:35](file:///f:/JustUS/Flutter/lib/core/local_storage/storage_service.dart#L35)).
   - Checkpoint: `kMissYou = 'chk_miss_you'` ([cache_service.dart:8](file:///f:/JustUS/Flutter/lib/core/local_storage/cache_service.dart#L8)).
2. **Initialization (`HomepageState.init`)**:
   - Executes `loadWithChangeDetection()`:
     - Loads cached total from `StorageService.getTotalMissYou()`.
     - Checks `CacheService.needsRefresh(kMissYou)`.
     - If refresh is required or cache is empty, fetches network total via `fetchTotalMissYou()`.
     - On successful fetch, saves count to storage and updates checkpoint timestamp.

### Offline Behavior

- If device is offline when tapping Miss You, `sbClient.rpc('send_missyou')` throws a network exception caught by `BaseRepository.tryCall()`.
- The error is wrapped into `GenericError`. `HomepageState` handles the error safely, `_isLoading` resets to `false`, and local count remains untouched.
- When network connectivity is restored, `HomepageState.init()` or pull-to-refresh syncs total count with Supabase.

---

## App Version Enforcement & Startup Check

### Version Check Pipeline

```
HomepageScreen.initState()
   │
   ├── PostFrameCallback: _loadData() [Parallel initialization of homepage, mood, profile, bucket]
   │
   └── PostFrameCallback: _updateService.checkVersion(context)
            │
            ├── PackageInfo.fromPlatform() -> Reads local app version & build number
            │
            ├── VersionRepository.checkAppVersion() -> GET /api/v1/app-version
            │                                             │
            │                                             ▼
            │                                      Node.js Backend
            │                                      (versionService.js -> reads app_version.json)
            │
            ├── Compares localBuild vs serverBuild
            │     - If localBuild >= serverBuild: No action needed.
            │
            └── Evaluates Mandatory Status:
                  mandatory = versionInfo.forceUpdate || localBuild < versionInfo.minBuild
```

### Force Update Dialog Behavior

- File: [update_service.dart:54-108](file:///f:/JustUS/Flutter/lib/core/version/update_service.dart#L54-L108)
- Displays a `VPDialog`:
  - Title: `update_availableTitle` ("Aggiornamento disponibile! 🚀").
  - Content: `update_newVersion` and `versionInfo.changelog`.
  - **Barrier Dismissible**: `barrierDismissible = !mandatory`. If mandatory update, tapping outside the dialog will **not** dismiss it.
  - **Action Buttons**:
    - Optional Update (`mandatory == false`): Shows "Later" (`update_later`) and "Update Now" (`update_now`). Tapping "Later" closes dialog.
    - Forced Update (`mandatory == true`): **Hides "Later" button**. Only "Update Now" button is available.

---

## Relationship between Miss You and Version Enforcement

1. **Initialization Concurrency**:
   - In `HomepageScreen.initState()`, `_loadData()` and `_updateService.checkVersion(context)` are both scheduled in `addPostFrameCallback`.
   - `_loadData()` initiates Miss You state initialization (`HomepageState.init()`), loading cached counts immediately.

2. **Interaction Blocking**:
   - If a mandatory force update is triggered (`localBuild < minBuild` or `forceUpdate == true`), `_showUpdateDialog()` overlays a modal dialog over `HomepageScreen`.
   - Because `barrierDismissible = false` and no cancel/later button is rendered, user interaction with `HomepageScreen` and `_MissYouButton` is **completely blocked**.
   - The user cannot tap Miss You or trigger network RPCs until the application is updated via the provided APK URL.

---

## Security & RLS Policies

- Table `public.missyou` access is governed by Row Level Security:
  - **SELECT**: Restricted to users belonging to the active partnership (`is_in_partnership(partnership_id)`).
  - **INSERT**: Restricted to authenticated users who are members of an active partnership.

---

## Discovered Bugs, Defects, and Inconsistencies

During reverse-engineering analysis, the following technical findings were identified:

### 1. DEFECT: Missing Tap Debounce / Double-Tap Protection on Miss You Button

* **WHAT**: `_MissYouButton` allows rapid consecutive taps without client-side debouncing or button disabling.
* **WHERE**: [homepage_screen.dart:422-432](file:///f:/JustUS/Flutter/lib/features/home/screens/homepage_screen.dart#L422-L432)
* **WHY**: `HomepageState.sendMissYou()` toggles `_isLoading = true`, but the `GestureDetector` in `homepage_screen.dart` does not check `hpState.isLoading` or disable `onTap`.
* **WHEN**: User rapidly taps the Miss You button.
* **IMPACT**: Multiple network RPC requests are dispatched simultaneously, inserting multiple duplicate rows into `public.missyou` and artificially inflating the counter.
* **CONFIDENCE**: **HIGH**

### 2. INCONSISTENCY: Unused `_missYouRefreshTimer` in `RealtimeSyncService`

* **WHAT**: `RealtimeSyncService` declares `Timer? _missYouRefreshTimer;` and cancels it in `dispose()`, but never uses it in `_handleMissYouPayload()`.
* **WHERE**: [realtime_sync_service.dart:41 & 634](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart#L41)
* **WHY**: `_handleMissYouPayload` handles `insert` events synchronously via `_homepageState.addMissYou()` without applying timer debouncing, leaving the timer variable dead code.
* **WHEN**: Inspecting realtime service code.
* **IMPACT**: Minor code cleanup issue; no runtime crash.
* **CONFIDENCE**: **HIGH**

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Miss You Button UI & Layout | **IMPLEMENTED** | `_MissYouButton` with glassmorphic styling |
| Heart Icon Pulse Animation | **IMPLEMENTED** | 2s continuous `AnimationController` loop |
| Shared Counter Calculation | **IMPLEMENTED** | PostgreSQL row count via `missyou` table |
| Realtime Event Broadcast & Sync | **IMPLEMENTED** | `RealtimeSyncService` listens to `missyou` INSERTs |
| Partner Avatar & Days Together | **IMPLEMENTED** | `_AvatarColumn` + `AppDateUtils.daysSince()` |
| Local Storage & Cache Checkpoints | **IMPLEMENTED** | `StorageService` + `CacheService` checkpoints |
| Startup App Version Check | **IMPLEMENTED** | `UpdateService.checkVersion()` via `/api/v1/app-version` |
| Force Update UI Blocking | **IMPLEMENTED** | Non-dismissible `VPDialog` without "Later" button |
| Tap Debounce Protection | **NOT IMPLEMENTED** | Rapid tapping fires duplicate RPC requests |

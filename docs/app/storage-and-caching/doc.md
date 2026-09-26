# Flutter Storage & Caching — JustUS

## Overview

JustUS persists all local state through two Android/iOS/Web storage backends:

- **SharedPreferences** — non-sensitive feature caches, checkpoints, user preferences.
- **flutter\_secure\_storage** — tokens, user/partner IDs, device fingerprint, session binding secret.

A third layer, **flutter\_cache\_manager** (`MediaCacheManager` + a parallel default cache), handles on-disk file caching of downloaded media images/videos.

All JSON encode/decode for the major feature caches is offloaded to isolates via `compute()`.

There are **three coordinated logout/invalidation mechanisms** — `StorageService.clearAll()`, `CacheService.clearAll()`, and `ApiService.clearHeadersCache()` — that must be understood together to reason about cross-account safety.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│ UI / Screens                                                       │
│  (read via Provider<FeatureState>)                                 │
└──────────────────────────┬─────────────────────────────────────────┘
                           │ Provider.of / Consumer / Selector
┌──────────────────────────▼─────────────────────────────────────────┐
│ Feature States  (extends BaseState)                                │
│  loadWithChangeDetection: cache → hasChanges → unawaited network   │
│  write-through: every mutation writes cache + updates checkpoint   │
└──────────┬────────────────────┬────────────────────┬───────────────┘
           │                    │                    │
┌──────────▼────────┐ ┌────────▼────────┐ ┌─────────▼──────────────┐
│ StorageService     │ │ CacheService    │ │ MediaCacheManager      │
│ (SP + Secure)      │ │ (SP only)       │ │ (flutter_cache_manager)│
└────────────────────┘ └─────────────────┘ └────────────────────────┘
```

---

## Storage Inventory — All Persisted Values

### Secure Storage (flutter\_secure\_storage)

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | Notes |
|---|---|---|---|---|---|---|---|---|
| `_keyUserId` | `user_id` | `int?` (stored as string) | `AuthState.setLoginData` | `StorageService.getUserId` (all repos, `BaseRepository`) | Account lifetime | `deleteAll` | `deleteAll` | Legacy sentinel `-1` translated to `null` on read (`:207`) |
| `_keyAccessToken` | `access_token` | `String?` | `AuthState.setLoginData`, `tokenRefreshed` listener, `ApiService._tryRefreshToken` | `AuthState.init`, `ApiService` reads from the live Supabase session (NOT from secure storage) | Session lifetime | `deleteAll` | `deleteAll` | Written in 3 places, but the listener and `_tryRefreshToken` observe the same SDK refresh (todo# 1.6); read in `AuthState.init` for bootstrap check only |
| `_keyRefreshToken` | `refresh_token` | `String?` | `AuthState.setLoginData`, `tokenRefreshed` listener, `ApiService._tryRefreshToken` | `AuthState.init` (bootstrap); the Supabase SDK uses its own in-session refresh token for refreshes | Session lifetime | `deleteAll` | `deleteAll` | Manual refresh now delegates to `auth.refreshSession()`; this key is a cold-start mirror only (todo# 1.6) |
| `_keyPartnerId` | `partner_id` | `int?` (stored as string) | `AuthState.setPartner`, `PartnerState.refreshFromRealtime` | `StorageService.getPartnerId` (all feature states/repos) | Partnership lifetime | `deleteAll` | `deleteAll` | Sentinel `-1` translated to `null` (`:207`) |
| `_keyPartnershipId` | `partnership_id` | `int?` (stored as string) | `AuthState.setPartner`, `PartnerState.refreshFromRealtime` | `StorageService.getPartnershipId`, `AuthState.init` | Partnership lifetime | `deleteAll` | `deleteAll` | |
| `_keyDeviceFingerprint` | `device_fingerprint` | `String` (UUID v4) | `StorageService.getOrCreateDeviceFingerprint` | `ApiService._buildHeaders`, `DeviceTokenService.getDeviceFingerprint`, `AuthState._syncBackendSession` | Device lifetime — **destroyed on logout** | `deleteAll` **deletes this** | `deleteAll` | See F-SC1 |
| `_keyRequestBindingSecret` | `request_binding_secret` | `String?` | `AuthState._syncBackendSession` via `StorageService.saveRequestBindingSecret` | `ApiService._buildHeaders` | Session lifetime | `deleteAll` | `deleteAll` | Also bridges into `ApiService._cachedRequestBindingSecret`; if missing, `ApiService._buildHeaders` re-runs `_syncBackendSession` through `onMissingBindingSecret` before signing (deduplicated in-flight, 30s cooldown) |

### SharedPreferences — Authentication & Identity

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | Notes |
|---|---|---|---|---|---|---|---|---|
| `_keyUsername` | `username` | `String?` | `AuthState.setLoginData` | `GameState._resolveCachedNames`, `GameRepository.submitAnswer`, all `notifyPartnerOnce` calls | Account lifetime | `p.clear()` | `clearAppCache` **does not** remove this | Non-sensitive (display name prefix). |
| `_keyPartnerDisplayName` | `partner_display_name` | `String?` | `StorageService.savePartner` | `StorageService.getPartnerDisplayName`, `AuthState.init` | Partnership lifetime | `p.clear()` | Not cleared (retained across wipe) | Removed by `clearPartner()` on dissolution. |

### SharedPreferences — Feature Caches

> When a partnership is active, every key below is stored as `base:<partnership_id>` (`StorageService._feat`); with no partnership (single user) the unqualified `base` key is used. All variants are purged on partnership transitions (F-SC8, see §Cross-partnership checkpoint contamination). `user_profile`, `profile_pic_version`, `drive_thumb_cache` stay account/device-scoped and are never namespaced.

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | Invalidation | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `_keyMissYouTotal` | `miss_you` | `int` | `HomepageState.fetchTotalMissYou`, `HomepageState.addMissYou` | `HomepageState._loadFromCache` | Until overwrite / 60s freshness gate | `p.clear()` | `clearAppCache` | `CacheService.needsRefresh(kMissYou)` time-based (60s) | Not changed by `sendMissYou` checkpoint update |
| `_keyMoodMe` | `mood_me` | `String` (emoji) | `MoodState.fetchMyMood`, `MoodState.updateMood` | `MoodState.loadCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | |
| `_keyMoodPartner` | `mood_partner` | `String` (emoji) | `MoodState.fetchPartnerMood` | `MoodState.loadCache`, `MoodState.loadPartnerMoodFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | |
| `_keyRecentEmojis` | `recent_emojis` | `List<String>` | `MoodState.fetchRecentCoupleEmojis`, `MoodState.updateMood` | `MoodState._loadMoodScreenCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | Up to 10 entries, order = recency |
| `_keyTimeline` | `mood_timeline` | `List<MoodEntry>` (JSON) | `MoodState.fetchTimeline`, `MoodState.loadMoreTimeline`, `MoodState.updateMood` | `MoodState._loadMoodScreenCache` | Until overwrite (partial pages only) | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | **Overwritten to only 4 items on each full refetch** — deep pages lost on re-init (`:179–184`) |
| `_keyBucketList` | `bucket_list` | `List<BucketItem>` (JSON) | `BucketState.fetchBucket`, `BucketState.applyRealtimeEvent` (debounced 2s, flushed on app-pause/dispose) | `BucketState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kBucketItems` checkpoint (created\_at-based) | |
| `_keyGameMatches` | `game_matches` | `int` | `GameState.fetchStats` | `GameState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kGameAnswers` checkpoint | |
| `_keyGameQuestion` | `game_question` | `GameNewQuestionResponse` (JSON) | `GameState.fetchNewQuestion`, `GameState.handleQuestionInsert/Update/Delete`, `GameState.submitAnswer` | `GameState._loadFromCache`, `GameState._resolveCachedNames` | Until overwritten or both\_answered | `p.clear()` | `clearAppCache` | Cleared explicitly on `both_answered` / delete (`clearCachedGameQuestion`) | Contains user names (optionA/optionB resolved on cache read at `:44–69`) |
| `_keyGameHistory` | `game_history` | `List<GameHistoryItem>` (JSON) | `GameState.fetchHistory`, `GameState.submitAnswer`, `GameState.handleAnswerInsert/Update/Delete` | `GameState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kGameAnswers` checkpoint | |
| `_keyDriveCache` | `drive_cache` | `List<DriveItem>` (JSON) | `DriveState.syncDriveItems`, `DriveState.refreshFromRealtime`, `DriveState.addFileItemR2`, `DriveState.deleteItem`, `DriveState.toggleFavorite`, `DriveState.addReaction` | `DriveState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kDriveItems` checkpoint (updated\_at-based) | Full list re-serialized on every mutation; writes serialized through `CacheWriteQueue` (F-SC12 resolved) |
| `_keyUserProfile` | `user_profile` | `User` (JSON) | `ProfileState.loadProfile`, `ProfileState.updateDisplayName`, `ProfileState.uploadProfilePhoto` | `ProfileState.loadProfile` (cache-first) | Until overwrite | `p.clear()` | `clearAppCache` | **None** — only overwritten on explicit `loadProfile(force)` | **Contains PII: email, authId, partnershipCode** — stored in plaintext (`:52–63` of `auth_models.dart`) |
| `_keyPartnerProfile` | `partner_profile` | `User` (JSON) | `ProfileState.loadProfile` | `ProfileState.loadProfile` (cache-first) | Until overwrite | `p.clear()` | `clearAppCache` | **None** | Same PII concern as user_profile |
| `_keyProfilePicVersion` | `profile_pic_version` | `int` (millisecondsSinceEpoch) | `ProfileState.uploadProfilePhoto` | **No consumer** | Until overwrite | `p.clear()` | `clearAppCache` | Dead write-only key — never read (`:317` of `storage_service.dart`) | F-SC2 |
| `_keyDriveThumbCache` | `drive_thumb_cache` | — | **No producer** | **No consumer** | N/A | `p.clear()` | `clearAppCache` | Dead key — declared (`:47`) and cleared but never written or read | F-SC3 |

### SharedPreferences — Checkpoints (CacheService)

> Checkpoint keys are stored as `chk_x:<partnership_id>` while a partnership is active and purged with the feature caches on partnership transitions (F-SC8). Cold-start compare happens inside a single partnership's namespace only.

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | See §Checkpoints |
|---|---|---|---|---|---|---|---|---|
| `kGameAnswers` | `chk_game_answers` | `String` (ISO timestamp or `EMPTY`) | `GameState._updateGameCheckpoint` | `BaseRepository.hasChanges` via `GameRepository.hasNewGameActivity` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** (survives wipe) | §Checkpoints |
| `kMoods` | `chk_moods` | `String` (ISO timestamp or `EMPTY`) | `MoodState._updateMoodsCheckpoint` | `BaseRepository.hasChanges` via `MoodRepository.hasNewMoods` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kBucketItems` | `chk_bucket_items` | `String` (ISO timestamp or `EMPTY`) | `BucketState._updateBucketCheckpoint` | `BaseRepository.hasChanges` via `BucketRepository.hasNewBucketItems` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kDriveItems` | `chk_drive_items` | `String` (ISO timestamp or `EMPTY`) | `DriveState._updateDriveCheckpointFromItems`, `syncDriveItems`, `hasDriveChanges` | `DriveRepository.fetchChangeProbe` (compared against `public.drive_change_probe()`), `fetchDriveItemsIncremental` (as query bound) | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kMissYou` | `chk_miss_you` | `String` (ISO timestamp or `EMPTY`) | `HomepageState.fetchTotalMissYou`, `HomepageState.sendMissYou` | `CacheService.needsRefresh` (time-based freshness gate, 60s) | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |

### SharedPreferences — App Preferences (outside StorageService)

| Key | Storage key string | Producer | Consumer | Notes |
|---|---|---|---|---|
| `LanguageHelper.storageKey` | `app_language_code` | `LanguageProvider.setLocale` | `LanguageProvider.loadSavedLocale`, `NotificationService.showRemoteMessage` | **Preserved on logout** — `StorageService.clearAll()` re-persists it after `p.clear()` (device-level preference, F-SC4 resolved) |
| `ThemeProvider.storageKey` | `app_theme_mode` | `ThemeProvider.setThemeMode` (stores the `ThemeMode` enum name) | `ThemeProvider.loadSavedMode` (before `runApp`), `MaterialApp.themeMode` via the root `Selector2` | **Preserved on logout** — re-persisted by `StorageService.clearAll()` alongside the language key; an unrecognized value falls back to `dark` |

### Media File Cache (flutter\_cache\_manager)

| Manager | Cache key / DB name | Max objects | Stale period | URL keys used | Consumer | Clear on logout/wipe? |
|---|---|---|---|---|---|---|
| `MediaCacheManager` (singleton) | `justus_media_cache` | 300 | 30 days | `item.content` (raw R2 filename like `drive/...`) from drive grid; `imageUrl` (profile R2 key) from `VPAvatar` | `DriveScreen._buildGridViewCell` (`:317`), `VPAvatar` (`:201–203`), via `CachedNetworkImage` | **NO** — `emptyCache()` exists in `DriveState` (`:282`) but is **never called** from UI. `DriveState.clearMediaCache` is dead code. |
| Default (`DefaultCacheManager`) | `libCachedImageData` (default) | default | 1 week default | Resolved `/api/v1/media/file?filename=...` URL from `drive_grid_item.dart:68`, `protected_network_image.dart:31` (no cacheManager param) | `DriveGridItem._buildContent` (`:79`), `ProtectedNetworkImage` in drive\_item\_screen (`:281`), `VPAvatar` fallback in vp\_widgets if cacheManager passed as default | **NO** |

---

## JSON Serialization Offloading

All large-structure cache operations use `compute()` to offload JSON encode/decode to background isolates:

| Operation | Isolate function | Location |
|---|---|---|
| `_saveJson(Map)` | `_isolateEncodeMap` | `storage_service.dart:23` |
| `_getJson(Map)` | `_isolateDecodeMap` | `storage_service.dart:17` |
| `_saveJsonList(List)` | `_isolateEncodeList` | `storage_service.dart:25` |
| `_getJsonList(List)` | `_isolateDecodeList` | `storage_service.dart:20` |
| `ApiService._safeCall` | `_isolateDecodeResponse` | `api_service.dart:20` |

On deserialization failure (`fromJson` throws), `_getJson`/`_getJsonList` catch the error and return `null`/`[]` respectively — silent data loss masked as empty cache.

---

## Checkpoint Analysis

### How checkpoints work

`CheckpointMixin.saveMaxTimestampCheckpoint` (`:4–31` of `checkpoint_mixin.dart`) takes a list of ISO-8601 timestamp strings, parses them, sorts descending, and writes the maximum as the new checkpoint. If the list is empty, it writes `CacheService.kCheckpointEmpty = 'EMPTY'`. Every write is epoch-gated on the fetch that produced it (see state-management doc, F-SM14 resolved).

`BaseRepository.hasChanges` (`:79–108` of `base_repository.dart`) compares the checkpoint against the server's `max(field)` queried from Supabase:
- `checkpoint == null` → true (never synced)
- `serverMax == null` (server has no rows) → true if checkpoint is not `EMPTY` (data was deleted)
- Both parseable → true if `serverDate.isAfter(checkpointDate)` (strict `>`)
- Equal timestamps → **false** (treated as no change)

`loadWithChangeDetection` (`:46–58` of `base_state.dart`) orchestrates: load cache → if `hasChanges` → `unawaited(fetchFromNetwork)` (fire-and-forget, no await).

Checkpoint keys are partnership-scoped (`chk_x:<partnership_id>` via `CacheService._scoped`), so `hasChanges` always compares within the current partnership's namespace; a partnership transition clears all checkpoint variants (F-SC8).

### Per-checkpoint analysis

**chk\_game\_answers** (`CacheService.kGameAnswers`)
- Updated by: `GameState._updateGameCheckpoint` (`:90–106` of `game_state.dart`) — max of `game_answers.updated_at` filtered by `[uid, partnerId]`.
- Compared field: `game_answers.updated_at` — bumped on every UPDATE by the `set_public_game_answers_updated_at` BEFORE-UPDATE trigger (including the upsert in `submitAnswer`), so partner answer changes are detected by checkpoint on cold start and polling fallback.

**chk\_moods** (`CacheService.kMoods`)
- Updated by: `MoodState._updateMoodsCheckpoint` (`:70–79` of `mood_state.dart`) — max of all timeline entry `createdAt` + `userMoodUpdatedAt` + `partnerMoodUpdatedAt`.
- Compared field: `moods.created_at`.
- Insert-only table → no update-miss issue.
- Boundary miss: new mood row with `created_at` exactly equal to the checkpoint max would be treated as `isAfter` → false → missed. Same-timestamp miss is unlikely in practice.

**chk\_bucket\_items** (`CacheService.kBucketItems`)
- Updated by: `BucketState._updateBucketCheckpoint` (`:59–65` of `bucket_state.dart`) — max of `items[i].updatedAt`.
- Compared field: `bucket_items.updated_at` — bumped on every UPDATE by the `set_public_bucket_items_updated_at` BEFORE-UPDATE trigger (including `toggleBucketItem`), so partner done-toggle changes are detected by checkpoint on cold start and polling fallback.
- Deletion still invisible to the checkpoint (rows disappear without a timestamp to compare) — Realtime DELETE + polling `refreshFromRealtime()` cover it.

**chk\_drive\_items** (`CacheService.kDriveItems`)
- Updated by: `DriveState._updateDriveCheckpointFromItems` / `syncDriveItems` — max of `updatedAt` from fetched items.
- Compared field: `max(drive_items.updated_at)`, returned by the `public.drive_change_probe()` RPC.
- Revalidation cost: one RPC per cycle. `DriveState` memoizes the probe for 10 s and shares it between the change gate and `syncDriveItems`; the memo is dropped on every local cache write and in `clear()` (logout / partnership switch).
- Incremental sync: `fetchDriveItemsIncremental` (of `drive_repository.dart`) applies `gt('updated_at', checkpoint)` — strict `>`: items with `updated_at` equal to checkpoint are skipped. Same-timestamp misses extremely unlikely (microsecond precision).
- **Deletion detection**: incremental fetch returns only existing rows, so deletions are invisible to the cursor. The same probe's `item_count` is compared against the cached list length (both in `_hasDriveChanges` and in `syncDriveItems`, from the memoized value); on mismatch it does a full fetch that **replaces** the list, dropping locally-deleted rows. A same-count swap (insert + delete between refreshes) slips past the count check and is recovered by Realtime DELETE events or polling `_refreshAll`. F-SC7

**chk\_miss\_you** (`CacheService.kMissYou`)
- Updated by: `HomepageState.fetchTotalMissYou` (`:51–54` of `homepage_state.dart`) and `sendMissYou` (`:78–80`) — writes `DateTime.now().toUtc().toIso8601String()` (local clock, not server time).
- Compared field: none — `CacheService.needsRefresh` (`:40–50`) uses this as a **time-based freshness gate** (60-second TTL). Does not compare against server data. Fine as designed.

### Cross-partnership checkpoint contamination — solved (F-SC8)

Feature caches **and** checkpoints are namespaced per-partnership: while a partnership with id `N` is active, every partnership-scoped cache key is stored as `base:N` and every checkpoint as `chk_x:N` (`StorageService._feat`, `CacheService._scoped`). The active namespace is bound at `AuthState.init` cold start (`storage_service.dart:setActivePartnership`) and after every partnership-id write.

On a genuine partnership transition the old scope is purged — feature caches and checkpoints are removed for the base (legacy unscoped), old, and new scopes, in both `StorageService.savePartnershipId` and `StorageService.clearPartner` (`purgeCacheVariants` + `CacheService.purge`). Writes with an unchanged id (cold start, realtime refresh) never purge, so caching survives app restarts.

1. A new partnership's cache miss → checkpoint `null` → `hasChanges` **true** → refetch.
2. Old-partnership keys are physically removed, so no stale data can be read even if scoping were bypassed.
3. Checkpoint-based hasChanges comparisons stay within a single partnership's namespace.

**Impact**: Re-partnering no longer shows previous-partner data on Drive, Bucket, Games, Mood, or MissYou tabs under the polling fallback or cold-start path. Verified by `Flutter/test/partnership_scope_test.dart` (F-SC8: namespacing, no-purge-on-same-id, purge on transition, `clearPartner` reset, wipe/logout namespace clearing).

**Assumption**: `partnerships.id` values are never reused after dissolution; combined with the transition purge this guarantees a fresh namespace per partnership history.

---

## Cache Expiration & Eviction

| Cache | Expiration | Eviction | Max size | Notes |
|---|---|---|---|---|
| `MediaCacheManager` (file cache) | `stalePeriod = 30 days` | LRU after 300 objects (`maxNrOfCacheObjects`) | 300 objects | `flutter_cache_manager` internal SQLite DB. Cleared on wipe (F-SC11 resolved); not cleared on logout (F-SC9). |
| `DefaultCacheManager` (file cache) | default (`stalePeriod = 7 days`) | default LRU | default | Used by `drive_grid_item`, `ProtectedNetworkImage` (when no `cacheManager` param). Cleared on wipe (F-SC11 resolved); not cleared on logout (F-SC9). |
| SharedPreferences feature caches | **No TTL** | Never evicted | N/A | Overwritten on each fetch. Multiple concurrent writes can race (see §Edge Cases). |
| Checkpoints | **No TTL** | Never evicted until overwritten | N/A | Reset on logout (`CacheService.clearAll`), **wipe** (`CacheService.clearAll` from `wipeAppData`), or explicit force-refresh (`clearCheckpoints`). |
| `PartnershipRepository._activePartnershipFuture` | In-memory only | Invalidated by `clearPartnershipCache()` or user-id mismatch detection | 1 future | Static map in `PartnershipRepository` (`:9–10`). Clears on realtime partnership event, but **not** on logout. Self-heals on next call with different user-id. |

---

## Logout Behavior

`AuthState.logout()` (`:534–548` of `auth_state.dart`):

1. `_authRepo.signOut()` — clears Supabase session (synchronous in-memory).
2. `CacheService.clearAll()` — removes all 5 checkpoint keys from SharedPreferences.
3. `StorageService.clearAll()` — `p.clear()` removes **all** SharedPreferences keys (feature caches and every constant in StorageService) **except `app_language_code`, which is read before and re-persisted after the clear**; `_secureStorage.deleteAll()` removes **all** secure storage keys.
4. `ApiService.clearHeadersCache()` — sets `_cachedDeviceFingerprint = null`, `_cachedRequestBindingSecret = null`.

**Net effect**: All cached feature data, identity, tokens, and the device fingerprint are wiped. The language preference (`app_language_code`) is preserved as a device-level preference. The media file cache (both `MediaCacheManager` and `DefaultCacheManager`) is **not** cleared. F-SC1 (fingerprint) and F-SC9 (media cache)

---

## Wipe Behavior

`ProfileState.wipeAppData()` (`:139–149` of `profile_state.dart`):
1. Backend `POST /api/v1/user/wipe` — server deletes the user's data.
2. `StorageService.clearAppCache()` — removes the feature-cache SharedPreferences keys.
3. `CacheService.clearAll()` — removes all 5 checkpoint keys (base + scoped variants).
4. `emptyAppMediaCaches()` — empties the `MediaCacheManager` **and** `DefaultCacheManager` file stores (best-effort; platform failures are logged, never fail the wipe).
5. Feature states `clear()` — resets in-memory state.
6. `RealtimeSyncService.refreshChannel()` — resubscribes after suppress/resume.

**Not wiped by wipe**: `app_language_code`, `username`, `partner_display_name` (`clearAppCache()` deliberately does not remove account-identity keys). F-SC10/F-SC11 resolved: checkpoints and media files are cleared so a fresh login genuinely starts empty and no previous media thumbnails pop from disk.

---

## Edge Cases & Race Conditions

### F-SC1: Logout destroys the device fingerprint

**Evidence**: `FlutterSecureStorage.deleteAll()` at `storage_service.dart:392` removes `_keyDeviceFingerprint`. On next login, `getOrCreateDeviceFingerprint` generates a new UUID v4 (`:180–181`).

**What**: The backend binds sessions to `device_fingerprint_hash` (`authMiddleware.js:170–171`, `session.utils.js:23–25`). A new fingerprint on each logout/reattempt resets the device identity, defeating risk-based detection (`authRisk.service.js:13–15`). The device fingerprint is intended to persist across sessions, not per-account.

**Impact**: Backend login-risk tracking and session binding become ineffective after logout/re-login. A malicious user could bypass device-level login-rate restrictions by logging out and back in.

**Confidence**: HIGH

---

### F-SC2: `profile_pic_version` is a dead write-only key

**Evidence**: `saveProfilePicVersion` called at `profile_state.dart:115–117` (write: `DateTime.now().millisecondsSinceEpoch`). `getProfilePicVersion` defined at `storage_service.dart:317–320`. Grep confirms **no consumer** — `getProfilePicVersion` is never called anywhere in the codebase.

**What**: The intended use was likely to bust the `MediaCacheManager` entry for the old profile picture by appending a version query parameter to the URL. Without a consumer, profile picture changes do not invalidate the cached image in `MediaCacheManager`. The new upload produces a different R2 filename (different UUID), so the new picture renders under a new cache key — but the old cached image remains in the file cache indefinitely, wasting disk space.

**Impact**: Low — cache key collision avoided by new filename. Minor disk waste. Dead code.

**Confidence**: HIGH

---

### F-SC3: `_keyDriveThumbCache` is a dead declared constant

**Evidence**: Declared at `storage_service.dart:47`. Listed in `clearAppCache` (`:377`). **No producer or consumer** exists anywhere in the codebase.

**Impact**: No functional impact. Dead constant.

**Confidence**: HIGH

---

### F-SC9: Media file cache not cleared on logout

**Evidence**: `logout()` at `auth_state.dart:534–548` clears SharedPreferences and secure storage but not the flutter\_cache\_manager file store — the wipe path clears it (`emptyAppMediaCaches()`, see Wipe Behavior) but logout does not. `DriveState.clearMediaCache()` (`:323–325`) delegates to `emptyAppMediaCaches()` but is still not wired into any UI/lifecycle hook.

**What**: On a shared device, after logging out of account A and into account B, cached images from account A's media (profile pictures, drive images) remain on disk. If `CachedNetworkImage` is given the same URL key (e.g. a profile picture object key that happens to match), the old image from account A is shown to account B. In practice, R2 object keys include user-specific paths (e.g. `drive/42/...`), so direct cross-account display via the same key is unlikely — but the files remain on disk and are accessible via the app's cache directory.

**Impact**: Privacy concern on shared devices. Cached files are not encrypted (flutter\_cache\_manager stores raw files in the app cache directory). Not a direct data-exposure bug (no R2 key reuse across accounts), but residual data persists.

**Confidence**: MEDIUM (unlikely actual display cross-account, but files remain)

---

### F-SC15: `StorageService.prefs` async getter reinitializes if `_prefs` is null

**Evidence**: `StorageService.prefs` (`:64–68`) — `_prefs ??= await SharedPreferences.getInstance()`. If `init()` was never called (should not happen in production, but could in tests or edge cases), `_prefs` is null and the async getter re-initializes lazily.

**What**: This is a safety net, not a bug. However, `prefsSync` (`:59–62`) asserts and throws in debug mode if `_prefs == null`. Code paths using `prefsSync` (none in production — all code uses `await prefs`) would crash. In practice, `main()` calls `init()` before any other code runs.

**Impact**: No production impact. Test infrastructure relies on `SharedPreferences.setMockInitialValues({})` in test setup, which pre-populates the singleton — but `StorageService.resetForTest()` at `:70–72` is defined but **never called** from tests (tests use `SharedPreferences.setMockInitialValues` instead). F-SC16

**Confidence**: HIGH (no production issue)

---

### F-SC16: `StorageService.resetForTest()` is defined but never called

**Evidence**: `resetForTest()` at `storage_service.dart:70–72` sets `_prefs = null`. Grep confirms it is never called from any test file. Tests use `SharedPreferences.setMockInitialValues({})` at the test `setUp` instead, which pre-populates the singleton before `StorageService.prefs` is ever accessed.

**What**: Dead test utility.

**Impact**: No functional impact. Tests work correctly because `SharedPreferences` mock is set up first.

**Confidence**: HIGH

---

### F-SC17: `Username` and `partner_display_name` survive wipe

**Evidence**: `clearAppCache()` at `:368–387` clears 14 keys — `_keyUsername` and `_keyPartnerDisplayName` are **not** in the list. `ProfileState.wipeAppData()` runs `clearAppCache()` + `CacheService.clearAll()` + `emptyAppMediaCaches()`, none of which remove the identity keys.

**What**: After a data wipe, the app retains the old username and partner display name. These are used by `GameState._resolveCachedNames` (`:51–69`) to resolve question option labels from cache, and by all `notifyPartnerOnce` calls to include a `partnerName` param. After a wipe + re-partner, the old username is correct (user's own name doesn't change), but the partner display name may be stale until re-fetched.

**Impact**: Minor — name corrects itself after the next `setPartner` call.

**Confidence**: MEDIUM

---

## Security Considerations

1. **PII in SharedPreferences plaintext**: `user_profile` and `partner_profile` JSON caches contain `email`, `authId`, and `partnershipCode` fields stored as unencrypted strings in SharedPreferences (`auth_models.dart:52–63`). On rooted/jailbroken devices, this data is accessible via filesystem inspection. Flutter secure storage is only used for tokens and IDs — not for profile PII. F-SC18 (MEDIUM confidence)

2. **Device fingerprint deleted on logout**: F-SC1 details this. The fingerprint should persist across sessions for device-level security (risk analysis, session binding). Deleting it on logout defeats its purpose.

3. **Media files not encrypted on disk**: flutter\_cache\_manager stores files in the app cache directory in plaintext. On a compromised device, cached R2 media (including profile pictures) is readable.

4. **`reportFailedLogin` is dead code**: The `AuthRepository.reportFailedLogin` method and the corresponding backend endpoint `POST /api/v1/auth/login-attempt` exist but are **never called** from the Flutter app (`auth_repository.dart:20–26`). Failed login attempts are not reported to the backend, so the backend risk-detection system has no client-side telemetry.

5. **Binding secret bridge across layers**: `StorageService.saveRequestBindingSecret` at `:186–189` directly mutates `ApiService._cachedRequestBindingSecret` — a static field on a different class. This creates a hidden bidirectional dependency that makes the boundary between storage and networking porous.

---

## Invariants

1. **`StorageService.init()` must be called before any read/write.** Satisfied by `main()` (`:49`). `prefsSync` asserts in debug; `prefs` lazy-inits as safety net.
2. **`clearAll()` must be called on every logout.** `AuthState.logout` satisfies this (`:537`). No other logout path exists.
3. **Feature caches are partitioned per-partnership, not per-user.** Read/write keys are namespaced with the active partnership id (`base:<partnership_id>`), so one account's cached data under partnership A is never exposed under partnership B; transitions purge all variants. Logout must clear all data — `StorageService.clearAll()` satisfies this by calling `p.clear()`.
4. **Feature caches cannot be read before `loadWithChangeDetection` completes.** This is an architectural invariant — all feature state reads (from UI) occur after `init()` completes. Violated only if realtime events arrive before init finishes (possible during startup).
5. **`MediaCacheManager` is a singleton** (`:11–12`). Only one instance exists per process. The `Config` (stalePeriod, maxNrOfCacheObjects) is fixed at construction time.
6. **Checkpoints are written after every successful network fetch.** Every `fetchFromNetwork` path writes a checkpoint. Partial failures (e.g. `fetchStats` succeeds but `fetchHistory` fails) may leave checkpoints inconsistent with the actual cache state. The checkpoint reflects whatever was fetched, not the full intended fetch.

---

## Tests

| Test file | Storage coverage |
|---|---|
| `Flutter/test/mood_state_test.dart` | Verifies `updateMood` writes to `StorageService.getMood('me')` on success (`:67`). F-SM12/F-SC14: on error `updateMood` fully rolls back `_recentEmojis`/timeline and never writes the optimistic `id:0,userId:0` phantom to the cache; success replaces the placeholder with the server-confirmed entry. Verifies `initHome` reads cached moods (`:87–97`). Uses `SharedPreferences.setMockInitialValues({})` + mock secure storage channel. |
| `Flutter/test/game_state_test.dart` | Verifies `fetchNewQuestion` caches the question (`:67–70`). Verifies `submitAnswer` updates history. Uses `SharedPreferences.setMockInitialValues({})` + mock secure storage channel. |
| `Flutter/test/test_helpers/mock_secure_storage.dart` | Mocks `flutter_secure_storage` platform channel for test isolation. |
| `Flutter/test/drive_sync_test.dart` | F-SC7 deletion detection via row-count mismatch + full-refetch merge; matching row counts keep the incremental cursor path; a re-entering tab inside the 10 s probe TTL issues no new probe while a local mutation invalidates it at once. |
| `Flutter/test/logout_state_reset_test.dart` | `drive.clear()` drops the memoized change probe, so the next account never inherits it. |
| `Flutter/test/drive_cache_serialization_test.dart` | F-SC12: concurrent optimistic mutation + trailing refresh serialize their cache writes — the cache ends equal to the final in-memory drive list (no older snapshot clobbering a newer one). |
| `Flutter/test/bucket_flush_test.dart` | F-SC13: app-pause and `dispose()` flush the pending 2s-debounced bucket cache write immediately. |
| `Flutter/test/partnership_scope_test.dart` | F-SC8: per-partnership namespacing of feature caches/checkpoints, no purge on same id, purge on transition, `clearPartner`/`clearAll`/`clearAppCache` namespace clearing. |
| `Flutter/test/profile_state_test.dart` | F-SC10/F-SC11: `wipeAppData` clears checkpoints, feature caches and profile keys (runs with `test_helpers/mock_path_provider.dart` so `emptyAppMediaCaches` executes for real). |
| `Flutter/test/test_helpers/mock_path_provider.dart` | Mocks `plugins.flutter.io/path_provider` so `flutter_cache_manager` works in widget tests. |
| `Flutter/test/api_service_test.dart` | Covers HTTP error handling — no storage-specific assertions. |

**Not covered by tests**: `StorageService` direct read/write paths (non-feature), `CheckpointMixin`, `BaseRepository.hasChanges`, `loadWithChangeDetection`, media-cache clearing on **logout**, `CacheService.needsRefresh`. (Concurrent cache write races and bucket dispose/app-pause flush are now covered — F-SC12/F-SC13.)

---

## Known Issues

- `DriveState.clearMediaCache()` delegates to `emptyAppMediaCaches()` but is still not called from any UI/lifecycle hook (the wipe path calls the helper directly). F-SC9
- `StorageService.getProfilePicVersion` / `saveProfilePicVersion` — write-only; no consumer exists.
- `StorageService._keyDriveThumbCache` — declared and cleared but never written or read.
- `reportFailedLogin` / `AuthRepository.reportFailedLogin` — defined but never called.
- `StorageService.resetForTest()` — defined but never called from tests.

---

## Implementation Status

| Component | Status |
|---|---|
| `StorageService` (SharedPreferences + secure storage) | IMPLEMENTED |
| `CacheService` (checkpoints + freshness gate) | IMPLEMENTED |
| `CheckpointMixin` (max-timestamp checkpoint) | IMPLEMENTED |
| `loadWithChangeDetection` (cache → checkpoint → fire-and-forget network) | IMPLEMENTED |
| `MediaCacheManager` (R2 file cache, 30-day TTL, 300 items) | IMPLEMENTED |
| `MediaCacheManager.emptyCache()` wired to UI | NOT IMPLEMENTED (dead code) |
| JSON encode/decode offloaded via `compute()` | IMPLEMENTED |
| Feature cache invalidation on partnership change | IMPLEMENTED (namespaced + purged on transition) |
| Media cache clearing on wipe | IMPLEMENTED (F-SC11: `emptyAppMediaCaches` from `wipeAppData`) |
| Media cache clearing on logout | NOT IMPLEMENTED (F-SC9) |
| `profile_pic_version` used to bust image cache | NOT IMPLEMENTED (dead write, F-SC2) |
| `reportFailedLogin` wired from UI | NOT IMPLEMENTED (dead code) |
| Language preference persistence across logout | IMPLEMENTED (preserved, F-SC4) |
| Theme preference persistence across restart + logout | IMPLEMENTED (`app_theme_mode`; restored pre-`runApp`, preserved by `clearAll`) |

---

## Notes

- **No per-user key namespacing.** All cache keys are global strings (e.g. `bucket_list`, `drive_cache`). Cross-account safety depends entirely on `clearAll()` being called on logout. No defense-in-depth exists.
- **SharedPreferences is not the ideal store for large JSON blobs.** `drive_cache` can grow to contain hundreds of `DriveItem` objects with metadata and reactions, all serialized into a single `p.setString` call on every mutation. On Android, SharedPreferences serializes all pending writes synchronously to disk on app backgrounding — large values cause jank.
- **`flutter_cache_manager` file store is separate from SharedPreferences.** Clearing SharedPreferences (via `p.clear()`) does NOT remove cached media files. Media cleanup requires explicit `MediaCacheManager().emptyCache()` calls, which are currently dead code.
- **Token storage is written by both the `tokenRefreshed` listener and `ApiService._tryRefreshToken`.** Both are downstream of the same Supabase SDK `auth.refreshSession()` call, and gotrue dedupes concurrent refreshes by refresh token, so the two writers persist identical values and cannot race (todo# 1.6).
- **`PartnershipRepository._activePartnershipFuture` is a static future-keyed cache.** It persists across tab switches and even across cold starts (the static variable lives for the process lifetime). This is the only in-memory-only cache in the system. All others are persisted to disk.

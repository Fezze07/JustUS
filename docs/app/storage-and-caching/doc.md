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
| `_keyAccessToken` | `access_token` | `String?` | `AuthState.setLoginData`, `tokenRefreshed` listener, `ApiService._tryRefreshToken` | `AuthState.init`, `ApiService._getHeaders` reads from Supabase live session (NOT from secure storage) | Session lifetime | `deleteAll` | `deleteAll` | Written in 3 places; read in 1 (`AuthState.init` for bootstrap check only) |
| `_keyRefreshToken` | `refresh_token` | `String?` | `AuthState.setLoginData`, `tokenRefreshed` listener, `ApiService._tryRefreshToken` | `ApiService._tryRefreshToken` (manual refresh proxy) | Session lifetime | `deleteAll` | `deleteAll` | |
| `_keyPartnerId` | `partner_id` | `int?` (stored as string) | `AuthState.setPartner`, `PartnerState.refreshFromRealtime` | `StorageService.getPartnerId` (all feature states/repos) | Partnership lifetime | `deleteAll` | `deleteAll` | Sentinel `-1` translated to `null` (`:207`) |
| `_keyPartnershipId` | `partnership_id` | `int?` (stored as string) | `AuthState.setPartner`, `PartnerState.refreshFromRealtime` | `StorageService.getPartnershipId`, `AuthState.init` | Partnership lifetime | `deleteAll` | `deleteAll` | |
| `_keyDeviceFingerprint` | `device_fingerprint` | `String` (UUID v4) | `StorageService.getOrCreateDeviceFingerprint` | `ApiService._buildHeaders`, `DeviceTokenService.getDeviceFingerprint`, `AuthState._syncBackendSession` | Device lifetime — **destroyed on logout** | `deleteAll` **deletes this** | `deleteAll` | See F-SC1 |
| `_keyRequestBindingSecret` | `request_binding_secret` | `String?` | `AuthState._syncBackendSession` via `StorageService.saveRequestBindingSecret` | `ApiService._buildHeaders` | Session lifetime | `deleteAll` | `deleteAll` | Also bridges into `ApiService._cachedRequestBindingSecret` (`:188`) |

### SharedPreferences — Authentication & Identity

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | Notes |
|---|---|---|---|---|---|---|---|---|
| `_keyUsername` | `username` | `String?` | `AuthState.setLoginData` | `GameState._resolveCachedNames`, `GameRepository.submitAnswer`, all `notifyPartnerOnce` calls | Account lifetime | `p.clear()` | `clearAppCache` **does not** remove this | Non-sensitive (display name prefix). |
| `_keyPartnerDisplayName` | `partner_display_name` | `String?` | `StorageService.savePartner` | `StorageService.getPartnerDisplayName`, `AuthState.init` | Partnership lifetime | `p.clear()` | Not cleared (retained across wipe) | **Not cleared on partnership dissolution** — `clearPartner()` removes it (`:364`). |

### SharedPreferences — Feature Caches

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | Invalidation | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `_keyMissYouTotal` | `miss_you` | `int` | `HomepageState.fetchTotalMissYou`, `HomepageState.addMissYou` | `HomepageState._loadFromCache` | Until overwrite / 60s freshness gate | `p.clear()` | `clearAppCache` | `CacheService.needsRefresh(kMissYou)` time-based (60s) | Not changed by `sendMissYou` checkpoint update |
| `_keyMoodMe` | `mood_me` | `String` (emoji) | `MoodState.fetchMyMood`, `MoodState.updateMood` | `MoodState.loadCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | |
| `_keyMoodPartner` | `mood_partner` | `String` (emoji) | `MoodState.fetchPartnerMood` | `MoodState.loadCache`, `MoodState.loadPartnerMoodFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | |
| `_keyRecentEmojis` | `recent_emojis` | `List<String>` | `MoodState.fetchRecentCoupleEmojis`, `MoodState.updateMood` | `MoodState._loadMoodScreenCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | Up to 10 entries, order = recency |
| `_keyTimeline` | `mood_timeline` | `List<MoodEntry>` (JSON) | `MoodState.fetchTimeline`, `MoodState.loadMoreTimeline`, `MoodState.updateMood` | `MoodState._loadMoodScreenCache` | Until overwrite (partial pages only) | `p.clear()` | `clearAppCache` | `CacheService.kMoods` checkpoint | **Overwritten to only 4 items on each full refetch** — deep pages lost on re-init (`:179–184`) |
| `_keyBucketList` | `bucket_list` | `List<BucketItem>` (JSON) | `BucketState.fetchBucket`, `BucketState.applyRealtimeEvent` (debounced 2s) | `BucketState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kBucketItems` checkpoint (created\_at-based) | |
| `_keyGameMatches` | `game_matches` | `int` | `GameState.fetchStats` | `GameState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kGameAnswers` checkpoint | |
| `_keyGameQuestion` | `game_question` | `GameNewQuestionResponse` (JSON) | `GameState.fetchNewQuestion`, `GameState.handleQuestionInsert/Update/Delete`, `GameState.submitAnswer` | `GameState._loadFromCache`, `GameState._resolveCachedNames` | Until overwritten or both\_answered | `p.clear()` | `clearAppCache` | Cleared explicitly on `both_answered` / delete (`clearCachedGameQuestion`) | Contains user names (optionA/optionB resolved on cache read at `:44–69`) |
| `_keyGameHistory` | `game_history` | `List<GameHistoryItem>` (JSON) | `GameState.fetchHistory`, `GameState.submitAnswer`, `GameState.handleAnswerInsert/Update/Delete` | `GameState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kGameAnswers` checkpoint | |
| `_keyDriveCache` | `drive_cache` | `List<DriveItem>` (JSON) | `DriveState.syncDriveItems`, `DriveState.refreshFromRealtime`, `DriveState.addFileItemR2`, `DriveState.deleteItem`, `DriveState.toggleFavorite`, `DriveState.addReaction` | `DriveState._loadFromCache` | Until overwrite | `p.clear()` | `clearAppCache` | `CacheService.kDriveItems` checkpoint (updated\_at-based) | Full list re-serialized on every mutation |
| `_keyUserProfile` | `user_profile` | `User` (JSON) | `ProfileState.loadProfile`, `ProfileState.updateBio`, `ProfileState.uploadProfilePhoto` | `ProfileState.loadProfile` (cache-first) | Until overwrite | `p.clear()` | `clearAppCache` | **None** — only overwritten on explicit `loadProfile(force)` | **Contains PII: email, authId, bio, partnershipCode** — stored in plaintext (`:52–63` of `auth_models.dart`) |
| `_keyPartnerProfile` | `partner_profile` | `User` (JSON) | `ProfileState.loadProfile` | `ProfileState.loadProfile` (cache-first) | Until overwrite | `p.clear()` | `clearAppCache` | **None** | Same PII concern as user_profile |
| `_keyProfilePicVersion` | `profile_pic_version` | `int` (millisecondsSinceEpoch) | `ProfileState.uploadProfilePhoto` | **No consumer** | Until overwrite | `p.clear()` | `clearAppCache` | Dead write-only key — never read (`:317` of `storage_service.dart`) | F-SC2 |
| `_keyDriveThumbCache` | `drive_thumb_cache` | — | **No producer** | **No consumer** | N/A | `p.clear()` | `clearAppCache` | Dead key — declared (`:47`) and cleared but never written or read | F-SC3 |

### SharedPreferences — Checkpoints (CacheService)

| Key constant | Storage key string | Data type | Producer | Consumer | Lifetime | Logout | Wipe | See §Checkpoints |
|---|---|---|---|---|---|---|---|---|
| `kGameAnswers` | `chk_game_answers` | `String` (ISO timestamp or `EMPTY`) | `GameState._updateGameCheckpoint` | `BaseRepository.hasChanges` via `GameRepository.hasNewGameActivity` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** (survives wipe) | §Checkpoints |
| `kMoods` | `chk_moods` | `String` (ISO timestamp or `EMPTY`) | `MoodState._updateMoodsCheckpoint` | `BaseRepository.hasChanges` via `MoodRepository.hasNewMoods` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kBucketItems` | `chk_bucket_items` | `String` (ISO timestamp or `EMPTY`) | `BucketState._updateBucketCheckpoint` | `BaseRepository.hasChanges` via `BucketRepository.hasNewBucketItems` | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kDriveItems` | `chk_drive_items` | `String` (ISO timestamp or `EMPTY`) | `DriveState._updateDriveCheckpointFromItems`, `syncDriveItems`, `hasDriveChanges` | `BaseRepository.hasChanges` via `DriveRepository.hasNewDriveItems`, `fetchDriveItemsIncremental` (as query bound) | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |
| `kMissYou` | `chk_miss_you` | `String` (ISO timestamp or `EMPTY`) | `HomepageState.fetchTotalMissYou`, `HomepageState.sendMissYou` | `CacheService.needsRefresh` (time-based freshness gate, 60s) | Until overwritten | `CacheService.clearAll` → `p.remove` | **Not cleared** | §Checkpoints |

### SharedPreferences — App Preferences (outside StorageService)

| Key | Storage key string | Producer | Consumer | Notes |
|---|---|---|---|---|
| `LanguageHelper.storageKey` | `app_language_code` | `LanguageProvider.setLocale` | `LanguageProvider.loadSavedLocale`, `NotificationService.showRemoteMessage` | **Deleted on logout** by `p.clear()` (`auth_state.dart:537`). Locale preference resets to system on logout. F-SC4 |

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

`CheckpointMixin.saveMaxTimestampCheckpoint` (`:4–26` of `checkpoint_mixin.dart`) takes a list of ISO-8601 timestamp strings, parses them, sorts descending, and writes the maximum as the new checkpoint. If the list is empty, it writes `CacheService.kCheckpointEmpty = 'EMPTY'`.

`BaseRepository.hasChanges` (`:79–108` of `base_repository.dart`) compares the checkpoint against the server's `max(field)` queried from Supabase:
- `checkpoint == null` → true (never synced)
- `serverMax == null` (server has no rows) → true if checkpoint is not `EMPTY` (data was deleted)
- Both parseable → true if `serverDate.isAfter(checkpointDate)` (strict `>`)
- Equal timestamps → **false** (treated as no change)

`loadWithChangeDetection` (`:46–58` of `base_state.dart`) orchestrates: load cache → if `hasChanges` → `unawaited(fetchFromNetwork)` (fire-and-forget, no await).

### Per-checkpoint analysis

**chk\_game\_answers** (`CacheService.kGameAnswers`)
- Updated by: `GameState._updateGameCheckpoint` (`:90–106` of `game_state.dart`) — max of `game_answers.created_at` filtered by `[uid, partnerId]`.
- Compared field: `game_answers.created_at`.
- Issue: game answers are upserted with `ON CONFLICT (game_id, user_id)` (`:51–55` of `game_repository.dart`). A partner's answer changes `selected_option` but does **not** update `created_at` (PostgreSQL upsert only updates changed columns). `hasChanges` therefore **misses partner answer changes** — returns false. Realtime handles answer updates via `handleAnswerUpdate`, but **polling fallback and cold-start miss this**. F-SC5

**chk\_moods** (`CacheService.kMoods`)
- Updated by: `MoodState._updateMoodsCheckpoint` (`:70–79` of `mood_state.dart`) — max of all timeline entry `createdAt` + `userMoodUpdatedAt` + `partnerMoodUpdatedAt`.
- Compared field: `moods.created_at`.
- Insert-only table → no update-miss issue.
- Boundary miss: new mood row with `created_at` exactly equal to the checkpoint max would be treated as `isAfter` → false → missed. Same-timestamp miss is unlikely in practice.

**chk\_bucket\_items** (`CacheService.kBucketItems`)
- Updated by: `BucketState._updateBucketCheckpoint` (`:59–65` of `bucket_state.dart`) — max of `items[i].createdAt`.
- Compared field: `bucket_items.created_at`.
- Issue: `toggleBucketItem` updates `done` via `bucket_items.update()` (`:57` of `bucket_repository.dart`) which does **not** change `created_at`. `hasChanges` therefore **misses partner done-toggle changes** — returns false. Realtime handles updates via `applyRealtimeEvent` case `'update'`, but **polling fallback and cold-start miss done-toggle changes**. F-SC6

**chk\_drive\_items** (`CacheService.kDriveItems`)
- Updated by: `DriveState._updateDriveCheckpointFromItems` (`:131–137`) / `syncDriveItems` (`:87–91`) — max of `updatedAt` from fetched items.
- Compared field: `v_drive_dashboard.updated_at`.
- Incremental sync: `fetchDriveItemsIncremental` (`:24–40` of `drive_repository.dart`) applies `gt('updated_at', checkpoint)` — strict `>`: items with `updated_at` equal to checkpoint are skipped. Same-timestamp misses extremely unlikely (microsecond precision).
- **Deletion miss**: `syncDriveItems` incremental fetch returns only existing rows. Deleted server rows do not appear. Without realtime, **deleted items persist in local cache forever**. Only realtime (`drive_items` DELETE event) triggers a full `refreshFromRealtime()` → full fetch. F-SC7

**chk\_miss\_you** (`CacheService.kMissYou`)
- Updated by: `HomepageState.fetchTotalMissYou` (`:51–54` of `homepage_state.dart`) and `sendMissYou` (`:78–80`) — writes `DateTime.now().toUtc().toIso8601String()` (local clock, not server time).
- Compared field: none — `CacheService.needsRefresh` (`:40–50`) uses this as a **time-based freshness gate** (60-second TTL). Does not compare against server data. Fine as designed.

### Cross-partnership checkpoint contamination

All checkpoints are **global keys** (not per-partnership). When a partnership dissolves and a new one forms:
1. Feature caches (`drive_cache`, `bucket_list`, `game_history`, `miss_you`, etc.) still hold the old partnership's data.
2. Checkpoints still hold timestamps derived from the old partnership's data.
3. On the new partnership's cold start, `hasChanges` compares the new partnership's `max(created_at/updated_at)` (which is likely older or absent) against the old checkpoint. If `newMax <= oldCheckpoint`, `hasChanges` returns **false** — no refresh occurs.
4. The UI displays the old partnership's data until a forced refresh (pull-to-refresh) or a realtime event with a higher timestamp.

**Impact**: After partnership change, feature tabs (Drive, Bucket, Games, Mood, MissYou) can display stale data from the previous partner indefinitely under the polling fallback or cold-start path. F-SC8

**Confidence**: HIGH — `BaseRepository.hasChanges` logic at `:79–108` confirms this. `clearPartner()` at `:359–364` does not touch feature caches or checkpoints.

---

## Cache Expiration & Eviction

| Cache | Expiration | Eviction | Max size | Notes |
|---|---|---|---|---|
| `MediaCacheManager` (file cache) | `stalePeriod = 30 days` | LRU after 300 objects (`maxNrOfCacheObjects`) | 300 objects | `flutter_cache_manager` internal SQLite DB. Not cleared on logout or wipe. |
| `DefaultCacheManager` (file cache) | default (`stalePeriod = 7 days`) | default LRU | default | Used by `drive_grid_item`, `ProtectedNetworkImage` (when no `cacheManager` param). Not cleared on logout or wipe. |
| SharedPreferences feature caches | **No TTL** | Never evicted | N/A | Overwritten on each fetch. Multiple concurrent writes can race (see §Edge Cases). |
| Checkpoints | **No TTL** | Never evicted until overwritten | N/A | Reset on logout (`CacheService.clearAll`) or explicit force-refresh (`clearCheckpoints`). |
| `PartnershipRepository._activePartnershipFuture` | In-memory only | Invalidated by `clearPartnershipCache()` or user-id mismatch detection | 1 future | Static map in `PartnershipRepository` (`:9–10`). Clears on realtime partnership event, but **not** on logout. Self-heals on next call with different user-id. |

---

## Logout Behavior

`AuthState.logout()` (`:534–548` of `auth_state.dart`):

1. `_authRepo.signOut()` — clears Supabase session (synchronous in-memory).
2. `CacheService.clearAll()` — removes all 5 checkpoint keys from SharedPreferences.
3. `StorageService.clearAll()` — `p.clear()` removes **all** SharedPreferences keys (including feature caches, `app_language_code`, and every constant in StorageService); `_secureStorage.deleteAll()` removes **all** secure storage keys.
4. `ApiService.clearHeadersCache()` — sets `_cachedDeviceFingerprint = null`, `_cachedRequestBindingSecret = null`.

**Net effect**: All cached feature data, identity, tokens, and the device fingerprint are wiped. The language preference (`app_language_code`) is also wiped, causing the app to fall back to the system locale on next launch. The media file cache (both `MediaCacheManager` and `DefaultCacheManager`) is **not** cleared. F-SC1 (fingerprint) and F-SC9 (media cache)

---

## Wipe Behavior

`ProfileState.wipeAppData()` (`:139–149` of `profile_state.dart`):
1. Backend `POST /api/v1/user/wipe` — server deletes the user's data.
2. `StorageService.clearAppCache()` — removes the 14 feature-cache SharedPreferences keys.
3. Feature states `clear()` — resets in-memory state.
4. `RealtimeSyncService.refreshChannel()` — resubscribes after suppress/resume.

**Not wiped**: checkpoints (`chk_*`), `app_language_code`, `username`, `partner_display_name`, `drive_thumb_cache`, `profile_pic_version`. F-SC10

**Not wiped**: media file cache (`MediaCacheManager`, `DefaultCacheManager`). F-SC11

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

### F-SC4: Logout wipes the persisted language preference

**Evidence**: `StorageService.clearAll()` calls `p.clear()` (`:390`). `LanguageProvider` persists locale under key `app_language_code` (`language_helper.dart:26`). `p.clear()` removes all SharedPreferences keys including this one.

**What**: After logout + re-login, the app resets to the system locale (or Italian fallback). This is arguably incorrect — language is a device-level preference, not an account-level one.

**Impact**: Minor UX annoyance on logout/re-login.

**Confidence**: HIGH

---

### F-SC5: `chk_game_answers` misses partner answer updates

**Evidence**: `game_repository.dart:51–55` — `submitAnswer` uses upsert with `ON CONFLICT (game_id, user_id)`. PostgreSQL updates only the specified columns. `selected_option` is updated, but `created_at` is unchanged (PostgreSQL does not auto-update `created_at` unless a trigger is defined). `hasChanges` at `base_repository.dart:107` compares `serverMax` (max `created_at`) against checkpoint — `created_at` has not changed, so `isAfter` returns false.

**What**: If the realtime channel is down (polling fallback after 3 consecutive failures), a partner answering a question is never detected by the change-detection mechanism. The history and stats remain stale until the user manually pulls to refresh.

**Impact**: Game history and match count stale under polling fallback. Realtime covers the online path.

**Confidence**: HIGH

---

### F-SC6: `chk_bucket_items` misses partner done-toggle changes

**Evidence**: `bucket_repository.dart:56–59` — `toggleBucketItem` updates `done` only. The `hasChanges` field is `created_at` (`:9` of `bucket_repository.dart`), which does not change on toggle. Therefore `serverDate.isAfter(checkpointDate)` returns false for a toggle event.

**What**: Same structural issue as F-SC5. Under polling fallback or cold start, partner toggling a bucket item done/undone is invisible to the change detector.

**Impact**: Bucket list stale under polling fallback. Realtime handles it.

**Confidence**: HIGH

---

### F-SC7: Drive incremental sync does not detect deletions

**Evidence**: `DriveRepository.fetchDriveItemsIncremental` (`:24–40`) runs `SELECT ... WHERE updated_at > $checkpoint`. Deleted rows do not appear in the query result. The merge logic at `drive_state.dart:79–84` keeps items from the previous in-memory list that are not in the new fetch — keeping the deleted item.

**What**: When realtime is down and only incremental sync runs, deleted drive items persist in the local cache indefinitely. The full path `refreshFromRealtime()` (triggered by realtime DELETE events) re-fetches the entire list and replaces the cache, which resolves this in the online case.

**Impact**: Deleted media visible locally after network hiccup; clears on next successful realtime event or pull-to-refresh.

**Confidence**: HIGH

---

### F-SC8: Cross-partnership checkpoint contamination

**Evidence**: See §Cross-partnership checkpoint contamination. `clearPartner()` at `storage_service.dart:359–364` clears partner_id/partnership_id/partner_display_name but not feature caches or checkpoints. `CacheService.clearAll()` runs only on logout, not on partnership change.

**Impact**: After re-partnering, old partner's mood, drive items, bucket items, game history, and miss-you count are displayed until the user pulls to refresh or a realtime event arrives with a timestamp newer than the old checkpoint.

**Confidence**: HIGH

---

### F-SC9: Media file cache not cleared on logout or wipe

**Evidence**: `DriveState.clearMediaCache()` (`:282–283`) calls `MediaCacheManager().emptyCache()`, but this method is **never invoked from any UI or lifecycle hook** — it is dead code. `logout()` at `auth_state.dart:534–548` clears SharedPreferences and secure storage but not the flutter\_cache\_manager file store. `wipeAppData()` at `profile_state.dart:139–149` calls `clearAppCache()` (SharedPreferences only).

**What**: On a shared device, after logging out of account A and into account B, cached images from account A's media (profile pictures, drive images) remain on disk. If `CachedNetworkImage` is given the same URL key (e.g. a profile picture object key that happens to match), the old image from account A is shown to account B. In practice, R2 object keys include user-specific paths (e.g. `drive/42/...`), so direct cross-account display via the same key is unlikely — but the files remain on disk and are accessible via the app's cache directory.

**Impact**: Privacy concern on shared devices. Cached files are not encrypted (flutter\_cache\_manager stores raw files in the app cache directory). Not a direct data-exposure bug (no R2 key reuse across accounts), but residual data persists.

**Confidence**: MEDIUM (unlikely actual display cross-account, but files remain)

---

### F-SC10: Wipe does not clear checkpoints

**Evidence**: `ProfileState.wipeAppData()` (`:143`) calls `StorageService.clearAppCache()` which removes feature cache keys but **not** the `chk_*` keys (those are managed by `CacheService`, which is not called). The wipe flow in `profile_screen.dart:93–108` clears in-memory state but does not call `CacheService.clearCheckpoints()`.

**What**: After a wipe, old checkpoints persist. On the next cold start, `hasChanges` compares the new (post-wipe) server timestamps (empty) against the old checkpoint. If old checkpoint was a real timestamp (not `EMPTY`), `hasChanges` returns true → refetches → empty data → writes `EMPTY` checkpoint. Self-corrects on first refresh. If old checkpoint was already `EMPTY` (server was empty before wipe too), returns false → no refetch needed → empty cache is consistent. So the wipe is functionally self-correcting, but the intermediate state depends on timing.

**Impact**: Negligible — self-corrects after the first successful network refresh.

**Confidence**: MEDIUM

---

### F-SC11: Wipe does not clear media file cache

**Evidence**: Same as F-SC9. `DriveState.clearMediaCache()` exists but is not called during the wipe flow (`profile_screen.dart:93–108`).

**What**: After a data wipe, cached media files (thumbnails, full images) from the now-deleted drive items persist in the flutter\_cache\_manager file store.

**Impact**: Disk waste. Not a privacy concern in practice (drive items deleted on server, and the files are only accessible by the same app instance). Minor.

**Confidence**: HIGH

---

### F-SC12: Concurrent cache writes race without serialization

**Evidence**: `DriveState.syncDriveItems` is guarded by `_isSyncing` (`:71`), but `addFileItemR2` (`:162`), `deleteItem` (`:200`), `addReaction` (`:225`), and `toggleFavorite` (`:252`) are **not** guarded by `_isSyncing`. All write to `StorageService.saveDriveItems(_driveItems)` asynchronously.

**What**: If a mutation (upload, delete, reaction, favorite) runs concurrently with `syncDriveItems`, both call `saveDriveItems` with different snapshots of `_driveItems`. The last writer wins. An optimistic update could be overwritten by a slightly older snapshot from a concurrent sync, losing the in-memory change (which would be corrected on the next realtime event or refresh).

**Impact**: Brief transient inconsistency in the drive tab. Self-corrects quickly.

**Confidence**: MEDIUM (requires timing of concurrent operations)

---

### F-SC13: `BucketState._flushCache` debounce can lose writes on dispose

**Evidence**: `BucketState.dispose()` (`:19–23`) cancels `_cacheDebounceTimer` then calls `unawaited(_flushCache())`. The unawaited call writes to SharedPreferences asynchronously — but `dispose()` is a synchronous lifecycle callback. If the widget tree is disposed before the unawaited write completes (e.g. navigation during a realtime event), the cache write may not persist.

**What**: When the BucketListScreen tab is disposed (during navigation or wipe), the in-memory state may contain unsaved realtime updates. The unawaited flush may complete after disposal or may be interrupted.

**Impact**: Minor — the next init() re-reads from cache and refetches if `hasChanges` is true.

**Confidence**: LOW

---

### F-SC14: Mood optimistic update can persist phantom entry to cache

**Evidence**: `MoodState.updateMood` (`:244–256` of `mood_state.dart`) inserts a local `MoodEntry(id: 0, userId: 0, ...)` into `_timeline` and calls `saveTimeline` before the server responds. If the app is killed between the optimistic write and the server response, the cache contains a phantom entry with `id: 0, userId: 0` that does not correspond to any server row.

**What**: On the next cold start, `_loadMoodScreenCache` loads the phantom entry into `_timeline`. On the subsequent network fetch, the phantom entry is overwritten (since `fetchTimeline` replaces the entire `_timeline`).

**Impact**: Phantom mood entry visible in the mood screen for up to one full initialization cycle.

**Confidence**: LOW (requires app kill in a narrow window)

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

**Evidence**: `clearAppCache()` at `:368–387` clears 14 keys — `_keyUsername` and `_keyPartnerDisplayName` are **not** in the list. `ProfileState.wipeAppData()` calls `clearAppCache()` only.

**What**: After a data wipe, the app retains the old username and partner display name. These are used by `GameState._resolveCachedNames` (`:51–69`) to resolve question option labels from cache, and by all `notifyPartnerOnce` calls to include a `partnerName` param. After a wipe + re-partner, the old username is correct (user's own name doesn't change), but the partner display name may be stale until re-fetched.

**Impact**: Minor — name corrects itself after the next `setPartner` call.

**Confidence**: MEDIUM

---

## Security Considerations

1. **PII in SharedPreferences plaintext**: `user_profile` and `partner_profile` JSON caches contain `email`, `authId`, `bio`, and `partnershipCode` fields stored as unencrypted strings in SharedPreferences (`auth_models.dart:52–63`). On rooted/jailbroken devices, this data is accessible via filesystem inspection. Flutter secure storage is only used for tokens and IDs — not for profile PII. F-SC18 (MEDIUM confidence)

2. **Device fingerprint deleted on logout**: F-SC1 details this. The fingerprint should persist across sessions for device-level security (risk analysis, session binding). Deleting it on logout defeats its purpose.

3. **Media files not encrypted on disk**: flutter\_cache\_manager stores files in the app cache directory in plaintext. On a compromised device, cached R2 media (including profile pictures) is readable.

4. **`reportFailedLogin` is dead code**: The `AuthRepository.reportFailedLogin` method and the corresponding backend endpoint `POST /api/v1/auth/login-attempt` exist but are **never called** from the Flutter app (`auth_repository.dart:20–26`). Failed login attempts are not reported to the backend, so the backend risk-detection system has no client-side telemetry.

5. **Binding secret bridge across layers**: `StorageService.saveRequestBindingSecret` at `:186–189` directly mutates `ApiService._cachedRequestBindingSecret` — a static field on a different class. This creates a hidden bidirectional dependency that makes the boundary between storage and networking porous.

---

## Invariants

1. **`StorageService.init()` must be called before any read/write.** Satisfied by `main()` (`:49`). `prefsSync` asserts in debug; `prefs` lazy-inits as safety net.
2. **`clearAll()` must be called on every logout.** `AuthState.logout` satisfies this (`:537`). No other logout path exists.
3. **Feature caches are global, not per-user.** There is no per-user key prefixing. Logout must clear all data. `StorageService.clearAll()` satisfies this by calling `p.clear()`.
4. **Feature caches cannot be read before `loadWithChangeDetection` completes.** This is an architectural invariant — all feature state reads (from UI) occur after `init()` completes. Violated only if realtime events arrive before init finishes (possible during startup).
5. **`MediaCacheManager` is a singleton** (`:11–12`). Only one instance exists per process. The `Config` (stalePeriod, maxNrOfCacheObjects) is fixed at construction time.
6. **Checkpoints are written after every successful network fetch.** Every `fetchFromNetwork` path writes a checkpoint. Partial failures (e.g. `fetchStats` succeeds but `fetchHistory` fails) may leave checkpoints inconsistent with the actual cache state. The checkpoint reflects whatever was fetched, not the full intended fetch.

---

## Tests

| Test file | Storage coverage |
|---|---|
| `Flutter/test/mood_state_test.dart` | Verifies `updateMood` writes to `StorageService.getMood('me')` (`:67`). Verifies `initHome` reads cached moods (`:87–97`). Uses `SharedPreferences.setMockInitialValues({})` + mock secure storage channel. |
| `Flutter/test/game_state_test.dart` | Verifies `fetchNewQuestion` caches the question (`:67–70`). Verifies `submitAnswer` updates history. Uses `SharedPreferences.setMockInitialValues({})` + mock secure storage channel. |
| `Flutter/test/test_helpers/mock_secure_storage.dart` | Mocks `flutter_secure_storage` platform channel for test isolation. |
| `Flutter/test/api_service_test.dart` | Covers HTTP error handling — no storage-specific assertions. |

**Not covered by tests**: `StorageService` direct read/write paths, `CacheService.checkpoints`, `CheckpointMixin`, `BaseRepository.hasChanges`, `loadWithChangeDetection`, `MediaCacheManager`, logout/wipe cache clearing, cross-partnership contamination, concurrent cache write races, `CacheService.needsRefresh`.

---

## Known Issues

- `DriveState.clearMediaCache()` is dead code — never called from UI or lifecycle.
- `StorageService.getProfilePicVersion` / `saveProfilePicVersion` — write-only; no consumer exists.
- `StorageService._keyDriveThumbCache` — declared and cleared but never written or read.
- `reportFailedLogin` / `AuthRepository.reportFailedLogin` — defined but never called.
- `StorageService.resetForTest()` — defined but never called from tests.
- `ThemeMode` is never persisted (`theme_provider.dart`) — always starts dark (documented in architecture doc).

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
| Feature cache invalidation on partnership change | NOT IMPLEMENTED (F-SC8) |
| Media cache clearing on logout/wipe | NOT IMPLEMENTED (F-SC9, F-SC11) |
| `profile_pic_version` used to bust image cache | NOT IMPLEMENTED (dead write, F-SC2) |
| `reportFailedLogin` wired from UI | NOT IMPLEMENTED (dead code) |
| Language preference persistence across logout | NOT IMPLEMENTED (wiped, F-SC4) |

---

## Notes

- **No per-user key namespacing.** All cache keys are global strings (e.g. `bucket_list`, `drive_cache`). Cross-account safety depends entirely on `clearAll()` being called on logout. No defense-in-depth exists.
- **SharedPreferences is not the ideal store for large JSON blobs.** `drive_cache` can grow to contain hundreds of `DriveItem` objects with metadata and reactions, all serialized into a single `p.setString` call on every mutation. On Android, SharedPreferences serializes all pending writes synchronously to disk on app backgrounding — large values cause jank.
- **`flutter_cache_manager` file store is separate from SharedPreferences.** Clearing SharedPreferences (via `p.clear()`) does NOT remove cached media files. Media cleanup requires explicit `MediaCacheManager().emptyCache()` calls, which are currently dead code.
- **Dual token refresh (Supabase listener + `ApiService._tryRefreshToken`) writes to the same secure-storage keys concurrently.** The `_isRefreshing` flag in `ApiService` prevents duplicate proxy refreshes, but does not prevent the Supabase built-in listener from writing simultaneously. Both writes target the same keys (`access_token`, `refresh_token`). The Supabase listener at `auth_state.dart:157–164` and `ApiService._tryRefreshToken` at `api_service.dart:298–303` can race.
- **`PartnershipRepository._activePartnershipFuture` is a static future-keyed cache.** It persists across tab switches and even across cold starts (the static variable lives for the process lifetime). This is the only in-memory-only cache in the system. All others are persisted to disk.

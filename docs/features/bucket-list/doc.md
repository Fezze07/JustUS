# Bucket List — Feature Documentation

> Status key: **IMPLEMENTED** · **PARTIALLY IMPLEMENTED** · **NOT IMPLEMENTED** · **UNCERTAIN**

---

## 1. Overview

The Shared Bucket List allows both partners in an active JustUS partnership to maintain a common list of goals or dreams. Both users share a single list scoped to their `partnership_id`. Either partner can create, toggle-complete, or delete items. Changes are propagated in real time to both devices via Supabase Realtime.

---

## 2. Data Model

### 2.1 Table: `bucket_items`

Source: `supabase-schema/SKILL.md`

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | `integer` | NO | Primary Key, auto-increment |
| `text` | `text` | NO | Item description |
| `done` | `boolean` | YES | Completion flag |
| `category` | `character varying` | YES | One of seven fixed values (see §3) |
| `created_at` | `timestamp with time zone` | YES | Set at INSERT by Supabase default |
| `partnership_id` | `integer` | YES | FK → `partnerships.id` |

There is no `updated_at` column. Toggle operations only update `done`; `created_at` remains unchanged. This has caching implications (§7.2).

There is no `user_id` column. Items are partnership-scoped, not user-scoped. The owning user is **not stored** in the database.

### 2.2 Dart Model: `BucketItem`

Source: `Flutter/lib/features/bucket_list/bucket_models.dart`

Fields: `id (int)`, `text (String)`, `done (bool)`, `createdAt (String ISO)`, `category (String)`, `partnershipId (int?)`.

- `done` decoded from `bool | int`.
- `category` defaults to `BucketCategory.all` (`'all'`) if absent, so null DB categories render through the "all" filter chip instead of the stale `'Tutti'` string (F-BL2 resolved).
- `partnershipId` nullable; populated from the fetch SELECT (`partnership_id` is now included, F-BL4 resolved).

---

## 3. Categories

Source: `Flutter/lib/features/bucket_list/bucket_category.dart`

Seven compile-time constants:

| Key | Color | Italian label |
|---|---|---|
| `Travel` | `#4FC3F7` | Viaggi |
| `Dates` | `#FF8A65` | Appuntamenti |
| `Goals` | `#81C784` | Obiettivi |
| `Crazy` | `#CE93D8` | Follie |
| `Adventure` | `#FFD54F` | Avventura |
| `Romantic` | `#F06292` | Romantico |
| `Homemade` | `#4DD0E1` | Fatto in casa |

`BucketCategory.all = 'all'` is a synthetic filter sentinel (not a storable category).

### 3.1 Category Validation — Layer by Layer

| Layer | Behavior |
|---|---|
| Flutter UI | Add-dialog only exposes 7 chips; no free-text category input |
| Flutter Repository | `addBucketItem` omits `category` key from INSERT if null or empty |
| Backend (Node.js) | NOT IMPLEMENTED — no bucket_items routes exist |
| Database | CHECK constraint `bucket_items_category_check` — allows NULL or the 7 bucket categories (F-BL3 resolved, applied to remote) |

Direct Supabase API access can store the 7 categories or NULL only; arbitrary strings are rejected.

---

## 4. Operations

All CRUD calls Supabase PostgREST directly from Flutter. No Node.js backend route for `bucket_items`.

### 4.1 Fetch

`BucketRepository.fetchBucketList` (bucket_repository.dart:18):

```
getActivePartnership() → resolves partnership_id
→ SELECT id, text, done, created_at, updated_at, category, partnership_id
   FROM bucket_items
   WHERE partnership_id = $partnershipId
   ORDER BY created_at DESC
```

- Returns all items (done and not-done), newest-first.
- `partnership_id` included in SELECT — `BucketItem.partnershipId` reflects the owning partnership after fetch.
- No active partnership → empty list returned (no error).

### 4.2 Add Item

`BucketRepository.addBucketItem` (bucket_repository.dart:35):

```
INSERT INTO bucket_items (text, done, partnership_id [, category])
VALUES ($text, false, $partnershipId [, $category])
```

Flow:
1. `BucketState.addItem` validates non-empty text (trims; if empty → error message, return).
2. Repository inserts row; `done = false` always.
3. Fires `notifyPartnerOnce(notificationKey: 'bucketItemAdded', params: {partnerName})` — unawaited.
4. No optimistic insert — Realtime INSERT event populates state.

Duplicate protection: None. Identical `(text, category)` rows can coexist.

Offline: Supabase call throws; error message shown; no queue or retry.

### 4.3 Toggle Done

`BucketRepository.toggleBucketItem` (bucket_repository.dart:56):

```
UPDATE bucket_items SET done = $done
WHERE id = $id AND partnership_id = $activePartnershipId
```

- Modify scoped by `partnership_id` (via `withPartnership` + `.match`) — defense-in-depth alongside RLS; throws `Exception('No active partnership')` if none is found.
- Optimistic UI via `_pendingChanges` map; Realtime UPDATE clears it.
- Idempotent at DB level. Rapid double-taps may show brief inconsistency.
- No notification on toggle.

### 4.4 Delete

`BucketRepository.deleteBucketItem` (bucket_repository.dart:62):

```
DELETE FROM bucket_items
WHERE id = $id AND partnership_id = $activePartnershipId
```

- Modify scoped by `partnership_id` (via `withPartnership` + `.match`) — defense-in-depth alongside RLS; throws `Exception('No active partnership')` if none is found.
- Optimistic UI via `_pendingDeletes` set; item reappears if network fails.
- No notification on delete.

---

## 5. Access Control (RLS)

Source: `supabase-policies/SKILL.md`

`bucket_items` → ALL operations restricted to members of the owning partnership. Policy enforced server-side via `partnership_id` membership check.

UPDATE and DELETE in `bucket_repository.dart` additionally filter by `partnership_id` (`withPartnership` + `.match`), so cross-partnership modification is blocked client-side as well as by RLS (F-BL7 resolved).

---

## 6. Realtime Synchronization

Source: `Flutter/lib/core/realtime/handlers/bucket_realtime_handler.dart` (wired by `RealtimeSyncService`; channel owned by `RealtimeSyncConnection`)

Subscribed via shared channel `justus-sync-<userId>-<generation>`:

```
.onPostgresChanges(
  event: PostgresChangeEvent.all,   // INSERT, UPDATE, DELETE
  schema: 'public',
  table: 'bucket_items',
  callback: <BucketRealtimeHandler.handle>,   // wired via RealtimeSyncService
)
```

### 6.1 Event Filtering

`BucketRealtimeHandler.handle` applies in order:

1. `RealtimeSyncSession.suppressProcessing` flag — drops event if true (auth transitions).
2. `RealtimeSyncSession.isPartnershipRecord(payload)` — strict match between row `partnership_id` and the session `partnershipId`; fails outright when the session has no partnership (F-RT9 resolved). Sparse DELETE payloads (default `REPLICA IDENTITY` → only the PK is delivered) are the sole exemption, still governed by `_knownIds` dedup + RLS (F-BL8 resolved).
3. `RealtimeSyncSession.markSeen(payload)` — dedup by `(table, eventType, id, commitTimestamp)` key; ring-buffer of 80 entries.

### 6.2 Dispatch

`BucketState.applyRealtimeEvent` called **immediately** — no debounce (mood uses 120ms debounce; bucket does not).

### 6.3 `applyRealtimeEvent` Logic

Source: `bucket_state.dart:130`

| Event | Behavior |
|---|---|
| `insert` | If `id` in `_knownIds` → return (dedup). Otherwise prepend to `_items`, add to `_knownIds`. |
| `update` | If `id` not in `_knownIds` → return. Find by index, replace item in-place. |
| `delete` | Read `oldRecord['id']`. If not in `_knownIds` → return. Remove from `_items` and `_knownIds`. |

After any change: 2-second debounced cache save + `notifyListeners()`.

---

## 7. Local Cache

### 7.1 StorageService

Source: `Flutter/lib/core/local_storage/storage_service.dart:240`

- SharedPreferences key: `bucket_list`.
- Full list serialized as JSON array on every flush.
- Cleared by `StorageService.clearAll()`.

### 7.2 Checkpoint

Source: `Flutter/lib/core/local_storage/cache_service.dart:6`

- Key: `chk_bucket_items`.
- Stores maximum `updated_at` timestamp from `_items` (`BucketItem.updatedAt`).
- `BaseRepository.hasChanges` compares server `MAX(updated_at)` to checkpoint.
- If server value is newer → checkpoint reset to EMPTY, full network fetch triggered.
- `bucket_items.updated_at` is bumped on every UPDATE (`done` toggle) by the `set_public_bucket_items_updated_at` trigger, so partner done-toggle changes are detected on cold start and during polling fallback.

### 7.3 Cache Flush Timing

| Trigger | Mechanism |
|---|---|
| `fetchBucket()` or `refreshFromRealtime()` completes | `_flushCache()` called directly |
| After Realtime event | 2-second debounced timer via `_scheduleCacheSave` |
| `BucketState.dispose()` | Timer cancelled; `_flushCache()` called unawaited |

---

## 8. Initialization Flow (Cold Start)

Source: `bucket_state.dart:27`, `bucket_list_screen.dart:27`

```
BucketListScreen.loadData()
  → BucketState.init()    [re-entrant guard: _isInitLoading]
    → loadWithChangeDetection(
        loadFromCache:    _loadFromCache,      // serve stale data immediately
        hasChanges:       _hasBucketChanges,   // compare MAX(created_at) vs checkpoint
        fetchFromNetwork: fetchBucket,         // if changed, full SELECT
      )
```

Homepage also calls `BucketState.init()` — re-entrant guard prevents double-fetch.

### 8.1 Force Refresh (Pull-to-Refresh)

```dart
await CacheService.clearCheckpoints([CacheService.kBucketItems]);
await _bucketState.init();
```

Clearing checkpoint forces `hasChanges` → `true` → mandatory network fetch.

---

## 9. UI

### 9.1 BucketListScreen

Source: `Flutter/lib/features/bucket_list/screens/bucket_list_screen.dart`

- Tab index: 3 in `MainShell`.
- Category filter: horizontal scrollable chips (`_selectedCategory` local state); client-side filter.
- Item list: `ListView.separated` with `AlwaysScrollableScrollPhysics`.
- Add dialog: `AlertDialog` with TextField (text) + ChoiceChip row (category). Default: `Travel`.
- Toggle: custom checkbox via `GestureDetector`. Optimistic via `_pendingChanges`. `unawaited`.
- Delete: `Dismissible` swipe right-to-left. Optimistic via `_pendingDeletes`. `unawaited`.

### 9.2 Homepage Preview

Source: `Flutter/lib/features/home/screens/homepage_screen.dart:443`

- Section: "Sogni da vivere".
- Shows up to 4 not-done items from `BucketState.items`.
- Tappable subtitle: `{count} attività in sospeso` → navigates to tab 3.
- No category filter applied.

---

## 10. Notifications

Trigger: on add item only (`bucket_repository.dart:49`).

- Key: `bucketItemAdded`, param: `partnerName` (current user's stored username).
- `notifyPartnerOnce` → backend `/api/v1/notify` → FCM to partner (unawaited).

Content (Flutter `notification_service.dart:250`):
- Title IT: "Nuovo desiderio nella bucket list"
- Body IT: "{partnerName} ha aggiunto qualcosa"
- Item text not included in notification.

Backend also defines `bucketItemAdded` with English strings ("New Wish in the Bucket List"). Which string is used depends on which layer builds the FCM payload — **UNCERTAIN**.

**Status: PARTIALLY IMPLEMENTED** — trigger on add only; no item content; toggle/delete unnotified.

---

## 11. Concurrent Modifications

| Scenario | Outcome |
|---|---|
| Both partners add simultaneously | Both INSERTs succeed; both items appear |
| Both toggle same item simultaneously | Last-write-wins at Postgres; Realtime delivers final state |
| Partner deletes while user is toggling | DELETE via Realtime removes item from `_items`; in-flight UPDATE may fail silently |
| Partner creates while user is offline | On reconnect, `refreshFromRealtime()` fetches full list |
| User creates while offline | Supabase call fails; error shown; no retry |

---

## 12. Incremental Synchronization Gaps

The `chk_bucket_items` checkpoint (max `updated_at`) detects new **inserts** and **updates** (done-toggles bump `updated_at` via the `set_public_bucket_items_updated_at` trigger). It cannot detect:

- Partner deletes (row gone; no timestamp to compare).

The delete gap is covered by Realtime during an active session and by polling `refreshFromRealtime()` after an offline period; stale `done` state no longer persists because toggle changes now bump the checkpoint cursor.

---

## 13. Polling Fallback

After 3+ consecutive Realtime failures, polling fallback activates (`RealtimeSyncConnection.activatePollingFallback` in `realtime_connection.dart`). `_refreshAll()` calls `BucketState.refreshFromRealtime()` → full network fetch. Insert/update/delete visibility is restored.

---

## 14. Findings

All F-BL audit findings are resolved — F-BL1 (dead `BucketItemTile`, deleted), F-BL2 (category fallback), F-BL3 (DB CHECK constraint), F-BL4 (SELECT populated), F-BL5/F-BL6 (cursor + updated_at trigger, 4.3), F-BL7 (modify scope), F-BL8 (filter strictness). See the Implementation Status summary.

---

## 15. Implementation Status Summary

| Area | Status |
|---|---|
| Seven categories (Flutter constants) | IMPLEMENTED |
| Category color mapping | IMPLEMENTED |
| Category i18n labels | IMPLEMENTED |
| Create item | IMPLEMENTED |
| Toggle done (optimistic UI) | IMPLEMENTED |
| Delete item (optimistic UI) | IMPLEMENTED |
| Partner visibility (shared partnership_id) | IMPLEMENTED |
| Realtime INSERT sync (granular) | IMPLEMENTED |
| Realtime UPDATE sync (granular) | IMPLEMENTED |
| Realtime DELETE sync (granular) | IMPLEMENTED |
| Realtime partnership filter (strict, sparse-DELETE exempt) | IMPLEMENTED |
| Fetch includes `partnership_id` (model populated) | IMPLEMENTED |
| Modify scope (toggle/delete) by `partnership_id` | IMPLEMENTED |
| Category fallback equals filter sentinel | IMPLEMENTED |
| Local cache (SharedPreferences) | IMPLEMENTED |
| Incremental sync — inserts only | IMPLEMENTED |
| Homepage preview (up to 4 pending items) | IMPLEMENTED |
| Push notification on add | PARTIALLY IMPLEMENTED |
| Push notification on toggle / delete | NOT IMPLEMENTED |
| Item text in push notification | NOT IMPLEMENTED |
| Category validation at database level | IMPLEMENTED (CHECK constraint) |
| Backend CRUD routes | NOT IMPLEMENTED |
| Offline queuing / retry | NOT IMPLEMENTED |
| Item edit | NOT IMPLEMENTED |
| Item ownership tracking | NOT IMPLEMENTED |
| Incremental sync — toggle changes | IMPLEMENTED (updated_at cursor) |
| Incremental sync — deletes | NOT IMPLEMENTED |

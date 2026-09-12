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
- `category` defaults to `'Tutti'` if absent — mismatched with `BucketCategory.all = 'all'` (F-BL2).
- `partnershipId` nullable and **never populated from fetch** (F-BL4).

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
| Database | `category` is `character varying, nullable`; no CHECK constraint |

Category validation is Flutter-UI-only. Direct Supabase API access can store arbitrary strings.

---

## 4. Operations

All CRUD calls Supabase PostgREST directly from Flutter. No Node.js backend route for `bucket_items`.

### 4.1 Fetch

`BucketRepository.fetchBucketList` (bucket_repository.dart:18):

```
getActivePartnership() → resolves partnership_id
→ SELECT id, text, done, created_at, category
   FROM bucket_items
   WHERE partnership_id = $partnershipId
   ORDER BY created_at DESC
```

- Returns all items (done and not-done), newest-first.
- `partnership_id` NOT in SELECT — `BucketItem.partnershipId` is always `null` after fetch.
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
UPDATE bucket_items SET done = $done WHERE id = $id
```

- No `partnership_id` filter — RLS is the only scope guard.
- Optimistic UI via `_pendingChanges` map; Realtime UPDATE clears it.
- Idempotent at DB level. Rapid double-taps may show brief inconsistency.
- No notification on toggle.

### 4.4 Delete

`BucketRepository.deleteBucketItem` (bucket_repository.dart:62):

```
DELETE FROM bucket_items WHERE id = $id
```

- No `partnership_id` filter — RLS is the only scope guard.
- Optimistic UI via `_pendingDeletes` set; item reappears if network fails.
- No notification on delete.

---

## 5. Access Control (RLS)

Source: `supabase-policies/SKILL.md`

`bucket_items` → ALL operations restricted to members of the owning partnership. Policy enforced server-side via `partnership_id` membership check.

UPDATE and DELETE in `bucket_repository.dart` filter only by `id`. RLS is the sole defence against cross-partnership modification. If RLS is disabled, any integer `id` can be targeted.

---

## 6. Realtime Synchronization

Source: `Flutter/lib/core/realtime/realtime_sync_service.dart`

Subscribed via shared channel `justus-sync-<userId>-<generation>`:

```
.onPostgresChanges(
  event: PostgresChangeEvent.all,   // INSERT, UPDATE, DELETE
  schema: 'public',
  table: 'bucket_items',
  callback: _handleBucketPayload,
)
```

### 6.1 Event Filtering

`_handleBucketPayload` applies in order:

1. `_suppressProcessing` flag — drops event if true (auth transitions).
2. `_isPartnershipRecord(payload)` — compares row `partnership_id` to `_partnershipId`. Passes if either is `null` (permissive — F-BL8).
3. `_markSeen(payload)` — dedup by `(table, eventType, id, commitTimestamp)` key; ring-buffer of 80 entries.

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
- Stores maximum `created_at` timestamp from `_items`.
- `BaseRepository.hasChanges` compares server `MAX(created_at)` to checkpoint.
- If server value is newer → checkpoint reset to EMPTY, full network fetch triggered.

**F-SC6 (inherited finding)**: `toggleBucketItem` updates only `done`; `created_at` is immutable. `hasChanges` cannot detect partner done-toggle changes on cold start or during polling fallback. Stale `done` state persists until forced refresh.

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

**F-BL1**: `BucketItemTile` (`widgets/bucket_item_tile.dart`) is **never instantiated**. Screen renders items inline via `_buildBucketItem`. The widget is dead code using a simpler `Card + ListTile` layout without category color or optimistic state.

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

The `chk_bucket_items` checkpoint detects only new **inserts** (via `created_at` comparison). It cannot detect:

- Partner done-toggle changes (UPDATE; `created_at` unchanged) — F-BL5 / F-SC6.
- Partner deletes (row gone; no timestamp to compare).

These gaps are covered only by Realtime during an active session. After offline periods, stale `done` state and missing deletes persist until pull-to-refresh.

---

## 13. Polling Fallback

After 3+ consecutive Realtime failures, polling fallback activates (`realtime_sync_service.dart:185`). `_refreshAll()` calls `BucketState.refreshFromRealtime()` → full network fetch. Insert/delete visibility is restored; toggle-change gaps remain (see §12).

---

## 14. Findings

### F-BL1: `BucketItemTile` is dead code

`widgets/bucket_item_tile.dart` — never instantiated. `BucketListScreen` renders items inline. The widget uses `Card + ListTile` without category color, badge, or optimistic state. Using it would regress UI fidelity.

### F-BL2: Category fallback `'Tutti'` mismatches filter sentinel `'all'`

`bucket_models.dart:30` — `fromJson` defaults `category` to `'Tutti'` on absent key. The "all" filter chip uses `BucketCategory.all = 'all'`. Items with null DB `category` display badge `'Tutti'` (raw, unlocalized) and `Colors.white70`. They appear in all-categories view but match no named filter chip.

### F-BL3: No category validation at database or backend layer

DB accepts any string or NULL for `category`. Flutter dialog-only enforcement. Direct Supabase API bypasses validation.

### F-BL4: `partnership_id` not fetched in SELECT

`bucket_repository.dart:26` — SELECT omits `partnership_id`. `BucketItem.partnershipId` is always `null` after fetch. Field exists in model and `toJson` but is never populated from server data.

### F-BL5: Checkpoint misses partner done-toggle changes (inherits F-SC6)

`hasChanges` is based on `MAX(created_at)` — unaffected by UPDATE. Stale `done` state persists on cold start after offline periods.

### F-BL6: No `updated_at` column

Toggle state has no server-side timestamp. Checkpoint-based detection of update changes is structurally impossible without a schema change.

### F-BL7: UPDATE/DELETE filter only by `id`

`toggleBucketItem` and `deleteBucketItem` omit `partnership_id` from WHERE. RLS is the sole defence. Misconfigured RLS enables cross-partnership modification.

### F-BL8: Realtime filter is permissive on missing `partnership_id`

`_isPartnershipRecord` returns `true` when `eventPartnershipId` is `null` (possible in sparse DELETE payloads). `_knownIds` dedup is the last safety net.

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
| Local cache (SharedPreferences) | IMPLEMENTED |
| Incremental sync — inserts only | IMPLEMENTED |
| Homepage preview (up to 4 pending items) | IMPLEMENTED |
| Push notification on add | PARTIALLY IMPLEMENTED |
| Push notification on toggle / delete | NOT IMPLEMENTED |
| Item text in push notification | NOT IMPLEMENTED |
| Category validation at database level | NOT IMPLEMENTED |
| Backend CRUD routes | NOT IMPLEMENTED |
| Offline queuing / retry | NOT IMPLEMENTED |
| Item edit | NOT IMPLEMENTED |
| Item ownership tracking | NOT IMPLEMENTED |
| Incremental sync — toggle changes | NOT IMPLEMENTED (F-BL5 / F-SC6) |
| Incremental sync — deletes | NOT IMPLEMENTED |

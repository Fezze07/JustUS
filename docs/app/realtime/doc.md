# Supabase Realtime Synchronization — JustUS

## Overview

JustUS uses a single Supabase Realtime channel per user (`justus-sync-$userId-$generation`) with **nine** Postgres Change subscriptions (all event types, no server-side logical filters). Events are pushed to the client, filtered against the local user/partner/partnership identity, deduplicated via a bounded LRU, optionally debounced, and dispatched through a shared `RealtimeHandler` template to per-feature strategies that mutate in-memory state and persist caches.

A **polling fallback** (15 s interval) and **exponential-backoff resubscription** (max 20 attempts) guarantee eventual synchronization when the WebSocket is unstable. Realtime is the fast path; the checkpoint-based `loadWithChangeDetection` cold-start path is the slow path.

Two layers of isolation are enforced:

1. **Server-side RLS** — Supabase filters which rows each JWT can read/write before an event is delivered on the WebSocket.
2. **Client-side relevance filters** — `RealtimeSyncSession.isRelevant*()`/`isPartnershipRecord()` re-verify the payload against the session ids (`userId`, `partnerId`, `partnershipId`) before processing.

## File map (post-refactor split)

The old single-file service was split by responsibility. `RealtimeSyncService` is now a thin facade; all connection and routing logic lives in six modules plus feature handlers that extend one shared base.

| File | Responsibility |
|---|---|
| `lib/core/realtime/realtime_sync_service.dart` | Facade: owns the 8 states, the shared `RealtimeSyncSession` (ids/dedup), the `RealtimeSyncConnection`, and the 9-binding table->handler wiring. Also wires each feature's handler strategy (immediate / debounced-refetch / FIFO / distinct). Public API: `start`, `configure`, `suppress`, `resume`, `refreshChannel`, `dispose`; owns `_refreshAll()`. |
| `lib/core/realtime/realtime_sync_session.dart` | `RealtimeSyncSession`: user/partner/partnership ids, `suppressProcessing`, dedup LRU (`markSeen`), row decoding (`currentRecord`, `rowInt`, `rowUserId`), relevance predicates (`isRelevant*`, `isPartnershipRecord`). |
| `lib/core/realtime/realtime_connection.dart` | `RealtimeSyncConnection (WidgetsBindingObserver)`: channel build + subscribe status handling, auth token-refresh listener, lifecycle resume/pause/unsubscribe, reconnect backoff, polling fallback, lazy `_refreshAll` hook. |
| `lib/core/realtime/realtime_table_binding.dart` | `RealtimeTableBinding` (+ `RealtimePayloadCallback` typedef): declarative table -> handler wiring for the 9 bindings. |
| `lib/core/realtime/realtime_handler.dart` | `RealtimeHandler` (abstract base, template method). Owns the shared preamble — suppression guard, relevance filter, `markSeen` dedup, plus `clear()`/`dispose()` — applied to every payload. Every feature handler extends it, so a change to suppress/relevance/dedup propagates to all features at once. |
| `lib/core/realtime/refetch_realtime_handler.dart` | `RefetchRealtimeHandler`: trailing-edge debounce (150 ms) collapsing a burst into **one** `refetch()` call. Replaces the former `PartnershipRealtimeHandler` / `DriveRealtimeHandler` / `UserProfilesRealtimeHandler` (three structurally identical full-refetch handlers). Wired with an `isRelevant` predicate + `refetch` closure in the facade. |
| `lib/core/realtime/handlers/mood_realtime_handler.dart` | `MoodRealtimeHandler` (extends base): `MoodChangeBatch` distinct-user coalescing (120 ms). |
| `lib/core/realtime/handlers/miss_you_realtime_handler.dart` | `MissYouRealtimeHandler` (extends base): immediate `addMissYou()` (insert) / `refreshFromRealtime()` (delete). |
| `lib/core/realtime/handlers/bucket_realtime_handler.dart` | `BucketRealtimeHandler` (extends base): immediate `BucketState.applyRealtimeEvent`. |
| `lib/core/realtime/handlers/game_realtime_handler.dart` | `GameRealtimeHandler` (extends base): immediate question insert/delete + `GameEventBuffer` FIFO flush (150 ms). |
| `lib/core/realtime/game_event_buffer.dart`, `mood_change_batch.dart` | Reusable coalescing primitives consumed by the game (FIFO) / mood (distinct-user) strategies — F-RT1/F-RT2. |

---

## Unified Handler Template

Every handler runs the same [template method](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_handler.dart):

```
RealtimeHandler.handle(payload)
  └─ log (table + eventType)
  └─ if session.suppressProcessing → drop          🔒 suppression (wipe flow)
  └─ if !isRelevant(payload) → drop                🎯 per-feature session predicate
  └─ if !session.markSeen(payload) → drop          🪞 80-entry dedup LRU
  └─ onNewEvent(payload) → feature strategy
```

The strategy is the only per-feature difference, and it is one of four shapes:

| Strategy | Owner | Applies to |
|---|---|---|
| **Immediate** (fire-and-forget in commit order) | `BucketRealtimeHandler`, `MissYouRealtimeHandler`, game question insert/delete | granular/instant apply, no coalescing possible or wanted |
| **Debounced refetch** (trailing edge -> one full refresh) | `RefetchRealtimeHandler` | partnerships, drive_items/reactions, user_profiles — expensive order-insensitive refetches |
| **FIFO buffer** (burst applied whole, in delivery order) | `GameRealtimeHandler` via `game_event_buffer.dart` | game_answers + question update — every intermediate event matters (F-RT1) |
| **Distinct set** (burst collapsed to union of keys) | `MoodRealtimeHandler` via `mood_change_batch.dart` | moods — a mixed self+partner burst must refresh *both* users (F-RT2) |

**Consequence**: the suppress flag, relevance rules and dedup are enforced exactly once; adding a feature is "one binding + one strategy wiring" in `RealtimeSyncService`, and touching the preamble touches every feature identically.

---

## The Pipeline

```
Supabase Postgres commit
  └─ (WAL → Realtime server)
        └─ WebSocket delivers PostgresChangePayload (RLS-filtered by JWT)
              └─ Channel: justus-sync-$userId-$generation
                    └─ onPostgresChanges(event: all, schema: public, table: <9 tables>)
                        └─ RealtimeHandler.handle (template): suppress guard, then
                            └─ relevance filter  (RealtimeSyncSession.isRelevant* / isPartnershipRecord)
                                ├─ dropped if not user/partner/partnership
                                └─ dedup            (RealtimeSyncSession.markSeen, 80-entry FIFO LRU)
                                      └─ if duplicate → dropped
                                      └─ if new → feature strategy (immediate | debounced refetch | FIFO | distinct set)
                                            └─ state update (feature state method)
                                                  └─ cache write (StorageService)
                                                        └─ notifyListeners()
                                                              └─ UI rebuild (Provider consumers)
```

| Stage | Where | Mechanism |
|---|---|---|
| Supabase event | Postgres WAL | `PostgresChangeEvent.all` (INSERT/UPDATE/DELETE) |
| Subscription | `realtime_connection.dart` `subscribe()` | 1 channel, 9 `.onPostgresChanges` bindings (wiring in `realtime_sync_service.dart`) |
| Filtering | `realtime_sync_session.dart` | Client relevance: user/partner/partnership |
| Deduplication | `realtime_sync_session.dart` `markSeen()` | FIFO LRU of 80 event keys |
| Debounce | handler files | 120/150 ms trailing-edge timers + buffered flush |
| State update | feature states | `refreshFromRealtime()` / granular handlers |
| UI update | `notifyListeners()` | Provider consumers (screens/tabs) |

---

## Subscription Configuration

Channel name: `justus-sync-$userId-$generation` — the generation counter (`RealtimeSyncConnection._generation`) is incremented on every `subscribe()`, so every (re)subscription gets a unique channel name. Supabase treats each as a brand-new subscription; the `subscribedGeneration != _generation` guard discards status callbacks from superseded channels.

| # | Table | Event types | Callback | Debounce | Dispatches to |
|---|---|---|---|---|---|
| 1 | `moods` | all | `MoodRealtimeHandler.handle` | 120 ms | `MoodState.refreshFromRealtime(changedUserId)` per **distinct** changed user (`mood_change_batch.dart`) |
| 2 | `partnerships` | all | `RefetchRealtimeHandler.handle` | 150 ms | `PartnerState.refreshFromRealtime` + `AuthState.refreshPartnershipFromRealtime` + `BaseRepository.clearPartnershipCache` |
| 3 | `missyou` | all | `MissYouRealtimeHandler.handle` | **none** (immediate) | `HomepageState.addMissYou` (insert) / `refreshFromRealtime` (delete) |
| 4 | `bucket_items` | all | `BucketRealtimeHandler.handle` | **none** (immediate) | `BucketState.applyRealtimeEvent` (granular insert/update/delete) |
| 5 | `game_questions` | all | `GameRealtimeHandler.handle` | **none** for insert/delete (immediate); 150 ms FIFO flush for update | `GameState.handleQuestionInsert/Delete` (immediate), `handleQuestionUpdate` (via `game_event_buffer.dart`) |
| 6 | `game_answers` | all | `GameRealtimeHandler.handle` | 150 ms FIFO flush (burst preserved) | `GameState.handleAnswerInsert/Update/Delete` (via `game_event_buffer.dart`) |
| 7 | `drive_items` | all | `RefetchRealtimeHandler.handle` | 150 ms | `DriveState.refreshFromRealtime` (full refetch) |
| 8 | `drive_item_reactions` | all | `RefetchRealtimeHandler.handle` | 150 ms | `DriveState.refreshFromRealtime` (full refetch) |
| 9 | `user_profiles` | all (update handled) | `RefetchRealtimeHandler.handle` | 150 ms | `ProfileState.loadProfile(force)` + `PartnerState.refreshFromRealtime` + `AuthState.refreshPartnershipFromRealtime` + `BaseRepository.clearPartnershipCache` |

All nine bindings register with `event: sb.PostgresChangeEvent.all`, `schema: 'public'`, and **no logical filters**. Row relevance is decided post-delivery in Dart.

---

## Debounce Timing

All debounces are **trailing-edge**: each incoming event cancels the pending timer and restarts it, so a burst collapses into one activation. The game debouncer additionally **buffers** its burst and flushes it FIFO, so no intermediate game event is dropped.

| Debouncer | Timer | Delay | Coalesces | Consequence of coalescing |
|---|---|---|---|---|
| Mood | `MoodChangeBatch` (`mood_change_batch.dart`) | 120 ms | multiple mood events | The **union** of distinct `changedUserId`s in the burst is flushed; a same-window burst from BOTH users refreshes both sides — nothing is skipped. |
| Partnership | `RefetchRealtimeHandler._refreshTimer` | 150 ms | partnership events | One full partnership refresh + cache clear. Order-insensitive (full refetch). |
| Game (answers + question updates) | `GameEventBuffer` (`game_event_buffer.dart`) | 150 ms | multiple game events | Full burst is buffered **FIFO** and every event is applied in delivery order — nothing is dropped. |
| Game (question insert/delete) | — | **none** | n/a | Immediate dispatch to `handleQuestionInsert/Delete` — explicitly bypasses the debounce "so events aren't dropped by debounce". |
| Drive | `RefetchRealtimeHandler._refreshTimer` | 150 ms | drive/reaction events | One full `DriveState.refreshFromRealtime()` — safer than granular, since it re-pulls the whole list. |
| User profile | `RefetchRealtimeHandler._refreshTimer` | 150 ms | `user_profiles` updates (self or partner row) | One refresh pass: partnership cache cleared, then `ProfileState.loadProfile(force: true)` + `PartnerState.refreshFromRealtime()` + `AuthState.refreshPartnershipFromRealtime()`. Full refetch, order-insensitive. |
| Bucket | — | **none** | n/a | Immediate granular `applyRealtimeEvent` in commit order. |
| MissYou | — | **none** | n/a | Immediate `addMissYou()` / `refreshFromRealtime()`. |
| Lifecycle resume | `RealtimeSyncConnection._lifecycleDebounceTimer` | 300 ms | app-resume bursts (task switcher) | One reconnect + full `_refreshAll`. |

---

## Deduplication — `RealtimeSyncSession.markSeen`

Data structures (`realtime_sync_session.dart`):

```dart
final Queue<String> _recentEventKeys = Queue<String>();
final Set<String> _recentEventKeySet = <String>{};
```

Event identity:

```dart
final row = currentRecord(payload);
final id = row['id'] ?? row['partnership_id'] ?? row['user_id'] ?? '';
final key = [
  payload.table,
  payload.eventType.name,
  id,
  payload.commitTimestamp.toUtc().toIso8601String(),
].join(':');
```

- Max tracked events: **80** (`const maxTrackedEvents = 80`). Oldest keys are evicted FIFO.
- Purpose: realtime platforms re-deliver events after a reconnect. Because every resubscription uses a *new* channel name, Supabase may replay recent committed events; the dedup absorbs replays within the 80-event window.
- The queue is **not** cleared on reconnect — it persists for the service lifetime, so replays across generations are deduplicated.

### Identity weaknesses

| Table | PK | `row['id']` present? | Dedup key identity |
|---|---|---|---|
| moods | `id` | yes | `moods:<event>:<id>:<commitTs>` — good |
| partnerships | `id` | yes | good |
| missyou | `id` | yes | good |
| bucket_items | `id` | yes | good |
| game_questions | `id` | yes | good |
| game_answers | composite `(game_id, user_id)` | **no** | falls back to `user_id` → `game_answers:<event>:<user_id>:<commitTs>` — **game_id not in the key** (F-RT6) |
| drive_items | `id` | yes | good |
| drive_item_reactions | `id` | yes | good |

`payload.commitTimestamp` is identical for every row committed in the **same transaction**. For `game_answers`, two answers by the same user in one transaction collapse to one key → the second is falsely dropped. In practice `submitAnswer` inserts a single row per request, so collisions are rare.

**Duplicate-risk window**: if more than 80 *other* events stream between the original delivery and a replay, the replay passes dedup and is processed again. Most handlers are idempotent (full refetches, `_knownIds` guards); **`addMissYou()` is not idempotent** and would double-count (F-RT5).

---

## Relevance Filtering

All filters gate on the session ids (`RealtimeSyncSession.userId/partnerId/partnershipId`, set by `configure()`).

| Filter | Rule | Notes |
|---|---|---|
| `RealtimeSyncSession.isRelevantMood` | `user_id == userId \|\| user_id == partnerId` | Guards self + partner moods |
| `isRelevantPartnership` | any of `user_id_1/user_id_2` in row == `userId` | Note: `user_id_a/b` also checked (unused columns, harmless) |
| `isRelevantMissYou` | → `isPartnershipRecord` | partnership_id match |
| `isPartnershipRecord` | `partnershipId == null` → `false` (strict); else `eventPartnershipId == partnershipId`. Sparse DELETE payloads (REPLICA IDENTITY DEFAULT → only PK delivered, no `partnership_id`) are exempt | Used by bucket, missyou, game_questions, drive_items |
| `isRelevantGame` | questions → partnership; answers → `user_id` self/partner | |
| `isRelevantDrive` | drive_items → partnership; reactions → `item_id` in local `_driveItems` | Reaction events for items not in the local list are dropped (F-RT8) |

### Note on the strict fallback

`isPartnershipRecord` returns `false` when the session `partnershipId == null` — incoming records are rejected, not "filtered everything in" (F-RT9 resolved). `configure()` defers subscription whenever `partnershipId == null`, so no channel exists without a partnership; the strict fallback is defense-in-depth for the pathological window where a channel outlives a partnership reset. The only accepted null-payload case is a DELETE event, whose `oldRecord` carries just the PK under the default `REPLICA IDENTITY` — feature-level `_knownIds` dedup and RLS still govern those events.

---

## Lifecycle

### start / auth events (`RealtimeSyncConnection.start`)

- `RealtimeSyncService.start()` → `RealtimeSyncConnection.start()` adds a `WidgetsBindingObserver` and subscribes to `_client.auth.onAuthStateChange`.
- `tokenRefreshed` → `_client.realtime.setAuth(token)` **without disconnecting** (recommended Supabase pattern). No reconnect is triggered.
- Any other auth event with `_foreground && userId != null` → `scheduleReconnect()`.

### configure (`RealtimeSyncService.configure`)

- Called post-frame by `RealtimeSyncScope` after every `AuthState`/`PartnerState` change (login, logout, partnership accepted/rejected).
- **No-op when IDs are unchanged**: retry/failure counters are reset and fields re-assigned (`RealtimeSyncSession` ids mutated), but if nothing changed the method returns before any log, reconnect, or unsubscribe — so the routine rebuilds of the `Consumer2` (e.g. after a profile edit's refresh batch) log **nothing**.
- On a real change: logs `configure() - CHANGE: ...`, resets `_reconnectAttempt` and `_consecutiveFailures`, clears the game-event FIFO buffer + mood batch, deactivates polling fallback.
- **Defers subscription** when `userId == null || partnershipId == null` → `unsubscribe()` and wait.
- On id change in foreground → `scheduleReconnect()`.

### subscribe (`RealtimeSyncConnection.subscribe`)

- Guarded by `_disposed || _subscribing || !_foreground || userId == null`.
- Increments `_generation`, calls `unsubscribe()`, then builds the 9-binding channel (from the facade's `RealtimeTableBinding` list) and `subscribe` with a status callback.
- Status handling:
  - `subscribed` → reset attempt/failure counters, deactivate polling, optionally `_refreshAll()` (when `refreshAfterSubscribe`).
  - `channelError` + `RealtimeCloseEvent` → `scheduleReconnect(closeEvent: ...)` (code-1002 → 3 s base delay).
  - `closed` / `channelError` / `timedOut` → `scheduleReconnect()`.
- Stale-generation guard: a status callback whose captured `subscribedGeneration != _generation` is ignored.

### unsubscribe (`RealtimeSyncConnection.unsubscribe`)

- Cancels `_reconnectTimer`, removes channel via `_client.removeChannel`. Guarded against no-op.

### Resume / Pause / Detach (`RealtimeSyncConnection.didChangeAppLifecycleState`)

- `resumed` → `_foreground = true`; if a user exists, a **300 ms lifecycle debounce timer** fires → `_reconnectAttempt = 0`, then `scheduleReconnect(refreshAfterSubscribe: true)` (reconnect + full `_refreshAll`).
- `paused` / `detached` / `hidden` → `_foreground = false`; cancel debounce and `unsubscribe()`. The WebSocket is torn down while backgrounded. On return to foreground the app **resubscribes and performs a full refresh** — the recovery mechanism for any events missed while backgrounded.
- `inactive` → no-op.

### JWT refresh

- Handled internally by Supabase on the existing connection; the client explicitly calls `setAuth` on `tokenRefreshed` to keep RLS authorizing the channel after token rotation. No reconnect, no event loss by design.

---

## Reconnection & Exponential Backoff (`RealtimeSyncConnection.scheduleReconnect`)

```
delayMs = clamp(baseDelay * 2^(reconnectAttempt-1), 1000, 60000)
  baseDelay  = 1000 ms  (normal)
             = 3000 ms  (close error code 1002 — WebSocket protocol error)
finalDelay  = delayMs + jitter,  jitter = ±25%
```

| Attempt | Shift | Normal base | Code-1002 base | Range |
|---|---|---|---|---|
| 1 | 0 | 1000 ms | 3000 ms | 1000–60000 |
| 2 | 1 | 2000 ms | 6000 ms | 1000–60000 |
| 3 | 2 | 4000 ms | 12000 ms | 1000–60000 |
| 4 | 3 | 8000 ms | 24000 ms | 1000–60000 |
| 5 | 4 | 16000 ms | 48000 ms | 1000–60000 |
| ≥6 | 5–7 | 32000–60000 ms | 60000 ms | 60000 |

- **Max attempts: 20.** When `_reconnectAttempt > 20`, reconnect stops; the counters reset on the next `configure()` or resume.
- **Refresh-after-subscribe**: only when requested (`refreshAfterSubscribe = true`), e.g. after lifecycle resume or `refreshChannel()`.
- **Code-1002 penalty**: base delay tripled for WebSocket protocol errors.

---

## Polling Fallback (`RealtimeSyncConnection.activatePollingFallback`)

- Activated when `_consecutiveFailures >= 3` — i.e. after three failed subscribe/reconnect cycles.
- `Timer.periodic(15 s)` calling `_refreshAll()` (full refresh of all seven feature states) plus an immediate `_refreshAll()` on activation.
- Stops when `_disposed || !_foreground`; deactivated on `subscribed` or on `configure()`.
- **Result**: even with Realtime completely down, data converges within 15 s. This is the eventual-synchronization guarantee.

---

## Wipe Suppression (`RealtimeSyncService.suppress`/`resume`/`refreshChannel`, `profile_screen.dart:152-167`)

- `suppress()` sets `RealtimeSyncSession.suppressProcessing = true` and clears the game-event FIFO buffer + mood batch; every handler checks the flag **before** dedup/filtering (so nothing is marked seen during the wipe).
- `resume(refresh: true)` clears the flag and runs `_refreshAll()`.
- The app-data wipe flow (`profile_screen.dart:152-167`) calls `suppress()` → `wipeAppData()` → **`refreshChannel()`** (never `resume()`). `refreshChannel()` → `unsubscribe()` → `subscribe(refreshAfterSubscribe: true)`. Since `subscribe()` resets `suppressProcessing = false` and grants `refreshAfterSubscribe`, the full refresh post-wipe resets suppression. Events arriving during the wipe are not marked seen and are re-delivered on the fresh channel — **no events are lost by suppression**.

---

## Per-Topic Deep Dive

### moods

- **Flow**: mood event → relevance (`user_id` self/partner) → dedup → `MoodChangeBatch` (120 ms trailing-edge, distinct-`changedUserId` union) → `MoodState.refreshFromRealtime(changedUserId)` for each distinct user in the burst. (`MoodRealtimeHandler`)
- `changedUserId == self` → only `_updateMoodsCheckpoint()` runs (the optimistic `updateMood` path already handled the local state — **no duplicate work**).
- `changedUserId == partner` → `fetchRecentEmojis()` + `fetchTimeline()` + `fetchPartnerMood()`.
- `null` → full fallback: `fetchMyMood()` + `fetchPartnerMood()` + shared fetches.
- Always ends with `_updateMoodsCheckpoint()`.
- Comment in `mood_state.dart:210`: *"Own action: optimistic update already handled everything"*.
- **Burst handling**: a same-window burst from BOTH users coalesces into the union of their ids, so each partition-owned refresh runs exactly once — neither side is skipped.

### partnerships

- **Flow**: partnership event → `isRelevantPartnership` (membership) → dedup → 150 ms debounce → `BaseRepository.clearPartnershipCache()` + `Future.wait([PartnerState.refreshFromRealtime(), AuthState.refreshPartnershipFromRealtime()])`. (`RefetchRealtimeHandler` instance)
- Refresh re-reads `getActivePartnership` (now uncached), applies partner/partnership id to `AuthState`, persists via `StorageService.savePartner`/`savePartnershipId`, and `notifyListeners()` → `RealtimeSyncScope` Consumer2 → `configure(new ids)` → channel replaced and re-bound to the correct partnership.
- **Acceptance path**: a status change `pending → accepted` is received by both users; each reconfigures and resubscribes. The accepting user's `refreshPartnershipFromRealtime` (spawned by `acceptPartner`) and the event-driven one are coalesced by the same `_partnershipRefreshTimer`.

### user_profiles

- **Purpose**: propagates self/partner profile edits (display name, profile picture) in realtime. Enabled by adding `user_profiles` to the `supabase_realtime` publication (`supabase/schemas/_cluster/publications.sql`) and the `user_profiles` binding in `realtime_sync_service.dart`. (update-only `RefetchRealtimeHandler` instance — event-type filter in the `isRelevant` wiring)
- **Flow**: `UPDATE` on `user_profiles` → `isRelevantUserProfile` (`user_id` == `userId` or `partnerId`) → dedup → 150 ms debounce → `BaseRepository.clearPartnershipCache()` + `Future.wait([ProfileState.loadProfile(force: true), PartnerState.refreshFromRealtime(), AuthState.refreshPartnershipFromRealtime()])`.
- `INSERT`/`DELETE` events are ignored (only `update` is processed) — profile rows are inserted at signup (before the channel is bound) and never deleted.
- `loadProfile(force: true)` bypasses the 1-minute throttle (`force` param) and refreshes both `_userProfile` and `_partnerProfile` plus the `user_profile`/`partner_profile` caches; the partnership refetches re-read uncached `v_active_partnership` and update `AuthState`/`StorageService` so `partner_display_name` stays in sync for games/homepage.
- **Self-edits**: the editing device also receives its own `UPDATE`; the refresh is idempotent (re-reads the same values).
- Same-channel dedup via `markSeen` prevents double-processing when a burst of `user_profiles` events for the same row arrives.

### missyou

- **Flow**: `isRelevantMissYou` (partnership) → dedup → **immediate**. (`MissYouRealtimeHandler`)
  - insert → `HomepageState.addMissYou()`: local `_totalMissYou += 1` + `saveTotalMissYou`. **Not idempotent** (F-RT5).
  - delete → `HomepageState.refreshFromRealtime()` → full `fetchMissYouTotal()`.
- Local counter overwritten by authoritative count on every full refetch (`fetchTotalMissYou`), so drift self-heals at the 60 s `CacheService.needsRefresh(kMissYou)` cadence or on any refresh.
- **Risk**: `addMissYou()` racing an in-flight `fetchTotalMissYou()` → the fetch snapshot can overwrite the increment; recovers on next poll (transient, LOW).

### bucket_items

- **Flow**: `isPartnershipRecord` → dedup → **immediate** `BucketState.applyRealtimeEvent(eventType, newRecord, oldRecord)`. (`BucketRealtimeHandler`)
- Granular, ordered application:
  - insert → guard `_knownIds.add(id)` (no-ops on duplicates) → prepend to `_items`.
  - update → guard `_knownIds.contains(id)` → replace item in place.
  - delete → guard `_knownIds.remove(id)` → remove from `_items`.
- State is kept in sync with server per event; debounced cache flush (`_flushCache`); `notifyListeners()` when changed.
- Because application is **immediate and in order**, no dedup false-positive beyond the 80-item replay window.
- **Risk**: `applyRealtimeEvent` races a concurrent full `refreshFromRealtime()` (from `_refreshAll`, polling, resume): the full-refetch snapshot (taken earlier) can overwrite the applied event (F-RT4).

### game_questions

- insert → **immediate** `handleQuestionInsert` → `fetchNewQuestion(showLoading: false)` (fresh question). (`GameRealtimeHandler`)
- delete → **immediate** `handleQuestionDelete` → clears the question if it matches and scrubs history by `questionId`.
- update → 150 ms FIFO flush → `handleQuestionUpdate`: updates `question`/`status`; on `both_answered` clears the question + cache.

### game_answers

- insert → **150 ms trailing-edge debounce + FIFO flush** → `handleAnswerInsert`.
- update → **150 ms trailing-edge debounce + FIFO flush** → `handleAnswerUpdate` (re-fetches authoritative status).
- delete → **150 ms trailing-edge debounce + FIFO flush** → `handleAnswerDelete` (clears per-user answer flags + history options).
- The DB trigger `update_game_question_status` sets `game_questions.status = 'both_answered'` once both rows exist, emitting a `game_questions` UPDATE back on the channel. On the waiting device both events (answer INSERT + status UPDATE) routinely land within 150 ms; the FIFO flush applies both in delivery order, so the INSERT is never dropped.

### drive_items / drive_item_reactions

- **Flow**: `isRelevantDrive` → dedup → 150 ms debounce → **full** `DriveState.refreshFromRealtime()`: re-fetch entire `v_drive_dashboard`, sort by `created_at`, rebuild favorites, refresh `_singleItem` if open, `saveDriveItems` to cache, update `chk_drive_items`. (`RefetchRealtimeHandler` instance)
- Guarded by `_isSyncing` — concurrent refreshes are skipped, not queued.
- **Deletion**: DELETE events arrive on the same channel (all events) → debounced full refetch → deleted items disappear from cache. Outside Realtime, `DriveState.syncDriveItems` detects deletions via a server row-count vs. cached-length comparison that triggers a full **replacing** refetch (storage doc F-SC7); a same-count swap (insert + delete between refreshes) is recovered only by Realtime/polling.

---

## Guarantees Assessment

### No duplicate processing — PARTIAL

- Dedup (80-entry LRU) absorbs replay-after-reconnect within the window; all resubscribes use a new channel name, so replays are expected and filtered.
- Most handlers are idempotent: full-refetch handlers (mood, drive, partnership, missyou-delete, game question insert), guarded handlers (`_knownIds` in bucket), keyed replace/remove in game history.
- **Exceptions**:
  - `addMissYou()` is a raw counter increment — a replay beyond the 80-event window double-counts (F-RT5). LOW likelihood.
  - `game_answers` dedup key can **collide** (false duplicate → event dropped), which errs in the *missed-event* direction, not duplicate (F-RT6).
- `BaseState.notifyListeners()` coalesces same-frame rebuild storms (frame-by-frame), not event-level — this is UI coalescing, separate from event dedup.

### No missed events — PARTIAL

Events are dropped in normal operation in three ways:

1. **Debounce coalescing (trailing-edge)** — bursts collapse into one activation, but the buffered payload is flushed **entirely** (FIFO), so intermediate events are no longer lost:
   - Game answers: all events of a burst are buffered and applied in delivery order via `game_event_buffer.dart`. In the common two-player flow, the partner's `game_answers` INSERT and the `both_answered` `game_questions` UPDATE landing within 150 ms are both applied — history and stats stay in sync.
   - Mood: the distinct `changedUserId` union of the burst is refreshed; a mixed-user burst refreshes both sides (`mood_change_batch.dart`).
2. **Reaction filtering** — `drive_item_reactions` events for items *not currently in the local drive list* are filtered out (`isRelevantDrive`); reaction state for a not-yet-loaded item is unavailable until next refresh (F-RT8).
3. **Replay/dedup boundary** — events older than the 80-entry window on a replay are re-processed (duplicate) or lost only in the sense described above.

**Backstops that recover dropped events** (eventual sync):
- Polling fallback `_refreshAll()` every 15 s while Realtime is degraded.
- `resume()` → reconnect + `_refreshAll`.
- `refreshAfterSubscribe` full refresh after lifecycle resume / `refreshChannel`.
- Cold-start `loadWithChangeDetection` per feature (checkpoint-based).

Because every handler converges to *server current state* on refetch, dropped intermediate events are eventually reflected — hence **eventual synchronization is achieved** even though per-event delivery is not lossless.

### Eventual synchronization — YES

Convergence is guaranteed (given connectivity) by the combination of: 15 s polling fallback, resume → resubscribe + `_refreshAll`, subscribe-success refreshes, and checkpoint-gated cold-start refetches. The worst-case staleness bound is ~15 s when Realtime is down, ~0 s when healthy (game-answer bursts are fully lossless).

### Correct account isolation — YES

Enforced server-side by RLS on the WebSocket (a JWT only receives rows its policies allow: self/own-partnership rows on every subscribed table) and re-verified client-side by `isRelevant*`. Account-level data is destroyed on logout (`clearAll()` removes all caches), and partnership-level cached state is namespaced per-partnership (storage doc, F-SC8 resolved) — see below.

### Correct partnership isolation — YES

`configure()` binds the channel keys and filters to the active partnership; `isPartnershipRecord` gates bucket/missyou/questions/drive; RLS gates server-side; re-partnering replaces the channel via `configure`. The Realtime layer converges to server state regardless of cache, and the caching layer no longer leaks across partnerships: feature caches + checkpoints are namespaced per-partnership and purged on partnership transition (storage doc, F-SC8 resolved), so a stale cold-start can no longer suppress the refetch that would show previous-partner data.

---

## Timestamp Checkpoint Races

The Realtime layer interacts with the partnership-scoped checkpoint keys (`chk_moods`, `chk_game_answers`, `chk_bucket_items`, `chk_drive_items`, `chk_miss_you`). Relevant races:

### R-1: Checkpoint write-back vs. concurrent Realtime refresh (LOW)

Every refresh writes a checkpoint computed from *its own* SELECT snapshot (`fetchTimeline` → `_updateMoodsCheckpoint`, `refreshFromRealtime` → `_updateDriveCheckpointFromItems`, etc.). When a fast refresh completes **after** a slower one that observed newer data, the checkpoint can be written *backwards* (regress). Because `checkpoint == null → hasChanges → true` and `serverDate.isAfter(checkpoint)` triggers refetch, a regression only causes a **redundant refetch**, never data loss. Net: self-healing; wasted round-trips.

### R-2: Checkpoint covering undelivered events (LOW)

A full refresh whose checkpoint `max(timestamp)` is *ahead* of the events the channel has delivered suppresses cold-start refetches for those rows. Since Realtime delivers the events independently, the UI still receives them in-session; only a *restart before delivery* would rely on the (too-far-ahead) checkpoint — mitigated by the fact that Realtime re-delivers recent commits after resubscribe (post-resume full refresh).

### R-3: Mood "optimistic" EMPTY checkpoint (`mood_state.dart:58-68`)

`_hasMoodChanges` writes `kCheckpointEmpty` when changes exist, *before* the fetch. `hasChanges` then returns `true` on the next cycle until a real fetch writes a real timestamp — i.e. it **forces** retries after failed fetches (good) but also forces one redundant cycle after every successful one (harmless).

### R-5: `chk_drive_items` strict `>` boundary

`fetchDriveItemsIncremental` uses `gt('updated_at', checkpoint)`; rows whose `updated_at` equals the checkpoint (multi-row same-transaction commits, or microsecond collisions) are skipped. Deletions are invisible to incremental fetches entirely — recovered by the count-mismatch full replace in `syncDriveItems`, by Realtime DELETE events, or by polling `_refreshAll`.

---

## Event Ordering

- Supabase delivers events per channel in commit order. The client does not re-sort.
- **Order-insensitive consumers** (full-refetch handlers): mood, drive, partnership, missyou-delete — safe under reordering/replay.
- **Order-sensitive consumers**:
  - `bucket applyRealtimeEvent` — applied immediately in delivery order; correct while the channel is healthy. The bucket/refresh race (F-RT4) is the ordering hazard.
  - `game` granular handlers — buffered FIFO (`game_event_buffer.dart`) and drained in delivery order, so bursts are applied without reordering or loss. The immediate question insert/delete paths bypass the buffer and preserve order.
- **Reconnect replay ordering**: Supabase replays recent commits after resubscribe; the dedup + post-resume `_refreshAll` normalize any out-of-order application.

---

## Findings

### F-RT4: Bucket realtime-apply vs. full-refresh replacement race (MEDIUM)

- **WHAT**: `BucketState.applyRealtimeEvent` mutates `_items` incrementally while `BucketState.refreshFromRealtime` (from `_refreshAll`, polling, resume) **replaces** `_items` with a snapshot. A full-refetch snapshot taken *before* an insert commits can complete *after* the event was applied and overwrite it.
- **WHERE**: `bucket_state.dart:80-91` (refresh) vs `130-162` (apply).
- **WHEN**: Any overlap of realtime events with a 15 s poll, resume refresh, or `refreshChannel`.
- **IMPACT**: Newly inserted item disappears from the list until the next event or refresh. `_knownIds` still contains its id (so a replay won't re-add it and the item is simply absent). Transient but persistent until a full refresh.
- **CONFIDENCE**: MEDIUM.

### F-RT5: `addMissYou()` is non-idempotent; dedup window overflow double-counts (LOW)

- **WHAT**: `HomepageState.addMissYou` unconditionally `_totalMissYou += 1` + persist. If a replay passes dedup (>80 intervening events, or key collision), the count is incremented twice for one server row. Also races an in-flight `fetchTotalMissYou` (snapshot overwrite).
- **WHERE**: `homepage_state.dart:64-68`; dedup window at `realtime_sync_session.dart` (`markSeen`).
- **WHEN**: Replays after long disconnect periods on a busy channel, or burst >80 events between delivery and replay.
- **IMPACT**: Transient wrong count; self-corrects on the next authoritative `fetchTotalMissYou` (60 s `kMissYou` freshness gate or any refresh). Nobody blocks on it — LOW.
- **CONFIDENCE**: LOW for occurrence, HIGH for non-idempotency of the path.

### F-RT6: `game_answers` dedup key omits `game_id` (LOW)

- **WHAT**: `markSeen` keys on `row['id'] ?? ... ?? row['user_id']`. `game_answers` has a composite PK and no `id` column (schema), so the key degrades to `game_answers:<event>:<user_id>:<commitTimestamp>`. Two answers by the same user in one transaction → identical key → second dropped.
- **WHERE**: `realtime_sync_session.dart` (`markSeen`); schema `game_answers` (composite `game_id,user_id`).
- **WHEN**: Batch/transactional multi-answer submits for one user (not produced by the current single-row `submitAnswer` path).
- **IMPACT**: Dropped event → stale history until refresh. The game-event FIFO buffer does not address dedup-key collisions.
- **CONFIDENCE**: LOW (occurrence), HIGH (key construction).

### F-RT7: Reconnect gives up permanently until lifecycle/configure (LOW)

- **WHAT**: After 20 reconnect attempts, `scheduleReconnect` stops. With polling fallback active, no further subscribe is ever attempted until `configure()` or app `resume` — a sustained outage leaves the app in 15 s polling indefinitely in the background whereas the WebSocket could have recovered.
- **WHERE**: `realtime_connection.dart` (`scheduleReconnect`, `activatePollingFallback`).
- **WHEN**: Network outage > ~15 minutes while the app stays foregrounded.
- **IMPACT**: Data freshness preserved (15 s polling) but realtime pushes are not resumed until user action. Acceptable degradation; deliberately chosen.
- **CONFIDENCE**: MEDIUM.

### F-RT8: Reaction events for unloaded drive items are filtered out (LOW)

- **WHAT**: `isRelevantDrive` for `drive_item_reactions` requires `item_id` present in the *current in-memory* drive list. A reaction on an item not in the local list is dropped — including reactions on items the local drive list is about to load.
- **WHERE**: `realtime_sync_session.dart` (`isRelevantDrive`).
- **WHEN**: Partner reacts to an item the user hasn't loaded (paged-out history).
- **IMPACT**: Reaction does not appear in the detail view until a full refresh. Minor.
- **CONFIDENCE**: HIGH.

### F-RT10: Checkpoint write-back can regress under concurrent refreshes (LOW)

- **WHAT**: Refresh A with an older snapshot can land *after* refresh B with a newer one and write a lower checkpoint max (R-1). Only causes a redundant refetch on next init.
- **WHERE**: shared checkpoints — `mood_state.dart:74-84`, `game_state.dart:91-108`, `drive_state.dart:193-201`, `base_repository.dart:79-108`.
- **IMPACT**: Extra round-trip; never data loss. Noted for completeness.
- **CONFIDENCE**: MEDIUM.

---

## Implementation Status

| Component | Status |
|---|---|
| Single channel, 9-table subscription (all events) | IMPLEMENTED |
| Client-side user/partner/partnership relevance filtering | IMPLEMENTED (`realtime_sync_session.dart`) |
| 80-event dedup LRU | IMPLEMENTED (`realtime_sync_session.dart`) |
| Per-table debounce (120/150 ms) + lifecycle debounce (300 ms) | IMPLEMENTED (handlers + `realtime_connection.dart`) |
| Generation counter stale-channel guard | IMPLEMENTED |
| Exponential backoff with jitter, code-1002 penalty, max 20 attempts | IMPLEMENTED |
| Polling fallback at 15 s after 3 consecutive failures | IMPLEMENTED |
| Resume → resubscribe + full `_refreshAll` | IMPLEMENTED |
| Pause/detach/hidden → unsubscribe | IMPLEMENTED |
| JWT `setAuth` on token refresh (no reconnect) | IMPLEMENTED |
| Wipe suppression (`suppress`/`resume`/`refreshChannel`) | IMPLEMENTED |
| Bucket granular in-order application | IMPLEMENTED |
| Game question insert/delete bypassing debounce | IMPLEMENTED |
| Game answer debounce lossless in bursts (FIFO buffer) | IMPLEMENTED |
| Mood debounce distinct-user burst handling | IMPLEMENTED |
| Service split into facade + connection + session + handlers | IMPLEMENTED |
| Unified `RealtimeHandler` template (shared suppress/relevance/dedup preamble) | IMPLEMENTED |
| `RefetchRealtimeHandler` unifies partnership/drive/user_profiles full-refetch strategy | IMPLEMENTED |
| Realtime auto-recovery while polling fallback active | NOT IMPLEMENTED (F-RT7) |

---

## Tests

No automated tests exercise the full realtime pipeline (`realtime_sync_scope.dart` and the `realtime_connection.dart`/handler classes are not referenced by any file in `Flutter/test/`), but the game-event FIFO buffer is covered at unit level (`test/game_event_buffer_test.dart`), the both-answered burst semantics is covered at state level (`test/game_burst_flow_test.dart`), and the mood distinct-user coalescing is covered at unit level (`test/mood_change_batch_test.dart`).

**Not covered**: subscription/channel lifecycle, generation guard, dedup LRU behavior, relevance filtering, backoff/polling transitions, resume/detach behavior, wipe suppression, and the remaining F-RT4–F-RT10 scenarios (full pipeline coverage planned in Phase 8).

---

## Notes

- **Single channel caps 9 tables**: all bindings share one WebSocket channel. A failure of one table's filter (e.g. malformed payload) is isolated per-callback, but a channel-level failure drops all nine simultaneously (designed). Binding order is preserved: the facade builds the `RealtimeTableBinding` list in table order and the connection iterates it when building the channel.
- **Mutations are fire-and-forget**: `submitAnswer`, `addBucketItem`, `toggleDone`, `uploadDriveItemToR2`, `deleteItem`, `addReaction` do not await server confirmation; state reconciliation relies on Realtime echoes + periodic refetches. No optimistic rollback exists for bucket/drive mutations — only mood implements optimistic update with rollback (`mood_state.dart:233-282`).
- **Realtime echo self-loop is handled**: the app receives its **own** mutations back on the channel. Bucket uses `_knownIds`; game uses `isOwnInsert`; mood uses the `changedUserId == self` no-op; drive/missyou use full refetch/idempotent increment. No duplicates arise from the self-echo path.
- **`notifyListeners()` is frame-coalesced** (`base_state.dart:22-29`): bursts of state writes during realtime refreshes produce a single rebuild per frame — this is UI coalescing, not event coalescing.
- **Realtime is the fast path, not the source of truth**: every consumer eventually re-fetches from the server (refresh handlers, polling, checkpoint-gated init). The system is eventually consistent by construction; per-event losslessness is not guaranteed in general (F-RT4), but game-answer bursts are lossless via the FIFO buffer and mood bursts refresh every distinct changed user.
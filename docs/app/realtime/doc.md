# Supabase Realtime Synchronization — JustUS

## Overview

JustUS uses a single Supabase Realtime channel per user (`justus-sync-$userId-$generation`) with **eight** Postgres Change subscriptions (all event types, no server-side logical filters). Events are pushed to the client, filtered against the local user/partner/partnership identity, deduplicated via a bounded LRU, optionally debounced, and dispatched to per-feature state handlers that mutate in-memory state and persist caches.

A **polling fallback** (15 s interval) and **exponential-backoff resubscription** (max 20 attempts) guarantee eventual synchronization when the WebSocket is unstable. Realtime is the fast path; the checkpoint-based `loadWithChangeDetection` cold-start path is the slow path.

Two layers of isolation are enforced:

1. **Server-side RLS** — Supabase filters which rows each JWT can read/write before an event is delivered on the WebSocket.
2. **Client-side relevance filters** — `_isRelevant*()`/`_isPartnershipRecord()` re-verify the payload against `_userId`, `_partnerId`, `_partnershipId` before processing.

---

## The Pipeline

```
Supabase Postgres commit
  └─ (WAL → Realtime server)
        └─ WebSocket delivers PostgresChangePayload (RLS-filtered by JWT)
              └─ Channel: justus-sync-$userId-$generation
                    └─ onPostgresChanges(event: all, schema: public, table: <8 tables>)
                          └─ relevance filter  (_isRelevant* / _isPartnershipRecord)
                                ├─ dropped if not user/partner/partnership
                                └─ dedup            (_markSeen, 80-entry FIFO LRU)
                                      └─ if duplicate → dropped
                                      └─ if new → per-table debounce (or immediate)
                                            └─ state update (feature state method)
                                                  └─ cache write (StorageService)
                                                        └─ notifyListeners()
                                                              └─ UI rebuild (Provider consumers)
```

| Stage | Where | Mechanism |
|---|---|---|
| Supabase event | Postgres WAL | `PostgresChangeEvent.all` (INSERT/UPDATE/DELETE) |
| Subscription | `realtime_sync_service.dart:268-317` | 1 channel, 8 `.onPostgresChanges` bindings |
| Filtering | `:509-563` | Client relevance: user/partner/partnership |
| Deduplication | `:584-608` | `_markSeen`, FIFO LRU of 80 event keys |
| Debounce | `:404-409, 418-426, 478-493, 502-506` | 120/150 ms trailing-edge timers |
| State update | feature states | `refreshFromRealtime()` / granular handlers |
| UI update | `notifyListeners()` | Provider consumers (screens/tabs) |

---

## Subscription Configuration

Channel name: `justus-sync-$userId-$generation` — the generation counter is incremented on every `_subscribe()` call, so every (re)subscription gets a unique channel name. Supabase treats each as a brand-new subscription; the `subscribedGeneration != _generation` guard (`:325-329`) discards status callbacks from superseded channels.

| # | Table | Event types | Callback | Debounce | Dispatches to |
|---|---|---|---|---|---|
| 1 | `moods` | all | `_handleMoodPayload` | 120 ms | `MoodState.refreshFromRealtime(changedUserId)` |
| 2 | `partnerships` | all | `_handlePartnershipPayload` | 150 ms | `PartnerState.refreshFromRealtime` + `AuthState.refreshPartnershipFromRealtime` + `BaseRepository.clearPartnershipCache` |
| 3 | `missyou` | all | `_handleMissYouPayload` | **none** (immediate) | `HomepageState.addMissYou` (insert) / `refreshFromRealtime` (delete) |
| 4 | `bucket_items` | all | `_handleBucketPayload` | **none** (immediate) | `BucketState.applyRealtimeEvent` (granular insert/update/delete) |
| 5 | `game_questions` | all | `_handleGamePayload` | **none** for insert/delete (immediate); 150 ms for update | `GameState.handleQuestionInsert/Delete` (immediate), `handleQuestionUpdate` (debounced) |
| 6 | `game_answers` | all | `_handleGamePayload` | 150 ms | `GameState.handleAnswerInsert/Update/Delete` (debounced) |
| 7 | `drive_items` | all | `_handleDrivePayload` | 150 ms | `DriveState.refreshFromRealtime` (full refetch) |
| 8 | `drive_item_reactions` | all | `_handleDrivePayload` | 150 ms | `DriveState.refreshFromRealtime` (full refetch) |

All eight bindings register with `event: sb.PostgresChangeEvent.all`, `schema: 'public'`, and **no logical filters**. Row relevance is decided post-delivery in Dart.

---

## Debounce Timing

All debounces are **trailing-edge**: each incoming event cancels the pending timer and restarts it, so only the *last* event in a burst triggers the work.

| Debouncer | Timer | Delay | Coalesces | Consequence of coalescing |
|---|---|---|---|---|
| Mood | `_moodRefreshTimer` | 120 ms | multiple mood events | One `refreshFromRealtime(changedUserId)` executes; `changedUserId` comes from the **last** event only (F-RT2). |
| Partnership | `_partnershipRefreshTimer` | 150 ms | partnership events | One full partnership refresh + cache clear. Order-insensitive (full refetch). |
| Game (answers + question updates) | `_gameRefreshTimer` | 150 ms | multiple game events | Only the **last** event's `(table, eventType, payload)` is applied (F-RT1). |
| Game (question insert/delete) | — | **none** | n/a | Immediate dispatch to `handleQuestionInsert/Delete` — explicitly bypasses the debounce "so events aren't dropped by debounce" (`:466`). |
| Drive | `_driveRefreshTimer` | 150 ms | drive/reaction events | One full `DriveState.refreshFromRealtime()` — safer than granular, since it re-pulls the whole list. |
| Bucket | — | **none** | n/a | Immediate granular `applyRealtimeEvent` in commit order. |
| MissYou | — | **none** | n/a | Immediate `addMissYou()` / `refreshFromRealtime()`. |
| Lifecycle resume | `_lifecycleDebounceTimer` | 300 ms | app-resume bursts (task switcher) | One reconnect + full `_refreshAll`. |

`_missYouRefreshTimer` is **declared but never used** (F-RT3).

---

## Deduplication — `_markSeen`

Data structures (`:61-62`):

```dart
final Queue<String> _recentEventKeys = Queue<String>();
final Set<String> _recentEventKeySet = <String>{};
```

Event identity (`:584-608`):

```dart
final row = _currentRecord(payload);
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

All filters gate on `_userId`, `_partnerId`, `_partnershipId` (set by `configure()`).

| Filter | Rule | Notes |
|---|---|---|
| `_isRelevantMood` (`:509-514`) | `user_id == _userId \|\| user_id == _partnerId` | Guards self + partner moods |
| `_isRelevantPartnership` (`:516-526`) | any of `user_id_1/user_id_2` in row == `_userId` | Note: `user_id_a/b` also checked (unused columns, harmless) |
| `_isRelevantMissYou` (`:528-529`) | → `_isPartnershipRecord` | partnership_id match |
| `_isPartnershipRecord` (`:532-540`) | `eventPartnershipId == _partnershipId`; **permissive (`true`) if `_partnershipId == null`** | Used by bucket, missyou, game_questions, drive_items |
| `_isRelevantGame` (`:542-552`) | questions → partnership; answers → `user_id` self/partner | |
| `_isRelevantDrive` (`:554-563`) | drive_items → partnership; reactions → `item_id` in local `_driveItems` | Reaction events for items not in the local list are dropped (F-RT9) |

### Note on the permissive fallback

`_isPartnershipRecord` returns `true` when `_partnershipId == null` — i.e. "filter everything in". This is **safe by construction**: `configure()` defers subscription whenever `partnershipId == null` (`:135-140`), so no channel exists without a partnership. The fallback only matters in the pathological window where the channel outlives a partnership reset; RLS still gates the events server-side.

---

## Lifecycle

### start / auth events (`:87-112`)

- `start()` adds a `WidgetsBindingObserver` and subscribes to `_client.auth.onAuthStateChange`.
- `tokenRefreshed` → `_client.realtime.setAuth(token)` **without disconnecting** (recommended Supabase pattern). No reconnect is triggered.
- Any other auth event with `_foreground && _userId != null` → `_scheduleReconnect()`.

### configure (`:114-145`)

- Called post-frame by `RealtimeSyncScope` after every `AuthState`/`PartnerState` change (login, logout, partnership accepted/rejected).
- Resets `_reconnectAttempt` and `_consecutiveFailures`, deactivates polling fallback.
- **Defers subscription** when `userId == null || partnershipId == null` → `_unsubscribe()` and wait.
- On id change in foreground → `_scheduleReconnect()`.

### subscribe (`:249-376`)

- Guarded by `_disposed || _subscribing || !_foreground || _userId == null`.
- Increments `_generation`, calls `_unsubscribe()`, then builds the 8-binding channel and `subscribe` with a status callback.
- Status handling:
  - `subscribed` → reset attempt/failure counters, deactivate polling, optionally `_refreshAll()` (when `refreshAfterSubscribe`).
  - `channelError` + `RealtimeCloseEvent` → `_scheduleReconnect(closeEvent: ...)` (code-1002 → 3 s base delay).
  - `closed` / `channelError` / `timedOut` → `_scheduleReconnect()`.
- Stale-generation guard: a status callback whose captured `subscribedGeneration != _generation` is ignored.

### unsubscribe (`:378-394`)

- Cancels `_reconnectTimer`, removes channel via `_client.removeChannel`. Guarded against no-op.

### Resume / Pause / Detach (`:148-175`)

- `resumed` → `_foreground = true`; if a user exists, a **300 ms lifecycle debounce timer** fires → `_reconnectAttempt = 0`, then `_scheduleReconnect(refreshAfterSubscribe: true)` (reconnect + full `_refreshAll`).
- `paused` / `detached` / `hidden` → `_foreground = false`; cancel debounce and `_unsubscribe()`. The WebSocket is torn down while backgrounded. On return to foreground the app **resubscribes and performs a full refresh** — the recovery mechanism for any events missed while backgrounded.
- `inactive` → no-op.

### JWT refresh

- Handled internally by Supabase on the existing connection; the client explicitly calls `setAuth` on `tokenRefreshed` to keep RLS authorizing the channel after token rotation. No reconnect, no event loss by design.

---

## Reconnection & Exponential Backoff (`:177-218`)

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

## Polling Fallback (`:220-247`)

- Activated when `_consecutiveFailures >= 3` (`:185-187`) — i.e. after three failed subscribe/reconnect cycles.
- `Timer.periodic(15 s)` calling `_refreshAll()` (full refresh of all seven feature states) plus an immediate `_refreshAll()` on activation.
- Stops when `_disposed || !_foreground`; deactivated on `subscribed` or on `configure()`.
- **Result**: even with Realtime completely down, data converges within 15 s. This is the eventual-synchronization guarantee.

---

## Wipe Suppression (`:64-85`, `profile_screen.dart:93-108`)

- `suppress()` sets `_suppressProcessing = true`; every handler checks it **before** dedup/filtering (so nothing is marked seen during the wipe).
- `resume(refresh: true)` clears the flag and runs `_refreshAll()`.
- The app-data wipe flow (`profile_screen.dart:93-108`) calls `suppress()` → `wipeAppData()` → **`refreshChannel()`** (never `resume()`). `refreshChannel()` → `_unsubscribe()` → `_subscribe(refreshAfterSubscribe: true)`. Since `_subscribe()` resets `_suppressProcessing = false` (`:260`) and grants `refreshAfterSubscribe`, the full refresh post-wipe resets `_suppressProcessing`. Events arriving during the wipe are not marked seen and are re-delivered on the fresh channel — **no events are lost by suppression**.

---

## Per-Topic Deep Dive

### moods

- **Flow**: mood event → relevance (`user_id` self/partner) → dedup → 120 ms debounce → `MoodState.refreshFromRealtime(changedUserId)`.
- `changedUserId == self` → only `_updateMoodsCheckpoint()` runs (the optimistic `updateMood` path already handled the local state — **no duplicate work**).
- `changedUserId == partner` → `fetchRecentEmojis()` + `fetchTimeline()` + `fetchPartnerMood()`.
- `null` → full fallback: `fetchMyMood()` + `fetchPartnerMood()` + shared fetches.
- Always ends with `_updateMoodsCheckpoint()`.
- Comment in `mood_state.dart:210`: *"Own action: optimistic update already handled everything"*.
- **Risk**: debounce captures `changedUserId` from the last event only; a same-120-ms burst from BOTH users refreshes only one side (F-RT2). Recovered by the next event or `_refreshAll`.

### partnerships

- **Flow**: partnership event → `_isRelevantPartnership` (membership) → dedup → 150 ms debounce → `BaseRepository.clearPartnershipCache()` + `Future.wait([PartnerState.refreshFromRealtime(), AuthState.refreshPartnershipFromRealtime()])`.
- Refresh re-reads `getActivePartnership` (now uncached), applies partner/partnership id to `AuthState`, persists via `StorageService.savePartner`/`savePartnershipId`, and `notifyListeners()` → `RealtimeSyncScope` Consumer2 → `configure(new ids)` → channel replaced and re-bound to the correct partnership.
- **Acceptance path**: a status change `pending → accepted` is received by both users; each reconfigures and resubscribes. The accepting user's `refreshPartnershipFromRealtime` (spawned by `acceptPartner`) and the event-driven one are coalesced by the same `_partnershipRefreshTimer`.

### missyou

- **Flow**: `_isRelevantMissYou` (partnership) → dedup → **immediate**.
  - insert → `HomepageState.addMissYou()`: local `_totalMissYou += 1` + `saveTotalMissYou`. **Not idempotent** (F-RT5).
  - delete → `HomepageState.refreshFromRealtime()` → full `fetchMissYouTotal()`.
- Local counter overwritten by authoritative count on every full refetch (`fetchTotalMissYou`), so drift self-heals at the 60 s `CacheService.needsRefresh(kMissYou)` cadence or on any refresh.
- **Risk**: `addMissYou()` racing an in-flight `fetchTotalMissYou()` → the fetch snapshot can overwrite the increment; recovers on next poll (transient, LOW).

### bucket_items

- **Flow**: `_isPartnershipRecord` → dedup → **immediate** `BucketState.applyRealtimeEvent(eventType, newRecord, oldRecord)`.
- Granular, ordered application:
  - insert → guard `_knownIds.add(id)` (no-ops on duplicates) → prepend to `_items`.
  - update → guard `_knownIds.contains(id)` → replace item in place.
  - delete → guard `_knownIds.remove(id)` → remove from `_items`.
- State is kept in sync with server per event; debounced cache flush (`_flushCache`); `notifyListeners()` when changed.
- Because application is **immediate and in order**, no dedup false-positive beyond the 80-item replay window.
- **Risk**: `applyRealtimeEvent` races a concurrent full `refreshFromRealtime()` (from `_refreshAll`, polling, resume): the full-refetch snapshot (taken earlier) can overwrite the applied event (F-RT4).

### game_questions

- insert → **immediate** `handleQuestionInsert` → `fetchNewQuestion(showLoading: false)` (fresh question).
- delete → **immediate** `handleQuestionDelete` → clears the question if it matches and scrubs history by `questionId`.
- update → 150 ms debounce → `handleQuestionUpdate`: updates `question`/`status`; on `both_answered` clears the question + cache.

### game_answers

- insert → **150 ms debounce** → `handleAnswerInsert`.
- update → **150 ms debounce** → `handleAnswerUpdate` (re-fetches authoritative status).
- delete → **150 ms debounce** → `handleAnswerDelete` (clears per-user answer flags + history options).
- `handleAnswerInsert` also detects both-answered → `_repo.updateQuestionStatus('both_answered')` → which generates a `game_questions` UPDATE event back on the channel (F-RT1 trigger).

### drive_items / drive_item_reactions

- **Flow**: `_isRelevantDrive` → dedup → 150 ms debounce → **full** `DriveState.refreshFromRealtime()`: re-fetch entire `v_drive_dashboard`, sort by `created_at`, rebuild favorites, refresh `_singleItem` if open, `saveDriveItems` to cache, update `chk_drive_items`.
- Guarded by `_isSyncing` (`:107`) — concurrent refreshes are skipped, not queued.
- **Deletion**: DELETE events arrive on the same channel (all events) → debounced full refetch → deleted items disappear from cache. This closes the storage-doc gap (F-SC7: incremental sync alone cannot detect deletions — Realtime is the mechanism that does, when online).

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

1. **Debounce coalescing (trailing-edge)** — burst events collapse into one activation:
   - Game answers: only the last `(table, eventType, payload)` is applied. In the common two-player flow, a partner's `game_answers` INSERT and the resulting `game_questions` UPDATE (both-answered) can arrive within 150 ms — the INSERT is **silently dropped**, the question is cleared (correct), but the history entry and stats never update until the next full refresh (F-RT1). **This is the most significant realtime correctness bug.**
   - Mood: `changedUserId` captured from the last event only; intra-window mixed-user bursts refresh one side (F-RT2).
2. **Reaction filtering** — `drive_item_reactions` events for items *not currently in the local drive list* are filtered out (`:562`); reaction state for a not-yet-loaded item is unavailable until next refresh (F-RT9).
3. **Replay/dedup boundary** — events older than the 80-entry window on a replay are re-processed (duplicate) or lost only in the sense described above.

**Backstops that recover dropped events** (eventual sync):
- Polling fallback `_refreshAll()` every 15 s while Realtime is degraded.
- `resume()` → reconnect + `_refreshAll`.
- `refreshAfterSubscribe` full refresh after lifecycle resume / `refreshChannel`.
- Cold-start `loadWithChangeDetection` per feature (checkpoint-based).

Because every handler converges to *server current state* on refetch, dropped intermediate events are eventually reflected — hence **eventual synchronization is achieved** even though per-event delivery is not lossless.

### Eventual synchronization — YES

Convergence is guaranteed (given connectivity) by the combination of: 15 s polling fallback, resume → resubscribe + `_refreshAll`, subscribe-success refreshes, and checkpoint-gated cold-start refetches. The worst-case staleness bound is ~15 s when Realtime is down, ~0 s when healthy (subject to F-RT1's dropped-burst recovery lag).

### Correct account isolation — YES

Enforced server-side by RLS on the WebSocket (a JWT only receives rows its policies allow: self/own-partnership rows on every subscribed table) and re-verified client-side by `_isRelevant*`. The only leak vector is the cross-*partnership* cached-state issue (below), not account-level, because `clearAll()` on logout removes all caches.

### Correct partnership isolation — YES (at the Realtime layer)

`configure()` binds the channel keys and filters to the active partnership; `_isPartnershipRecord` gates bucket/missyou/questions/drive; RLS gates server-side; re-partnering replaces the channel via `configure`. **Caveat (cross-doc):** feature caches + checkpoints are global and not cleared on partnership change (storage doc F-SC8), so a stale cold-start can *suppress* a refetch and show previous-partner data — this is a caching-layer issue that Realtime alone masks but does not fix.

---

## Timestamp Checkpoint Races

The Realtime layer interacts with the shared checkpoint keys (`chk_moods`, `chk_game_answers`, `chk_bucket_items`, `chk_drive_items`, `chk_miss_you`). Relevant races:

### R-1: Checkpoint write-back vs. concurrent Realtime refresh (LOW)

Every refresh writes a checkpoint computed from *its own* SELECT snapshot (`fetchTimeline` → `_updateMoodsCheckpoint`, `refreshFromRealtime` → `_updateDriveCheckpointFromItems`, etc.). When a fast refresh completes **after** a slower one that observed newer data, the checkpoint can be written *backwards* (regress). Because `checkpoint == null → hasChanges → true` and `serverDate.isAfter(checkpoint)` triggers refetch, a regression only causes a **redundant refetch**, never data loss. Net: self-healing; wasted round-trips.

### R-2: Checkpoint covering undelivered events (LOW)

A full refresh whose checkpoint `max(timestamp)` is *ahead* of the events the channel has delivered suppresses cold-start refetches for those rows. Since Realtime delivers the events independently, the UI still receives them in-session; only a *restart before delivery* would rely on the (too-far-ahead) checkpoint — mitigated by the fact that Realtime re-delivers recent commits after resubscribe (post-resume full refresh).

### R-3: Mood "optimistic" EMPTY checkpoint (`mood_state.dart:58-68`)

`_hasMoodChanges` writes `kCheckpointEmpty` when changes exist, *before* the fetch. `hasChanges` then returns `true` on the next cycle until a real fetch writes a real timestamp — i.e. it **forces** retries after failed fetches (good) but also forces one redundant cycle after every successful one (harmless).

### R-4: `chk_game_answers` update-blindness (cross-doc F-SC5)

The checkpoint is `max(created_at)` over `game_answers`, but answer *updates* change `selected_option` without touching `created_at` (Postgres upsert). The checkpoint cannot see partner answer changes even when healthy — Realtime's `handleAnswerUpdate` is what covers the online case; polling fallback does not. This is the primary cold-start blind spot for games.

### R-5: `chk_drive_items` strict `>` boundary (cross-doc F-SC7)

`fetchDriveItemsIncremental` uses `gt('updated_at', checkpoint)`; rows whose `updated_at` equals the checkpoint (multi-row same-transaction commits, or microsecond collisions) are skipped. Deletions are invisible to incremental fetches entirely — only Realtime DELETE events (full refetch) or polling `_refreshAll` recover them.

---

## Event Ordering

- Supabase delivers events per channel in commit order. The client does not re-sort.
- **Order-insensitive consumers** (full-refetch handlers): mood, drive, partnership, missyou-delete — safe under reordering/replay.
- **Order-sensitive consumers**:
  - `bucket applyRealtimeEvent` — applied immediately in delivery order; correct while the channel is healthy. The bucket/refresh race (F-RT4) is the ordering hazard.
  - `game` granular handlers — the 150 ms debounce *reorders* by effectively keeping only the last event of a burst (F-RT1). The immediate question insert/delete paths preserve order.
- **Reconnect replay ordering**: Supabase replays recent commits after resubscribe; the dedup + post-resume `_refreshAll` normalize any out-of-order application.

---

## Findings

### F-RT1: Game debounce silently drops intermediate answer events (HIGH)

- **WHAT**: All `game_questions` updates and **all `game_answers` events** share one trailing-edge `_gameRefreshTimer` (150 ms). Each new event cancels the previous timer, so only the closure captured by the *last* event executes. Intermediate `game_answers` INSERT/UPDATE/DELETE events are never applied.
- **WHERE**: `realtime_sync_service.dart:478-493` (`_handleGamePayload`).
- **WHY**: Trailing-edge debounce with payload capture, plus the comment at `:466` acknowledging the drop risk only for question insert/delete — which are the paths that bypass it.
- **WHEN**: The common two-player turn: partner answers → their `game_answers` INSERT arrives → timer scheduled; the accepting device (or partner's success handler) then calls `updateQuestionStatus('both_answered')` → `game_questions` UPDATE arrives within 150 ms → **the answer INSERT is cancelled**. Reproducible whenever the two events land within 150 ms on the waiting device.
- **IMPACT**: The question clears correctly (via `handleQuestionUpdate` on `both_answered`), but `handleAnswerInsert` never runs → the game's **history entry partner option and match stats are stale** until the next full refresh (`_refreshAll`/poll/resume/pull-to-refresh). UI silently inconsistent with server for an unbounded window.
- **CONFIDENCE**: HIGH.

### F-RT2: Mood debounce captures only the last `changedUserId` (MEDIUM)

- **WHAT**: `_moodRefreshTimer` closure binds `changedUserId` from the last payload of a burst. If own and partner mood events land within 120 ms, the refresh executes only for one side.
- **WHERE**: `realtime_sync_service.dart:404-409` (`_handleMoodPayload`).
- **WHY**: Coalescing with per-call binding, not per-burst aggregation.
- **WHEN**: Ambient: two users updating moods rapidly. Own-event side is a no-op by design; the partner side can be skipped entirely.
- **IMPACT**: Partner mood card (`_partnerMood`) may display stale emoji until a later event or refresh. Timeline is a partial mitigation (`fetchTimeline` covers both users).
- **CONFIDENCE**: MEDIUM.

### F-RT3: `_missYouRefreshTimer` is dead code (LOW)

- **WHAT**: Declared at `realtime_sync_service.dart:41`, cancelled in `dispose()` (`:634`), but **never scheduled anywhere**.
- **WHERE**: `realtime_sync_service.dart:41,634`.
- **IMPACT**: None — missyou events are processed immediately. Dead field.
- **CONFIDENCE**: HIGH.

### F-RT4: Bucket realtime-apply vs. full-refresh replacement race (MEDIUM)

- **WHAT**: `BucketState.applyRealtimeEvent` mutates `_items` incrementally while `BucketState.refreshFromRealtime` (from `_refreshAll`, polling, resume) **replaces** `_items` with a snapshot. A full-refetch snapshot taken *before* an insert commits can complete *after* the event was applied and overwrite it.
- **WHERE**: `bucket_state.dart:80-91` (refresh) vs `130-162` (apply).
- **WHEN**: Any overlap of realtime events with a 15 s poll, resume refresh, or `refreshChannel`.
- **IMPACT**: Newly inserted item disappears from the list until the next event or refresh. `_knownIds` still contains its id (so a replay won't re-add it and the item is simply absent). Transient but persistent until a full refresh.
- **CONFIDENCE**: MEDIUM.

### F-RT5: `addMissYou()` is non-idempotent; dedup window overflow double-counts (LOW)

- **WHAT**: `HomepageState.addMissYou` unconditionally `_totalMissYou += 1` + persist. If a replay passes dedup (>80 intervening events, or key collision), the count is incremented twice for one server row. Also races an in-flight `fetchTotalMissYou` (snapshot overwrite).
- **WHERE**: `homepage_state.dart:64-68`; dedup window at `realtime_sync_service.dart:602`.
- **WHEN**: Replays after long disconnect periods on a busy channel, or burst >80 events between delivery and replay.
- **IMPACT**: Transient wrong count; self-corrects on the next authoritative `fetchTotalMissYou` (60 s `kMissYou` freshness gate or any refresh). Nobody blocks on it — LOW.
- **CONFIDENCE**: LOW for occurrence, HIGH for non-idempotency of the path.

### F-RT6: `game_answers` dedup key omits `game_id` (LOW)

- **WHAT**: `_markSeen` keys on `row['id'] ?? ... ?? row['user_id']`. `game_answers` has a composite PK and no `id` column (schema), so the key degrades to `game_answers:<event>:<user_id>:<commitTimestamp>`. Two answers by the same user in one transaction → identical key → second dropped.
- **WHERE**: `realtime_sync_service.dart:586-592`; schema `game_answers` (composite `game_id,user_id`).
- **WHEN**: Batch/transactional multi-answer submits for one user (not produced by the current single-row `submitAnswer` path).
- **IMPACT**: Dropped event → stale history until refresh. Overlaps with F-RT1 impact.
- **CONFIDENCE**: LOW (occurrence), HIGH (key construction).

### F-RT7: Reconnect gives up permanently until lifecycle/configure (LOW)

- **WHAT**: After 20 reconnect attempts, `_scheduleReconnect` stops (`:189-194`). With polling fallback active, no further subscribe is ever attempted until `configure()` or app `resume` — a sustained outage leaves the app in 15 s polling indefinitely in the background whereas the WebSocket could have recovered.
- **WHERE**: `realtime_sync_service.dart:189-194, 220-247`.
- **WHEN**: Network outage > ~15 minutes while the app stays foregrounded.
- **IMPACT**: Data freshness preserved (15 s polling) but realtime pushes are not resumed until user action. Acceptable degradation; deliberately chosen.
- **CONFIDENCE**: MEDIUM.

### F-RT8: Reaction events for unloaded drive items are filtered out (LOW)

- **WHAT**: `_isRelevantDrive` for `drive_item_reactions` requires `item_id` present in the *current in-memory* `_driveItems` (`:562`). A reaction on an item not in the local list is dropped — including reactions on items the local drive list is about to load.
- **WHERE**: `realtime_sync_service.dart:554-563`.
- **WHEN**: Partner reacts to an item the user hasn't loaded (paged-out history).
- **IMPACT**: Reaction does not appear in the detail view until a full refresh. Minor.
- **CONFIDENCE**: HIGH.

### F-RT9: Partnership filter is permissive when `_partnershipId == null` (INFO)

- **WHAT**: `_isPartnershipRecord` returns `true` when the local partnership id is null (`:533-534`).
- **WHERE**: `realtime_sync_service.dart:532-540`.
- **WHY safe**: `configure()` refuses to subscribe without a partnership (`:135-140`); RLS still enforces server-side. Documented as defense-in-depth posture, not a bug.
- **CONFIDENCE**: HIGH (that it is safe by construction).

### F-RT10: Checkpoint write-back can regress under concurrent refreshes (LOW)

- **WHAT**: Refresh A with an older snapshot can land *after* refresh B with a newer one and write a lower checkpoint max (R-1). Only causes a redundant refetch on next init.
- **WHERE**: shared checkpoints — `mood_state.dart:70-79`, `game_state.dart:90-106`, `drive_state.dart:131-137`, `base_repository.dart:79-108`.
- **IMPACT**: Extra round-trip; never data loss. Noted for completeness.
- **CONFIDENCE**: MEDIUM.

---

## Implementation Status

| Component | Status |
|---|---|
| Single channel, 8-table subscription (all events) | IMPLEMENTED |
| Client-side user/partner/partnership relevance filtering | IMPLEMENTED |
| 80-event dedup LRU | IMPLEMENTED |
| Per-table debounce (120/150 ms) + lifecycle debounce (300 ms) | IMPLEMENTED |
| Generation counter stale-channel guard | IMPLEMENTED |
| Exponential backoff with jitter, code-1002 penalty, max 20 attempts | IMPLEMENTED |
| Polling fallback at 15 s after 3 consecutive failures | IMPLEMENTED |
| Resume → resubscribe + full `_refreshAll` | IMPLEMENTED |
| Pause/detach/hidden → unsubscribe | IMPLEMENTED |
| JWT `setAuth` on token refresh (no reconnect) | IMPLEMENTED |
| Wipe suppression (`suppress`/`resume`/`refreshChannel`) | IMPLEMENTED |
| Bucket granular in-order application | IMPLEMENTED |
| Game question insert/delete bypassing debounce | IMPLEMENTED |
| Game answer debounce lossless in bursts | NOT IMPLEMENTED (F-RT1) |
| Mood debounce multi-user burst handling | NOT IMPLEMENTED (F-RT2) |
| Realtime auto-recovery while polling fallback active | NOT IMPLEMENTED (F-RT7) |

---

## Tests

No automated tests exercise the realtime pipeline. `realtime_sync_service.dart` and `realtime_sync_scope.dart` are not referenced by any file in `Flutter/test/`.

**Not covered**: subscription/channel lifecycle, generation guard, dedup LRU behavior, debounce coalescing, relevance filtering, backoff/polling transitions, resume/detach behavior, wipe suppression, and the F-RT1–F-RT10 scenarios.

---

## Notes

- **Single channel caps 8 tables**: all bindings share one WebSocket channel. A failure of one table's filter (e.g. malformed payload) is isolated per-callback, but a channel-level failure drops all eight simultaneously (designed).
- **Mutations are fire-and-forget**: `submitAnswer`, `addBucketItem`, `toggleDone`, `uploadDriveItemToR2`, `deleteItem`, `addReaction` do not await server confirmation; state reconciliation relies on Realtime echoes + periodic refetches. No optimistic rollback exists for bucket/drive mutations — only mood implements optimistic update with rollback (`mood_state.dart:233-282`).
- **Realtime echo self-loop is handled**: the app receives its **own** mutations back on the channel. Bucket uses `_knownIds`; game uses `isOwnInsert`; mood uses the `changedUserId == self` no-op; drive/missyou use full refetch/idempotent increment. No duplicates arise from the self-echo path.
- **`notifyListeners()` is frame-coalesced** (`base_state.dart:22-29`): bursts of state writes during realtime refreshes produce a single rebuild per frame — this is UI coalescing, not event coalescing.
- **Realtime is the fast path, not the source of truth**: every consumer eventually re-fetches from the server (refresh handlers, polling, checkpoint-gated init). The system is eventually consistent by construction; per-event losslessness is not guaranteed (F-RT1, F-RT2, F-RT4).
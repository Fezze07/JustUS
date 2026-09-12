# JustUS Flutter - State Management Architecture

## Overview

JustUS uses the `provider` package on top of plain `ChangeNotifier` classes. There is no custom state-management library, no `ValueNotifier`-based domains, and no Redux/BLoC. All feature state lives in one app-lifetime managed object per feature, created once at the widget root (`main.dart:96-112`) and handed to widgets exclusively through `Provider.of`/`Consumer`/`Selector`. State synchronization with the server is done by each feature state itself (cache-first + checkpoint-driven refresh), plus a global `RealtimeSyncService` that pushes changes into the states.

The four building blocks are:

1. `BaseState` (`Flutter/lib/shared/utils/state/base_state.dart`, 99 lines) — abstract `ChangeNotifier` with frame-coalesced `notifyListeners`, `setLoading`/`setMessage`, `runSafe`, `handleResult`, and `loadWithChangeDetection`.
2. Feature states — nine classes extending `BaseState` (some with `CheckpointMixin`).
3. `ResultWrapper<T>` (`Flutter/lib/core/network/result_wrapper.dart`, 25 lines) — sealed Success / GenericError / NetworkError.
4. `CheckpointMixin` (`Flutter/lib/core/local_storage/checkpoint_mixin.dart`, 53 lines) — writes max-timestamp checkpoints into `CacheService` (SharedPreferences).

State definition sites:

| State | File | Base | Persistence source |
|---|---|---|---|
| AuthState | `features/auth/auth_state.dart` | BaseState + WidgetsBindingObserver | StorageService (tokens, user, partner) |
| PartnerState | `features/partnership/partner_state.dart` | BaseState | none (reads stored partner via repos) |
| HomepageState | `features/home/homepage_state.dart` | BaseState | StorageService.get/saveTotalMissYou |
| MoodState | `features/mood/mood_state.dart` | BaseState + CheckpointMixin | StorageService (moods, emojis, timeline) |
| BucketState | `features/bucket_list/bucket_state.dart` | BaseState + CheckpointMixin | StorageService.get/saveBucketList |
| GameState | `features/games/game_state.dart` | BaseState + CheckpointMixin | StorageService (question, history, matches) |
| DriveState | `features/drive/drive_state.dart` | BaseState + CheckpointMixin | StorageService.get/saveDriveItems |
| ProfileState | `features/settings/profile_state.dart` | BaseState | StorageService (profiles) |
| LanguageProvider | `core/localization/language_provider.dart` | ChangeNotifier (not BaseState) | SharedPreferences (direct) |
| ThemeProvider | `core/theme/theme_provider.dart` | ChangeNotifier (not BaseState) | none (never persisted) |
| TabIndexNotifier | `shared/widgets/tab_screen.dart` | ChangeNotifier (not BaseState) | none (ephemeral) |

## BaseState

`BaseState` (base_state.dart:10) adds to `ChangeNotifier`:
- `isLoading` getter backed by `_isLoading` (base_state.dart:15).
- `message` getter backed by `_message` (base_state.dart:16); consumed by screens/`ErrorHandler` UI.
- `notifyListeners()` override (base_state.dart:22-29) — frame coalescing.
- `setLoading` / `setMessage` / `clearMessage` (base_state.dart:31-44) — mutators that also notify.
- `loadWithChangeDetection` (base_state.dart:46-59) — cache → change-check → optional fire-and-forget fetch.
- `handleResult<T>` (base_state.dart:62-76) — switch over `ResultWrapper`; Success runs optional `onSuccess`, GenericError/NetworkError route to `ErrorHandler` and notify.
- `runSafe` (base_state.dart:79-98) — loading-state + error envelope for async actions; returns `Future<bool>`.

### Frame coalescing analysis

Implementation (base_state.dart:22-29):

```dart
void notifyListeners() {
  if (_pendingNotify) return;                       // (a) dedupe while pending
  _pendingNotify = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pendingNotify = false;                         // (b) reset BEFORE delivery
    if (hasListeners) super.notifyListeners();      // (c) deliver once, end of frame
  });
}
```

Behavior:
- Multiple `notifyListeners()` calls in the same synchronous block collapse into one delivery at the end of the current frame (`(a)` drops all subsequent calls). This is the intended "no rebuild storm" behavior.
- Delivery is deferred to the post-frame phase (`(c)`), outside build/layout/paint — safe against "setState during build" style issues and safe here because provider's listener (`markNeedsBuild`) is triggered safely post-frame.
- `hasListeners` guard means a notification is silently dropped if no widgets are subscribed at delivery time.

Does it actually prevent redundant rebuilds?
- YES for true same-frame bursts: e.g. `setLoading(true)` + `setMessage(...)` + `notifyListeners()` called back-to-back with no `await` between them deliver exactly one notification.
- NO for the dominant real-world pattern: the typical `setLoading(true); notifyListeners(); await network(); setLoading(false); notifyListeners()`. The `await` interrupts the synchronous block, so the two notifications land in *different* frames (`isLoading=true` frame, then `false` frame) — there is nothing to coalesce across frames, so the widget still rebuilds twice (loading → loaded). Evidence: `homepage_state.dart:70-88` (`sendMissYou`), `game_state.dart:143-216` (`submitAnswer`).
- NO across multiple providers: coalescing is per-instance (`_pendingNotify` is a field of each `BaseState`). Ten providers firing `notifyListeners` in the same frame each individually schedule a post-frame callback and each still rebuild their own dependents. The "startup rebuild storm" the doc comment claims to prevent (base_state.dart:18-20) is *not* prevented across providers — only within a single state.

Edge cases / risks:
- `(b)` resets `_pendingNotify` before delivering. If a listener synchronously calls a method that calls `notifyListeners()` again during the delivery, a new callback is scheduled for a later frame — no recursion, but a chain of one-frame-per-batch notifications can span multiple frames.
- **Idle-frame dependency**: the callback only runs when a frame is actually drawn. If `notifyListeners()` is invoked while the app is idle (e.g. a background/realtime sync completing with no animation or input scheduled), `addPostFrameCallback` registers for the *next* frame, but nothing necessarily schedules one — the notification can be delayed until the next unrelated frame (input, animation, timer) occurs. In practice the always-running homepage pulse animation (`homepage_screen.dart:36-44`) and cursor/animation sources schedule frames continuously, but on a static screen with no animations the delivery timing is not guaranteed. Confidence: HIGH that delivery is deferred; MEDIUM that a real stall occurs (frame sources above usually mask it).
- Because `notifyListeners` returns before listeners are called, any code that reads observable state immediately after notification still sees the mutated values (mutations happen before notify) — ordering is fine.

## loadWithChangeDetection

Real implementation (base_state.dart:46-59):

```dart
await loadFromCache();                 // (1) seed state from disk
final changed = await hasChanges();    // (2) compare checkpoint vs server
if (changed) {
  unawaited(fetchFromNetwork()         // (3) fire-and-forget full refresh
    .catchError((e, st) => ErrorHandler.handle(e, stackTrace: st)));
}
```

The user-supplied pipeline "cache → checkpoint → network → comparison → state update" maps to:
1. **cache**: `loadFromCache` populates in-memory state from `StorageService` (SharedPreferences) and is expected to call `notifyListeners()` itself (e.g. `bucket_state.dart:41-45`, `mood_state.dart:81-101`).
2. **checkpoint**: the `<state>Changes()` callback reads the checkpoint and compares against server max-timestamp — via `CheckpointMixin`-persisted values and repository helpers (`base_repository.dart:79-108` `hasChanges`, `CacheService.needsRefresh` `cache_service.dart:40-50`). Some states perform an extra network RPC inside `hasChanges` (e.g. `_hasBucketChanges` calls `getActivePartnership` + `hasNewBucketItems`, bucket_state.dart:47-57).
3. **network**: `fetchFromNetwork` is invoked **unawaited** only if `hasChanges` returned `true`. Each state's `fetchFromNetwork` runs its own repo fetches, writes StorageService, writes the checkpoint (optimistically cleared in some states: `mood_state.dart:63-67`, `bucket_state.dart:52-55`, `drive_state.dart:48-55`).
4. **comparison**: the ONLY comparison is the boolean `hasChanges` decision. The network result is unconditionally applied — there is no merge, no diff, no conflict resolution. The "comparison" is purely a gate that decides *whether to fetch*, not *how to apply*.
5. **state update**: occurs inside each state's success handler (`handleResult`/`handleAsync` onSuccess) which replaces the whole collection/object, then persists.

Callers: `HomepageState.init` (homepage_state.dart:26-34), `MoodState.initHome`/`initMoodScreen` (mood_state.dart:30-56), `BucketState.init` (bucket_state.dart:27-39), `GameState.init` (game_state.dart:31-38), `DriveState.initialLoad` (drive_state.dart:34-46).

### Failure cases

1. **Fire-and-forget: no completion signal** — `fetchFromNetwork()` is unawaited (base_state.dart:55). Callers of `init()` cannot know when the refresh finished; subsequent operations cannot coordinate with it; `isLoading` is never set by `loadWithChangeDetection`, so the UI shows whatever was in cache and there is no loading indicator for the refresh. Confidence: HIGH (structural).
2. **`hasChanges` failure skips refresh silently** — if `hasChanges` throws (e.g. offline during `_hasBucketChanges` network calls), `changed` never resolves and the network fetch is skipped. `BucketState.init` only has `try/finally` (bucket_state.dart:31-37) so the exception propagates to the caller (`unawaited(loadData())` in `tab_screen.dart:59`) → unhandled async error → routed to `ErrorHandler` via the zone guard (main.dart:37-81). No data refresh happens; the app keeps showing cached data with no error surface for the *user* (only logs/dialog per `error_handler.dart:145-151`). Confidence: HIGH.
3. **Re-`init` duplication / no dedupe** — `loadWithChangeDetection` has no in-flight guard. `HomepageState.init` and `MoodState.initHome` call it with no internal guard (unlike `BucketState._isInitLoading` bucket_state.dart:28, `DriveState._initialLoading` drive_state.dart:35, `GameState._isFetchingQuestion`). Tab re-activation (TabScreenMixin loadData) and pull-to-refresh can start a second fetch while the first is still running → two concurrent network fetches, last-write-wins, no ordering guarantee. Confidence: HIGH.
4. **Stale-response overwrite (no generation token)** — because fetch is unawaited and un-guarded, a slow first fetch can land *after* a faster second fetch and overwrite the newer data with older data. There is no request-id/epoch check anywhere in the states. Confidence: MEDIUM (possible, not observed in tests).
5. **Checkpoint semantics can force repeated fetches** — optimistic checkpoint resets (`CacheService.kCheckpointEmpty`, `cache_service.dart:9`) are written inside `hasChanges` only when `changed == true` (mood_state.dart:63-67). If the subsequent network fetch fails, the checkpoint stays `EMPTY`, so every subsequent `init()` computes `hasChanges == true` again and refires the network fetch — a retry-every-init loop, and a duplicate fetch per init even while the network is down. Confidence: HIGH (both states do this).
6. **Null/empty server data misread as deletion** — `BaseRepository.hasChanges` returns `checkpoint != kCheckpointEmpty` when the server returns no max row (base_repository.dart:95-98): an `EMPTY` checkpoint plus an empty server table is treated as "no changes", but a *real* timestamp checkpoint plus empty server table is treated as "everything was deleted" → forces a full refetch. Correct in most cases but conflates "server hole / RLS-invisible data" with "deleted". Confidence: MEDIUM.

## ResultWrapper

`ResultWrapper<T>` (result_wrapper.dart:6-25) is a sealed class with `Success<T>.value`, `GenericError<T>.code/message/details`, and `NetworkError<T>.message`. It is consumed through extensions on `Result` types defined in `all_imports.dart` (e.g. `handleAsync`, `handle`, `valueOrNull`, `isSuccess`, `isError`) that are used pervasively in states. BaseState's `handleResult` (base_state.dart:62-76) routes `GenericError`/`NetworkError` into `ErrorHandler.handle` and calls `notifyListeners()`, but does NOT clear data or revert state — errors leave the last good state intact. Note: two states use the raw `handle` while others use `handleAsync`; `GameState.fetchStats` uses `result.handle(...)` (game_state.dart:221-226), `fetchHistory` uses `handleAsync` (game_state.dart:233-239) — inconsistent style, and `ProfileState.loadProfile` reads `valueOrNull` directly (profile_state.dart:79).

## Provider wiring

- Constructed once at root: `MultiProvider` in `main.dart:96-112` with `ChangeNotifierProvider(create: ...)` for `LanguageProvider`, `AuthState`, `PartnerState`, `ThemeProvider`, `HomepageState`, `MoodState`, `BucketState`, `GameState`, `DriveState`, `ProfileState`. All are created lazily on first `read`/`watch`? No — `create` factories run on first access by a dependent consumer; in practice all are touched during startup (splash) or first tab build.
- `RealtimeSyncScope` (core/realtime/realtime_sync_scope.dart:8-76) reads the states via `context.read` (lines 25-31), builds a single `RealtimeSyncService`, starts it (line 32), and re-provides it via `Provider<RealtimeSyncService>.value` (line 58). It uses `Consumer2<AuthState, PartnerState>` (line 38) to re-`configure` the service whenever auth/partner identities change. **ProfileState is not wired into RealtimeSyncService.**
- Consumption pattern: `context.read<State>()` for fire-and-forget mutations (58 usages), `Consumer`/`Consumer2` for rebuild-on-any-change when Selector types get unwieldy (login_screen.dart:83, register_screen.dart:67, partner_screen.dart:69), and `Selector` (7 sites: profile, bucket, homepage×3, mood, game×3, drive×4, localization) to rebuild only slices. Because notifications are deferred (frame-coalesced), every provider-driven rebuild is delayed by one frame relative to plain `ChangeNotifier`.
- Because `AuthState` and `PartnerState` are above `RealtimeSyncScope`, the service keeps direct references to live instances — states are never recreated when screens navigate.

## Session state

- Authoritative in-memory session: `AuthState` (`auth_state.dart`) — `_accessToken/_refreshToken/_username/_userId/_partnerId/_partnershipId/_partnerDisplayName` (lines 37-43), with `isLoggedIn => _accessToken != null && nonempty` (line 61), `hasPartner => _partnerId != null` (line 62).
- Disk authority: `StorageService` (init in main.dart:49) mirrors every field: `setLoginData` writes 4 keys (auth_state.dart:423-426), `setPartner` writes partner keys (auth_state.dart:440-442).
- Server authority for tokens: Supabase Auth (`Supabase.instance.client.auth`). On `tokenRefreshed`, AuthState syncs the new tokens to StorageService and its fields (auth_state.dart:153-165). Legacy mismatch: `_accessToken` kept in SharedPreferences is only used by `isLoggedIn`; actual API calls use `ApiService` headers (session-sync binding secret, documented in architecture scope).
- Init: `AuthState.init` (auth_state.dart:80-179) sets `ApiService.onSessionExpired → logout` (line 81-86), is idempotent (cancels subscriptions, line 89-92), loads local data in parallel (lines 95-111), reconciles with `currentSession` (line 114-150), registers FCM token, subscribes to `onAuthStateChange` and device-token refresh, and registers as a `WidgetsBindingObserver` for locale re-sync on lifecycle events (lines 176-197). The "authoritative-state + local cache" reconciliation: if Supabase has a session but local username is empty, it refetches the profile (lines 118-130); if Supabase has NO session but local tokens exist, it forces `logout()` (line 116).
- Logout: `logout()` (auth_state.dart:534-549) signs out Supabase, clears checkpoints (`CacheService.clearAll`), clears StorageService, drops all auth/partner fields, and notifies. **It does NOT clear the six feature states** (Homepage/Mood/Bucket/Game/Drive/Profile) — stale in-memory data survives into the next session (see F-SM7). `LogoutUtils.performLogout` (logout_utils.dart:39-48) additionally pops to the LoginScreen, but never resets feature states.
- Session expiry path: any 401 during API calls triggers `ApiService.onSessionExpired = logout` (auth_state.dart:81-86; api_service 401 handling documented in architecture scope), which runs `AuthState.logout`, while `requiresReauth` error codes (`AUTH-FAIL-001/002/003/006`, error_codes.dart:118-123) show a reauth dialog (error_handler.dart:145-146). Two competing logout triggers exist (global callback + reauth dialog) — both funnel into the same `logout()`.

## Partnership state

- Two overlapping objects: `AuthState` holds partner *identity* (`_partnerId`, `_partnershipId`, `_partnerDisplayName`, auth_state.dart:39-43) while `PartnerState` holds the full `_partnershipInfo` (partner + pendingRequests + anniversary, partner_state.dart:17-28). `RealtimeSyncScope` treats them as complementary sources and must merge them: `resolvedPartnershipId = authState.partnershipId ?? partnerState.partnershipInfo?.partnershipId` (realtime_sync_scope.dart:46-47); `partnerId = authState.partnerId ?? partnerState.partnershipInfo?.partner?.id` (lines 51-52).
- Refresh paths that write both: `RealtimeSyncService._handlePartnershipPayload` (realtime_sync_service.dart:412-427) calls `BaseRepository.clearPartnershipCache()` then `Future.wait([partnerState.refreshFromRealtime(), authState.refreshPartnershipFromRealtime()])`. `authState.refreshPartnershipFromRealtime` (auth_state.dart:447-477) re-derives fields from `getPartnership()` and clears partner if status isn't `accepted`. `PartnerState.refreshFromRealtime` (partner_state.dart:66-72) re-applies the whole `PartnershipResponse` and re-saves partner/partnershipId to StorageService (partner_state.dart:74-85).
- Risk: two independent transitions can run in parallel against the same conceptual object (e.g. `acceptPartner` in PartnerState vs `acceptInvitation` in AuthState) — no shared lock, storage written by both. Convergence depends on whichever notify lands last. Confidence: MEDIUM that a transient mismatch occurs; the app recovers on next realtime/frame because both refresh paths converge to the same backend `getPartnership()`.

## Feature states

### HomepageState (no CheckpointMixin)
- Fields: `_totalMissYou`, `_message`, `_isLoading` (homepage_state.dart:11-13). `_isLoading` is declared but never used by any method — `init`/`fetchTotalMissYou`/`addMissYou` never set it (lines 26-58, 64-68); only `sendMissYou` sets it (line 71). UI never reads `isLoading` on this state. This is dead boilerplate that does not implement "loading state" (see F-SM11-adjacent; here it's simply unused).
- `addMissYou` is an optimistic counter bump + unawaited save (homepage_state.dart:64-68). Realtime `insert` events call `addMissYou()` directly (realtime_sync_service.dart:435-436), i.e. the same code path used for the user's own action — an insert trigger on the user's own row double-counts if the optimistic bump already happened. (Linked to architecture F8.)
- `refreshFromRealtime` just re-fetches the total (homepage_state.dart:60-62).

### MoodState (CheckpointMixin)
- Cache mode `kMoods` checkpoint only records timestamps; two init flavors: `initHome` (my+partner mood, mood_state.dart:30-42) and `initMoodScreen` (emojis+timeline, mood_state.dart:44-56).
- `updateMood` (mood_state.dart:233-282): optimistic mutate (mood, recentEmojis, timeline + StorageService writes + notify, lines 238-258), then network; on success reconcile from server (`_userMood = value.emoji`, line 263) and checkpoint; on error **rolls back** mood/timeline/timelineOffset (lines 272-279) but **does not restore `_recentEmojis`** (`_recentEmojis.add(new)` still contains the failed emoji) — inconsistent rollback (F-SM12).
- `refreshFromRealtime({changedUserId})` (mood_state.dart:207-231) skips work for own changed id (optimistic already applied), fetches partner mood only for partner activity, everything only when id unknown — a nice targeted-refresh dedupe.

### BucketState (CheckpointMixin)
- Mutations are fire-and-forget: `addItem`/`toggleDone`/`deleteItem` call the repo and only route **errors** to `handleResult` (bucket_state.dart:95-126); the comment says "Realtime is source of truth" (line 93). No optimistic local mutation on call — the UI updates only when the realtime `applyRealtimeEvent` lands (bucket_state.dart:130-162), so every mutation depends on the realtime channel (fallback: polling) being healthy.
- `_knownIds` (Set<int>) mirrors the id space of `_items` for O(1) dedupe of inserts/updates/deletes (bucket_state.dart:12, 43, 140-153). Rebuilt fully on fetch (lines 72-74). Duplicated state, guarded consistently.
- Cache debounce: `_scheduleCacheSave` 2s Timer → `_flushCache` (bucket_state.dart:166-176); `dispose()` flushes synchronously-async via `unawaited` (lines 18-23) — the last 2s of changes can be lost if the app is killed abruptly after dispose completes before the unawaited write finishes. Confidence: MEDIUM.

### GameState (CheckpointMixin)
- Fields in lines 9-15; **declares its own `_message` and `_isLoading`** (lines 12-13) and `@override`s the BaseState getters (lines 20-23) — shadowing `BaseState._message`/`_isLoading` (base_state.dart:11-12). Two independent `message`/`isLoading` storage slots in the same object; `setLoading`/`setMessage` (base_state.dart:31-39) mutate the *other* slots that GameState getters don't read. Any future `setMessage` call on GameState would be invisible to the UI. Currently GameState always assigns its own private fields directly (lines 127, 155, 167, 201, 206...), so behavior is consistent today but the abstraction is broken (F-SM11).
- `init` (game_state.dart:31-38) fetches stats+history in background (`_fetchAllInBackground`, lines 81-88); question handling is event-driven: `fetchNewQuestion` guards with `_isFetchingQuestion` (lines 109-110).
- Realtime handlers perform surgical state surgery on `_currentQuestion` and `_history` (handleAnswerInsert 339-419, handleQuestionUpdate 313-337, handleAnswerDelete 252-293) plus storage sync — a large hand-rolled diff/reconcile layer on top of the checkpoint system.

### DriveState (CheckpointMixin)
- Incremental sync: `syncDriveItems` (drive_state.dart:70-104) uses `fetchDriveItemsIncremental` (server-side `updated_at > last_sync`), merges by id replace (lines 79-83), updates checkpoint from max `updatedAt` (lines 87-91); guarded by `_isSyncing` in both `syncDriveItems` (line 71) and `refreshFromRealtime` (line 107).
- `_singleItem` (drive_state.dart:16) is a *copy* of an item from `_driveItems` used as the detail-view model; it is manually re-synced in `refreshFromRealtime` (lines 117-121), `addReaction` (lines 239-243), `toggleFavorite` (lines 263, 273). Duplicated reference state with manual mirroring — divergence if one of the mirror paths is skipped (F-SM10).
- Optimistic mutation + rollback: `deleteItem` keeps a backup list and restores on error (lines 201-220); `toggleFavorite` restores the item and re-saves on failure (lines 266-276); `addFileItemR2`/`addReaction` apply only server-side onSuccess. Inconsistent strategies between write paths.

### ProfileState (no CheckpointMixin)
- Custom pipeline, NOT `loadWithChangeDetection` (profile_state.dart:35-82): guard `if (isLoading) return` (line 37) + 1-minute throttle `_lastFetch` (lines 27, 41-43) + cache-first (lines 47-55) + parallel `Future.wait` of 3 fetches (lines 59-63), with per-result success handling (lines 65-80). Setting `_anniversaryDate` from `partnershipResult.valueOrNull` (line 79) — but if the partnership fetch fails, no anniversary and no error (valueOrNull is null-safe).
- `updateBio`, `uploadProfilePhoto`, `updateAnniversaryDate`, `wipeAppData` (lines 84-149): all `runSafe`-wrapped, optimistic in-place `copyWith` on the user profile + StorageService rewrites. `isUploading` handled with explicit notify (lines 103-126) but `runSafe(showLoading: false)` — so uploading does not trigger the BaseState loading path.
- Not realtime-refreshed (F-SM6): no RealtimeSyncService wiring; the profile only refreshes when the homepage `_loadData` or explicit `loadProfile(force: true)` runs. Note `profile_screen.dart` does NOT use TabScreenMixin either.

### Standalone providers (not BaseState)
- `LanguageProvider` (language_provider.dart:6-44): normal `ChangeNotifier`; loads saved locale before `runApp` (main.dart:72-73), persists to SharedPreferences on change (line 41), dedupes no-op locale sets (lines 32-34).
- `ThemeProvider` (theme_provider.dart:3-18): normal `ChangeNotifier`; `ThemeMode.dark` default, never persisted (widget root `Selector2` rebuilds MaterialApp themeMode, main.dart:114-128). Light theme is effectively unsupported (design-system scope F-DS8).
- `TabIndexNotifier` (tab_screen.dart:6-15): `index` setter notifies only on actual change; shared by MainShell (`main_shell.dart:15`) and all `TabScreen` widgets.

## Tab state

- Authoritative tab index: `MainShellState._currentIndex` (main_shell.dart:14), mutated via `switchToTab`/`HomeBottomNav.onIndexChanged` (lines 18-22, 57-61), backed by an `IndexedStack` (line 45-49) that keeps all built children alive.
- `_builtPages` set (main_shell.dart:16) records which tabs have been instantiated; unbuilt tabs render `SizedBox.shrink()` (line 48) — lazy build, but pages are never disposed once built.
- `TabIndexNotifier` is a *copy* of the same index for `TabScreenMixin` widgets (tab_screen.dart:49-61): on tab switch with matching index, it resets `_dataLoadedOnce` and re-calls `loadData()` on re-entry (lines 50-53). Five screens use it: Game, Mood, Bucket, Drive, Favorites. **Homepage and Profile do not extend `TabScreen`** and therefore never reload on tab switch-back (F-SM8) — deliberate for homepage (always resident) but makes Profile rely on realtime-less staleness.
- Duplicated index state (`_currentIndex` + `TabIndexNotifier.index`) is always written together in the same code paths (main_shell.dart:18-22, 57-61) — no drift observed, but it is two stores updated in lockstep.

## How state is refreshed (summary)

| Trigger | Mechanism | Affected states |
|---|---|---|
| App start / splash | `AuthState.init` (splash_screen.dart:22-27); homepage then fires 4 parallel inits (homepage_screen.dart:79-84) | auth, partner (fetchPartnership splash:30-31), homepage, mood, profile, bucket |
| Tab activation | `TabScreenMixin._tryLoadData` → `loadData()` (tab_screen.dart:56-61) | game, mood, bucket, drive, favorites |
| Pull-to-refresh | `loadData(force: true)` clears checkpoints first (game_screen.dart, mood_screen.dart:24-26, homepage_screen.dart:66-72, profile loadProfile(force)) | all |
| Realtime insert/update/delete | `RealtimeSyncService` handlers debounced 120-150ms → state methods (realtime_sync_service.dart:396-507) | mood, partnership (partner+auth), homepage (missyou), bucket, game, drive |
| Polling fallback (15s) after 3 failures | `_activatePollingFallback` → `_refreshAll` (realtime_sync_service.dart:185-187, 220-238, 610-622) | all except profile |
| Resume from background | lifecycle observer → `_refreshAll` after reconnect (realtime_sync_service.dart:155-164, 340-342) | all except profile |

## How state is persisted

- All feature data → `StorageService` (SharedPreferences-backed; documented in architecture scope) at every mutation success: moods (mood_state.dart:142,156,169,183,255), bucket list (bucket_state.dart:174), game question/history/matches (game_state.dart:122,173,202,224,236), drive items (drive_state.dart:85,122,187,204,263), homepage total (homepage_state.dart:50,66), profiles (profile_state.dart:68,77,91,114).
- Sync cursors → `CacheService` checkpoints in SharedPreferences: `chk_game_answers`, `chk_moods`, `chk_bucket_items`, `chk_drive_items`, `chk_miss_you` (cache_service.dart:4-9).
- Corrupted/partial caches are never validated on load: `StorageService.getBucketList()` returns whatever was stored; decode errors are not caught per-field (loads assume well-formed JSON). Confidence: HIGH (evidenced by absence of any validation in the cache loaders above).

## Errors and their effect on state

- `runSafe` catch (base_state.dart:87-90): logs + `ErrorHandler.handle`; returns `false`; **no rollback by default** — state keeps last good values. Rollbacks exist only where written explicitly (drive delete/favorite, mood update) or where the mutation is skipped until server confirms (bucket).
- `handleResult` on GenericError/NetworkError (base_state.dart:69-74) also notifies — the state rebuilds with unchanged data (a spurious rebuild but no data loss).
- Reauth-critical errors open the reauth dialog (error_handler.dart:145-146); API 401s call global `logout()` (auth_state.dart:81-86). Both leave feature data in memory untouched.
- "No questions" is silently swallowed in GameState (game_state.dart:128-132) — an intentional error-as-state ('no question' clears `_currentQuestion`).
- A failure of any single repo inside `Future.wait` in `ProfileState.loadProfile` (profile_state.dart:59-63) aborts the whole parallel batch unless wrapped — two of the three calls `handleResult` internally but `getPartnership` result is consumed via `valueOrNull` (line 79). If `getPartnership` throws (not returns an error wrapper), `Future.wait` rejects → `runSafe` catches → profile never updated. Confidence: MEDIUM (depends on repo wrapping).

## Concurrent operation handling

- Guards: `BucketState._isInitLoading` (+try/finally, bucket_state.dart:28-38), `DriveState._initialLoading`/`_isSyncing` (drive_state.dart:35, 71, 107), `DriveState.loadSingleItem` last-write-wins (line 143-147), `GameState._isFetchingQuestion` (line 109-110), `ProfileState.isLoading` early-return + `_lastFetch` throttle (profile_state.dart:37-43), `MoodState._isSyncingLocale` in AuthState locale sync (auth_state.dart:201), `_currentUserId ??=` in GameState (line 41) to avoid duplicate reads.
- Debounced: PartnerState search 300ms (partner_state.dart:37-39); RealtimeSyncService per-table timers 120-150ms (realtime_sync_service.dart:404-411, 418-425, 478-493, 502-506); Bucket cache flush 2s (bucket_state.dart:168); locale sync 500ms on resume (auth_state.dart:185-186); `BaseRepository.fetchMaxTimestamp` dedupes concurrent duplicate timestamp queries via a static pending-futures map (base_repository.dart:16-57) — the *only* shared concurrent-operation dedupe in the codebase.
- Absent: no request cancellation, no timeout-abort, no versioning/generation tokens for in-flight fetches, no global serialization of init vs realtime (a realtime apply can race a full fetch), no dedupe of `init()` on Homepage/Mood.

## Whether state survives navigation

- YES everywhere: all states live at the app root (`main.dart:96-112`) above `Navigator`; screens are popped/pushed but states never dispose except `AuthState` (which subscribes/unsubscribes from Supabase and never loses data). Navigation never creates or destroys feature state.
- IndexedStack keeps tab widget states alive across tab switches (main_shell.dart:45-49), so local widget state (scroll offsets, TextEditingControllers, `_builtPages`) survives too.
- Exception in navigation semantics: `ThemeProvider` and `LanguageProvider` are root-level too, so theme/locale survive, but ThemeProvider's value is never persisted (lost on process restart).

## Whether state survives app lifecycle

- Paused/detached: `RealtimeSyncService` unsubscribes (realtime_sync_service.dart:165-171) — in-memory state preserved, channel dropped, events missed while backgrounded are re-fetched on resume via `refreshAfterSubscribe: true` (lines 155-164, 340-342).
- Process death / restart: all state starts empty and is rebuilt from StorageService on next `init()`; checkpoint system ensures network refresh only happens when server `max(timestamp)` > checkpoint, so a cold start is cheap when nothing changed.
- Missed-events gap: while backgrounded, `_suppressProcessing` and unsubscribed channel mean missed events are NOT replayed by Supabase realtime — they are recovered only because `_refreshAll()` runs on resume/subscribe and `hasCheckpoint` comparisons catch up by timestamp. Confidence: HIGH that refresh-all on resume covers it; LOW that every corner (e.g. wipe-data suppress flow, realtime_sync_service.dart:64-76) restores resume().

## Findings

- **F-SM1** — Frame-coalesced `notifyListeners` depends on an actually drawn frame. `WHAT`: delivery scheduled via `addPostFrameCallback` (base_state.dart:25). `WHERE`: base_state.dart:22-29. `WHY`: deferral to end of frame deliberately trades immediacy for coalescing. `WHEN`: any task that mutates state outside a frame while the UI is idle. `IMPACT`: notification can be delayed until the next unrelated frame, or dropped if no frame occurs (mitigated by per-state `hasListeners`, and masked by always-running animations such as homepage pulse `homepage_screen.dart:36-44`). `CONFIDENCE`: HIGH (deferral), MEDIUM (observable stall).
- **F-SM2** — "Prevents rebuild storms" claim is only intra-state, and does not reduce redundant rebuilds across the await boundary. `WHAT`: per-instance `_pendingNotify` collapses same-frame sync bursts only. `WHERE`: base_state.dart:13,22-29. `WHY`: `await` splits the loading sequence into two frames (setLoading(true) then setLoading(false)), and other states each coalesce independently. `WHEN`: any loading mutation on any screen. `IMPACT`: rebuild count per state is unchanged for the common path; cross-provider storms still rebuild all dependents per provider. `CONFIDENCE`: HIGH.
- **F-SM3** — `loadWithChangeDetection` is fire-and-forget. `WHAT`: `unawaited(fetchFromNetwork())`, no completion/completion-error surfaced to caller, no `isLoading`. `WHERE`: base_state.dart:55. `WHY`: caching pipeline designed so cache is the UI, network is a silent revalidation. `WHEN`: every `init()`; `HomepageScreen._loadData` `Future.wait` completes *before* the network refresh finishes (homepage_screen.dart:79-84). `IMPACT`: callers (tab loads, refresh) can't sequence on the refresh; no UI progress for the revalidation. `CONFIDENCE`: HIGH.
- **F-SM4** — `hasChanges` exception silently skips the refresh. `WHAT`: no try/catch around `hasChanges()` or `fetchFromNetwork()` in `loadWithChangeDetection`. `WHERE`: base_state.dart:52-58. `WHY`: `hasChanges` performs real network work (e.g. `getActivePartnership` + `hasNewBucketItems`, bucket_state.dart:47-57). `WHEN`: offline/DB errors during init. `IMPACT`: state stays cache-only; error surfaces via unhandled async zone (`main.dart:37-81`) instead of a user message; `BucketState.init` finally-block clears the guard (bucket_state.dart:37-38) so re-init retries. `CONFIDENCE`: HIGH.
- **F-SM5** — Partner identity is duplicated across `AuthState` and `PartnerState` with separate refresh paths. `WHAT`: `_partnerId/_partnershipId` in AuthState vs `_partnershipInfo` in PartnerState; realtime updates both from the same source (realtime_sync_service.dart:418-425), and `RealtimeSyncScope` must merge them (realtime_sync_scope.dart:46-53). `WHERE`: auth_state.dart:39-43, partner_state.dart:17-28, realtime_sync_scope.dart:46-53. `WHY`: Auth owned the identity for routing; Partner owned the full response; never unified. `WHEN`: simultaneous partnership transitions (accept in AuthState auth_state.dart:382-403 vs accept in PartnerState partner_state.dart:100-116). `IMPACT`: transient divergence, storage written twice; converges next frame. `CONFIDENCE`: MEDIUM.
- **F-SM6** — `ProfileState` is not realtime-refreshed and never reloads on tab switch-back. `WHAT`: ProfileScreen uses neither TabScreenMixin nor RealtimeSyncService wiring (realtime_sync_scope.dart:24-31 omits profile). `WHERE`: profile_screen.dart:16 (plain StatefulWidget), realtime_sync_scope.dart:24-31. `WHY`: loadProfile uses cache+throttle instead (profile_state.dart:35-82). `WHEN`: partner changes profile, user stays on app. `IMPACT`: profile shows stale data until homepage reload or explicit force. `CONFIDENCE`: HIGH.
- **F-SM7** — Feature states are never cleared on logout/login-switch. `WHAT`: `AuthState.logout` clears auth+storage+checkpoints but not the six feature states (logout_utils.dart:39-48 doesn't either). `WHERE`: auth_state.dart:534-549. `WHY`: logout was scoped to session data. `WHEN`: logout, or a second user logging in on the same app. `IMPACT`: truncated/stale mood/bucket/game/drive/homepage data visible to the next session until each init() overwrites it (init is checkpoint-gated, so if checkpoints were just written for the previous user... they were cleared by `CacheService.clearAll`, so refresh happens — but the stale in-memory values show during that window). `CONFIDENCE`: HIGH.
- **F-SM8** — Homepage and Profile skip `TabScreenMixin`, so tab re-activation never re-runs their loads. `WHAT`: homepage_screen.dart:25 (plain StatefulWidget, one-shot postFrame load homepage_screen.dart:50-56), profile_screen.dart:16. `WHERE`: main_shell.dart:26-33. `WHY`: homepage assumed always-resident; profile staleness is F-SM6. `WHEN`: switch A-way and back. `IMPACT`: no refresh on return (only pull-to-refresh or external triggers). `CONFIDENCE`: HIGH (matches navigation F-N7).
- **F-SM9** — Homepage `_loadData` launches four concurrent `init()`s with no shared loading state. `WHAT`: `Future.wait([homepageState.init(), moodState.initHome(), profileState.loadProfile(), bucketState.init()])`. `WHERE`: homepage_screen.dart:79-84. `WHY`: init()s are fire-and-forget by design (F-SM3). `WHEN`: every homepage load/refresh. `IMPACT`: four independent fetches per user-visible refresh, no cancel/dedupe across them, no aggregate loading indicator. `CONFIDENCE`: HIGH.
- **F-SM10** — `DriveState._singleItem` is a manually mirrored copy of an element of `_driveItems`. `WHAT`: separate fields updated in refreshFromRealtime/addReaction/toggleFavorite. `WHERE`: drive_state.dart:16,117-121,239-243,263,273. `WHY`: detail screen needs a stable snapshot; mirroring was copied ad hoc. `WHEN`: any operation path that skips one of the mirror statements. `IMPACT`: detail view and grid can disagree on reactions/favorites. `CONFIDENCE`: LOW (mirror statements are all present in the same code paths today).
- **F-SM11** — GameState shadows BaseState's `_message`/`_isLoading`. `WHAT`: own fields (game_state.dart:12-13) + `@override` getters (game_state.dart:20-23) while BaseState keeps separate storage (base_state.dart:11-12) mutated by `setLoading`/`setMessage` (base_state.dart:31-39). `WHERE`: game_state.dart:12-23. `WHY`: GameState predates/parallels BaseState helpers. `WHEN`: any future `setMessage`/`handleResult(notifyOnSuccess)` usage on GameState. `IMPACT`: silent dead message/loading slots — the base helpers become no-ops for this state. `CONFIDENCE`: HIGH.
- **F-SM12** — Incomplete optimistic rollback in `MoodState.updateMood`. `WHAT`: error path restores mood+timeline but not `_recentEmojis` (still has the new emoji prepended). `WHERE`: mood_state.dart:271-281 vs 243. `WHY`: rollback list forgot the emoji list. `WHEN`: `updateMood` network failure after optimistic write. `IMPACT`: recent-emoji chip shows an emoji the server never accepted; is re-saved to StorageService (mood_state.dart:277). `CONFIDENCE`: HIGH (code reads directly).
- **F-SM13** — `HomepageState._isLoading` is declared but never used. `WHAT`: field + getter (homepage_state.dart:13,19) never set by any path except `sendMissYou` (line 71). `WHERE`: homepage_state.dart:13,19,26-88. `WHY`: legacy field retained. `WHEN`: UI wants loading state on the homepage. `IMPACT`: no loading UX for miss-you total; equivalent to F-SM11 for this state. `CONFIDENCE`: HIGH.
- **F-SM14** — Checkpoint writes race their removals. `WHAT`: `CacheService.clearAll` (cache_service.dart:52) runs during logout/wipe while in-flight fetch success handlers re-write checkpoints afterwards (e.g. mood_state.dart:266, bucket_state.dart:54). `WHERE`: auth_state.dart:536, profile_state.dart:143-144 + per-state onSuccess writes. `WHY`: fire-and-forget fetches can still be running when logout/wipe clears checkpoints. `WHEN`: logout/wipe while a revalidation is in flight. `IMPACT`: a leftover checkpoint for the previous user makes the next init() assume data fresh (refresh skipped) — or a stale-invalidated EMPTY forces an extra network hit; lack of sequencing around clear/refresh is the root. `CONFIDENCE`: MEDIUM.
- **F-SM15** — No automated tests cover BaseState, coalescing, or loadWithChangeDetection. `WHAT`: test tree contains only state/repo unit tests; nothing exercises `BaseState.notifyListeners`, `runSafe`, `handleResult`, `loadWithChangeDetection` (grep shows zero references outside `lib/`). `WHERE`: `Flutter/test/`. `WHY`: base-state added as internal scaffolding without dedicated specs. `WHEN`: regression in coalescing/change-detection goes undetected. `IMPACT`: the most reused infrastructure is the least tested. `CONFIDENCE`: HIGH.

## Invariants

- Exactly one instance of each feature state exists for the app lifetime; never recreated by navigation.
- A state's in-memory data and StorageService copy are written together in every success path (exceptions: generated/derived slices like `_knownIds`, `_singleItem`).
- Checkpoints are the single synchronization cursor per feature; `EMPTY` means "unknown, must re-fetch".
- Init is a screen-driven operation (TabScreenMixin or homepage `_loadData`), never application-global; auth init is the sole exception (splash).
- Logout clears session + checkpoints + storage, but deliberately leaves feature in-memory state untouched (only wipe clears both — profile_screen.dart:97-106).
- BaseState notification is deferred one frame; code must never rely on synchronous listener invocation.
- ThemeProvider value survives navigation but not process restart; LanguageProvider persists via SharedPreferences.

## Implementation status

| Concern | Status |
|---|---|
| BaseState hooking into ChangeNotifier | IMPLEMENTED (base_state.dart:10-29) |
| Frame coalescing | IMPLEMENTED (partial — per-instance only) |
| loadWithChangeDetection | IMPLEMENTED (base_state.dart:46-59) |
| Change-check via checkpoint vs server max-timestamp | IMPLEMENTED (base_repository.dart:79-108, checkpoint_mixin.dart) |
| Stale-while-revalidate cache pattern | IMPLEMENTED (all cache states) |
| Optimistic updates w/ rollback | PARTIALLY IMPLEMENTED (drive, mood; bucket deferred to realtime; F-SM12 rollback gap) |
| Realtime push into local state | IMPLEMENTED (realtime_sync_service.dart; profile excluded) |
| De-duplication of concurrent fetches | PARTIALLY IMPLEMENTED (per-state guards; homepage/mood unguarded; no shared coordinator) |
| Stale-response handling (ordering) | NOT IMPLEMENTED |
| State survival across navigation | IMPLEMENTED (root-provided) |
| State survival across lifecycle | IMPLEMENTED (resume refresh-all; background unsubscribe) |
| Feature state reset on logout | NOT IMPLEMENTED (F-SM7) |
| Automated tests for state layer | NOT IMPLEMENTED (F-SM15) |

## Notes

- `BaseState` doc comment claims "startup rebuild storm" protection (base_state.dart:18-20); cross-provider storms are not actually prevented (F-SM2).
- `handleResult(notifyOnSuccess:)` (base_state.dart:68) is unused across the codebase (no call passes `true`), but reauth-critical `GenericError` results still notify via the error branch (base_state.dart:71,74).
- The `Selector`-based slices mean most widgets rebuild on small typed views of state; combined with F-SM1 deferral, the effective update pipeline is: mutate → post-frame single notify → provider marks dependents → next frame rebuild.
- `RealtimeSyncService` holds strong references to all feature states except ProfileState (realtime_sync_scope.dart:24-31); adding profile support is the single largest missing wiring.
- Drive incremental sync is the only feature using server-side `updated_at` cursoring (drive_repository.dart:32); all others re-fetch lists wholesale on change.
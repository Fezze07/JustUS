# Mood Subsystem - JustUS

## Overview

This document provides a reverse-engineered analysis of the **Mood & Emotions Subsystem** in the JustUS application. It traces the full execution lifecycle of mood updates, emoji selection, partner sharing, timeline rendering, real-time synchronization, and caching capabilities across the Flutter frontend, Node backend, and Supabase PostgreSQL database.

The mood subsystem allows users to select or input Unicode emojis to express their current emotional state, share mood updates with their linked partner in real-time, view a historical couple mood timeline, and manage a recent emoji history.

---

## Architecture & Component Mapping

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER FRONTEND LAYER                         │
│  MoodScreen • EmojiPickerSheet • EmojiPickerWidget • MoodState           │
│  MoodRepository • RealtimeSyncService • HomepageScreen                  │
└────────────────────┬───────────────────────────────▲────────────────────┘
                     │                               │
          Supabase   │                               │ Supabase Realtime
          RPC call   │                               │ Postgres Changes
                     ▼                               │ (table: moods)
┌────────────────────────────────────────────────────┴────────────────────┐
│                             SUPABASE LAYER                              │
│  Tables: public.moods, public.emojis, public.users                      │
│  RPCs: mood_set, emoji_get_or_create                                    │
│  RLS Policies: SELECT / INSERT for self & active partner                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [mood_screen.dart](file:///f:/JustUS/Flutter/lib/features/mood/screens/mood_screen.dart): Renders recent emojis horizontal bar, update status button, timeline list with date/time formatting, and load more pagination.
   - [emoji_picker_sheet.dart](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart): Modal bottom sheet rendering single-emoji custom text field and 49 predefined default + user historical emojis grid.
   - [mood_state.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart): State manager maintaining `_userMood`, `_partnerMood`, `_recentEmojis`, and `_timeline`. Implements optimistic UI updates and rollback on failure.
   - [mood_repository.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart): Interacts with Supabase database (`mood_set` RPC, queries on `moods` joined with `emojis`) and triggers FCM notifications (`notifyPartnerOnce`).
   - [mood_models.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_models.dart): Data models `MoodEntry` and `MoodResponse`.

2. **Database Layer (Supabase / PostgreSQL)**:
   - `public.emojis`: Dictionary table storing unique emoji character strings (`id` bigint PK, `emoji_char` text UNIQUE).
   - `public.moods`: Historical log of mood entries (`id` integer PK, `user_id` integer FK, `mood_type_id` bigint FK to `emojis.id`, `partnership_id` integer FK to `partnerships.id`, `created_at` timestamptz).
   - `mood_set(p_emoji_char)` RPC: Stored procedure that resolves or inserts the emoji into `public.emojis`, appends a new entry into `public.moods`, tagged with the caller's `accepted` `partnership_id` (NULL when the caller has none), and returns the inserted row including the server-generated `created_at`.

---

## Data Model & Database Schema

### Database Tables

#### 1. `public.emojis`
| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | `bigint` | `PRIMARY KEY` | Unique identifier for emoji character. |
| `emoji_char` | `text` | `NOT NULL`, `UNIQUE` | Raw Unicode emoji string (e.g. `🥰`, `🔥`). |

#### 2. `public.moods`
| Column Name | Data Type | Constraints | Description |
|---|---|---|---|
| `id` | `integer` | `PRIMARY KEY` | Unique identifier for mood entry. |
| `user_id` | `integer` | `FOREIGN KEY (users.id)` | Identifier of the user who set the mood. |
| `mood_type_id` | `bigint` | `FOREIGN KEY (emojis.id)` | Reference to the emoji dictionary record. |
| `partnership_id` | `integer` | `FOREIGN KEY (partnerships.id) ON DELETE CASCADE`, indexed | Couple the mood belongs to; deleted with the partnership. |
| `created_at` | `timestamp with time zone` | `DEFAULT NOW()` | UTC timestamp when mood was recorded. |

### Application Model (`MoodEntry`)

Defined in [mood_models.dart:39-83](file:///f:/JustUS/Flutter/lib/features/mood/mood_models.dart#L39-L83):
- `id` (`int`): Primary key of the mood row.
- `userId` (`int?`): Owner user ID.
- `emoji` (`String`): Extracted Unicode emoji string (`emoji_char`).
- `createdAt` (`String`): ISO8601 timestamp.
- `isMine` (`bool`): `true` if `userId == currentUserId`.

---

## End-to-End Execution Trace: Mood Creation

```
User Action (Select Emoji in Sheet or Custom Input)
                           │
                           ▼
          Validation & Duplicate Check
    (Input length == 1 character; input != currentMood)
                           │
                           ▼
              Optimistic Local State Update
    (Set _userMood = emoji, prepend to _recentEmojis,
     insert into _timeline[0], save to StorageService)
                           │
                           ▼
             Supabase RPC Call: mood_set
    (Calls sbClient.rpc('mood_set', {p_emoji_char: emoji})
     + Triggers push notification notifyPartnerOnce)
                           │
                           ├── Success ─────────────────────────────┐
                           │                                        │
                           ▼                                        ▼
                  Database Persistence                    Partner Realtime Sync
          1. Resolves/Inserts public.emojis            1. Supabase Realtime emits
          2. Inserts public.moods row                     INSERT on public.moods
          3. Returns the persisted row                 2. Partner RealtimeSyncService
             (server created_at)                         receives payload
                           │                           3. Invokes fetchPartnerMood()
                           │                              & fetchTimeline()
                           │                           4. UI updates on partner device
                           ▼
                   Failure Rollback
          (Reverts _userMood, _recentEmojis,
           and _timeline to pre-tap state)
```

### Detailed Component Steps

1. **Emoji Selection & Validation**
   - File: [emoji_picker_sheet.dart:113-158](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart#L113-L158)
   - **Predefined Emoji Tap**: Calls `_selectPredefinedEmoji(emoji)`.
   - **Custom TextField Input**: User enters text in `TextField` and taps Add. `_addEmoji()` validates:
     - `input.isNotEmpty` (if empty -> `context.loc.mood_enterEmoji`).
     - `input.characters.length == 1` (using `characters` getter to correctly validate Unicode grapheme clusters; if > 1 -> `context.loc.mood_enterSingleEmoji`).
   - **Duplicate Validation**: Compares selected emoji against `context.read<MoodState>().userMood`. If equal, triggers `ErrorCodes.localMoodDuplicate` ("Hai già impostato questa emoji come mood attuale") and aborts.

2. **Optimistic Local State Update**
   - File: [mood_state.dart:288-335](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart#L288-L335)
   - Backs up previous state (`previousMood`, `previousTimestamp`, `previousTimeline`).
   - Sets `_userMood = emoji` and leaves `_userMoodUpdatedAt` at the last server value until the response arrives.
   - Prepends emoji to `_recentEmojis` (deduplicating existing occurrences).
   - Inserts new `MoodEntry` at index 0 of `_timeline` (capping initial view at 5 items) with the previous server timestamp as its placeholder.
   - Keeps the optimistic state **in memory only**; the cache is written after the server confirms (F-SC14).
   - Calls `notifyListeners()`, refreshing local UI instantly.

3. **Backend & Database RPC Execution**
   - File: [mood_repository.dart:8-27](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L8-L27)
   - Invokes `sbClient.rpc('mood_set', params: {'p_emoji_char': emojiChar})`. The RPC returns the inserted `public.moods` row.
   - In PostgreSQL, procedure `mood_set`:
     - Resolves the caller's `accepted` partnership id (`partnerships` where the caller is a member and `status = 'accepted'`), NULL if none.
     - Calls `emoji_get_or_create(p_emoji_char)` to resolve or insert the emoji string in `public.emojis`.
     - Inserts a row into `public.moods` with `user_id = user_current_id()`, `mood_type_id`, `partnership_id` and `created_at = NOW()` (server default), then returns the persisted row.
   - Maps the returned row through `MoodEntry.fromJson`, taking `created_at` from the server, never from `DateTime.now()`.
   - Fires asynchronous partner push notification request via `notifyPartnerOnce(notificationKey: 'moodUpdated', params: {'emojiChar': emojiChar})`.

4. **Realtime Broadcast & Partner UI Update**
   - File: [mood_realtime_handler.dart](file:///f:/JustUS/Flutter/lib/core/realtime/handlers/mood_realtime_handler.dart)
   - Supabase Realtime emits `INSERT` event on table `public.moods`.
   - Partner's `MoodRealtimeHandler` catches payload in `handle()`.
   - Verifies relevance via `RealtimeSyncSession.isRelevantMood` (`changedUserId == session.userId || changedUserId == session.partnerId`).
   - Deduplicates event key (`RealtimeSyncSession.markSeen`).
   - Applies 120ms debounce via `MoodChangeBatch` (distinct-`changedUserId` coalescing, F-RT2).
   - Executes `MoodState.refreshFromRealtime(changedUserId)`.
   - Partner's app invokes `fetchPartnerMood()`, `fetchRecentEmojis()`, and `fetchTimeline()`, updating the partner's UI.

5. **Failure Rollback**
   - File: [mood_state.dart:340-352](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart#L340-L352)
   - If the RPC network call fails, `result.isError` evaluates to `true`.
   - `MoodState` restores `_userMood`, `_userMoodUpdatedAt`, `_recentEmojis`, and `_timeline` to their pre-tap values.
   - The cache was never written optimistically, so it already reflects the pre-update state; `notifyListeners()` repaints.

---

## Functional Features & Requirements Analysis

### 1. Default & User Emojis
- **Default Emojis**: A static array of 49 curated Unicode emojis (`_defaultEmojis`) is defined in [emoji_picker_sheet.dart:20-69](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart#L20-L69).
- **User Emojis**: `_loadUserEmojis()` calls `MoodRepository.fetchMoods()`, extracts all distinct emojis previously recorded by the couple (`moods.map((e) => e.emoji).toSet().toList()`), and prepends them to the picker grid before the default emojis ([emoji_picker_sheet.dart:77-111](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart#L77-L111)).

### 2. Custom Text & Single-Emoji Validation
- Users can input any valid Unicode emoji in the text field in `EmojiPickerSheet`.
- String validation uses `input.characters.length != 1` to support multi-byte Unicode emoji grapheme clusters while blocking multi-character text strings.

### 3. Recent Emojis
- Fetched via `MoodRepository.fetchRecentCoupleEmojis()` ([mood_repository.dart:86-109](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L86-L109)).
- Queries `public.moods` for both couple members (`user_id IN (uid, partnerId)`), ordered by `created_at DESC`, limited to 10 rows.
- Deduplicates emojis while preserving chronological recency.
- Displayed horizontally in `MoodScreen` recents bar (`_buildRecentItem`).

### 4. Partner Sharing & Visibility
- Ownership is determined by `public.moods.user_id`.
- Partner visibility is enforced by RLS policies: a user can read rows where `user_id = user_current_id()` OR `partnership_is_partner(user_id) = true`.
- `MoodState.fetchPartnerMood()` queries `public.moods` where `user_id = partnerId` ordered by `created_at DESC LIMIT 1`.

### 5. Mood Timeline & Pagination
- Displays couple history entries sorted by `created_at DESC`.
- Page size: 4 items.
- `loadMoreTimeline()` increments `_timelineOffset` and appends next batch of 4 items using `.range(offset, offset + limit - 1)`.
- Renders entry timestamp formatted as `d MMMM` (e.g., "11 Settembre") and `HH:mm` (e.g., "20:45").
- Displays color-coded borders: `context.palette.primary` for user's own entries (`isMine: true`), `context.palette.accentPink` for partner's entries (`isMine: false`).

---

## Operational Mechanics & Behaviors

### 1. Timestamps & Ordering
- `public.moods.created_at` is generated by PostgreSQL (`DEFAULT NOW()`); `mood_set` returns the persisted row and the client takes `created_at` from it. The device clock never stamps a mood row or its checkpoint.
- The `CacheService.kMoods` checkpoint is the newest `created_at` actually returned by the server, so a device clock that runs ahead cannot suppress future fetches.
- **Forward-skew guard**: if a response's newest `created_at` is behind the stored checkpoint (for example a legacy checkpoint written by the old device-clock path), `MoodState._updateMoodsCheckpoint` logs the regression and resets the checkpoint to the returned timestamp.
- All queries sort entries explicitly using `.order('created_at', ascending: false)`.

### 2. Duplicate Behavior
- Setting the **exact same emoji consecutively** is blocked on the client side (`input == currentMood` -> `ErrorCodes.localMoodDuplicate`).
- Database schema permits duplicate emoji entries over time across different timestamps.

### 3. Edit & Delete Behavior
- **NOT IMPLEMENTED**. `public.moods` is an append-only log. No UI controls, repository methods, or backend APIs exist to edit or delete existing mood entries.

### 4. Caching & Checkpoint Behavior
- Implements `CheckpointMixin` with key `CacheService.kMoods`.
- `_hasMoodChanges()` checks `MoodRepository.hasNewMoods()`, which compares the server's newest `public.moods.created_at` with the cached checkpoint (strictly newer -> fetch).
- If no new rows exist, loads data from local `StorageService` (`getMood`, `getRecentEmojis`, `getTimeline`).
- If new rows exist, fetches network data and updates the max timestamp checkpoint from the newest returned row.

---

## Security & RLS Policies

- Table `public.moods` RLS policies:
  - **SELECT**: Allowed if `user_id = user_current_id()` OR `partnership_is_partner(user_id) = true`.
  - **INSERT / UPDATE / DELETE**: Restricted to the owner (`user_id = user_current_id()`). INSERT and UPDATE additionally require `partnership_id IS NULL OR partnership_is_member(partnership_id)`, so a client cannot attach a mood to another pair's partnership or to a pending/cancelled one.
- `public.moods.partnership_id` references `public.partnerships(id)` with `ON DELETE CASCADE`, so a couple's mood history is removed with the partnership. No backfill was needed (the table was empty); a mood written outside a partnership stays `NULL`. `mood_set` resolves the caller's `accepted` partnership and stores its id, so a paired user's new mood always belongs to the couple.
- RPC `mood_set`: Configured as `SECURITY INVOKER`, ensuring execution respects caller RLS credentials (including the partnership lookup).

---

## Discovered Bugs, Defects, and Inconsistencies

During reverse-engineering analysis, the following technical findings were identified:

- None (all prior findings fixed).

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Set Mood (Emoji Selection) | **IMPLEMENTED** | Predefined grid + custom emoji input |
| Single-Emoji Validation | **IMPLEMENTED** | Validates Unicode grapheme cluster length |
| Duplicate Mood Block | **IMPLEMENTED** | Blocks setting identical consecutive mood |
| Partner Mood Sharing | **IMPLEMENTED** | RLS shared visibility + push notifications |
| Recent Couple Emojis | **IMPLEMENTED** | `fetchRecentCoupleEmojis()` (last 10 entries) |
| Mood Timeline & Pagination | **IMPLEMENTED** | `fetchTimeline()` with offset pagination |
| Realtime Synchronization | **IMPLEMENTED** | `RealtimeSyncService` listens to `moods` INSERTs |
| Checkpoint & Cache Strategy | **IMPLEMENTED** | `CheckpointMixin` + `CacheService.kMoods` |
| Edit / Delete Mood Entries | **NOT IMPLEMENTED** | Append-only database design |

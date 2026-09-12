# Mood Subsystem - JustUS

## Overview

This document provides a reverse-engineered analysis of the **Mood & Emotions Subsystem** in the JustUS application. It traces the full execution lifecycle of mood updates, emoji selection, partner sharing, timeline rendering, real-time synchronization, caching, and analytics capabilities across the Flutter frontend, Node backend, and Supabase PostgreSQL database.

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
│  RPCs: set_mood, get_or_create_emoji                                    │
│  RLS Policies: SELECT / INSERT for self & active partner                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [mood_screen.dart](file:///f:/JustUS/Flutter/lib/features/mood/screens/mood_screen.dart): Renders recent emojis horizontal bar, update status button, timeline list with date/time formatting, and load more pagination.
   - [emoji_picker_sheet.dart](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart): Modal bottom sheet rendering single-emoji custom text field and 49 predefined default + user historical emojis grid.
   - [mood_state.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart): State manager maintaining `_userMood`, `_partnerMood`, `_recentEmojis`, and `_timeline`. Implements optimistic UI updates and rollback on failure.
   - [mood_repository.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart): Interacts with Supabase database (`set_mood` RPC, queries on `moods` joined with `emojis`) and triggers FCM notifications (`notifyPartnerOnce`).
   - [mood_models.dart](file:///f:/JustUS/Flutter/lib/features/mood/mood_models.dart): Data models `MoodEntry` and `MoodResponse`.

2. **Database Layer (Supabase / PostgreSQL)**:
   - `public.emojis`: Dictionary table storing unique emoji character strings (`id` bigint PK, `emoji_char` text UNIQUE).
   - `public.moods`: Historical log of mood entries (`id` integer PK, `user_id` integer FK, `mood_type_id` bigint FK to `emojis.id`, `created_at` timestamptz).
   - `set_mood(p_emoji_char)` RPC: Stored procedure that resolves or inserts the emoji into `public.emojis` and appends a new entry into `public.moods`.

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
| `created_at` | `timestamp with time zone` | `DEFAULT NOW()` | UTC timestamp when mood was recorded. |

### Application Model (`MoodEntry`)

Defined in [mood_models.dart:39-87](file:///f:/JustUS/Flutter/lib/features/mood/mood_models.dart#L39-L87):
- `id` (`int`): Primary key of the mood row.
- `userId` (`int?`): Owner user ID.
- `emoji` (`String`): Extracted Unicode emoji string (`emoji_char`).
- `note` (`String?`): Optional note text (model field present, but backend RPC does not store notes).
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
             Supabase RPC Call: set_mood
    (Calls sbClient.rpc('set_mood', {p_emoji_char: emoji})
     + Triggers push notification notifyPartnerOnce)
                           │
                           ├── Success ─────────────────────────────┐
                           │                                        │
                           ▼                                        ▼
                  Database Persistence                    Partner Realtime Sync
          1. Resolves/Inserts public.emojis            1. Supabase Realtime emits
          2. Inserts public.moods row                     INSERT on public.moods
          3. Returns success response                  2. Partner RealtimeSyncService
                                                          receives payload
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
   - File: [mood_state.dart:233-257](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart#L233-L257)
   - Backs up previous state (`previousMood`, `previousTimestamp`, `previousTimeline`).
   - Sets `_userMood = emoji` and `_userMoodUpdatedAt = now`.
   - Prepends emoji to `_recentEmojis` (deduplicating existing occurrences).
   - Inserts new `MoodEntry` at index 0 of `_timeline` (capping initial view at 5 items).
   - Saves updated state asynchronously to `StorageService` (`saveMood`, `saveRecentEmojis`, `saveTimeline`).
   - Calls `notifyListeners()`, refreshing local UI instantly.

3. **Backend & Database RPC Execution**
   - File: [mood_repository.dart:8-29](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L8-L29)
   - Invokes `sbClient.rpc('set_mood', params: {'p_emoji_char': emojiChar})`.
   - In PostgreSQL, procedure `set_mood`:
     - Calls `get_or_create_emoji(p_emoji_char)` to resolve or insert the emoji string in `public.emojis`.
     - Inserts a row into `public.moods` with `user_id = current_user_id()`, `mood_type_id`, and `created_at = NOW()`.
   - Fires asynchronous partner push notification request via `notifyPartnerOnce(notificationKey: 'moodUpdated', params: {'emojiChar': emojiChar})`.

4. **Realtime Broadcast & Partner UI Update**
   - File: [realtime_sync_service.dart:396-410](file:///f:/JustUS/Flutter/lib/core/realtime/realtime_sync_service.dart#L396-L410)
   - Supabase Realtime emits `INSERT` event on table `public.moods`.
   - Partner's `RealtimeSyncService` catches payload in `_handleMoodPayload()`.
   - Verifies relevance via `_isRelevantMood` (`userId == _userId || userId == _partnerId`).
   - Deduplicates event key (`_markSeen`).
   - Applies 120ms debounce timer (`_moodRefreshTimer`).
   - Executes `MoodState.refreshFromRealtime(changedUserId)`.
   - Partner's app invokes `fetchPartnerMood()`, `fetchRecentEmojis()`, and `fetchTimeline()`, updating the partner's UI.

5. **Failure Rollback**
   - File: [mood_state.dart:271-280](file:///f:/JustUS/Flutter/lib/features/mood/mood_state.dart#L271-L280)
   - If the RPC network call fails, `result.isError` evaluates to `true`.
   - `MoodState` restores `_userMood`, `_userMoodUpdatedAt`, and `_timeline` to their pre-tap values.
   - Reverts `StorageService` values and calls `notifyListeners()`.

---

## Functional Features & Requirements Analysis

### 1. Default & User Emojis
- **Default Emojis**: A static array of 49 curated Unicode emojis (`_defaultEmojis`) is defined in [emoji_picker_sheet.dart:20-69](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart#L20-L69).
- **User Emojis**: `_loadUserEmojis()` calls `MoodRepository.fetchMoods()`, extracts all distinct emojis previously recorded by the couple (`moods.map((e) => e.emoji).toSet().toList()`), and prepends them to the picker grid before the default emojis ([emoji_picker_sheet.dart:77-111](file:///f:/JustUS/Flutter/lib/features/mood/widgets/emoji_picker_sheet.dart#L77-L111)).

### 2. Custom Text & Single-Emoji Validation
- Users can input any valid Unicode emoji in the text field in `EmojiPickerSheet`.
- String validation uses `input.characters.length != 1` to support multi-byte Unicode emoji grapheme clusters while blocking multi-character text strings.
- **Custom Note Field**: Model `MoodEntry` contains a `note` property, but neither `set_mood` RPC nor the Flutter `updateMood()` method accepts or persists custom note text.

### 3. Recent Emojis
- Fetched via `MoodRepository.fetchRecentCoupleEmojis()` ([mood_repository.dart:86-109](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L86-L109)).
- Queries `public.moods` for both couple members (`user_id IN (uid, partnerId)`), ordered by `created_at DESC`, limited to 10 rows.
- Deduplicates emojis while preserving chronological recency.
- Displayed horizontally in `MoodScreen` recents bar (`_buildRecentItem`).

### 4. Partner Sharing & Visibility
- Ownership is determined by `public.moods.user_id`.
- Partner visibility is enforced by RLS policies: a user can read rows where `user_id = current_user_id()` OR `is_partner_of(user_id) = true`.
- `MoodState.fetchPartnerMood()` queries `public.moods` where `user_id = partnerId` ordered by `created_at DESC LIMIT 1`.

### 5. Mood Timeline & Pagination
- Displays couple history entries sorted by `created_at DESC`.
- Page size: 4 items.
- `loadMoreTimeline()` increments `_timelineOffset` and appends next batch of 4 items using `.range(offset, offset + limit - 1)`.
- Renders entry timestamp formatted as `d MMMM` (e.g., "11 Settembre") and `HH:mm` (e.g., "20:45").
- Displays color-coded borders: `AppColors.primary` for user's own entries (`isMine: true`), `Colors.pinkAccent` for partner's entries (`isMine: false`).

---

## Analytics & Trend Calculations

The task prompt required analyzing analytics calculations and verifying operation on the stored dataset:

### Empirical Audit Findings

1. **Analytics UI Button**:
   - File: [mood_screen.dart:49-52](file:///f:/JustUS/Flutter/lib/features/mood/screens/mood_screen.dart#L49-L52)
   - `MoodScreen` app bar includes an analytics icon button (`Icons.analytics`).
   - **Finding**: The `onPressed` callback is completely **empty** (`onPressed: () {}`). Tapping the analytics button performs no action and renders no charts or statistical views.

2. **Trend Calculations**:
   - The "Recent Trends" feature described in project documentation operates strictly on `fetchRecentCoupleEmojis()` ([mood_repository.dart:86-109](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L86-L109)).
   - **Algorithm**:
     ```dart
     final data = await _fetchMoodsForUsers([uid, partnerId], select: 'emojis(emoji_char)', limit: 10);
     final emojis = data.map((m) => m['emojis']['emoji_char']).where((e) => e.isNotEmpty).toList();
     final unique = <String>[];
     for (final e in emojis) {
       if (seen.add(e)) unique.add(e);
     }
     return unique;
     ```
   - **Verification**: Operates directly on the actual `public.moods` dataset for the active couple. It selects the 10 most recent entries from the database, extracts emoji characters, and returns a unique ordered list representing current emotional trends.

---

## Operational Mechanics & Behaviors

### 1. Timestamps & Ordering
- Timestamps are generated by PostgreSQL (`created_at DEFAULT NOW()`) or UTC ISO8601 strings.
- All queries sort entries explicitly using `.order('created_at', ascending: false)`.

### 2. Duplicate Behavior
- Setting the **exact same emoji consecutively** is blocked on the client side (`input == currentMood` -> `ErrorCodes.localMoodDuplicate`).
- Database schema permits duplicate emoji entries over time across different timestamps.

### 3. Edit & Delete Behavior
- **NOT IMPLEMENTED**. `public.moods` is an append-only log. No UI controls, repository methods, or backend APIs exist to edit or delete existing mood entries.

### 4. Caching & Checkpoint Behavior
- Implements `CheckpointMixin` with key `CacheService.kMoods`.
- `_hasMoodChanges()` checks `MoodRepository.hasNewMoods()`, which queries `public.moods` for `created_at > cached_checkpoint_timestamp`.
- If no new rows exist, loads data from local `StorageService` (`getMood`, `getRecentEmojis`, `getTimeline`).
- If new rows exist, fetches network data and updates the max timestamp checkpoint.

---

## Security & RLS Policies

- Table `public.moods` RLS policies:
  - **SELECT**: Allowed if `user_id = current_user_id()` OR `is_partner_of(user_id) = true`.
  - **INSERT / UPDATE / DELETE**: Restricted to the owner (`user_id = current_user_id()`).
- RPC `set_mood`: Configured as `SECURITY INVOKER`, ensuring execution respects caller RLS credentials.

---

## Discovered Bugs, Defects, and Inconsistencies

During reverse-engineering analysis, the following technical findings were identified:

### 1. DEFECT: Dead Analytics Button in `MoodScreen`

* **WHAT**: The analytics icon button in `MoodScreen` header has an empty callback.
* **WHERE**: [mood_screen.dart:49-52](file:///f:/JustUS/Flutter/lib/features/mood/screens/mood_screen.dart#L49-L52)
* **WHY**: Button was placed in UI layout but analytics view / chart calculation screen was never implemented.
* **WHEN**: User taps the analytics icon in the top app bar of `MoodScreen`.
* **IMPACT**: No feedback or screen transition occurs when tapped.
* **CONFIDENCE**: **HIGH**

### 2. INCONSISTENCY: Unused `note` Field in Data Model

* **WHAT**: `MoodEntry` model contains a `note` property, but `set_mood` RPC and `updateMood()` method do not support custom notes.
* **WHERE**: [mood_models.dart:44](file:///f:/JustUS/Flutter/lib/features/mood/mood_models.dart#L44) and [mood_repository.dart:8-29](file:///f:/JustUS/Flutter/lib/features/mood/mood_repository.dart#L8-L29)
* **WHY**: Database schema / RPC `set_mood` takes only `p_emoji_char`. Notes are not stored in `public.moods`.
* **WHEN**: Inspecting model definitions vs database functions.
* **IMPACT**: Dead model property.
* **CONFIDENCE**: **HIGH**

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
| Mood Analytics Button | **NOT IMPLEMENTED** | Button exists in UI with empty `onPressed` callback |
| Mood Note Field | **NOT IMPLEMENTED** | Model property exists, but backend RPC lacks note column |
| Edit / Delete Mood Entries | **NOT IMPLEMENTED** | Append-only database design |

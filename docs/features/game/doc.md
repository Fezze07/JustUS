# Couple Game Subsystem - JustUS

## Overview

This document describes the **Couple Game subsystem** in the JustUS application. Question text is served from a static Supabase catalog (`game_question_bank`) — there is **no AI generation, no backend route and no external provider**. The subsystem selects a question for the couple, tracks each partner's vote (Option A vs Option B, where the options are the two partners), computes agreement, synchronizes partner answers in realtime, and keeps a local history.

The game engages linked couples with relationship quiz questions ("Who is more likely to…"). Each question is an instance row in `game_questions` referencing a catalog entry by stable `question_code`; each vote is a row in `game_answers`.

---

## Architecture & Component Mapping

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER FRONTEND                        │
│  GameScreen • GameState • GameRepository                     │
│  GameQuestionBankRepository • GameModels                     │
│  RealtimeSyncService (GameRealtimeHandler + GameEventBuffer) │
└───────────────┬──────────────────────────────▲──────────────┘
                │ Supabase SDK (PostgREST)      │ Supabase Realtime
                │ RLS-scoped reads/writes       │ (game_questions, game_answers)
                ▼                               │
┌───────────────────────────────────────────────┴─────────────┐
│                    SUPABASE (PostgreSQL)                     │
│  game_question_bank  (static catalog, SELECT-only)           │
│  game_questions      (per-couple question instance)          │
│  game_answers        (per-user vote)                         │
│  trigger: update_game_question_status → 'both_answered'      │
└──────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [game_screen.dart](file:///f:/JustUS/Flutter/lib/features/games/screens/game_screen.dart): Game tab UI. Renders the current-question card (`GameNewQuestionResponse`), the Option A / Option B voting buttons, the "you vs partner" answer status avatars, and the last five history entries (`GameHistoryItem`) via `GameHistoryCard`. Empty states: `game_noQuestionAvailable` when the catalog has no question for the couple's locale, `game_allCaughtUp` otherwise.
   - [game_state.dart](file:///f:/JustUS/Flutter/lib/features/games/game_state.dart): `GameState extends BaseState with CheckpointMixin`. Owns `_currentQuestion`, `_history`, `_noQuestionAvailable` and the realtime handlers. Subscribes to `LanguageProvider` and refetches the active question + history (read-only) when the language changes; never inserts a question on a locale switch.
   - [game_repository.dart](file:///f:/JustUS/Flutter/lib/features/games/game_repository.dart): `GameRepository extends BaseRepository`. All data access goes through Supabase (no backend call): `fetchActiveQuestion` (read-only), `fetchNewGameQuestion` (create-from-catalog-if-missing), `submitAnswer`, `fetchAnswerStatus`, `hasNewGameActivity` (checkpoint gate), `fetchGameHistory`.
   - [game_question_bank_repository.dart](file:///f:/JustUS/Flutter/lib/features/games/game_question_bank_repository.dart): `GameQuestionBankRepository` — catalog access: `fetchQuestionsByLocale`, `fetchQuestionText`, `fetchTextsForCodes`, `pickQuestionForGame`, all with locale fallback.
   - [game_models.dart](file:///f:/JustUS/Flutter/lib/features/games/game_models.dart): `GameQuestionBankItem` (catalog row), `GameNewQuestionResponse` (active question), `GameHistoryItem` (history row, with `isMatched`/`isDisagreed`), plus the shared helpers `resolvePlayerName` and `optionLabelFor`.
   - Realtime: [game_realtime_handler.dart](file:///f:/JustUS/Flutter/lib/core/realtime/handlers/game_realtime_handler.dart) routes `game_questions`/`game_answers` events into `GameState`; `game_questions` **insert/delete** dispatch immediately, every other game event is buffered FIFO in `game_event_buffer.dart` and flushed in delivery order.

2. **Database Layer (Supabase / PostgreSQL)**: see the schema section below. There is no Node.js/Express involvement in this feature.

---

## Database Schema

### `game_question_bank` (catalog)

- **SQL Source:** [game_question_bank.sql](file:///f:/JustUS/supabase/schemas/public/tables/game_question_bank.sql)
- **Columns:** `question_code` (`text`, NOT NULL), `locale` (`text`, NOT NULL), `text` (`text`, NOT NULL), `created_at` / `updated_at` (`timestamptz`, DEFAULT `now()`).
- **Primary Key:** `(question_code, locale)` — the same question code may have one row per locale, so new translations are added without touching Flutter.
- **RLS:** `game_question_bank_read_all` — `FOR SELECT TO PUBLIC USING (true)`. The catalog is world-readable; no client role can write it (the broad table GRANT is not exercised because no INSERT/UPDATE policy exists).
- **Trigger:** `set_public_game_question_bank_updated_at` (BEFORE UPDATE → `set_current_timestamp_updated_at()`).
- **Seed:** the repository contains **no seed** for this table (only the SQL tests insert rows), so a fresh database starts with an empty catalog and the app shows the "no question available" state until rows are loaded.

### `game_questions` (per-couple instance)

- **SQL Source:** [game_questions.sql](file:///f:/JustUS/supabase/schemas/public/tables/game_questions.sql)
- **Columns:** `id` (`integer`, PK, DEFAULT `nextval('game_questions_id_seq')`), `created_at` (`timestamptz`), `partnership_id` (`integer`, FK → `partnerships.id` ON DELETE CASCADE), `question_code` (`text`), `status` (`text`, DEFAULT `'pending'`), `user_id_a` / `user_id_b` (`integer`, FK → `users.id`).
- **Indexes:** `idx_game_questions_partnership_id`, `idx_game_questions_user_id_a`, `idx_game_questions_user_id_b`, `idx_game_questions_question_code`.
- **RLS:** `game_questions_related` (`FOR ALL TO PUBLIC`, `USING` + `WITH CHECK` on `is_in_partnership(partnership_id)`).
- There is **no `text`/`question` column** and **no `active` flag**: text lives in the catalog and the active question is the couple's newest row whose `status != 'both_answered'`.

### `game_answers` (votes)

- **SQL Source:** [game_answers.sql](file:///f:/JustUS/supabase/schemas/public/tables/game_answers.sql)
- **Columns:** `game_id` (`integer`, FK → `game_questions.id` ON DELETE CASCADE), `user_id` (`integer`, FK → `users.id` ON DELETE CASCADE), `selected_option` (`integer`), `created_at` / `updated_at` (`timestamptz`).
- **Primary Key:** `(game_id, user_id)` — one vote per user per question; re-voting is an upsert. Index `idx_game_answers_user_id`.
- **Triggers:**
  - `set_public_game_answers_updated_at` (BEFORE UPDATE) — bumps `updated_at` on every vote change (the checkpoint compares on this field).
  - `tr_game_answers_update_question_status` (AFTER INSERT OR UPDATE) → `update_game_question_status()`: flips the parent `game_questions.status` to `'both_answered'` once `COUNT(game_answers WHERE game_id = NEW.game_id) >= 2`.
- **RLS:** `game_answers_delete_own`, `game_answers_manage_own` (INSERT: self + parent game in an accepted partnership), `game_answers_related_select` (SELECT through the parent game in an accepted partnership), `game_answers_update_own`.

---

## End-to-End Execution Trace

```
1. Cold start / tab activation (GameScreen.loadData → GameState.init)
   │
   └── loadWithChangeDetection:
         ├── _loadFromCache: restore _currentQuestion (GameNewQuestionResponse) and
         │     _history from StorageService; re-resolve option labels for the current locale.
         ├── _hasGameChanges → GameRepository.hasNewGameActivity(uid, partnerId, partnershipId):
         │     ├── game_answers.updated_at (user_id IN [uid, partnerId]) via CacheService.kGameAnswers
         │     └── else game_questions.created_at (partnership_id) via CacheService.kGameQuestions
         └── _fetchAllInBackground (unawaited): Future.wait([fetchHistory, _fetchActiveQuestion])

2. Read the active question (read-only, never inserts)
   │
   └── GameRepository.fetchActiveQuestion → _fetchActiveQuestionFor(ctx):
         ├── getActivePartnership() → partnershipId + partnerId (throws if none)
         ├── SELECT game_questions WHERE partnership_id = ? AND status != 'both_answered'
         │     ORDER BY created_at DESC LIMIT 1
         ├── if none → return null (GameState sets _noQuestionAvailable)
         ├── SELECT game_answers.user_id WHERE game_id = ? → hasAnswered / partnerAnswered
         ├── resolve text via GameQuestionBankRepository.fetchQuestionText(question_code, locale)
         │     (walks LanguageHelper.localeChain: requested locale → app fallback)
         └── build GameNewQuestionResponse with optionA/optionB = partner display names

3. Create a question if the couple has none (user taps "find another one")
   │
   └── GameState.fetchNewQuestion → GameRepository.fetchNewGameQuestion:
         ├── if an active question already exists → return it (no insert, no notification)
         ├── SELECT game_questions.question_code WHERE partnership_id = ? (played codes)
         ├── pickQuestionForGame(locale, excludeCodes) from game_question_bank:
         │     walks the locale chain; picks a random row excluding already-played codes;
         │     if every code is excluded it falls back to the whole locale pool
         ├── if the catalog (and fallback locale) is empty → Success(null)
         │     → GameState sets noQuestionAvailable and clears any cached question
         ├── random swap: userIdA / userIdB = (child, partner) or (partner, child)
         ├── INSERT game_questions (partnership_id, question_code, status: 'pending',
         │     user_id_a, user_id_b) → RETURN id, status, users
         └── notifyPartnerOnce('newQuestion') (fire-and-forget)

4. Voting
   │
   └── GameState.submitAnswer('A' | 'B') → maps the code to userIdA / userIdB
         → GameRepository.submitAnswer(questionId, selectedOption):
               UPSERT game_answers { game_id, user_id, selected_option }
                 ON CONFLICT (game_id, user_id)
               unawaited(notifyPartnerOnce('answerSubmitted', {partnerName}))
         → GameState optimistically sets hasAnswered, updates _history and its checkpoint,
           and clears the active question once the partner had already answered.

5. Realtime synchronization
   │
   └── GameRealtimeHandler (subscription scoped to the active partnership):
         ├── game_questions INSERT → handleQuestionInsert → fetchNewQuestion(showLoading: false)
         ├── game_questions DELETE → handleQuestionDelete → clear question + scrub history
         ├── game_questions UPDATE → handleQuestionUpdate → update status only;
         │     on 'both_answered' clear the question + cache
         └── game_answers INSERT/UPDATE/DELETE → buffered FIFO → handleAnswerInsert /
               handleAnswerUpdate (re-fetch authoritative status) / handleAnswerDelete

6. Completion & match evaluation
   │
   └── When both partners have answered, the DB trigger sets status = 'both_answered'
         and emits a game_questions UPDATE (clears the waiting device's active question).
         GameHistoryItem.isMatched  → userOption == partnerOption
         GameHistoryItem.isDisagreed → userOption != partnerOption
```

---

## Question Selection, Locale Fallback & Catalog

### Selection rule (`pickQuestionForGame`)

- Reads the whole catalogue for a locale in one query (`fetchQuestionsByLocale`), filters out already-played `question_code`s **client-side**, and picks a random entry.
- Excludes codes the couple has already played (queried from `game_questions`). If the exclusion empties the pool, it falls back to the entire locale pool (so play never hard-stops) without a second DB round trip.
- Walks `LanguageHelper.localeChain(locale)` (e.g. `en → it`); the first locale that yields an item wins. A code with no translation in any chained locale stays empty in history.

### Text resolution

- `fetchQuestionText(questionCode, locale)` — one `(question_code, locale)` lookup per chained locale until a non-empty text is found.
- `fetchTextsForCodes(codes, locale)` — history path: one `IN (...)` query per chained locale, resolving as many codes as possible per pass and stopping when all are resolved (avoids per-code round trips).

### Language change at runtime

`GameState` registers a `LanguageProvider` listener. On a real language change it calls the **read-only** `fetchActiveQuestion` and `fetchHistory` (with the current checkpoint epoch/token), so the on-screen question switches language without inserting a new question or notifying the partner. `setLanguageCode` clears the game question/history cache and the `kGameAnswers` checkpoint so the next `init()` re-fetches.

---

## Game Mechanics: A/B Options, Voting & Realtime Sync

### 1. A/B option mapping

- Options do **not** represent arbitrary answers; each represents one partner.
- `fetchNewGameQuestion` assigns `userIdA`/`userIdB` to the creator and the partner in a **random** order (`Random().nextBool()`), so neither partner is always Option A.
- Labels come from `resolvePlayerName` (self → own name / `common_youTitle`; partner → partner display name / `common_partner`) wrapped by `optionLabelFor` (falls back to `game_optionA`/`game_optionB` when a user id is null).

### 2. Voting

- `GameState.submitAnswer` maps `'A'`/`'B'` to the corresponding user id and calls `GameRepository.submitAnswer`.
- The repository upserts `game_answers` with conflict target `(game_id, user_id)` and fires `notifyPartnerOnce('answerSubmitted', {partnerName})`.
- `game_answers_update_own` / `game_answers_manage_own` RLS restrict each member to their own row, validated against the parent game's accepted partnership.

### 3. Realtime synchronization

- The subscription is configured per active partnership (both `game_questions` and `game_answers` are in the `supabase_realtime` publication).
- `game_questions` INSERT/DELETE are applied immediately; all other events go through the `GameEventBuffer` FIFO flush (trailing-edge 150 ms). This keeps a partner's answer INSERT and the subsequent `both_answered` UPDATE — which routinely land within the debounce window — applied in delivery order rather than keeping only the last event.
- Self echoes are guarded: `handleQuestionInsert` ignores the client's own question id, and `handleAnswerInsert` ignores the current user's own insert.

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| Static Supabase question catalog (`game_question_bank`) | **IMPLEMENTED** | PK `(question_code, locale)`, SELECT-only RLS |
| No AI / no external provider / no backend route | **IMPLEMENTED** | `Backend/features/ai/**` deleted; `api_service.dart` has no `generateAiQuestion` |
| `question_code` stable reference | **IMPLEMENTED** | Written only on insert (`game_repository.dart`), never regenerated |
| Random question without repeats | **IMPLEMENTED** | `pickQuestionForGame` excludes played codes, falls back to the full pool |
| Locale-aware text with fallback chain | **IMPLEMENTED** | `LanguageHelper.localeChain` in the bank repository |
| Runtime language switch | **IMPLEMENTED** | `GameState` read-only refetch on `LanguageProvider` change |
| Read-only active-question fetch | **IMPLEMENTED** | `fetchActiveQuestion` never inserts/notifies |
| Empty-catalog state | **IMPLEMENTED** | `pickQuestionForGame` → `Success(null)` → `noQuestionAvailable` |
| Partner A/B option mapping | **IMPLEMENTED** | Random creator/partner order; display names |
| Realtime answer sync + FIFO burst handling | **IMPLEMENTED** | `GameRealtimeHandler` + `GameEventBuffer` |
| Server-side completion trigger | **IMPLEMENTED** | `tr_game_answers_update_question_status` → `'both_answered'` |
| Catalog seed in the repository | **NOT IMPLEMENTED** | Rows must be loaded into `game_question_bank` out-of-band |

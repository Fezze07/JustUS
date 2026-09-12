# Couple AI Game Subsystem - JustUS

## Overview

This document provides a reverse-engineered analysis of the **Couple AI Game Subsystem** in the JustUS application. It covers end-to-end question generation, prompt templates, OpenRouter model fallback chains, daily token quota management, in-memory circuit breaking, request idempotency, A/B answer mapping, real-time partner answer synchronization, match calculation, and historical game statistics.

The Couple AI Game subsystem engages linked couples by generating daily relationship quiz questions ("Who is more likely to..."), tracking individual votes (Option A vs Option B), calculating agreement matches, and maintaining a historical log of couple answers.

---

## Architecture & Component Mapping

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FLUTTER FRONTEND LAYER                         │
│  GameScreen • GameState • GameRepository • GameModels                   │
│  RealtimeSyncService                                                    │
└────────────────────┬───────────────────────────────▲────────────────────┘
                     │                               │
       REST API /    │                               │ Supabase Realtime
       Supabase SDK  │                               │ Postgres Changes
                     ▼                               │ (game_questions, game_answers)
┌────────────────────────────────────────────────────┴────────────────────┐
│                       NODE.JS / EXPRESS API LAYER                       │
│  POST /api/v1/ai/question                                               │
│  Middleware: authenticated → capability → limited → withIdempotency      │
│              → signed → validated                                       │
│  Services: createAiQuestion → reserveAiTokens → canExecute              │
│            → generateAIQuestion (OpenRouter API)                        │
└────────────────────┬────────────────────────────────────────────────────┘
                     │
                     ▼ External Provider Call
┌─────────────────────────────────────────────────────────────────────────┐
│                           OPENROUTER AI API                             │
│  Primary: openrouter/free                                               │
│  Fallback 1: openai/gpt-oss-120b:free                                   │
│  Fallback 2: nvidia/nemotron-3-super:free                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Roles

1. **Flutter Frontend**:
   - [game_screen.dart](file:///f:/JustUS/Flutter/lib/features/games/screens/game_screen.dart): UI rendering for current question card, Option A / Option B voting buttons, match statistics counter, and historical game list.
   - [game_state.dart](file:///f:/JustUS/Flutter/lib/features/games/game_state.dart): State manager maintaining `_currentQuestion`, `_history`, and `_gameStats`. Handles answer submission, real-time question/answer payloads, and local state persistence.
   - [game_repository.dart](file:///f:/JustUS/Flutter/lib/features/games/game_repository.dart): Network repository calling Express AI API (`_api.generateAiQuestion()`), Supabase tables (`game_questions`, `game_answers`), and stored procedure (`get_game_stats`).
   - [game_models.dart](file:///f:/JustUS/Flutter/lib/features/games/game_models.dart): Data models `GameNewQuestionResponse`, `GameQuestion`, `GameAnswer`, `GameHistoryItem`, and `GameStatsResponse`.

2. **Node.js / Express API**:
   - [ai.routes.js](file:///f:/JustUS/Backend/features/ai/ai.routes.js): Express router defining `POST /api/v1/ai/question` with composite rate limiting, idempotency middleware, request signing, and schema validation.
   - [aiQuestion.service.js](file:///f:/JustUS/Backend/features/ai/aiQuestion.service.js): Orchestrates template selection, circuit breaker evaluation, token quota reservation, AI provider call, and failure reporting.
   - [aiConfig.js](file:///f:/JustUS/Backend/config/aiConfig.js): Contains 64 Italian question templates (`tipiDomanda`), OpenRouter model array, AI prompt builder, response cleaner, and token count estimator.
   - Infrastructure Services: `circuitBreaker.js`, `quotaService.js`, `idempotencyStore.js`.

3. **Database Layer (Supabase / PostgreSQL)**:
   - `public.game_questions`: Table storing generated game questions. Columns: `id` (integer PK), `partnership_id` (integer FK), `question` (text), `status` (character varying, e.g. `'pending'`, `'both_answered'`), `user_id_a` (integer FK), `user_id_b` (integer FK), `created_at` (timestamptz).
   - `public.game_answers`: Table storing user votes. Composite PK: `(game_id, user_id)`. Columns: `game_id` (integer FK), `user_id` (integer FK), `selected_option` (integer FK/id), `created_at` (timestamptz).
   - `get_game_stats(p_uid, p_partner_id)` RPC: Stored procedure calculating total agreement matches between partners.

---

## End-to-End Execution Trace

```
1. Question Request (Flutter UI / GameRepository)
   │
   ├── Checks active question in DB (public.game_questions where status != 'both_answered')
   │     ├── If active question exists: Reuses existing question (bypasses AI call)
   │     └── If no active question: Invokes POST /api/v1/ai/question
   │
2. Backend Middleware Pipeline (Express)
   │
   ├── authenticated() -> Validates JWT
   ├── capability("can_ai_call") -> Verifies user permissions
   ├── limited(aiRateLimit) -> Enforces composite rate limits (IP, User, Endpoint)
   ├── withIdempotency("ai-question") -> Checks 24h in-memory idempotency cache
   ├── signed("ai-question") -> Validates request signature
   └── validated({ body: aiSchema }) -> Validates optional request body
   │
3. Pre-Execution Checks (createAiQuestion)
   │
   ├── Selects template from tipiDomanda (64 Italian prefixes)
   ├── Circuit Breaker Check (canExecute("ai-question"))
   │     └── If open (>= 5 failures within 60s): Throws SYS_FAIL_001 with static fallbackQuestion
   └── Quota Reservation (reserveAiTokens(userId, 120))
         └── If quota exceeded (> 4000 tokens/day): Logs security event & throws SEC_BLOCK_001
   │
4. AI Provider & Fallback Model Loop (generateAIQuestion)
   │
   ├── Model 1: "openrouter/free"
   │     ├── Sends POST to https://openrouter.ai/api/v1/chat/completions (timeout: 12s)
   │     ├── Cleans response (cleanAiResponse: strips markdown & non-JSON text)
   │     └── Parses & validates JSON schema (parseAiQuestion: requires {"question": "..."})
   │
   ├── Fallback Model 2: "openai/gpt-oss-120b:free" (If Model 1 throws HTTP/timeout/parse error)
   ├── Fallback Model 3: "nvidia/nemotron-3-super:free" (If Model 2 fails)
   └── If all 3 models fail: Increments circuit breaker failure counter (onFailure)
   │
5. Persistence & Database Insertion (Flutter GameRepository)
   │
   ├── Inserts into public.game_questions (partnership_id, question, status='pending', user_id_a, user_id_b)
   └── Triggers partner push notification (notifyPartnerOnce('newQuestion'))
   │
6. Voting & Partner Synchronization (Flutter GameScreen)
   │
   ├── User A votes Option A or B -> Upserts into public.game_answers (game_id, user_id, selected_option)
   ├── Realtime Broadcast -> Supabase Realtime emits INSERT on game_answers
   ├── Partner User B receives event via RealtimeSyncService -> Updates local GameState
   │
7. Result Calculation
   │
   └── When both partners have answered (hasAnswered && partnerAnswered):
         ├── Updates public.game_questions status to 'both_answered'
         ├── Evaluates Match (isMatched: userOption == partnerOption) or Disagreement
         └── Refreshes match statistics (get_game_stats RPC)
```

---

## Infrastructure Analysis & Required Questions

### 1. Quota Enforcement (`quotaService.js`)

- **Enforcement Location**: Enforced in Node.js Backend inside `createAiQuestion()` ([aiQuestion.service.js:31](file:///f:/JustUS/Backend/features/ai/aiQuestion.service.js#L31)) prior to dispatching any HTTP call to OpenRouter.
- **Limit & Budget**: Default daily token limit is **4,000 tokens per day** (`env.aiDailyTokenLimit` in [env.js:47](file:///f:/JustUS/Backend/config/env.js#L47)). Each request reserves an up-front fixed budget of **120 tokens** (`reserveAiTokens(user.profileId, 120)`).
- **Token Counting**:
  - Up-front reservation: 120 tokens subtracted from available daily budget before making the AI request.
  - Post-generation estimation: `estimateTokenCount(text)` in `aiConfig.js` estimates actual response length via `Math.max(1, Math.ceil(text.length / 4))`.
- **Reset Schedule**: Resets daily at **UTC Midnight**. `getDayKey()` returns `new Date().toISOString().slice(0, 10)` (`YYYY-MM-DD`).
- **Scope**: **Per User**. The tracking key in `aiDailyUsage` map is `${userId}:${dayKey}` using `user.profileId`.

### 2. Circuit Breaker (`circuitBreaker.js`)

- **State Location**: Lives in Node.js process **in-memory `Map`** (`circuits = new Map()`) in `Backend/core/infra/circuitBreaker.js`.
- **Threshold**: **5 consecutive failures** (`env.aiCircuitBreakerThreshold = 5`).
- **Cooldown Duration**: **60 seconds** (`env.aiCircuitBreakerCooldownMs = 60_000`).
- **State Transition**:
  - When failure count reaches 5, `openUntil` is set to `Date.now() + 60,000`.
  - While open, `canExecute("ai-question")` returns `{ allowed: false, retryAfterMs }`.
  - Throws `AppError(SYS_FAIL_001)` with error details containing `fallbackQuestion` ("Chi dei due sceglierebbe la meta migliore per una vacanza?") and `retryAfterMs`.
  - Upon any successful AI completion (`onSuccess`), `failures` and `openUntil` are reset to 0.
- **Process Restart Survival**: **NO**. Because state is stored in an in-memory `Map`, process restarts clear all circuit states (`circuits.clear()`) and reset failure counters to 0.

### 3. Idempotency Store (`idempotencyStore.js`)

- **Middleware**: `withIdempotency("ai-question")` in `ai.routes.js`.
- **Key Format**: `namespace:userId:key` built from request header `x-idempotency-key`.
- **Expiration**: Cached responses expire after **24 hours** (`24 * 60 * 60_000` ms).
- **Process Restart Survival**: **NO**. Idempotency cache is stored in Node process memory (`responses = new Map()`). Server restarts wipe all cached idempotent responses.

### 4. Concurrency & Race Condition Vulnerabilities

- **Quota Bypass**: Synchronous JavaScript map access prevents thread race conditions inside a single Node event loop execution, but if a single user dispatches multiple simultaneous asynchronous HTTP requests before the quota limit is reached, all requests will evaluate `current + tokens <= 4000` concurrently before any of them finish, exceeding the total daily budget.
- **Circuit Breaker Bypass**: Multiple concurrent requests sent while failure count is at 4 will all pass `canExecute()` simultaneously before any of them record a 5th failure.
- **Idempotency Bypass**: If two identical requests containing the same `x-idempotency-key` arrive simultaneously before the first request completes and calls `saveEntry()`, both requests will pass the `getEntry()` check and execute duplicate AI queries.

---

## AI Prompt Templates & Provider Fallback Chains

### 1. Italian Prompt Templates (`tipiDomanda`)

Defined in [aiConfig.js:4-21](file:///f:/JustUS/Backend/config/aiConfig.js#L4-L21). Contains **64 Italian question prefix templates**, categorized into:
- Comparison prefixes: `"Chi è più propenso a…"`, `"Chi è più bravo a…"`, `"Chi impiega più tempo a…"`, `"Chi è più romantico…"`, `"Chi ha più pazienza…"`.
- Preference & hypothetical prefixes: `"Quale dei due preferisce…"`, `"Quale dei due sarebbe capace di…"`, `"Quale dei due farebbe una figuraccia mentre…"`.
- Couple scenario prefixes: `"Tra voi due, chi sarebbe più adatto a…"`, `"Tra voi two, chi finirebbe per…"`, `"Chi dei due scoppierebbe a ridere mentre…"`.

### 2. OpenRouter Provider Fallback Chain

The AI provider loop iterates through array `MODELS` in [aiConfig.js:27-31](file:///f:/JustUS/Backend/config/aiConfig.js#L27-L31):

1. **Model 1 (Primary)**: `"openrouter/free"`
2. **Model 2 (Fallback 1)**: `"openai/gpt-oss-120b:free"`
3. **Model 3 (Fallback 2)**: `"nvidia/nemotron-3-super:free"`

#### Execution Logic
- Sends HTTP POST to `https://openrouter.ai/api/v1/chat/completions` with a 12-second timeout (`env.aiTimeoutMs = 12000`).
- If Model 1 throws an error (HTTP 4xx/5xx, timeout, network failure, or returns empty/invalid content), the error is caught, logged as `ai.model_failed`, and execution immediately proceeds to Model 2, then Model 3.
- If all 3 models fail, the error is thrown up to `generateQuestionController`, which calls `onAiQuestionFailure("ai-question")` to record a failure in the circuit breaker.

---

## Response Validation & Sanitization

Generated AI responses undergo multi-stage validation before being returned to the user:

1. **Markdown & Formatting Cleanup (`cleanAiResponse`)**:
   - File: [ai.utils.js:6-21](file:///f:/JustUS/Backend/features/ai/ai.utils.js#L6-L21)
   - Strips markdown code blocks (````json ... ```` or ```` ... ````).
   - Trims any trailing or leading text outside the outer JSON braces `{ ... }`.
2. **JSON Schema Parsing (`parseAiQuestion`)**:
   - File: [ai.utils.js:30-37](file:///f:/JustUS/Backend/features/ai/ai.utils.js#L30-L37)
   - Executes `JSON.parse(cleanedText)`.
   - Validates that `json.question` exists and is a non-empty string.
   - Truncates question text to a maximum of `maxTokens * 4` characters (160 * 4 = 640 chars).
   - If `JSON.parse()` fails or `question` property is missing, throws an exception, triggering the model fallback loop.

---

## Game Mechanics: A/B Options, Voting & Realtime Sync

### 1. A/B Option Mapping

- Options do **not** represent arbitrary answers; they represent the two partners.
- In `GameRepository.fetchNewGameQuestion()` ([game_repository.dart:109-113](file:///f:/JustUS/Flutter/lib/features/games/game_repository.dart#L109-L113)):
  - `userIdA` is assigned to the creator/requester of the question.
  - `userIdB` is assigned to the partner.
  - `Option A` displays `nameFor(userIdA)` ("Tu" or user's display name).
  - `Option B` displays `nameFor(userIdB)` (Partner's display name).

### 2. Voting & Answer Submission

- User selects Option A or Option B in `GameScreen`.
- Calls `GameRepository.submitAnswer(questionId, selectedOption)`.
- Executes SQL `UPSERT` on `public.game_answers` with composite conflict target `(game_id, user_id)`.
- Fires partner push notification `notifyPartnerOnce('answerSubmitted')`.

### 3. Realtime Synchronization & Match Calculation

- `RealtimeSyncService` subscribes to Postgres change events on `game_questions` and `game_answers`.
- When an `INSERT` or `UPDATE` on `game_answers` is received, `_handleGamePayload` updates local `GameState`.
- When both partners have submitted answers (`hasAnswered && partnerAnswered`):
  - Flutter calls `updateQuestionStatus(questionId, 'both_answered')` on `public.game_questions`.
  - Matches are evaluated:
    - **Match** (`isMatched`): `userOption == partnerOption` (both partners voted for the same person).
    - **Disagreement** (`isDisagreed`): `userOption != partnerOption`.
  - Invokes `get_game_stats` RPC to update total couple matches count.

---

## Discovered Bugs, Defects, and Inconsistencies

During reverse-engineering analysis, the following technical findings were identified:

### 1. DEFECT: In-Memory Infrastructure Volatility

* **WHAT**: Circuit breaker states, token quota counters, and idempotency responses are stored in Node process memory maps.
* **WHERE**: `circuitBreaker.js`, `quotaService.js`, `idempotencyStore.js`.
* **WHY**: No external cache store (such as Redis) is configured for infrastructure state management.
* **WHEN**: Backend process restarts or redeploys.
* **IMPACT**: Server restarts clear all active rate limits, token quotas, circuit breaker cooldowns, and cached idempotency keys.
* **CONFIDENCE**: **HIGH**

### 2. DEFECT: Client-Side Status Update Dependency

* **WHAT**: Updating question status to `'both_answered'` relies on the client application calling `updateQuestionStatus()`.
* **WHERE**: [game_state.dart:205 & 411](file:///f:/JustUS/Flutter/lib/features/games/game_state.dart#L205)
* **WHY**: No database trigger or backend service automatically updates `game_questions.status` when the second `game_answers` row is inserted.
* **WHEN**: Both partners answer a question, but the second answering client closes the app or loses connection before calling `updateQuestionStatus()`.
* **IMPACT**: Question remains in `'pending'` status in database, preventing new questions from being generated until manual status cleanup occurs.
* **CONFIDENCE**: **HIGH**

---

## Implementation Status Matrix

| Subsystem / Feature | Status | Notes |
|---|---|---|
| 64 Italian Question Templates | **IMPLEMENTED** | `tipiDomanda` in `aiConfig.js` |
| OpenRouter Multi-Model Fallback | **IMPLEMENTED** | 3-model chain (`free`, `gpt-oss-120b`, `nemotron-3`) |
| Response Cleaning & Validation | **IMPLEMENTED** | `cleanAiResponse` & `parseAiQuestion` |
| Daily Token Quota (4000 tokens) | **IMPLEMENTED** | `quotaService.js` (per-user, resets UTC midnight) |
| Circuit Breaker Protection | **IMPLEMENTED** | 5 failures -> 60s cooldown with static fallback |
| Idempotency Key Middleware | **IMPLEMENTED** | `withIdempotency` 24h cache |
| Partner A/B Option Mapping | **IMPLEMENTED** | Options map to couple member display names |
| Realtime Answer Sync | **IMPLEMENTED** | `RealtimeSyncService` listens to `game_answers` |
| Agreement Match Calculation | **IMPLEMENTED** | `isMatched` check & `get_game_stats` RPC |
| Persistent Infrastructure State | **NOT IMPLEMENTED** | Quotas/circuits reset on server restart (in-memory) |
| Server-Side Status Trigger | **NOT IMPLEMENTED** | Client must call `updateQuestionStatus` |

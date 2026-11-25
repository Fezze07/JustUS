# JustUS — Fixing Phase · Master Todo List

> **Purpose**: the live worklist for verified defects. Everything already closed is archived in [`docs/fixing-phase-log.md`](docs/fixing-phase-log.md) (→ Outcome by phase, → Item index, → Decisions of record).
> **This file is tracked and committed with each fix.** Rules for working an item: `.agents/skills/fix-workflow/SKILL.md`.
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target `file:line`, the exact defect, the concrete fix and acceptance criteria.
> **Finding-ID prefixes**: `17.x` media delivery, `18.x` retention/backend safety, `21.x` schema/RLS/DB invariants, `22.x` docs/dead code, `23.x` regression tests, `24.x` first-use correctness/security, `25.x` validation and CI.
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

**Latest audit baseline (2026-11-24, branch `dev`)**: Flutter analysis clean and **439 tests passed**; `Backend/npm test` **305 passed / 27 suites**, lint 0 errors / 4 warnings; backend syntax and circular-dependency checks passed; duplication scan exited 0 (with reported clones). `npm run validate` could not start in this Windows PowerShell environment because `bash` is unavailable. SQL scripts were not run locally (no `bash` or `psql`); read-only checks against the linked Supabase project are documented in the audit. The Android debug build did not complete with the installed JDK 26; a build on the CI's JDK 21 and a signed release build remain unverified.

---

## Phase 0 — Ground truth & safety net

- [ ] **0.1 Re-run the baseline before touching anything**
  - Commands: `cd Flutter && flutter analyze && flutter test`; `cd Backend && npm test && npm run check && npm run madge:circular`; root `npm run scan:duplicates`.
  - Latest observed: 439 Flutter tests pass and analysis is clean; 305 backend tests / 27 suites pass, lint has 0 errors / 4 warnings; syntax, circular-dependency and duplication commands exit 0.
  - `npm run validate` currently stops before checks on this Windows host because it invokes `bash`; SQL tests were not run locally.
  - Acceptance: the baseline is reproducible in the chosen CI environment, including SQL tests, and any runner limitations are resolved or documented.

- [ ] **0.2 Confirm the migration/apply path before any SQL item**
  - `supabase/schemas/**` is the source of truth; there are no tracked migrations. Applying a schema change means `npx supabase@3.3.0 db query --remote --yes --file <script>.sql` (fix-workflow §1.9).
  - Acceptance: the linked project is reachable, or every Phase 21 item is explicitly left `Unverified` with the query that still needs to run.

---

## Phase 24 — First-use correctness & security (🟠 HIGH / 🟡 MEDIUM)

### 24.1 Make active game-question creation atomic (🟡 MEDIUM)
- [x] **Status: ✅ FIXED (2026-11-25, on `dev`)** — Added `public.game_get_or_create_question(integer, text[])` (`supabase/schemas/public/functions/game_get_or_create_question.sql:1-106`) locking the `accepted` `partnerships` row `FOR UPDATE`, returning any active row (`created=false`) or calling `game_pick_question` + inserting `'pending'` (`created=true`); added partial unique index `idx_game_questions_one_active_per_partnership` (`supabase/schemas/public/tables/game_questions.sql:28`); updated `GameRepository.fetchNewGameQuestion` (`Flutter/lib/features/games/game_repository.dart:86-127`) to call the RPC and notify only when `created == true`. Applied to remote DB. · **Verification**: `npx supabase@3.3.0 db query --remote --yes --file supabase/test/game_get_or_create_question.test.sql` passed; `flutter analyze` clean; `flutter test test/game_get_or_create_question_test.dart test/game_state_test.dart` 15 passed. · **Residual**: no two-client concurrent barrier test was run against a live staging session; concurrency serialization relies on `FOR UPDATE` on `partnerships` and the partial unique index.
- **Sources**: no doc — current-code review.
- **Files**: `Flutter/lib/features/games/game_repository.dart:87-91,118-123,186-191`, `Flutter/lib/features/games/game_state.dart:241-243`, `Flutter/lib/features/games/screens/game_screen.dart:345`, `supabase/schemas/public/tables/game_questions.sql:9-12`.
- **Defect**: each device checks for an active question and then inserts in separate requests; `_isFetchingQuestion` only serializes one `GameState` instance. When both partners press “try again” together, both can observe no active row and insert different pending questions. The table has no uniqueness constraint for one active question per partnership, and the reader returns only the newest row; before Realtime converges the clients (or while one is offline), an answer to the other row can become detached from the visible game.
- **Fix**: move “return the active question or create one” into one database transaction/RPC, with a partnership-level lock or equivalent uniqueness guarantee, and return the winning row to both callers.
- **Unverified — needs** two authenticated staging clients; no live concurrent reproduction was run.
- **Acceptance**: a concurrency test starts two create requests for the same partnership behind a barrier; both receive the same question ID and exactly one active question row exists.

### 24.2 Fail closed when Android release signing is missing (🟠 HIGH)
- **Sources**: `README.md:177` documents APK distribution and in-app updates.
- **Files**: `Flutter/android/app/build.gradle.kts:11-12,53-57`, `.gitignore:26`.
- **Defect**: on a clean checkout without the ignored `key.properties`, `release` silently uses the debug signing config. APKs built on different machines may have different debug certificates, so a real couple cannot install the next release over the existing app; debug signing is also not a production release identity.
- **Fix**: make release builds fail unless a protected production keystore is explicitly configured; never silently substitute the debug key.
- **Acceptance**: a release build without signing configuration fails with a clear message; two consecutive configured releases report the same expected certificate and Android installs the second as an update to the first.

### 24.3 Keep partnership routing state consistent (🟡 MEDIUM)
- **Sources**: no doc — current-code review.
- **Files**: `Flutter/lib/features/auth/auth_state.dart:351-363,670-683`, `Flutter/lib/shared/utils/auth/auth_navigation_utils.dart:29-43`, `Flutter/lib/features/partnership/partner_state.dart:92-105`, `Flutter/lib/features/home/screens/main_shell.dart:130-147`.
- **Defect**: if the partnership read in `AuthState.login()` fails, it is swallowed and login still succeeds with `AuthState.hasPartner == false`. The route helper performs another read and can select `MainShell` using `PartnerState.partner != null`, but `MainShell` checks only `AuthState.hasPartner` and redirects back to `PartnerScreen`. `PartnerState._applyPartnership()` updates its own state and storage without reconciling `AuthState`, so a transient failure followed by a successful retry can leave the user unable to enter the shared app.
- **Fix**: make post-auth partnership resolution update one canonical state before selecting a route; have the shell and route helper use the same resolved membership state. Do not treat a failed lookup as proof that the user has no partner.
- **Unverified — needs** a focused Flutter regression test for the failure-then-success sequence; the state mismatch is verified statically, but no runtime reproduction was run.
- **Acceptance**: a test makes the login-time partnership read fail and the route-time read succeed; routing settles in `MainShell`, `AuthState` and `PartnerState` agree on the partnership, and the shell does not redirect back to `PartnerScreen`.

---

## Known non-bugs & deliberate decisions

- **Shared media rate-limit bucket (40/user/min for reads, uploads and deletes)** — deliberate, recorded in `docs/audits/media-delete-audit.md` §F-5. Do not "fix" without a product decision.
- **15 MB pre-compression upload cap** — deliberate (phase 5.4).
- **Fingerprint survives logout** — deliberate (phase 10.1); `docs/app/storage-and-caching/doc.md:51,207` is correct.
- **Notification preference is device-level across accounts** — documented in `storage_service.dart:446-452`; distinct from the background-delivery bug archived as 19.7.
- **Homepage does not use `TabScreenMixin`; Profile is not wired to realtime** — documented in `docs/app/architecture/doc.md:460-464` and `docs/app/state-management/doc.md:140`.
- **`debug_` table/function prefix** — deliberate (phase 10.17).
- **Nonce fail-open, `session_is_live` fail-open, orphan-sweep read-failure skip** — accepted decisions #36, #37, #45 in `docs/fixing-phase-log.md`.
- **Authenticated `SECURITY DEFINER` partnership read RPCs** — the live advisor flags `partnership_get_cancellation()` and `partnership_get_pending_invitations()`, but both functions filter through `user_current_id()` (`users.auth_id = auth.uid()`) and return only the caller's own partnership rows; anonymous execution is revoked. Do not revoke without preserving the client flow.
- **Supabase RLS status** — a read-only live catalog query found RLS enabled on all 26 public tables. This does not replace per-policy behavior tests.
- **Unused-index advisor notices** — not treated as removal tasks: low/zero usage on this project's current traffic is not proof an index is dead.

---

## Not confirmed (do not track as fixes until reproduced)

S6 mood recent chips · S7 first drive tile highlight · S9 302 forwards `Authorization` to R2 · S10 legacy token without `session_id` · S11 cancellation cleanup race · S12 timeout double-response · S13 idempotency caches errors · S14 custom rate-limit window · S15 logger stdout before sanitization · S16 pre-relationship moods · S17 crafted `drive_items` key (closed by 17.2) · S18 missing `seed.sql` (archived as 21.10, see `docs/fixing-phase-log.md` § Item index) · S19 hosted SQL test privileges · S20 `game_questions` FKs without `ON DELETE`
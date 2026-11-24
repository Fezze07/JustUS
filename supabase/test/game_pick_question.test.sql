-- =============================================================================
-- game_pick_question: one-row catalogue selection at 1,000+ rows (report Q3)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/game_pick_question.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   990001/990002 accepted partnership 990001
--   990003 is not a member of 990001
--   Locale zz-pick-en: pick_en_played (played), pick_en_new (unplayed)
--   Locale zz-pick-it: pick_it_new (unplayed)
-- The zz-pick-* locales keep the assertions independent of the real catalogue.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000990001', 'game-pick-a@test.local'),
  ('00000000-0000-0000-0000-000000990002', 'game-pick-b@test.local'),
  ('00000000-0000-0000-0000-000000990003', 'game-pick-c@test.local');

DELETE FROM public.users
WHERE auth_id IN (
  '00000000-0000-0000-0000-000000990001',
  '00000000-0000-0000-0000-000000990002',
  '00000000-0000-0000-0000-000000990003'
);

INSERT INTO public.users (id, auth_id, email) VALUES
  (990001, '00000000-0000-0000-0000-000000990001', 'game-pick-a@test.local'),
  (990002, '00000000-0000-0000-0000-000000990002', 'game-pick-b@test.local'),
  (990003, '00000000-0000-0000-0000-000000990003', 'game-pick-c@test.local');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (990001, 990001, 990002, 'accepted');

INSERT INTO public.game_question_bank (question_code, locale, text) VALUES
  ('pick_en_played', 'zz-pick-en', 'Played English'),
  ('pick_en_new',    'zz-pick-en', 'New English'),
  ('pick_it_new',    'zz-pick-it', 'New Italian');

INSERT INTO public.game_questions (partnership_id, question_code, user_id_a, user_id_b) VALUES
  (990001, 'pick_en_played', 990001, 990002);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000990001","role":"authenticated"}';

DO $$
DECLARE
  v_item public.game_question_bank;
BEGIN
  -- A: unplayed English wins over the played English row.
  v_item := public.game_pick_question(990001, ARRAY['zz-pick-en', 'zz-pick-it']);
  IF v_item.question_code IS DISTINCT FROM 'pick_en_new' THEN
    RAISE EXCEPTION 'A failed: expected pick_en_new, got %', v_item.question_code;
  END IF;

  -- B: a locale with no rows is skipped in favour of the next one.
  v_item := public.game_pick_question(990001, ARRAY['zz-pick-missing', 'zz-pick-it']);
  IF v_item.question_code IS DISTINCT FROM 'pick_it_new' THEN
    RAISE EXCEPTION 'B failed: expected pick_it_new, got %', v_item.question_code;
  END IF;

  -- C: when the first locale with rows is exhausted, replay one of its rows
  -- instead of falling through to the next locale.
  INSERT INTO public.game_questions
    (partnership_id, question_code, user_id_a, user_id_b)
  VALUES
    (990001, 'pick_en_new', 990001, 990002);

  v_item := public.game_pick_question(990001, ARRAY['zz-pick-en', 'zz-pick-it']);
  IF v_item.question_code NOT IN ('pick_en_played', 'pick_en_new') THEN
    RAISE EXCEPTION 'C failed: expected an English replay, got %',
      v_item.question_code;
  END IF;

  -- D: no catalogue row in any chained locale returns NULL.
  v_item := public.game_pick_question(990001, ARRAY['zz-pick-empty']);
  IF v_item.question_code IS NOT NULL THEN
    RAISE EXCEPTION 'D failed: expected no row, got %', v_item.question_code;
  END IF;
END $$;

RESET ROLE;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000990003","role":"authenticated"}';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_item public.game_question_bank;
BEGIN
  -- E: a user outside the partnership gets no row.
  v_item := public.game_pick_question(990001, ARRAY['zz-pick-en', 'zz-pick-it']);
  IF v_item.question_code IS NOT NULL THEN
    RAISE EXCEPTION 'E failed: a non-member picked %', v_item.question_code;
  END IF;
END $$;

ROLLBACK;

SELECT 'game-pick-question: passed (unplayed first, locale order, replay fallback, non-member null)' AS result;

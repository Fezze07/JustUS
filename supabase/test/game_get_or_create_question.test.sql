-- =============================================================================
-- game_get_or_create_question: atomic active-question get-or-create + unique index
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/game_get_or_create_question.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
-- =============================================================================

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000990101', 'game-atomic-a@test.local'),
  ('00000000-0000-0000-0000-000000990102', 'game-atomic-b@test.local'),
  ('00000000-0000-0000-0000-000000990103', 'game-atomic-c@test.local');

DELETE FROM public.users
WHERE auth_id IN (
  '00000000-0000-0000-0000-000000990101',
  '00000000-0000-0000-0000-000000990102',
  '00000000-0000-0000-0000-000000990103'
);

INSERT INTO public.users (id, auth_id, email) VALUES
  (990101, '00000000-0000-0000-0000-000000990101', 'game-atomic-a@test.local'),
  (990102, '00000000-0000-0000-0000-000000990102', 'game-atomic-b@test.local'),
  (990103, '00000000-0000-0000-0000-000000990103', 'game-atomic-c@test.local');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (990101, 990101, 990102, 'accepted');

INSERT INTO public.game_question_bank (question_code, locale, text) VALUES
  ('atomic_en_1', 'zz-atomic-en', 'Atomic Question 1'),
  ('atomic_en_2', 'zz-atomic-en', 'Atomic Question 2');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000990101","role":"authenticated"}';

DO $$
DECLARE
  v_first jsonb;
  v_active_count integer;
  v_unique_violated boolean := false;
BEGIN
  -- A: first call creates a new pending question.
  v_first := public.game_get_or_create_question(990101, ARRAY['zz-atomic-en']);
  IF v_first IS NULL OR (v_first->>'created')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'A failed: expected created=true, got %', v_first;
  END IF;
  IF (v_first->>'status') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'A failed: expected status=pending, got %', v_first;
  END IF;

  -- C: partial unique index blocks a second active row for the same partnership.
  BEGIN
    INSERT INTO public.game_questions (partnership_id, question_code, status, user_id_a, user_id_b)
    VALUES (990101, 'atomic_en_2', 'pending', 990101, 990102);
  EXCEPTION WHEN unique_violation THEN
    v_unique_violated := true;
  END;
  IF NOT v_unique_violated THEN
    RAISE EXCEPTION 'C failed: partial unique index did not reject second active row';
  END IF;

  SELECT count(*) INTO v_active_count
  FROM public.game_questions
  WHERE partnership_id = 990101
    AND status IS DISTINCT FROM 'both_answered';
  IF v_active_count <> 1 THEN
    RAISE EXCEPTION 'C failed: expected 1 active row, got %', v_active_count;
  END IF;
END $$;

-- B: partner calling concurrently/afterwards receives the same active question with created=false.
RESET ROLE;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000990102","role":"authenticated"}';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_existing_id integer;
  v_second jsonb;
  v_third jsonb;
BEGIN
  SELECT id INTO v_existing_id
  FROM public.game_questions
  WHERE partnership_id = 990101
    AND status IS DISTINCT FROM 'both_answered';

  v_second := public.game_get_or_create_question(990101, ARRAY['zz-atomic-en']);
  IF (v_second->>'id')::integer IS DISTINCT FROM v_existing_id
     OR (v_second->>'created')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'B failed: expected existing id % with created=false, got %', v_existing_id, v_second;
  END IF;

  -- D: once the active row is marked both_answered, a new active row can be created.
  UPDATE public.game_questions SET status = 'both_answered' WHERE id = v_existing_id;

  v_third := public.game_get_or_create_question(990101, ARRAY['zz-atomic-en']);
  IF v_third IS NULL
     OR (v_third->>'created')::boolean IS NOT TRUE
     OR (v_third->>'id')::integer = v_existing_id THEN
    RAISE EXCEPTION 'D failed: expected new question after both_answered, got %', v_third;
  END IF;

  -- E: empty catalog returns NULL when no active question exists.
  UPDATE public.game_questions SET status = 'both_answered' WHERE id = (v_third->>'id')::integer;
  IF public.game_get_or_create_question(990101, ARRAY['zz-atomic-empty']) IS NOT NULL THEN
    RAISE EXCEPTION 'E failed: expected NULL for empty catalog';
  END IF;
END $$;

-- F: non-member returns NULL.
RESET ROLE;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000990103","role":"authenticated"}';
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  IF public.game_get_or_create_question(990101, ARRAY['zz-atomic-en']) IS NOT NULL THEN
    RAISE EXCEPTION 'F failed: non-member received a question';
  END IF;
END $$;

ROLLBACK;

SELECT 'game-get-or-create-question: passed (atomic create, idempotent partner read, unique index, both_answered transition, empty catalog, non-member)' AS result;

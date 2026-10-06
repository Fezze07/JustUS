-- =============================================================================
-- updated_at cursor triggers
-- (covers audit finding 4.3: game_answers / bucket_items must bump updated_at on
--  UPDATE so hasChanges detects partner answer and done-toggle changes)
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/updated_at_triggers.test.sql
--
-- Notes on how the timestamps are asserted:
--   * The trigger functions set NEW.updated_at = now(), and now() is
--     transaction-stable. Comparing two updates inside one transaction would
--     always show equal values, so each fixture row is re-seeded with an
--     explicitly old timestamp and the assertion is that the timestamp
--     ADVANCED past that seed. The re-seed uses DELETE + INSERT because an
--     UPDATE would fire the very trigger under test.
--   * Every comparison checks IS NULL first. `NULL <= x` evaluates to NULL, so
--     an unset updated_at would silently satisfy a naive "<=" assertion.
--   * The behaviour is exercised as the signed-in partner and as service_role,
--     because the trigger has to fire on the client write path too.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9001 alice <-> 9002 bob : 9001 accepted partnership
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@rt4-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@rt4-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'RT4AAA'),
  (9002, 'Bob',   'RT4BBB');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9001, 9001, 9002, 'accepted');

INSERT INTO public.game_questions (id, partnership_id, question_code, status, user_id_a, user_id_b) VALUES
  (9001, 9001, 'game_q_checkpoint', 'pending', 9001, 9002);

-- The wording lives in the bank now, so the code above is seeded there too.
INSERT INTO public.game_question_bank (question_code, locale, text) VALUES
  ('game_q_checkpoint', 'it', 'Mandatory checkpoint test question');

-- Every fixture row carries a 2020-01-01 timestamp pair, so an advancing
-- trigger is unmistakable.
INSERT INTO public.bucket_items (id, text, partnership_id, created_at, updated_at) VALUES
  (9001, 'checkpoint bucket item', 9001,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz);

-- Pre-flight
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users          WHERE id IN (9001, 9002)) <> 2
     OR (SELECT count(*) FROM public.partnerships WHERE id = 9001) <> 1
     OR (SELECT count(*) FROM public.bucket_items WHERE id = 9001) <> 1
     OR (SELECT count(*) FROM public.game_questions WHERE id = 9001) <> 1 THEN
    RAISE EXCEPTION 'fixture failed: the checkpoint fixtures are incomplete';
  END IF;
  IF (SELECT updated_at FROM public.bucket_items WHERE id = 9001)
       IS DISTINCT FROM '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'fixture failed: bucket_items.updated_at was not seeded to 2020-01-01';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A: updated_at columns exist and the expected triggers are present
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'game_answers'
      AND column_name = 'updated_at'
  ) THEN
    RAISE EXCEPTION 'A failed: game_answers.updated_at missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bucket_items'
      AND column_name = 'updated_at'
  ) THEN
    RAISE EXCEPTION 'A failed: bucket_items.updated_at missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_schema = 'public' AND event_object_table = 'game_answers'
      AND trigger_name = 'set_public_game_answers_updated_at'
  ) THEN
    RAISE EXCEPTION 'A failed: set_public_game_answers_updated_at trigger missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_schema = 'public' AND event_object_table = 'bucket_items'
      AND trigger_name = 'set_public_bucket_items_updated_at'
  ) THEN
    RAISE EXCEPTION 'A failed: set_public_bucket_items_updated_at trigger missing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A2. Sweep: every public table with an updated_at column must carry an enabled
--     BEFORE UPDATE trigger. Checking only the two tables named in finding 4.3
--     would let a trigger go missing on any other table unnoticed.
--
--     Read from pg_trigger as the owner: information_schema hides rows the
--     current role may not see, so the sweep could silently check nothing.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r       record;
  v_checked int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tbl
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE a.attrelid = c.oid
          AND a.attname = 'updated_at'
          AND NOT a.attisdropped
          AND a.attnum > 0
      )
    ORDER BY c.relname
  LOOP
    v_checked := v_checked + 1;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_trigger t
      JOIN pg_class c2 ON c2.oid = t.tgrelid
      JOIN pg_namespace n2 ON n2.oid = c2.relnamespace
      WHERE n2.nspname = 'public'
        AND c2.relname = r.tbl
        AND NOT t.tgisinternal
        AND t.tgenabled <> 'D'
        AND (t.tgtype::int & 2) <> 0    -- BEFORE  (INSTEAD OF is 64)
        AND (t.tgtype::int & 64) = 0
        AND (t.tgtype::int & 16) <> 0   -- UPDATE
    ) THEN
      RAISE EXCEPTION 'A2 failed: public.% has an updated_at column but no enabled BEFORE UPDATE trigger', r.tbl;
    END IF;
  END LOOP;

  -- The sweep must not have iterated over an empty set, which would pass.
  IF v_checked < 8 THEN
    RAISE EXCEPTION 'A2 failed: the sweep only covered % table(s); expected at least 8', v_checked;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B: the bucket done-toggle (the hasChanges signal) advances updated_at.
--    Run as the signed-in partner, since that is the client write path.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

DO $$
DECLARE
  v_rows       int;
  v_updated_at timestamptz;
  v_created_at timestamptz;
BEGIN
  UPDATE public.bucket_items SET done = true WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'B failed: the done-toggle matched % row(s)', v_rows;
  END IF;

  SELECT created_at, updated_at INTO v_created_at, v_updated_at
    FROM public.bucket_items WHERE id = 9001;

  IF v_updated_at IS NULL THEN
    RAISE EXCEPTION 'B failed: bucket_items.updated_at is NULL after the toggle';
  END IF;
  IF v_updated_at <= v_created_at THEN
    RAISE EXCEPTION 'B failed: bucket_items updated_at (%) did not advance past the seeded value (%)',
      v_updated_at, v_created_at;
  END IF;
  IF (SELECT done FROM public.bucket_items WHERE id = 9001) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'B failed: bucket_items.done was not set';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C-prep: re-seed the answer row at 2020-01-01 so the next UPDATE has to move
--         updated_at forward to be considered a pass.
-- ---------------------------------------------------------------------------
RESET ROLE;
DELETE FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002;
INSERT INTO public.game_answers (game_id, user_id, selected_option, created_at, updated_at) VALUES
  (9001, 9002, 1,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz);

-- C: changing an answer advances updated_at, and the new option is stored.
--    Run as bob, the owner of the answer row: the game_answers update policy is
--    self-scoped, so alice matching 0 rows here would be correct RLS, not a bug.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';
DO $$
DECLARE
  v_rows       int;
  v_updated_at timestamptz;
BEGIN
  UPDATE public.game_answers
    SET selected_option = 2
    WHERE game_id = 9001 AND user_id = 9002;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'C failed: the answer change matched % row(s)', v_rows;
  END IF;

  SELECT updated_at INTO v_updated_at
    FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002;

  IF v_updated_at IS NULL THEN
    RAISE EXCEPTION 'C failed: game_answers.updated_at is NULL after the change';
  END IF;
  IF v_updated_at <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'C failed: game_answers updated_at (%) did not advance past the seeded value', v_updated_at;
  END IF;
  IF (SELECT selected_option FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002)
       IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'C failed: selected_option was not updated';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D-prep: re-seed again for the ON CONFLICT path.
-- ---------------------------------------------------------------------------
RESET ROLE;
DELETE FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002;
INSERT INTO public.game_answers (game_id, user_id, selected_option, created_at, updated_at) VALUES
  (9001, 9002, 1,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';

-- D: ON CONFLICT DO UPDATE (the client submitAnswer path) also advances
--    updated_at, without duplicating the answer row.
DO $$
DECLARE
  v_updated_at timestamptz;
BEGIN
  INSERT INTO public.game_answers (game_id, user_id, selected_option)
    VALUES (9001, 9002, 3)
    ON CONFLICT (game_id, user_id)
    DO UPDATE SET selected_option = EXCLUDED.selected_option;

  SELECT updated_at INTO v_updated_at
    FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002;

  IF v_updated_at IS NULL THEN
    RAISE EXCEPTION 'D failed: game_answers.updated_at is NULL after ON CONFLICT DO UPDATE';
  END IF;
  IF v_updated_at <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'D failed: ON CONFLICT DO UPDATE left updated_at at %', v_updated_at;
  END IF;
  IF (SELECT selected_option FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002)
       IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'D failed: ON CONFLICT DO UPDATE did not store the new option';
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9001 AND user_id = 9002) <> 1 THEN
    RAISE EXCEPTION 'D failed: ON CONFLICT DO UPDATE duplicated the answer row';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E-prep: a drive_items row seeded at 2020-01-01 for the service_role check.
-- ---------------------------------------------------------------------------
RESET ROLE;
INSERT INTO public.drive_items (id, type, name, partnership_id, created_at, updated_at) VALUES
  (9001, 'image', 'checkpoint.png', 9001,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz);

-- ---------------------------------------------------------------------------
-- E: service_role writes bump updated_at too, so a backend-driven change is
--    not invisible to a client polling for changes.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_rows       int;
  v_updated_at timestamptz;
BEGIN
  UPDATE public.drive_items SET name = 'renamed-by-service.png' WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'E failed: the service_role update matched % row(s)', v_rows;
  END IF;

  SELECT updated_at INTO v_updated_at FROM public.drive_items WHERE id = 9001;
  IF v_updated_at IS NULL THEN
    RAISE EXCEPTION 'E failed: drive_items.updated_at is NULL after a service_role update';
  END IF;
  IF v_updated_at <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'E failed: service_role update left updated_at at %', v_updated_at;
  END IF;
END $$;

ROLLBACK;

SELECT 'updated_at-triggers: passed (pre-flight, A columns+triggers, A2 full trigger sweep, B bucket done-toggle, C answer change, D ON CONFLICT DO UPDATE, E service_role)' AS result;
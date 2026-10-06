-- =============================================================================
-- Shared tables carry an explicit WITH CHECK
-- (covers audit finding 2.3: FOR ALL policies on partnership-scoped tables)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_shared_table_with_check.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
--
-- The four partnership-scoped tables share the same policy shape, so a table
-- that silently dropped out of the sweep would go unnoticed if the leak check
-- only looked at one of them. Every table is therefore probed on its own.
-- =============================================================================

BEGIN;

-- Runs a statement and returns the SQLSTATE it raised, or NULL if it
-- succeeded. Used so a rejection can be asserted to be exactly 42501
-- (insufficient_privilege) rather than any error at all.
CREATE FUNCTION pg_temp.rls_try(p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  RETURN v_state;
END $$;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9001 alice <-> 9002 bob    : 9001 accepted partnership
--   9001 alice <-> 9003 carol  : 9002 pending partnership
--   9001 alice <-> 9004 dave   : 9003 rejected partnership
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@rls-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@rls-test.local'),
  (9003, '00000000-0000-0000-0000-000000000003', 'carol@rls-test.local'),
  (9004, '00000000-0000-0000-0000-000000000004', 'dave@rls-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'ALICE1'),
  (9002, 'Bob',   'BOB222'),
  (9003, 'Carol', 'CAROL3'),
  (9004, 'Dave',  'DAVE44');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9001, 9001, 9002, 'accepted'),
  (9002, 9001, 9003, 'pending'),
  (9003, 9001, 9004, 'rejected');

INSERT INTO public.drive_items (id, type, name, partnership_id) VALUES
  (9010, 'image', 'accepted-photo.png', 9001),
  (9011, 'image', 'pending-photo.png',  9002),
  (9012, 'image', 'rejected-photo.png', 9003);

INSERT INTO public.bucket_items (id, text, partnership_id) VALUES
  (9020, 'accepted-bucket', 9001),
  (9021, 'pending-bucket',  9002),
  (9022, 'rejected-bucket', 9003);

INSERT INTO public.missyou (id, partnership_id) VALUES
  (9030, 9001),
  (9031, 9002),
  (9032, 9003);

INSERT INTO public.game_questions (id, partnership_id, question_code, user_id_a, user_id_b) VALUES
  (9040, 9001, 'game_q_accepted', 9001, 9002),
  (9041, 9002, 'game_q_pending',  9001, 9003),
  (9042, 9003, 'game_q_rejected', 9001, 9004);

-- The wording lives in the bank now, so the codes above are seeded there too.
INSERT INTO public.game_question_bank (question_code, locale, text) VALUES
  ('game_q_accepted',      'it', 'accepted-q'),
  ('game_q_pending',       'it', 'pending-q'),
  ('game_q_rejected',      'it', 'rejected-q'),
  ('game_q_accepted_new',  'it', 'accepted-new-q');

-- Pre-flight: a fixture that failed to insert would leave every "must be 0"
-- leak assertion satisfied for the wrong reason.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.drive_items    WHERE id IN (9010, 9011, 9012)) <> 3
     OR (SELECT count(*) FROM public.bucket_items   WHERE id IN (9020, 9021, 9022)) <> 3
     OR (SELECT count(*) FROM public.missyou        WHERE id IN (9030, 9031, 9032)) <> 3
     OR (SELECT count(*) FROM public.game_questions WHERE id IN (9040, 9041, 9042)) <> 3 THEN
    RAISE EXCEPTION 'fixture failed: the shared-row fixtures are incomplete';
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = 9001) IS DISTINCT FROM 'accepted'
     OR (SELECT status FROM public.partnerships WHERE id = 9002) IS DISTINCT FROM 'pending'
     OR (SELECT status FROM public.partnerships WHERE id = 9003) IS DISTINCT FROM 'rejected' THEN
    RAISE EXCEPTION 'fixture failed: the partnership statuses are not as intended';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Assertions evaluated as `authenticated` = alice
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

-- A. writes into the accepted partnership still work (no regression).
--    The row counts are what is asserted: a write that RLS filtered out would
--    not raise, so checking only for "no exception" would pass either way.
DO $$
DECLARE
  v_rows  int;
  v_rows2 int;
  v_rows3 int;
  v_rows4 int;
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_items (id, type, name, partnership_id)
    VALUES (9110, 'image', 'accepted-new.png', 9001)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A failed: drive_items insert into the accepted partnership raised %', v_state;
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.bucket_items (id, text, partnership_id)
    VALUES (9111, 'accepted-new-bucket', 9001)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A failed: bucket_items insert into the accepted partnership raised %', v_state;
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.missyou (id, partnership_id) VALUES (9112, 9001)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A failed: missyou insert into the accepted partnership raised %', v_state;
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_questions (id, partnership_id, question_code, user_id_a, user_id_b)
    VALUES (9113, 9001, 'game_q_accepted_new', 9001, 9002)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A failed: game_questions insert into the accepted partnership raised %', v_state;
  END IF;

  -- All four rows must actually be visible to alice, otherwise the inserts
  -- were no-ops.
  IF (SELECT count(*) FROM public.drive_items    WHERE id = 9110) <> 1
     OR (SELECT count(*) FROM public.bucket_items   WHERE id = 9111) <> 1
     OR (SELECT count(*) FROM public.missyou        WHERE id = 9112) <> 1
     OR (SELECT count(*) FROM public.game_questions WHERE id = 9113) <> 1 THEN
    RAISE EXCEPTION 'A failed: a row inserted into the accepted partnership is not readable back';
  END IF;

  UPDATE public.drive_items    SET name = 'renamed.png'     WHERE id = 9010;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A failed: drive_items update matched % row(s)', v_rows;
  END IF;

  UPDATE public.bucket_items   SET done = true              WHERE id = 9020;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A failed: bucket_items update matched % row(s)', v_rows;
  END IF;

  UPDATE public.missyou        SET created_at = now()       WHERE id = 9030;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A failed: missyou update matched % row(s)', v_rows;
  END IF;

  UPDATE public.game_questions SET status = 'both_answered'  WHERE id = 9040;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A failed: game_questions update matched % row(s)', v_rows;
  END IF;

  DELETE FROM public.drive_items    WHERE id = 9110;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  DELETE FROM public.bucket_items   WHERE id = 9111;
  GET DIAGNOSTICS v_rows2 = ROW_COUNT;
  DELETE FROM public.missyou        WHERE id = 9112;
  GET DIAGNOSTICS v_rows3 = ROW_COUNT;
  DELETE FROM public.game_questions WHERE id = 9113;
  GET DIAGNOSTICS v_rows4 = ROW_COUNT;

  IF v_rows <> 1 OR v_rows2 <> 1 OR v_rows3 <> 1 OR v_rows4 <> 1 THEN
    RAISE EXCEPTION 'A failed: delete matched %, %, %, % row(s) (expected 1 each)',
      v_rows, v_rows2, v_rows3, v_rows4;
  END IF;

  IF (SELECT count(*) FROM public.drive_items    WHERE id IN (9110, 9111, 9112, 9113)) <> 0
     OR (SELECT count(*) FROM public.bucket_items   WHERE id IN (9110, 9111, 9112, 9113)) <> 0
     OR (SELECT count(*) FROM public.missyou        WHERE id IN (9110, 9111, 9112, 9113)) <> 0
     OR (SELECT count(*) FROM public.game_questions WHERE id IN (9110, 9111, 9112, 9113)) <> 0 THEN
    RAISE EXCEPTION 'A failed: a delete did not remove the row';
  END IF;
END $$;

-- B. INSERT into a pending partnership must be rejected with 42501 on all four
--    tables, and the leak check must cover all four tables too.
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_items (id, type, name, partnership_id)
    VALUES (9120, 'image', 'pending-insert.png', 9002)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: drive_items insert into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.bucket_items (id, text, partnership_id)
    VALUES (9121, 'pending-insert', 9002)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: bucket_items insert into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.missyou (id, partnership_id) VALUES (9122, 9002)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: missyou insert into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_questions (id, partnership_id, question_code, user_id_a, user_id_b)
    VALUES (9123, 9002, 'game_q_pending', 9001, 9003)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: game_questions insert into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- C. INSERT into a rejected partnership must be rejected with 42501.
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_items (id, type, name, partnership_id)
    VALUES (9130, 'image', 'rejected-insert.png', 9003)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C failed: drive_items insert into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.bucket_items (id, text, partnership_id)
    VALUES (9131, 'rejected-insert', 9003)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C failed: bucket_items insert into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.missyou (id, partnership_id) VALUES (9132, 9003)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C failed: missyou insert into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_questions (id, partnership_id, question_code, user_id_a, user_id_b)
    VALUES (9133, 9003, 'game_q_rejected', 9001, 9004)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C failed: game_questions insert into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- D. UPDATE that moves a row out of the accepted partnership must be rejected:
--    the explicit WITH CHECK guards the NEW row.
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.drive_items SET partnership_id = 9002 WHERE id = 9010$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: drive_items moved into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.bucket_items SET partnership_id = 9003 WHERE id = 9020$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: bucket_items moved into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.missyou SET partnership_id = 9002 WHERE id = 9030$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: missyou moved into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.game_questions SET partnership_id = 9003 WHERE id = 9040$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: game_questions moved into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  -- The moves must not have partially applied on any table.
  IF (SELECT partnership_id FROM public.drive_items    WHERE id = 9010) IS DISTINCT FROM 9001
     OR (SELECT partnership_id FROM public.bucket_items   WHERE id = 9020) IS DISTINCT FROM 9001
     OR (SELECT partnership_id FROM public.missyou        WHERE id = 9030) IS DISTINCT FROM 9001
     OR (SELECT partnership_id FROM public.game_questions WHERE id = 9040) IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'D failed: a partnership_id changed despite the rejection';
  END IF;
END $$;

-- B/C/D-post. Verify no rejected row was persisted, with the RLS bypass in
-- place: alice cannot read the pending/rejected partnerships, so checking as
-- alice would see nothing and "pass" regardless.
RESET ROLE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.drive_items    WHERE id IN (9120, 9130))
     OR EXISTS (SELECT 1 FROM public.bucket_items   WHERE id IN (9121, 9131))
     OR EXISTS (SELECT 1 FROM public.missyou        WHERE id IN (9122, 9132))
     OR EXISTS (SELECT 1 FROM public.game_questions WHERE id IN (9123, 9133)) THEN
    RAISE EXCEPTION 'B/C failed: a rejected row was persisted';
  END IF;
  IF (SELECT partnership_id FROM public.drive_items    WHERE id = 9011) IS DISTINCT FROM 9002
     OR (SELECT partnership_id FROM public.bucket_items   WHERE id = 9021) IS DISTINCT FROM 9002
     OR (SELECT partnership_id FROM public.missyou        WHERE id = 9031) IS DISTINCT FROM 9002
     OR (SELECT partnership_id FROM public.game_questions WHERE id = 9041) IS DISTINCT FROM 9002 THEN
    RAISE EXCEPTION 'D failed: a pending-partnership row was modified';
  END IF;
  IF (SELECT partnership_id FROM public.drive_items    WHERE id = 9012) IS DISTINCT FROM 9003
     OR (SELECT partnership_id FROM public.bucket_items   WHERE id = 9022) IS DISTINCT FROM 9003
     OR (SELECT partnership_id FROM public.missyou        WHERE id = 9032) IS DISTINCT FROM 9003
     OR (SELECT partnership_id FROM public.game_questions WHERE id = 9042) IS DISTINCT FROM 9003 THEN
    RAISE EXCEPTION 'D failed: a rejected-partnership row was modified';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- anon must be able neither to read nor to write
-- ---------------------------------------------------------------------------
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  IF (SELECT count(*) FROM public.drive_items)    <> 0 THEN
    RAISE EXCEPTION 'anon failed: drive_items visible';
  END IF;
  IF (SELECT count(*) FROM public.bucket_items)   <> 0 THEN
    RAISE EXCEPTION 'anon failed: bucket_items visible';
  END IF;
  IF (SELECT count(*) FROM public.missyou)        <> 0 THEN
    RAISE EXCEPTION 'anon failed: missyou visible';
  END IF;
  IF (SELECT count(*) FROM public.game_questions) <> 0 THEN
    RAISE EXCEPTION 'anon failed: game_questions visible';
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_items (id, type, name, partnership_id)
    VALUES (9140, 'image', 'anon-insert.png', 9001)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'anon failed: insert into drive_items gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- service_role retains full write access (RLS bypass preserved)
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_rows int;
BEGIN
  IF (SELECT count(*) FROM public.drive_items WHERE id IN (9010, 9011, 9012)) <> 3 THEN
    RAISE EXCEPTION 'I failed: service_role lost drive_items access';
  END IF;

  INSERT INTO public.bucket_items (id, text, partnership_id) VALUES (9150, 'svc-pending', 9002);
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role insert into the pending partnership matched % row(s)', v_rows;
  END IF;

  UPDATE public.drive_items SET partnership_id = 9002 WHERE id = 9011;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role update matched % row(s)', v_rows;
  END IF;

  DELETE FROM public.bucket_items WHERE id = 9150;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role delete matched % row(s)', v_rows;
  END IF;

  UPDATE public.drive_items SET partnership_id = 9001 WHERE id = 9011;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role restore update matched % row(s)', v_rows;
  END IF;
END $$;

ROLLBACK;

SELECT 'shared-table-with-check: passed (pre-flight, A accepted writes, B pending inserts, C rejected inserts, D cross-partnership moves, B/C/D-post leak checks, anon, I service_role)' AS result;
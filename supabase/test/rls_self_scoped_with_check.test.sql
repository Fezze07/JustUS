-- =============================================================================
-- WITH CHECK sweep: self-scoped and parent-scoped writes
-- (hardens and renames rls_with_check_sweep.test.sql)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_self_scoped_with_check.test.sql
--
-- Assertions:
--   * WITH CHECK violations must be 42501 (insufficient_privilege). Other
--     SQLSTATES mean RLS is not the guard, and "no error" means the write
--     succeeded silently.
--   * RLS-filtered UPDATEs that do not change key fields return 0 rows; a
--     failed reassignment must leave the original row exactly as it was. This
--     is checked against the row's current state, not by re-counting.
-- =============================================================================

BEGIN;

-- Try a statement and return the SQLSTATE if it raises an exception, or NULL
-- if it succeeds. This allows us to pin the expected privilege error.
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

INSERT INTO public.game_questions (id, partnership_id, question, user_id_a, user_id_b) VALUES
  (9040, 9001, 'accepted-q',  9001, 9002),
  (9041, 9002, 'pending-q',   9001, 9003),
  (9043, 9001, 'accepted-q2', 9001, 9002);

INSERT INTO public.moods (id, user_id, mood_type_id) VALUES
  (9050, 9002, NULL),
  (9053, 9001, NULL);

-- Pre-flight
DO $$
BEGIN
  IF (SELECT count(*) FROM public.drive_items     WHERE id IN (9010, 9011, 9012)) <> 3 THEN
    RAISE EXCEPTION 'fixture failed: drive_items incomplete';
  END IF;
  IF (SELECT count(*) FROM public.game_questions  WHERE id IN (9040, 9041, 9043)) <> 3 THEN
    RAISE EXCEPTION 'fixture failed: game_questions incomplete';
  END IF;
  IF (SELECT count(*) FROM public.moods           WHERE id IN (9050, 9053)) <> 2 THEN
    RAISE EXCEPTION 'fixture failed: moods incomplete';
  END IF;
  IF (SELECT count(*) FROM public.users           WHERE id IN (9001, 9002, 9003, 9004)) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: users incomplete';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles  WHERE user_id IN (9001, 9002, 9003, 9004)) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: user_profiles incomplete';
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = 9001) IS DISTINCT FROM 'accepted'
     OR (SELECT status FROM public.partnerships WHERE id = 9002) IS DISTINCT FROM 'pending'
     OR (SELECT status FROM public.partnerships WHERE id = 9003) IS DISTINCT FROM 'rejected' THEN
    RAISE EXCEPTION 'fixture failed: partnership statuses are incorrect';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Assertions as authenticated = alice
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

-- A. moods: cannot reassign ownership to another user; normal edits must work
DO $$
DECLARE
  v_state text;
  v_uid int;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.moods SET user_id = 9002 WHERE id = 9053$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A failed: reassigning own mood gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_uid := (SELECT user_id FROM public.moods WHERE id = 9053);
  IF v_uid IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'A failed: the mood''s ownership changed to %', v_uid;
  END IF;

  UPDATE public.moods SET mood_type_id = NULL WHERE id = 9053;
  IF (SELECT user_id FROM public.moods WHERE id = 9053) IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'A failed: mood ownership changed during a non-ownership update';
  END IF;
  IF (SELECT mood_type_id FROM public.moods WHERE id = 9053) IS NOT NULL THEN
    RAISE EXCEPTION 'A failed: the non-ownership edit did not stick';
  END IF;
END $$;

-- B. users: cannot reassign id; non-key edits allowed
DO $$
DECLARE
  v_state text;
  v_id int;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.users SET id = 9005 WHERE id = 9001$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: users.id reassignment gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_id := (SELECT id FROM public.users WHERE id = 9001);
  IF v_id IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'B failed: users.id changed to %', v_id;
  END IF;

  UPDATE public.users SET updated_at = now() WHERE id = 9001;
  IF (SELECT id FROM public.users WHERE id = 9001) IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'B failed: users.id changed during a non-key update';
  END IF;
END $$;

-- C. user_profiles: cannot reassign ownership; non-key edits allowed
DO $$
DECLARE
  v_state text;
  v_uid int;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.user_profiles SET user_id = 9005 WHERE user_id = 9001$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C failed: user_profiles.user_id reassignment gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_uid := (SELECT user_id FROM public.user_profiles WHERE user_id = 9001);
  IF v_uid IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'C failed: profile ownership changed to %', v_uid;
  END IF;

  UPDATE public.user_profiles SET display_name = 'Alicia' WHERE user_id = 9001;
  IF (SELECT user_id FROM public.user_profiles WHERE user_id = 9001) IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'C failed: profile ownership changed during a non-key update';
  END IF;
  IF (SELECT display_name FROM public.user_profiles WHERE user_id = 9001) IS DISTINCT FROM 'Alicia' THEN
    RAISE EXCEPTION 'C failed: non-key edit to user_profiles did not stick';
  END IF;
END $$;

-- D. game_answers: parent game must be in an accepted partnership
DO $$
DECLARE
  v_state text;
  v_count int;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_answers (game_id, user_id, selected_option)
    VALUES (9041, 9001, 1)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: insert into pending game gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  -- Insert an answer for the accepted game, then attempt to move it to pending
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_answers (game_id, user_id, selected_option)
    VALUES (9043, 9001, 3)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'D failed: setup insert into accepted game gave %', v_state;
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9043 AND user_id = 9001) <> 1 THEN
    RAISE EXCEPTION 'D failed: setup insert did not persist the row';
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.game_answers SET game_id = 9041 WHERE game_id = 9043 AND user_id = 9001$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: moving answer into pending game gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9041 AND user_id = 9001) <> 0 THEN
    RAISE EXCEPTION 'D failed: answer leaked into pending game';
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9043 AND user_id = 9001) <> 1 THEN
    RAISE EXCEPTION 'D failed: answer was moved despite the rejection';
  END IF;

  DELETE FROM public.game_answers WHERE game_id = 9043 AND user_id = 9001;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'D failed: delete of the accepted game answer matched % row(s)', v_count;
  END IF;
END $$;

-- E. drive_item_reactions: parent item must be in an accepted partnership
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_item_reactions (user_id, item_id)
    VALUES (9001, 9011)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E failed: reaction on pending item gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_item_reactions (user_id, item_id)
    VALUES (9001, 9010)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'E failed: reaction on accepted item gave %', v_state;
  END IF;
  IF (SELECT count(*) FROM public.drive_item_reactions WHERE user_id = 9001 AND item_id = 9010) <> 1 THEN
    RAISE EXCEPTION 'E failed: setup reaction did not persist';
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.drive_item_reactions SET item_id = 9011 WHERE user_id = 9001 AND item_id = 9010$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E failed: moving reaction onto pending item gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT item_id FROM public.drive_item_reactions WHERE user_id = 9001 AND item_id = 9010) IS DISTINCT FROM 9010 THEN
    RAISE EXCEPTION 'E failed: reaction item changed despite the rejection';
  END IF;
  IF EXISTS (SELECT 1 FROM public.drive_item_reactions WHERE user_id = 9001 AND item_id = 9011) THEN
    RAISE EXCEPTION 'E failed: reaction leaked onto the pending item';
  END IF;

  DELETE FROM public.drive_item_reactions WHERE user_id = 9001 AND item_id = 9010;
END $$;

-- F. favorites: item must be in an accepted partnership; ownership is self-scoped
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.favorites (user_id, item_id) VALUES (9001, 9011)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'F failed: favorite on pending item gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.favorites (user_id, item_id) VALUES (9001, 9010)$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'F failed: favorite on accepted item gave %', v_state;
  END IF;
  IF (SELECT count(*) FROM public.favorites WHERE user_id = 9001 AND item_id = 9010) <> 1 THEN
    RAISE EXCEPTION 'F failed: setup favorite did not persist';
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.favorites SET item_id = 9012 WHERE user_id = 9001 AND item_id = 9010$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'F failed: moving favorite onto rejected item gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT item_id FROM public.favorites WHERE user_id = 9001 AND item_id = 9010) IS DISTINCT FROM 9010 THEN
    RAISE EXCEPTION 'F failed: favorite item changed despite the rejection';
  END IF;
  IF EXISTS (SELECT 1 FROM public.favorites WHERE user_id = 9001 AND item_id = 9012) THEN
    RAISE EXCEPTION 'F failed: favorite leaked onto the rejected item';
  END IF;

  DELETE FROM public.favorites WHERE user_id = 9001 AND item_id = 9010;
END $$;

-- G. partnerships: inserts must include the caller as a member
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9002, 9003, 'pending')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: partnership created without caller as member gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  UPDATE public.partnerships SET anniversary_date = current_date WHERE id = 9001;
  IF (SELECT anniversary_date FROM public.partnerships WHERE id = 9001) IS NULL THEN
    RAISE EXCEPTION 'G failed: a member could not update their own partnership';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- anon: blocked from the new write paths
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.favorites (user_id, item_id) VALUES (9001, 9010)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'anon failed: favorite insert gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9001, 9002, 'accepted')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'anon failed: partnership insert gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.drive_item_reactions (user_id, item_id)
    VALUES (9001, 9010)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'anon failed: reaction insert gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.game_answers (game_id, user_id, selected_option)
    VALUES (9040, 9001, 1)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'anon failed: game_answers insert gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- service_role: RLS bypass preserved
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_count int;
BEGIN
  INSERT INTO public.favorites (user_id, item_id) VALUES (9002, 9011);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'I failed: favorites insert matched % row(s)', v_count;
  END IF;

  INSERT INTO public.drive_item_reactions (user_id, item_id) VALUES (9003, 9012);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'I failed: reactions insert matched % row(s)', v_count;
  END IF;

  INSERT INTO public.game_answers (game_id, user_id, selected_option) VALUES (9041, 9003, 2);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'I failed: game_answers insert matched % row(s)', v_count;
  END IF;

  IF (SELECT count(*) FROM public.favorites           WHERE item_id = 9011 AND user_id = 9002) <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role cannot see favorites';
  END IF;
  IF (SELECT count(*) FROM public.drive_item_reactions WHERE item_id = 9012 AND user_id = 9003) <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role cannot see reactions';
  END IF;
  IF (SELECT count(*) FROM public.game_answers         WHERE game_id = 9041 AND user_id = 9003) <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role cannot see game_answers';
  END IF;
END $$;

ROLLBACK;

SELECT 'self-scoped-with-check: passed (pre-flight, A moods, B users, C user_profiles, D game_answers, E reactions, F favorites, G partnerships, anon, I service_role)' AS result;
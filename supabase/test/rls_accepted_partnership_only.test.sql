-- =============================================================================
-- Access to a partnership requires status = 'accepted'
-- (covers audit finding 2.2: is_in_partnership / is_partner_of)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_accepted_partnership_only.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
--
-- Assertion style used here:
--   * boolean helpers are compared with `IS DISTINCT FROM`, never `<>`, because
--     `NULL <> true` is NULL and a NULL return would pass silently;
--   * a write that RLS filters out reports 0 rows rather than raising, so the
--     row count is what is asserted; a WITH CHECK violation must be 42501 and
--     no other SQLSTATE is accepted;
--   * fixtures are verified as superuser before the role is switched, so a
--     broken fixture cannot make every later assertion pass by hiding rows.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9001 alice <-> 9002 bob   : partnership 9001 accepted
--   9001 alice <-> 9003 carol : partnership 9002 pending  (alice is sender)
--   9001 alice <-> 9004 dave  : partnership 9003 rejected
-- Shared rows are seeded per partnership so visibility can be asserted.
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
  ('game_q_accepted', 'it', 'accepted-q'),
  ('game_q_pending',  'it', 'pending-q'),
  ('game_q_rejected', 'it', 'rejected-q');

INSERT INTO public.game_answers (game_id, user_id, selected_option) VALUES
  (9040, 9001, 1),
  (9040, 9002, 2),
  (9041, 9001, 1),
  (9042, 9001, 1);

INSERT INTO public.moods (id, user_id, mood_type_id) VALUES
  (9050, 9002, NULL),
  (9051, 9003, NULL),
  (9052, 9004, NULL),
  (9053, 9001, NULL);

-- ---------------------------------------------------------------------------
-- Pre-flight: as superuser, confirm the fixtures exist in the intended state.
-- Without this, a fixture that failed to insert would leave every visibility
-- count at 0 and the "must be 0" assertions would pass for the wrong reason.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships WHERE id = 9001) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'fixture failed: partnership 9001 is not accepted';
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = 9002) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'fixture failed: partnership 9002 is not pending';
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = 9003) IS DISTINCT FROM 'rejected' THEN
    RAISE EXCEPTION 'fixture failed: partnership 9003 is not rejected';
  END IF;
  IF (SELECT count(*) FROM public.drive_items    WHERE id IN (9010, 9011, 9012)) <> 3
     OR (SELECT count(*) FROM public.bucket_items   WHERE id IN (9020, 9021, 9022)) <> 3
     OR (SELECT count(*) FROM public.missyou        WHERE id IN (9030, 9031, 9032)) <> 3
     OR (SELECT count(*) FROM public.game_questions WHERE id IN (9040, 9041, 9042)) <> 3 THEN
    RAISE EXCEPTION 'fixture failed: the shared-row fixtures are incomplete';
  END IF;
  IF (SELECT count(*) FROM public.moods) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: expected 4 mood rows';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Assertions evaluated as `authenticated` = alice
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

DO $$
BEGIN
  -- A. helpers: accepted -> true, pending/rejected -> false
  IF public.is_in_partnership(9001) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'A failed: accepted partnership not recognized (got %)',
      coalesce(public.is_in_partnership(9001)::text, 'NULL');
  END IF;
  IF public.is_in_partnership(9002) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'A failed: pending partnership grants access (got %)',
      coalesce(public.is_in_partnership(9002)::text, 'NULL');
  END IF;
  IF public.is_in_partnership(9003) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'A failed: rejected partnership grants access (got %)',
      coalesce(public.is_in_partnership(9003)::text, 'NULL');
  END IF;
  IF public.is_partner_of(9002) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'A failed: accepted partner not recognized (got %)',
      coalesce(public.is_partner_of(9002)::text, 'NULL');
  END IF;
  IF public.is_partner_of(9003) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'A failed: pending counterpart treated as partner (got %)',
      coalesce(public.is_partner_of(9003)::text, 'NULL');
  END IF;
  IF public.is_partner_of(9004) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'A failed: rejected counterpart treated as partner (got %)',
      coalesce(public.is_partner_of(9004)::text, 'NULL');
  END IF;

  -- B. shared tables: only the accepted partnership's rows are visible
  IF (SELECT count(*) FROM public.drive_items WHERE id IN (9010, 9011, 9012)) <> 1 THEN
    RAISE EXCEPTION 'B failed: drive_items visibility != 1 (pending/rejected leak)';
  END IF;
  IF (SELECT count(*) FROM public.drive_items WHERE id = 9010) <> 1 THEN
    RAISE EXCEPTION 'B failed: accepted drive row not readable';
  END IF;

  IF (SELECT count(*) FROM public.bucket_items WHERE id IN (9020, 9021, 9022)) <> 1 THEN
    RAISE EXCEPTION 'B failed: bucket_items visibility != 1 (pending/rejected leak)';
  END IF;
  IF (SELECT count(*) FROM public.missyou     WHERE id IN (9030, 9031, 9032)) <> 1 THEN
    RAISE EXCEPTION 'B failed: missyou visibility != 1 (pending/rejected leak)';
  END IF;
  IF (SELECT count(*) FROM public.game_questions WHERE id IN (9040, 9041, 9042)) <> 1 THEN
    RAISE EXCEPTION 'B failed: game_questions visibility != 1 (pending/rejected leak)';
  END IF;

  -- C. transitive policy: game_answers are only visible through an accepted game
  IF (SELECT count(*) FROM public.game_answers WHERE game_id IN (9040, 9041, 9042)) <> 2 THEN
    RAISE EXCEPTION 'C failed: game_answers visibility != 2 (pending/rejected leak)';
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9040) <> 2 THEN
    RAISE EXCEPTION 'C failed: the accepted game''s two answers are not both readable';
  END IF;

  -- D. moods: own row or accepted partner; pending/rejected counterpart invisible
  IF (SELECT count(*) FROM public.moods) <> 2 THEN
    RAISE EXCEPTION 'D failed: moods visible from pending/rejected counterpart';
  END IF;
  IF (SELECT count(*) FROM public.moods WHERE user_id = 9002) <> 1 THEN
    RAISE EXCEPTION 'D failed: accepted partner mood not readable';
  END IF;
  IF (SELECT count(*) FROM public.moods WHERE user_id IN (9003, 9004)) <> 0 THEN
    RAISE EXCEPTION 'D failed: pending/rejected counterpart mood readable';
  END IF;

  -- E. v_drive_dashboard respects the same rule
  IF (SELECT count(*) FROM public.v_drive_dashboard) <> 1 THEN
    RAISE EXCEPTION 'E failed: v_drive_dashboard leaks pending/rejected rows';
  END IF;
  IF (SELECT count(*) FROM public.v_drive_dashboard WHERE id = 9010) <> 1 THEN
    RAISE EXCEPTION 'E failed: v_drive_dashboard hides accepted row';
  END IF;
END $$;

-- F. the accepted partnership stays writable (no regression). Asserting the
--    row counts matters: an INSERT silently blocked by RLS would otherwise
--    "pass" a statement that only checked that DELETE did not error.
DO $$
DECLARE
  v_rows int;
BEGIN
  INSERT INTO public.drive_items (id, type, name, partnership_id)
  VALUES (9090, 'image', 'accepted-insert.png', 9001);
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'F failed: insert into the accepted partnership matched % row(s)', v_rows;
  END IF;

  DELETE FROM public.drive_items WHERE id = 9090;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'F failed: delete of the accepted row matched % row(s)', v_rows;
  END IF;

  UPDATE public.bucket_items SET text = 'accepted-edit' WHERE id = 9020;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'F failed: update of the accepted bucket row matched % row(s)', v_rows;
  END IF;
END $$;

-- G. inserting into a pending/rejected partnership must be rejected by WITH
--    CHECK with 42501. A foreign key or check-constraint failure would mean
--    RLS was not what stopped it, so the SQLSTATE is pinned exactly.
DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    INSERT INTO public.drive_items (id, type, name, partnership_id)
    VALUES (9091, 'image', 'pending-insert.png', 9002);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: insert into pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    INSERT INTO public.bucket_items (id, text, partnership_id)
    VALUES (9092, 'rejected-insert', 9003);
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: insert into rejected partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Recipient side of the pending invitation (bob is accepted, carol/dave not)
-- ---------------------------------------------------------------------------
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';
DO $$
BEGIN
  IF public.is_in_partnership(9001) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'H1 failed: bob lost accepted access';
  END IF;
  IF public.is_partner_of(9001) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'H1 failed: bob does not see alice as partner';
  END IF;
  IF (SELECT count(*) FROM public.moods) <> 2 THEN
    RAISE EXCEPTION 'H1 failed: bob cannot see accepted partner mood (own + alice expected)';
  END IF;
END $$;

-- carol: pending request sender is not a partner (her own mood remains readable)
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000003"}';
DO $$
BEGIN
  IF public.is_in_partnership(9002) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'H2 failed: carol granted access to her pending partnership';
  END IF;
  IF public.is_partner_of(9001) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'H2 failed: carol sees alice as partner on a pending request';
  END IF;
  IF (SELECT count(*) FROM public.drive_items) <> 0 THEN
    RAISE EXCEPTION 'H2 failed: carol can read pending-partnership drive rows';
  END IF;
  IF (SELECT count(*) FROM public.bucket_items) <> 0 THEN
    RAISE EXCEPTION 'H2 failed: carol can read pending-partnership bucket rows';
  END IF;
  IF (SELECT count(*) FROM public.moods) <> 1 THEN
    RAISE EXCEPTION 'H2 failed: carol can read partner moods on a pending request';
  END IF;
END $$;

-- dave: rejected request grants nothing (his own mood remains readable)
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000004"}';
DO $$
BEGIN
  IF public.is_in_partnership(9003) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'H3 failed: dave granted access to his rejected partnership';
  END IF;
  IF public.is_partner_of(9001) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'H3 failed: dave sees alice as partner on a rejected request';
  END IF;
  IF (SELECT count(*) FROM public.moods) <> 1 THEN
    RAISE EXCEPTION 'H3 failed: dave can read another user mood (own only expected)';
  END IF;
  IF (SELECT count(*) FROM public.moods WHERE user_id IN (9001, 9002, 9003)) <> 0 THEN
    RAISE EXCEPTION 'H3 failed: dave can read alice/bob side moods on a rejected request';
  END IF;
END $$;

-- Unauthenticated (anon) must see nothing
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.drive_items)     <> 0 THEN
    RAISE EXCEPTION 'anon failed: drive_items visible';
  END IF;
  IF (SELECT count(*) FROM public.bucket_items)    <> 0 THEN
    RAISE EXCEPTION 'anon failed: bucket_items visible';
  END IF;
  IF (SELECT count(*) FROM public.missyou)         <> 0 THEN
    RAISE EXCEPTION 'anon failed: missyou visible';
  END IF;
  IF (SELECT count(*) FROM public.game_questions)  <> 0 THEN
    RAISE EXCEPTION 'anon failed: game_questions visible';
  END IF;
  IF (SELECT count(*) FROM public.game_answers)    <> 0 THEN
    RAISE EXCEPTION 'anon failed: game_answers visible';
  END IF;
  IF (SELECT count(*) FROM public.moods)           <> 0 THEN
    RAISE EXCEPTION 'anon failed: moods visible';
  END IF;
  IF (SELECT count(*) FROM public.v_drive_dashboard) <> 0 THEN
    RAISE EXCEPTION 'anon failed: v_drive_dashboard visible';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- I. service_role retains full access (RLS bypass preserved)
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
  IF (SELECT count(*) FROM public.bucket_items WHERE id IN (9020, 9021, 9022)) <> 3 THEN
    RAISE EXCEPTION 'I failed: service_role lost bucket_items access';
  END IF;
  IF (SELECT count(*) FROM public.missyou WHERE id IN (9030, 9031, 9032)) <> 3 THEN
    RAISE EXCEPTION 'I failed: service_role lost missyou access';
  END IF;
  IF (SELECT count(*) FROM public.game_questions WHERE id IN (9040, 9041, 9042)) <> 3 THEN
    RAISE EXCEPTION 'I failed: service_role lost game_questions access';
  END IF;
  IF (SELECT count(*) FROM public.moods WHERE id IN (9050, 9051, 9052, 9053)) <> 4 THEN
    RAISE EXCEPTION 'I failed: service_role lost moods access';
  END IF;

  -- Write through the bypass, so "it can read" is not mistaken for "it can act".
  UPDATE public.bucket_items SET text = 'service-edit' WHERE id = 9021;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'I failed: service_role update matched % row(s)', v_rows;
  END IF;
END $$;

ROLLBACK;

SELECT 'accepted-partnership-only: passed (pre-flight, A helpers, B shared tables, C transitive game_answers, D moods, E v_drive_dashboard, F accepted writes, G pending/rejected inserts, H1/H2/H3 counterpart sides, anon, I service_role)' AS result;
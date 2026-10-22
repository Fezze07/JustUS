-- =============================================================================
-- Partnership creation: only partnership_request creates a row, only the
-- recipient can accept it, and membership is immutable  (covers 11.1, 11.2)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLBACKed at the end, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_partnership_creation.test.sql
--
-- Contract under test:
--   * no client may INSERT into public.partnerships. A row exists only when
--     partnership_request created it, so the partnership_code gate inside that
--     function cannot be skipped and `status` can never be forged to
--     'accepted';
--   * partnership_request still works for the backend, which is the only
--     caller that creates rows (it runs on service_role);
--   * only the recipient (user_id_2) may accept a pending request, so the
--     sender cannot push its own request into an accepted partnership. That
--     holds through the RPC and through a direct UPDATE of `status`, which the
--     partnership_guard_status trigger rejects for the sender;
--   * membership is immutable: no UPDATE may change `user_id_1` / `user_id_2`
--     (covers todo.md 11.2), so an existing pair cannot be re-pointed to a
--     third party.
--
-- Assertion style follows the rest of this directory: IS DISTINCT FROM for
-- comparisons, a pinned SQLSTATE (42501) for a denied write, and a re-read with
-- the RLS bypass in place after every negative case.
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
--   9001 alice  : free, profile code ALICE1
--   9002 bob    : free, profile code BOB222
--   9003 carol  : free, profile code CAROL3
--   9004 dave   : free, profile code DAVE4
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@partnership-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@partnership-test.local'),
  (9003, '00000000-0000-0000-0000-000000000003', 'carol@partnership-test.local'),
  (9004, '00000000-0000-0000-0000-000000000004', 'dave@partnership-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'ALICE1'),
  (9002, 'Bob',   'BOB222'),
  (9003, 'Carol', 'CAROL3'),
  (9004, 'Dave',  'DAVE4');

-- ---------------------------------------------------------------------------
-- A. as alice (authenticated): no client insert may create a partnership.
--    Every shape of the forgery is tried, because the old FOR ALL policy
--    accepted all of them.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

DO $$
DECLARE
  v_state text;
BEGIN
  -- The original forgery: self as user_id_1, a victim as user_id_2, and no
  -- status at all, so the column default 'accepted' used to apply.
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2)
    VALUES (9001, 9002)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A failed: insert with the default status gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  -- The same forgery, with the status written out explicitly.
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9001, 9002, 'accepted')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A failed: insert with status accepted gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  -- A pending row would bypass the partnership_code gate of partnership_request.
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9001, 9002, 'pending')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A failed: insert with status pending gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  -- A third party named as user_id_1, with the caller as user_id_2.
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9003, 9001, 'pending')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A failed: insert naming a third party gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- A-post: the forged rows must not exist, checked with the RLS bypass in place.
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.partnerships) <> 0 THEN
    RAISE EXCEPTION 'A-post failed: % partnership row(s) were created by a client',
      (SELECT count(*) FROM public.partnerships)::text;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. as anon: still denied (the INSERT grant and the policy are both gone)
-- ---------------------------------------------------------------------------
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.partnerships (user_id_1, user_id_2, status)
    VALUES (9001, 9002, 'accepted')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B failed: anon insert gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. the sanctioned path: the backend calls partnership_request on
--    service_role, which is the only caller that may create a row.
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT public.partnership_request('bob@partnership-test.local', 'BOB222', 9001) INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'C failed: partnership_request returned no id';
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'C failed: partnership_request created a % row, expected pending',
      coalesce((SELECT status FROM public.partnerships WHERE id = v_id), 'NULL');
  END IF;

  IF (SELECT user_id_1 FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9001
     OR (SELECT user_id_2 FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9002 THEN
    RAISE EXCEPTION 'C failed: partnership_request created the wrong pair';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D. the recipient accepts the request
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9001 AND user_id_2 = 9002;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'D failed: the pending request is not visible to the recipient';
  END IF;

  PERFORM public.partnership_accept(v_id);

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'D failed: the recipient could not accept the request';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E. the sender may NOT accept its own request: carol requests alice, tries to
--    accept it herself, and the row must stay pending until alice accepts.
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT public.partnership_request('alice@partnership-test.local', 'ALICE1', 9003) INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'E failed: partnership_request returned no id';
  END IF;
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000003"}';
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9003 AND user_id_2 = 9001;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'E failed: the sent request is not visible to its sender';
  END IF;

  PERFORM public.partnership_accept(v_id);

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'E failed: the sender accepted its own request (status %)',
      coalesce((SELECT status FROM public.partnerships WHERE id = v_id), 'NULL');
  END IF;
END $$;

-- ...and the recipient still can.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9003 AND user_id_2 = 9001;

  PERFORM public.partnership_accept(v_id);

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'E failed: the recipient could not accept the request';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- G. the sender may not promote its own request to 'accepted' through a
--    direct UPDATE either - the partnership_guard_status trigger rejects it.
--    Other column updates stay allowed for a member.
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT public.partnership_request('bob@partnership-test.local', 'BOB222', 9004) INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'G failed: partnership_request returned no id';
  END IF;
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000004"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9004 AND user_id_2 = 9002;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'G failed: the sent request is not visible to its sender';
  END IF;

  v_state := pg_temp.rls_try(format(
    'UPDATE public.partnerships SET status = %s WHERE id = %s',
    quote_literal('accepted'), v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: the sender set status to accepted and got %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'G failed: the request is no longer pending';
  END IF;

  -- a member may still update the other columns of the row
  v_state := pg_temp.rls_try(format(
    'UPDATE public.partnerships SET anniversary_date = current_date WHERE id = %s', v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'G failed: the anniversary update was refused with %', v_state;
  END IF;
END $$;

-- ...and the recipient still can.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000002"}';
DO $$
DECLARE
  v_id integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9004 AND user_id_2 = 9002;

  PERFORM public.partnership_accept(v_id);

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'G failed: the recipient could not accept the request';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- H. membership is immutable: a member of an accepted pair may not re-point it
--    to a third party, which would cut the partner off and hand the couple's
--    data to someone else.
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9001 AND user_id_2 = 9002;

  IF v_id IS NULL
     OR (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'H failed: the alice-bob partnership is not accepted';
  END IF;

  v_state := pg_temp.rls_try(format(
    'UPDATE public.partnerships SET user_id_2 = 9003 WHERE id = %s', v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'H failed: re-pointing user_id_2 gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try(format(
    'UPDATE public.partnerships SET user_id_1 = 9003 WHERE id = %s', v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'H failed: re-pointing user_id_1 gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try(format(
    'UPDATE public.partnerships SET user_id_1 = NULL WHERE id = %s', v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'H failed: nulling user_id_1 gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- H-post: the accepted pair is untouched, checked with the RLS bypass in place.
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.partnerships
       WHERE user_id_1 = 9001 AND user_id_2 = 9002 AND status = 'accepted') <> 1 THEN
    RAISE EXCEPTION 'H-post failed: the accepted alice-bob pair is gone';
  END IF;

  IF EXISTS (SELECT 1 FROM public.partnerships WHERE user_id_1 = 9001 AND user_id_2 = 9003)
     OR EXISTS (SELECT 1 FROM public.partnerships WHERE user_id_1 = 9003 AND user_id_2 = 9002) THEN
    RAISE EXCEPTION 'H-post failed: a re-pointed row exists';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- F. final state: exactly the three accepted rows the sanctioned path produced
-- ---------------------------------------------------------------------------
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.partnerships) <> 3 THEN
    RAISE EXCEPTION 'F failed: % partnership row(s) exist, expected 3',
      (SELECT count(*) FROM public.partnerships)::text;
  END IF;

  IF (SELECT count(*) FROM public.partnerships WHERE status = 'accepted') <> 3 THEN
    RAISE EXCEPTION 'F failed: the three sanctioned requests are not all accepted';
  END IF;
END $$;

ROLLBACK;

SELECT 'partnership-creation: passed (A client inserts denied, A-post no rows, B anon denied, C partnership_request creates the row, D recipient accepts, E sender cannot accept, F final state, G sender cannot set status directly, H membership is immutable)' AS result;

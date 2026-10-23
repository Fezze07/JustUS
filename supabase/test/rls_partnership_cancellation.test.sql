-- =============================================================================
-- Partnership cancellation: the status guard's transition whitelist
-- (covers acceptance criteria of the cancellation state machine, §3.2)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLBACKed at the end, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_partnership_cancellation.test.sql
--
-- Contract under test (partnership-cancellation.md §3.2):
--   * accepted -> cancelled requires a member, `cancel_requested_by = caller`
--     and a non-NULL `cancel_expires_at` (`API-VALIDATION-010`);
--   * cancelled -> accepted requires a member and clears both cancel fields
--     (`API-VALIDATION-011`), including for the service-role expiry path;
--   * cancelled -> cancelled may not move the requester or the expiry
--     (`API-VALIDATION-012`);
--   * the cancellation fields are read-only on a non-status update, so a raw
--     PATCH cannot pre-seed or tamper with them;
--   * any other status change is rejected (`API-VALIDATION-012`);
--   * pending -> accepted is still recipient-only (`API-VALIDATION-008`);
--   * a partner decline records `cancel_declined_at`, while a requester
--     restore, the service-role expiry path and every other update preserve
--     it, so a client cannot clear or forge the cooldown;
--   * a member may raw-`DELETE` only a `pending` row: an accepted or
--     cancelled row is left untouched, and `anon` holds no `DELETE`/`TRUNCATE`.
--
-- Sections A (request), B (delete), C (revert) and E (tamper); D (cooldown),
-- F (accept), G (expiry), H (11.1/11.2) and I/J belong to later items.
--
-- RLS limits UPDATE to the two members, so a non-member's UPDATE matches zero
-- rows instead of reaching the trigger; those cases assert the row is
-- unchanged.
-- =============================================================================

BEGIN;

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
--   9101 alice / 9102 bob / 9103 carol / 9104 dave
--   alice-bob   accepted  (request by user_id_1, then member revert)
--   carol-dave  accepted  (request by user_id_2, then partner revert)
--   alice-carol pending   (revert of a non-cancelled row)
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9101, '00000000-0000-0000-0000-000000000101', 'alice@cancellation-test.local'),
  (9102, '00000000-0000-0000-0000-000000000102', 'bob@cancellation-test.local'),
  (9103, '00000000-0000-0000-0000-000000000103', 'carol@cancellation-test.local'),
  (9104, '00000000-0000-0000-0000-000000000104', 'dave@cancellation-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9101, 'Alice', 'CAL101'),
  (9102, 'Bob',   'CAL102'),
  (9103, 'Carol', 'CAL103'),
  (9104, 'Dave',  'CAL104');

INSERT INTO public.partnerships (user_id_1, user_id_2, status) VALUES
  (9101, 9102, 'accepted'),
  (9103, 9104, 'accepted'),
  (9101, 9103, 'pending');

-- Resolve the id while RLS is bypassed, so the non-member case can name a row
-- it is not allowed to see.
CREATE TEMP TABLE pids AS
SELECT
  max(id) FILTER (WHERE user_id_1 = 9101 AND user_id_2 = 9102) AS ab,
  max(id) FILTER (WHERE user_id_1 = 9103 AND user_id_2 = 9104) AS cd
FROM public.partnerships;

SELECT set_config('test.cd_id', cd::text, true) FROM pids;

-- ---------------------------------------------------------------------------
-- A. request cancellation
-- ---------------------------------------------------------------------------
-- A1. user_id_1 (alice) requests on the accepted alice-bob row.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9101,
           cancel_expires_at = now() + interval '7 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A1 failed: the member request was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9101 THEN
    RAISE EXCEPTION 'A1 failed: the row is not cancelled with alice as requester';
  END IF;

  IF (SELECT cancel_expires_at FROM public.partnerships WHERE id = v_id)
       NOT BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 hour' THEN
    RAISE EXCEPTION 'A1 failed: cancel_expires_at is not about 7 days ahead';
  END IF;
END $$;

-- A2. a second request may not take over the existing one.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000102"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9102,
           cancel_expires_at = now() + interval '7 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A2 failed: a second request gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9101 THEN
    RAISE EXCEPTION 'A2 failed: the requester was swapped by a second request';
  END IF;
END $$;

-- A3. a non-member cannot request (RLS matches zero rows).
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION 'A3 failed: the non-member can see the alice-bob row';
  END IF;

  v_state := pg_temp.rls_try($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9101,
           cancel_expires_at = now() + interval '7 days'
     WHERE user_id_1 = 9101 AND user_id_2 = 9102$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A3 failed: the non-member update gave %, expected no error and no rows', v_state;
  END IF;
END $$;

-- A4. anon cannot request either.
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9101,
           cancel_expires_at = now() + interval '7 days'
     WHERE user_id_1 = 9101 AND user_id_2 = 9102$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A4 failed: the anon update gave %, expected no error and no rows', v_state;
  END IF;
END $$;

-- A-post: the alice-bob row still belongs to alice, checked with RLS bypassed.
RESET ROLE;
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9101 AND user_id_2 = 9102) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships
          WHERE user_id_1 = 9101 AND user_id_2 = 9102) IS DISTINCT FROM 9101 THEN
    RAISE EXCEPTION 'A-post failed: a non-member or anon changed the alice-bob row';
  END IF;
END $$;

-- A5. user_id_2 (dave) requests on the accepted carol-dave row.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9104,
           cancel_expires_at = now() + interval '7 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A5 failed: the user_id_2 request was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9104 THEN
    RAISE EXCEPTION 'A5 failed: the row is not cancelled with dave as requester';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. revert / decline
-- ---------------------------------------------------------------------------
-- C1. the requester (alice) reverts her own request.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'accepted',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C1 failed: the requester revert was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS NOT NULL
     OR (SELECT cancel_expires_at FROM public.partnerships WHERE id = v_id) IS NOT NULL
     OR (SELECT cancel_declined_at FROM public.partnerships WHERE id = v_id) IS NOT NULL THEN
    RAISE EXCEPTION 'C1 failed: the row is not accepted with NULL cancellation fields and no decline';
  END IF;
END $$;

-- C2. the partner (carol) declines dave's request.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000103"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'accepted',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C2 failed: the partner decline was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS NOT NULL
     OR (SELECT cancel_expires_at FROM public.partnerships WHERE id = v_id) IS NOT NULL THEN
    RAISE EXCEPTION 'C2 failed: the row is not accepted with NULL cancellation fields';
  END IF;

  IF (SELECT cancel_declined_at FROM public.partnerships WHERE id = v_id)
       NOT BETWEEN now() - interval '1 minute' AND now() THEN
    RAISE EXCEPTION 'C2 failed: the partner decline did not record cancel_declined_at';
  END IF;

  PERFORM set_config('test.declined_at',
    (SELECT cancel_declined_at::text FROM public.partnerships WHERE id = v_id), true);
END $$;

-- C2b. a raw PATCH can neither clear nor forge the decline timestamp: the
--      trigger forces it back to the stored value.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
  v_before timestamptz;
BEGIN
  SELECT id, cancel_declined_at INTO v_id, v_before FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  IF v_before IS NULL THEN
    RAISE EXCEPTION 'C2b failed: no decline timestamp to protect';
  END IF;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_declined_at = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C2b failed: clearing the timestamp gave %', v_state;
  END IF;

  IF (SELECT cancel_declined_at FROM public.partnerships WHERE id = v_id)
       IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'C2b failed: the client cleared cancel_declined_at';
  END IF;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_declined_at = now() - interval '10 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C2b failed: forging the timestamp gave %', v_state;
  END IF;

  IF (SELECT cancel_declined_at FROM public.partnerships WHERE id = v_id)
       IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'C2b failed: the client forged cancel_declined_at';
  END IF;
END $$;

-- C3. a non-member cannot revert.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9104,
           cancel_expires_at = now() + interval '7 days'
     WHERE user_id_1 = 9103 AND user_id_2 = 9104$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C3 setup failed: the request was refused with %', v_state;
  END IF;
END $$;

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_state text;
BEGIN
  -- alice is not a member of carol-dave
  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'accepted',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE id = %s$q$, current_setting('test.cd_id')::integer));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C3 failed: the non-member revert gave %, expected no error and no rows', v_state;
  END IF;
END $$;

RESET ROLE;
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'C3 failed: a non-member reverted the carol-dave request';
  END IF;
END $$;

-- C4. a revert of a non-cancelled row is rejected: the sender of the pending
--     alice-carol request may not promote it to accepted.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9103;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'accepted',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C4 failed: promoting a pending row gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'C4 failed: the pending row is no longer pending';
  END IF;
END $$;

-- C5. the service-role expiry path may revert without a user JWT.
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.partnerships
       SET status = 'accepted',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE user_id_1 = 9103 AND user_id_2 = 9104$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'C5 failed: the service-role revert was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'C5 failed: the service-role revert did not restore accepted';
  END IF;

  -- The expiry path is not a partner decline, so it must not touch the cooldown.
  IF (SELECT cancel_declined_at FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104)
       IS DISTINCT FROM current_setting('test.declined_at')::timestamptz THEN
    RAISE EXCEPTION 'C5 failed: the service-role revert changed cancel_declined_at';
  END IF;
END $$;

-- C6. a requester restore keeps the stored decline timestamp.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_before timestamptz;
BEGIN
  SELECT id, cancel_declined_at INTO v_id, v_before FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  UPDATE public.partnerships
     SET status = 'cancelled',
         cancel_requested_by = 9104,
         cancel_expires_at = now() + interval '7 days'
   WHERE id = v_id;

  UPDATE public.partnerships
     SET status = 'accepted',
         cancel_requested_by = NULL,
         cancel_expires_at = NULL
   WHERE id = v_id;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted'
     OR (SELECT cancel_declined_at FROM public.partnerships WHERE id = v_id)
          IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'C6 failed: the requester restore disturbed the cooldown';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E. tamper with the cancellation fields
-- ---------------------------------------------------------------------------
-- Re-request on carol-dave as dave so there is a cancelled row to tamper with.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    UPDATE public.partnerships
       SET status = 'cancelled',
           cancel_requested_by = 9104,
           cancel_expires_at = now() + interval '7 days'
     WHERE user_id_1 = 9103 AND user_id_2 = 9104$q$);
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'E setup failed: the request was refused with %', v_state;
  END IF;
END $$;

-- E1. cannot swap the requester while cancelled.
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_requested_by = 9103
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E1 failed: swapping the requester gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9104 THEN
    RAISE EXCEPTION 'E1 failed: the requester was swapped';
  END IF;
END $$;

-- E2. cannot change the expiry while cancelled.
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_expires_at = now() + interval '30 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E2 failed: changing the expiry gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- E3. cannot clear the requester while cancelled.
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_requested_by = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E3 failed: clearing the requester gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- E4. cannot pre-seed the cancellation fields on an accepted row.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_requested_by = 9101
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E4 failed: setting the requester on an accepted row gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET cancel_expires_at = now() + interval '7 days'
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E4 failed: setting the expiry on an accepted row gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- E5. an ordinary column stays writable on a cancelled row.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET anniversary_date = current_date
     WHERE id = %s$q$, v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'E5 failed: the anniversary update was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9104 THEN
    RAISE EXCEPTION 'E5 failed: the ordinary update disturbed the cancellation state';
  END IF;
END $$;

-- E6. any other status transition is rejected (cancelled -> pending).
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.partnerships
       SET status = 'pending',
           cancel_requested_by = NULL,
           cancel_expires_at = NULL
     WHERE id = %s$q$, v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'E6 failed: cancelled -> pending gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. raw DELETE is limited to pending rows (11.3)
-- ---------------------------------------------------------------------------
-- Runs last so the fixtures are in their final states: alice-bob accepted,
-- carol-dave cancelled, alice-carol pending.
-- B1. neither member may delete the accepted alice-bob row.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_count integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  DELETE FROM public.partnerships WHERE id = v_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'B1 failed: alice deleted the accepted row';
  END IF;
END $$;

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000102"}';
DO $$
DECLARE
  v_id integer;
  v_count integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  DELETE FROM public.partnerships WHERE id = v_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'B1 failed: bob deleted the accepted row';
  END IF;
END $$;

-- B2. neither member may delete the cancelled carol-dave row.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000103"}';
DO $$
DECLARE
  v_id integer;
  v_count integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  DELETE FROM public.partnerships WHERE id = v_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'B2 failed: carol deleted the cancelled row';
  END IF;
END $$;

SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_count integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  DELETE FROM public.partnerships WHERE id = v_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'B2 failed: dave deleted the cancelled row';
  END IF;
END $$;

-- B3. the creator may still delete the pending alice-carol request.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_count integer;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9103;

  DELETE FROM public.partnerships WHERE id = v_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'B3 failed: the pending delete removed % rows, expected 1', v_count;
  END IF;
END $$;

-- B-post: the accepted and cancelled rows survived, the pending row is gone.
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.partnerships
       WHERE (user_id_1 = 9101 AND user_id_2 = 9102)
          OR (user_id_1 = 9103 AND user_id_2 = 9104)) <> 2 THEN
    RAISE EXCEPTION 'B-post failed: a member deleted an accepted or cancelled row';
  END IF;

  IF EXISTS (SELECT 1 FROM public.partnerships
       WHERE user_id_1 = 9101 AND user_id_2 = 9103) THEN
    RAISE EXCEPTION 'B-post failed: the pending row was not deleted';
  END IF;
END $$;

-- B4. anon lost DELETE and TRUNCATE; authenticated keeps DELETE.
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try($q$
    DELETE FROM public.partnerships
     WHERE id = current_setting('test.cd_id')::integer$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'B4 failed: the anon delete gave %, expected 42501',
      coalesce(v_state, 'no error (the delete was attempted)');
  END IF;
END $$;

RESET ROLE;
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.partnerships', 'DELETE')
     OR has_table_privilege('anon', 'public.partnerships', 'TRUNCATE') THEN
    RAISE EXCEPTION 'B4 failed: anon still holds DELETE or TRUNCATE';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.partnerships', 'DELETE') THEN
    RAISE EXCEPTION 'B4 failed: authenticated lost its DELETE grant';
  END IF;
END $$;

-- Restore the pending fixture so the final-state check sees all three rows.
INSERT INTO public.partnerships (user_id_1, user_id_2, status) VALUES (9101, 9103, 'pending');

-- ---------------------------------------------------------------------------
-- Final state: alice-bob accepted, alice-carol pending, carol-dave cancelled
-- with dave still the requester.
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9101 AND user_id_2 = 9102) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'final failed: alice-bob is not accepted';
  END IF;

  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9101 AND user_id_2 = 9103) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'final failed: alice-carol is not pending';
  END IF;

  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships
          WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS DISTINCT FROM 9104
     OR (SELECT cancel_expires_at FROM public.partnerships
          WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS NULL THEN
    RAISE EXCEPTION 'final failed: carol-dave is not cancelled with dave as requester';
  END IF;

  IF (SELECT cancel_declined_at FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104)
       IS DISTINCT FROM current_setting('test.declined_at')::timestamptz THEN
    RAISE EXCEPTION 'final failed: the cooldown timestamp changed during the tamper section';
  END IF;
END $$;

ROLLBACK;

SELECT 'partnership-cancellation: passed (A request by either member, A-post non-member/anon unchanged, B accepted/cancelled delete denied for both members, B pending delete works, B anon denied/no anon DELETE or TRUNCATE, C requester/partner revert, C partner decline timestamp, C raw PATCH cannot clear/forge it, C non-member denied, C revert of non-cancelled denied, C service-role revert keeps it, C requester restore keeps it, E tamper denied, E ordinary update allowed, final state)' AS result;

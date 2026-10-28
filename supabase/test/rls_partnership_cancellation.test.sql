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
-- Contract under test (docs/features/partnership/doc.md "Security & Authorization Boundaries"
-- and docs/supabase/schema/doc.md):
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
--     cancelled row is left untouched, and `anon` holds no `DELETE`/`TRUNCATE`;
--   * `partnership_request_cancel` performs the request for either member,
--     rejects a non-member and an `anon` caller, and refuses a retry inside
--     the 24h cooldown (`API-VALIDATION-013`);
--   * `partnership_cancel_revert` restores the caller's `cancelled` row to
--     `accepted` with both cancel fields cleared, and rejects a non-member or
--     a non-cancelled row (`API-VALIDATION-011`);
--   * `partnership_expire_cancellations` reverts every expired request in one
--     statement, leaves non-expired ones and `cancel_declined_at` alone, and is
--     not executable by `authenticated` or `anon`;
--   * `partnership_get_cancellation` returns the caller's cancelled row with the
--     counterpart identity and `requested_by_me`, nothing for a non-member, and
--     lazily expires a stale request before answering;
--   * `partnership_get_cancellation_partner` resolves the counterpart of a
--     cancelled row for the backend and is not executable by clients.
--
-- Sections A (request, raw and RPC), B (delete), C (revert), D (cooldown),
-- E (tamper), G (expiry), K (cancellation read), L (push partner), F
-- (accept by partner), I (double-accept guard and cancelled-sender freeze) and
-- the J mood checks; H (11.1/11.2) belongs to a later item.
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
--   9101 alice / 9102 bob / 9103 carol / 9104 dave / 9105 erin / 9106 frank
--   alice-bob   accepted  (request by user_id_1, then member revert)
--   carol-dave  accepted  (request by user_id_2, then partner revert)
--   alice-carol pending   (revert of a non-cancelled row)
--   erin-frank  accepted  (RPC request and cooldown; declined 25h ago so the
--                          first RPC call is allowed)
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9101, '00000000-0000-0000-0000-000000000101', 'alice@cancellation-test.local'),
  (9102, '00000000-0000-0000-0000-000000000102', 'bob@cancellation-test.local'),
  (9103, '00000000-0000-0000-0000-000000000103', 'carol@cancellation-test.local'),
  (9104, '00000000-0000-0000-0000-000000000104', 'dave@cancellation-test.local'),
  (9105, '00000000-0000-0000-0000-000000000105', 'erin@cancellation-test.local'),
  (9106, '00000000-0000-0000-0000-000000000106', 'frank@cancellation-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9101, 'Alice', 'CAL101'),
  (9102, 'Bob',   'CAL102'),
  (9103, 'Carol', 'CAL103'),
  (9104, 'Dave',  'CAL104'),
  (9105, 'Erin',  'CAL105'),
  (9106, 'Frank', 'CAL106');

INSERT INTO public.partnerships (user_id_1, user_id_2, status, cancel_declined_at) VALUES
  (9101, 9102, 'accepted', NULL),
  (9103, 9104, 'accepted', NULL),
  (9101, 9103, 'pending',  NULL),
  (9105, 9106, 'accepted', now() - interval '25 hours');

-- Resolve the ids while RLS is bypassed, so the non-member case can name a row
-- it is not allowed to see.
CREATE TEMP TABLE pids AS
SELECT
  max(id) FILTER (WHERE user_id_1 = 9101 AND user_id_2 = 9102) AS ab,
  max(id) FILTER (WHERE user_id_1 = 9103 AND user_id_2 = 9104) AS cd,
  max(id) FILTER (WHERE user_id_1 = 9105 AND user_id_2 = 9106) AS ef
FROM public.partnerships;

SELECT set_config('test.cd_id', cd::text, true) FROM pids;
SELECT set_config('test.ef_id', ef::text, true) FROM pids;

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

-- A6. the RPC performs the same request for user_id_1. The stored decline is
--     25h old, so the cooldown has run out (D covers the blocked case).
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000105"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9105 AND user_id_2 = 9106;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)', v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A6 failed: the RPC request was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9105 THEN
    RAISE EXCEPTION 'A6 failed: the RPC did not cancel the row with erin as requester';
  END IF;

  IF (SELECT cancel_expires_at FROM public.partnerships WHERE id = v_id)
       NOT BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 hour' THEN
    RAISE EXCEPTION 'A6 failed: the RPC expiry is not about 7 days ahead';
  END IF;
END $$;

-- A7. the RPC rejects a second request on the already-cancelled row.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000106"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9105 AND user_id_2 = 9106;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)', v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A7 failed: a second RPC request gave %, expected 42501',
      coalesce(v_state, 'no error (the request was allowed)');
  END IF;

  IF (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9105 THEN
    RAISE EXCEPTION 'A7 failed: the second RPC request took over the existing one';
  END IF;
END $$;

-- A8. the RPC accepts the other member (user_id_2) as requester too.
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.partnerships
   SET status = 'accepted',
       cancel_requested_by = NULL,
       cancel_expires_at = NULL
 WHERE user_id_1 = 9105 AND user_id_2 = 9106;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000106"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9105 AND user_id_2 = 9106;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)', v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'A8 failed: the user_id_2 RPC request was refused with %', v_state;
  END IF;

  IF (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9106 THEN
    RAISE EXCEPTION 'A8 failed: the RPC did not record frank as requester';
  END IF;
END $$;

-- A9. a non-member cannot request someone else's partnership.
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.partnerships
   SET status = 'accepted',
       cancel_requested_by = NULL,
       cancel_expires_at = NULL
 WHERE user_id_1 = 9105 AND user_id_2 = 9106;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)',
    current_setting('test.ef_id')));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A9 failed: a non-member RPC request gave %, expected 42501',
      coalesce(v_state, 'no error (the request was allowed)');
  END IF;
END $$;

-- A10. anon cannot call the RPC at all (no EXECUTE grant).
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)',
    current_setting('test.ef_id')));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'A10 failed: the anon RPC call gave %, expected 42501',
      coalesce(v_state, 'no error (the request was allowed)');
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS DISTINCT FROM 'accepted'
     OR (SELECT cancel_requested_by FROM public.partnerships
          WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS NOT NULL THEN
    RAISE EXCEPTION 'A-post2 failed: a non-member or anon RPC call changed the erin-frank row';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. revert / decline
-- ---------------------------------------------------------------------------
-- C1. the requester (alice) reverts her own request through the RPC.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9101 AND user_id_2 = 9102;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_cancel_revert(%s)', v_id));
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

-- C2. the partner (carol) declines dave's request through the RPC.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000103"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_cancel_revert(%s)', v_id));
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

-- C3. a non-member cannot revert (raw and RPC).
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

  v_state := pg_temp.rls_try(format('SELECT public.partnership_cancel_revert(%s)',
    current_setting('test.cd_id')::integer));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C3 failed: the non-member RPC revert gave %, expected 42501',
      coalesce(v_state, 'no error (the revert was allowed)');
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

-- C4. a revert of a non-cancelled row is rejected (raw and RPC): the sender of
--     the pending alice-carol request may not promote it to accepted.
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

  v_state := pg_temp.rls_try(format('SELECT public.partnership_cancel_revert(%s)', v_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'C4 failed: the RPC on a pending row gave %, expected 42501',
      coalesce(v_state, 'no error (the revert was allowed)');
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
-- D. 24h cooldown after a partner decline
-- ---------------------------------------------------------------------------
-- D1. a decline inside the last 24h blocks the RPC request.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)', v_id));
  IF v_state IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'D1 failed: a request inside the cooldown gave %, expected P0001',
      coalesce(v_state, 'no error (the request was allowed)');
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'D1 failed: the refused request changed the row';
  END IF;
END $$;

-- D2. once the decline is older than 24h the same request succeeds.
RESET ROLE;
RESET request.jwt.claims;
ALTER TABLE public.partnerships DISABLE TRIGGER guard_public_partnerships_status;
UPDATE public.partnerships
   SET cancel_declined_at = now() - interval '25 hours'
 WHERE user_id_1 = 9103 AND user_id_2 = 9104;
ALTER TABLE public.partnerships ENABLE TRIGGER guard_public_partnerships_status;
SELECT set_config('test.declined_at',
  (SELECT cancel_declined_at::text FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104), true);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_id integer;
  v_state text;
BEGIN
  SELECT id INTO v_id FROM public.partnerships
    WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  v_state := pg_temp.rls_try(format('SELECT public.partnership_request_cancel(%s)', v_id));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'D2 failed: the request after the cooldown was refused with %', v_state;
  END IF;

  IF (SELECT status FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 'cancelled'
     OR (SELECT cancel_requested_by FROM public.partnerships WHERE id = v_id) IS DISTINCT FROM 9104 THEN
    RAISE EXCEPTION 'D2 failed: the RPC request after the cooldown did not cancel the row';
  END IF;
END $$;

-- D3. restore the carol-dave fixture for the tamper section.
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.partnerships
   SET status = 'accepted',
       cancel_requested_by = NULL,
       cancel_expires_at = NULL
 WHERE user_id_1 = 9103 AND user_id_2 = 9104;

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

-- ---------------------------------------------------------------------------
-- G. expiry reverts every expired request in one statement
-- ---------------------------------------------------------------------------
-- G1. an expired erin-frank request is reverted; the non-expired carol-dave
--     request and the cooldown timestamp are left alone.
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.partnerships
   SET status = 'cancelled',
       cancel_requested_by = 9105,
       cancel_expires_at = now() - interval '1 minute'
 WHERE user_id_1 = 9105 AND user_id_2 = 9106;

DO $$
DECLARE
  v_count integer;
  v_before timestamptz;
BEGIN
  SELECT cancel_declined_at INTO v_before FROM public.partnerships
    WHERE user_id_1 = 9105 AND user_id_2 = 9106;

  v_count := public.partnership_expire_cancellations();
  IF v_count < 1 THEN
    RAISE EXCEPTION 'G1 failed: the expiry reverted % rows, expected at least 1', v_count;
  END IF;

  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS DISTINCT FROM 'accepted'
     OR (SELECT cancel_requested_by FROM public.partnerships
          WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS NOT NULL
     OR (SELECT cancel_expires_at FROM public.partnerships
          WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS NOT NULL THEN
    RAISE EXCEPTION 'G1 failed: the expired request was not reverted cleanly';
  END IF;

  -- The pair survives and the cooldown timestamp is untouched.
  IF (SELECT count(*) FROM public.partnerships
       WHERE user_id_1 = 9105 AND user_id_2 = 9106) <> 1 THEN
    RAISE EXCEPTION 'G1 failed: the expiry removed the partnership row';
  END IF;

  IF (SELECT cancel_declined_at FROM public.partnerships
       WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'G1 failed: the expiry changed cancel_declined_at';
  END IF;

  -- The non-expired carol-dave request is untouched.
  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9103 AND user_id_2 = 9104) IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'G1 failed: the expiry reverted a non-expired request';
  END IF;
END $$;

-- G2. the expiry is backend-only: neither authenticated nor anon may call it.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try('SELECT public.partnership_expire_cancellations()');
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G2 failed: the authenticated call gave %, expected 42501',
      coalesce(v_state, 'no error (the call was allowed)');
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.partnership_expire_cancellations()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.partnership_expire_cancellations()', 'EXECUTE') THEN
    RAISE EXCEPTION 'G2 failed: the expiry function is executable by a client role';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.partnership_expire_cancellations()', 'EXECUTE') THEN
    RAISE EXCEPTION 'G2 failed: service_role cannot execute the expiry function';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- K. read the cancellation for the PartnerScreen (B.4)
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.user_profiles SET profile_pic_url = 'cal-test/carol.png' WHERE user_id = 9103;
UPDATE public.user_profiles SET profile_pic_url = 'cal-test/dave.png'  WHERE user_id = 9104;

-- K1. the requester (dave) gets carol's identity and requested_by_me = true.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_n integer;
  v_pid integer;
  v_partner integer;
  v_name text;
  v_pic text;
  v_by_me boolean;
BEGIN
  SELECT count(*) INTO v_n FROM public.partnership_get_cancellation();
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'K1 failed: the request read returned % rows, expected 1', v_n;
  END IF;

  SELECT partnership_id, partner_id, partner_display_name, partner_profile_pic_url, requested_by_me
    INTO v_pid, v_partner, v_name, v_pic, v_by_me
    FROM public.partnership_get_cancellation();

  IF v_pid IS DISTINCT FROM current_setting('test.cd_id')::integer
     OR v_partner IS DISTINCT FROM 9103
     OR v_name IS DISTINCT FROM 'Carol'
     OR v_pic IS DISTINCT FROM 'cal-test/carol.png'
     OR v_by_me IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'K1 failed: unexpected read (% %, % %, %)',
      v_pid, v_partner, v_name, v_pic, v_by_me;
  END IF;
END $$;

-- K2. the partner (carol) gets the same row with requested_by_me = false.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000103"}';
DO $$
DECLARE
  v_pid integer;
  v_partner integer;
  v_name text;
  v_pic text;
  v_by_me boolean;
BEGIN
  SELECT partnership_id, partner_id, partner_display_name, partner_profile_pic_url, requested_by_me
    INTO v_pid, v_partner, v_name, v_pic, v_by_me
    FROM public.partnership_get_cancellation();

  IF v_pid IS DISTINCT FROM current_setting('test.cd_id')::integer
     OR v_partner IS DISTINCT FROM 9104
     OR v_name IS DISTINCT FROM 'Dave'
     OR v_pic IS DISTINCT FROM 'cal-test/dave.png'
     OR v_by_me IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'K2 failed: unexpected read (% %, % %, %)',
      v_pid, v_partner, v_name, v_pic, v_by_me;
  END IF;
END $$;

-- K3. a non-member gets nothing.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';
DO $$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.partnership_get_cancellation();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'K3 failed: a non-member saw % cancellation rows', v_n;
  END IF;
END $$;

-- K4. an expired request is reverted by the read and returns no row.
RESET ROLE;
RESET request.jwt.claims;
UPDATE public.partnerships
   SET status = 'cancelled',
       cancel_requested_by = 9105,
       cancel_expires_at = now() - interval '1 minute'
 WHERE user_id_1 = 9105 AND user_id_2 = 9106;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000106"}';
DO $$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.partnership_get_cancellation();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'K4 failed: the expired request still returned % rows', v_n;
  END IF;

  IF (SELECT status FROM public.partnerships
       WHERE user_id_1 = 9105 AND user_id_2 = 9106) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'K4 failed: the read did not lazily expire the request';
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;

-- ---------------------------------------------------------------------------
-- L. backend resolves the ex-partner for the request push (B.5)
-- ---------------------------------------------------------------------------
-- L1. service_role resolves the cancelled carol-dave pair in both directions.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF public.partnership_get_cancellation_partner(9104) IS DISTINCT FROM 9103
     OR public.partnership_get_cancellation_partner(9103) IS DISTINCT FROM 9104 THEN
    RAISE EXCEPTION 'L1 failed: the cancelled pair was not resolved in both directions';
  END IF;
END $$;

-- L2. an accepted pair and an unknown user resolve to NULL.
DO $$
BEGIN
  IF public.partnership_get_cancellation_partner(9101) IS NOT NULL THEN
    RAISE EXCEPTION 'L2 failed: the accepted alice-bob pair resolved an ex-partner';
  END IF;

  IF public.partnership_get_cancellation_partner(9199) IS NOT NULL THEN
    RAISE EXCEPTION 'L2 failed: an unknown user resolved an ex-partner';
  END IF;
END $$;

-- L3. clients cannot call it.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try('SELECT public.partnership_get_cancellation_partner(9103)');
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'L3 failed: the authenticated call gave %, expected 42501',
      coalesce(v_state, 'no error (the call was allowed)');
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.partnership_get_cancellation_partner(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.partnership_get_cancellation_partner(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'L3 failed: the function is executable by a client role';
  END IF;

  IF NOT has_function_privilege('service_role', 'public.partnership_get_cancellation_partner(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'L3 failed: service_role cannot execute the function';
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;

-- Restore the pending fixture so the final-state check sees all three rows.
DELETE FROM public.partnerships WHERE user_id_1 = 9101 AND user_id_2 = 9103;
INSERT INTO public.partnerships (user_id_1, user_id_2, status) VALUES (9101, 9103, 'pending');

-- ---------------------------------------------------------------------------
-- I. double-accept hole (B.7)
-- ---------------------------------------------------------------------------
RESET ROLE;
RESET request.jwt.claims;
INSERT INTO public.partnerships (user_id_1, user_id_2, status) VALUES (9105, 9103, 'pending');
DO $$
DECLARE
  v_pid integer;
  v_state text;
BEGIN
  SELECT id INTO v_pid FROM public.partnerships WHERE user_id_1 = 9105 AND user_id_2 = 9103;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000103"}';
  v_state := pg_temp.rls_try(format('SELECT public.partnership_accept(%s)', v_pid));
  RESET ROLE;
  RESET request.jwt.claims;
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'I1 failed: double-accept gave %, expected 42501', coalesce(v_state, 'no error');
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = v_pid) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'I1 failed: the pending row was accepted despite existing partnership';
  END IF;
  DELETE FROM public.partnerships WHERE id = v_pid;
END $$;

-- I2. a cancelled sender cannot start a new pairing (B.8).
RESET ROLE;
RESET request.jwt.claims;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  v_msg text;
BEGIN
  BEGIN
    PERFORM public.partnership_request('frank@cancellation-test.local', 'CAL106', 9103);
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;

  IF v_msg IS NULL OR v_msg NOT LIKE 'API-VALIDATION-004:%' THEN
    RAISE EXCEPTION 'I2 failed: the cancelled sender request gave %',
      coalesce(v_msg, 'no error (the request was created)');
  END IF;

  IF EXISTS (SELECT 1 FROM public.partnerships
              WHERE user_id_1 = 9103 AND user_id_2 = 9106) THEN
    RAISE EXCEPTION 'I2 failed: the cancelled sender created a request';
  END IF;
END $$;
RESET ROLE;

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

-- ---------------------------------------------------------------------------
-- J. moods follow the partnership (A.5 cascade, A.6 write, A.7 policy)
-- ---------------------------------------------------------------------------
-- J2. mood_set writes the caller's accepted partnership id (A.6).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}';
DO $$
DECLARE
  v_partnership_id integer;
BEGIN
  PERFORM public.mood_set('🧪');

  SELECT partnership_id INTO v_partnership_id FROM public.moods
   WHERE user_id = 9101 ORDER BY id DESC LIMIT 1;

  IF v_partnership_id IS DISTINCT FROM (SELECT id FROM public.partnerships
       WHERE user_id_1 = 9101 AND user_id_2 = 9102) THEN
    RAISE EXCEPTION 'J2 failed: mood_set did not attach the accepted partnership';
  END IF;
END $$;

-- J3. a user without an accepted partnership writes NULL.
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}';
DO $$
DECLARE
  v_partnership_id integer;
BEGIN
  PERFORM public.mood_set('🧪');

  SELECT partnership_id INTO v_partnership_id FROM public.moods
   WHERE user_id = 9104 ORDER BY id DESC LIMIT 1;

  IF v_partnership_id IS NOT NULL THEN
    RAISE EXCEPTION 'J3 failed: an unpaired mood did not keep partnership_id NULL';
  END IF;
END $$;

-- J4. a client cannot attach a mood to a partnership it does not belong to
--     (the cancelled carol-dave row).
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}';
DO $$
DECLARE
  v_state text;
BEGIN
  v_state := pg_temp.rls_try(format($q$
    INSERT INTO public.moods (user_id, mood_type_id, partnership_id)
    VALUES (9101, NULL, %s)$q$, current_setting('test.cd_id')));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'J4 failed: attaching a mood to a foreign partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- J5. a mood may stay unattached, but it cannot be attached to, or moved onto,
--     a partnership the caller belongs to that is not accepted.
DO $$
DECLARE
  v_mood_id integer;
  v_pending_id integer;
  v_state text;
BEGIN
  INSERT INTO public.moods (user_id, mood_type_id) VALUES (9101, NULL)
    RETURNING id INTO v_mood_id;

  SELECT id INTO v_pending_id FROM public.partnerships
   WHERE user_id_1 = 9101 AND user_id_2 = 9103;

  v_state := pg_temp.rls_try(format($q$
    INSERT INTO public.moods (user_id, mood_type_id, partnership_id)
    VALUES (9101, NULL, %s)$q$, v_pending_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'J5 failed: attaching a pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try(format($q$
    UPDATE public.moods SET partnership_id = %s WHERE id = %s$q$, v_pending_id, v_mood_id));
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'J5 failed: moving a mood onto a pending partnership gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  IF (SELECT partnership_id FROM public.moods WHERE id = v_mood_id) IS NOT NULL THEN
    RAISE EXCEPTION 'J5 failed: the mood moved despite the rejection';
  END IF;

  v_state := pg_temp.rls_try(format($q$
    INSERT INTO public.moods (user_id, mood_type_id, partnership_id)
    VALUES (9101, NULL, %s)$q$,
    (SELECT id FROM public.partnerships
      WHERE user_id_1 = 9101 AND user_id_2 = 9102)));
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'J5 failed: attaching the accepted partnership gave %', v_state;
  END IF;
END $$;

RESET ROLE;
RESET request.jwt.claims;

-- J1. deleting the partnership cascades its moods (A.5). Runs last because it
--     removes the carol-dave fixture.
DO $$
DECLARE
  v_mood_id integer;
BEGIN
  INSERT INTO public.moods (user_id, mood_type_id, partnership_id)
    SELECT 9104, NULL, id FROM public.partnerships
     WHERE user_id_1 = 9103 AND user_id_2 = 9104
    RETURNING id INTO v_mood_id;

  IF v_mood_id IS NULL THEN
    RAISE EXCEPTION 'J1 failed: the mood insert was refused';
  END IF;

  DELETE FROM public.partnerships
   WHERE user_id_1 = 9103 AND user_id_2 = 9104;

  IF EXISTS (SELECT 1 FROM public.moods WHERE id = v_mood_id) THEN
    RAISE EXCEPTION 'J1 failed: the mood outlived the partnership';
  END IF;
END $$;

ROLLBACK;

SELECT 'partnership-cancellation: passed (A request by either member, A RPC request by either member/non-member/anon/second request, A-post non-member/anon unchanged, B accepted/cancelled delete denied for both members, B pending delete works, B anon denied/no anon DELETE or TRUNCATE, C requester/partner revert via RPC, C partner decline timestamp, C raw PATCH cannot clear/forge it, C non-member denied raw/RPC, C revert of non-cancelled denied raw/RPC, C service-role revert keeps it, C requester restore keeps it, D cooldown blocks then allows, E tamper denied, E ordinary update allowed, G expiry reverts only expired, G expiry backend-only, K requester/partner read, K non-member empty, K lazy expiry, L push partner both ways/NULL/client denied, F requester cannot accept, F partner accepts and cascades, F expired accept rejected, J mood cascade, J mood_set partnership attach/null, J mood policy foreign/pending rejected, I paired recipient cannot accept a second request, I cancelled sender cannot start a new pairing, final state)' AS result;

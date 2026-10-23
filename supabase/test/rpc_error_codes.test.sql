-- =============================================================================
-- RPC raises carry an app error code (todo.md 10.18)
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rpc_error_codes.test.sql
--
-- The client resolves the code to a localized message, so the code prefix is a
-- contract: the RPCs below must raise '<CODE>: <developer text>' and nothing
-- else. Any drift fails here.
--
--   partnership_request        API-VALIDATION-003  caller id not resolvable
--                              API-VALIDATION-004  sender already partnered
--                              API-VALIDATION-005  email/code do not match
--                              API-VALIDATION-006  self-invitation
--   missyou_send               API-VALIDATION-007  no accepted partnership
--   partnership_request_cancel API-VALIDATION-010  no accepted partnership for the caller
--                              API-VALIDATION-013  a decline is inside the 24h cooldown
--   partnership_cancel_revert  API-VALIDATION-011  no cancelled partnership for the caller
--   partnership_accept         API-VALIDATION-012  caller already has an active partnership
--   partnership_cancel_accept  API-VALIDATION-014  the cancellation request has expired
-- =============================================================================

BEGIN;

-- Unauthenticated postgres session: auth.uid() is NULL. Cleared explicitly so
-- the 003/007 cases stay deterministic if a runner sets session claims.
SELECT set_config('request.jwt.claims', '', true);
SELECT set_config('request.jwt.claim.sub', '', true);

-- Temporary assertion helper: run p_sql, expect a raise whose message starts
-- with p_expected. Lifted into pg_temp so it disappears with the rollback.
CREATE FUNCTION pg_temp.expect_raise(p_expected text, p_sql text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    v_msg := SQLERRM;
  END;

  IF v_msg IS NULL THEN
    RAISE EXCEPTION 'expected % but nothing was raised', p_expected;
  END IF;

  IF v_msg NOT LIKE p_expected || '%' THEN
    RAISE EXCEPTION 'expected % but got %', p_expected, v_msg;
  END IF;
END;
$fn$;

INSERT INTO public.users (id, auth_id, email) VALUES
  (9160, '00000000-0000-0000-0000-000000009160', 'rpc-codes-self@test.local'),
  (9161, '00000000-0000-0000-0000-000000009161', 'rpc-codes-target@test.local'),
  (9162, '00000000-0000-0000-0000-000000009162', 'rpc-codes-busy@test.local'),
  (9166, '00000000-0000-0000-0000-000000009166', 'rpc-codes-cancel@test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9160, 'Codes Self', 'SELF01'),
  (9161, 'Codes Target', 'TGT222'),
  (9162, 'Codes Busy', 'BUSY33'),
  (9166, 'Codes Cancel', 'CNCL66');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status, cancel_requested_by, cancel_expires_at, cancel_declined_at) VALUES
  (9163, 9162, 9161, 'accepted',  NULL, NULL, now()),
  (9164, 9161, 9166, 'cancelled', 9161, now() - interval '1 minute', NULL),
  (9165, 9166, 9161, 'pending',   NULL, NULL, NULL);

-- 003: no auth context and no override -> user_current_id() is NULL.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-003',
  $q$SELECT public.partnership_request('rpc-codes-target@test.local', 'TGT222', NULL)$q$
);

-- 004: sender 9162 already has an accepted partnership.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-004',
  $q$SELECT public.partnership_request('rpc-codes-target@test.local', 'TGT222', 9162)$q$
);

-- 005: sender 9160 is free but no profile matches that email + code.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-005',
  $q$SELECT public.partnership_request('nobody@test.local', 'ZZZZZZ', 9160)$q$
);

-- 006: sender 9160 invites themself with their own code.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-006',
  $q$SELECT public.partnership_request('rpc-codes-self@test.local', 'SELF01', 9160)$q$
);

-- 007: missyou_send with no accepted partnership for the current user.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-007',
  $q$SELECT public.missyou_send()$q$
);

-- 010: 9160 has no accepted partnership, so the cancel request finds no row.
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000009160"}', true);
SELECT pg_temp.expect_raise(
  'API-VALIDATION-010',
  $q$SELECT public.partnership_request_cancel(9163)$q$
);

-- 013: 9161 is a member of accepted 9163, declined moments ago.
SELECT set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000009161"}', true);
SELECT pg_temp.expect_raise(
  'API-VALIDATION-013',
  $q$SELECT public.partnership_request_cancel(9163)$q$
);

-- 011: 9161 asks to revert an accepted (not cancelled) partnership.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-011',
  $q$SELECT public.partnership_cancel_revert(9163)$q$
);

-- 012: 9161 already holds accepted 9163, so accepting pending 9165 is refused.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-012',
  $q$SELECT public.partnership_accept(9165)$q$
);

-- 014: cancelled 9164 expired; 9166 is the member who did not request it.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-014',
  $q$SELECT public.partnership_cancel_accept(9164, 9166)$q$
);

ROLLBACK;

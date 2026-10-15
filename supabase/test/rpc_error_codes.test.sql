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
-- contract: request_partnership and send_missyou must raise
-- '<CODE>: <developer text>' and nothing else. Any drift fails here.
--
--   request_partnership  API-VALIDATION-003  caller id not resolvable
--                        API-VALIDATION-004  sender already partnered
--                        API-VALIDATION-005  email/code do not match
--                        API-VALIDATION-006  self-invitation
--   send_missyou         API-VALIDATION-007  no accepted partnership
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
  (9162, '00000000-0000-0000-0000-000000009162', 'rpc-codes-busy@test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9160, 'Codes Self', 'SELF01'),
  (9161, 'Codes Target', 'TGT222'),
  (9162, 'Codes Busy', 'BUSY33');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9163, 9162, 9161, 'accepted');

-- 003: no auth context and no override -> current_user_id() is NULL.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-003',
  $q$SELECT public.request_partnership('rpc-codes-target@test.local', 'TGT222', NULL)$q$
);

-- 004: sender 9162 already has an accepted partnership.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-004',
  $q$SELECT public.request_partnership('rpc-codes-target@test.local', 'TGT222', 9162)$q$
);

-- 005: sender 9160 is free but no profile matches that email + code.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-005',
  $q$SELECT public.request_partnership('nobody@test.local', 'ZZZZZZ', 9160)$q$
);

-- 006: sender 9160 invites themself with their own code.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-006',
  $q$SELECT public.request_partnership('rpc-codes-self@test.local', 'SELF01', 9160)$q$
);

-- 007: send_missyou with no accepted partnership for the current user.
SELECT pg_temp.expect_raise(
  'API-VALIDATION-007',
  $q$SELECT public.send_missyou()$q$
);

ROLLBACK;

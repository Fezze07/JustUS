-- =============================================================================
-- purge_user_devices_dead_sessions: rows die with the session they belong to
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/prune_user_devices_dead_sessions.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures. One auth user (the handle_new_auth_user trigger provisions the
-- public.users row) and two auth.sessions rows (one live, one expired but not
-- yet purged by GoTrue). The four user_devices rows are inserted in the same
-- DO block that resolves the provisioned user id, covering every state:
--   * linked to a live session                          -- must survive
--   * linked to an expired session (row still present)  -- must be pruned
--   * linked to a session that no longer exists (logged out) -- must be pruned
--   * no session_id at all (pre-column / backstop case) -- must survive
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email)
VALUES ('00000000-0000-0000-0000-000000000301', 'prune-dev@justus.test');

INSERT INTO auth.sessions (id, user_id, not_after) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000301', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000301', now() - interval '1 hour');

DO $$
DECLARE
  v_user_id integer;
  v_dev_count integer;
BEGIN
  SELECT id INTO v_user_id FROM public.users WHERE auth_id = '00000000-0000-0000-0000-000000000301';
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fixture failed: the auth user was not provisioned';
  END IF;

  INSERT INTO public.user_devices (user_id, device_token, session_id) VALUES
    (v_user_id, 'fcm-token-live-session-0001', '00000000-0000-0000-0000-00000000a001'),
    (v_user_id, 'fcm-token-expired-session-0002', '00000000-0000-0000-0000-00000000a002'),
    (v_user_id, 'fcm-token-gone-session-0003', '00000000-0000-0000-0000-00000000dead'),
    (v_user_id, 'fcm-token-null-session-0004', NULL);

  -- Pre-flight: a fixture that failed to insert would leave every "must be
  -- gone" assertion satisfied for the wrong reason.
  SELECT count(*) INTO v_dev_count
  FROM public.user_devices WHERE device_token IN (
    'fcm-token-live-session-0001',
    'fcm-token-expired-session-0002',
    'fcm-token-gone-session-0003',
    'fcm-token-null-session-0004'
  );
  IF v_dev_count <> 4 THEN
    RAISE EXCEPTION 'fixture failed: expected 4 user_devices rows, found %', v_dev_count;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A. The prune removes exactly the two dead-session rows and returns 2.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pruned integer;
  v_user_id integer;
BEGIN
  SELECT public.purge_user_devices_dead_sessions() INTO v_pruned;
  SELECT id INTO v_user_id FROM public.users WHERE auth_id = '00000000-0000-0000-0000-000000000301';

  IF v_pruned <> 2 THEN
    RAISE EXCEPTION 'A failed: prune returned %, expected 2', v_pruned;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.user_devices WHERE device_token = 'fcm-token-live-session-0001') THEN
    RAISE EXCEPTION 'A failed: the live-session row was pruned';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_devices WHERE device_token = 'fcm-token-null-session-0004') THEN
    RAISE EXCEPTION 'A failed: the sessionless row was pruned';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_devices WHERE device_token = 'fcm-token-expired-session-0002') THEN
    RAISE EXCEPTION 'A failed: the expired-session row survived';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_devices WHERE device_token = 'fcm-token-gone-session-0003') THEN
    RAISE EXCEPTION 'A failed: the logged-out session row survived';
  END IF;

  IF (SELECT count(*) FROM public.user_devices WHERE user_id = v_user_id AND device_token IN (
    'fcm-token-live-session-0001',
    'fcm-token-expired-session-0002',
    'fcm-token-gone-session-0003',
    'fcm-token-null-session-0004'
  )) <> 2 THEN
    RAISE EXCEPTION 'A failed: unexpected number of rows survived the prune';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. Idempotent: a second call prunes nothing else.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_pruned integer;
BEGIN
  SELECT public.purge_user_devices_dead_sessions() INTO v_pruned;
  IF v_pruned <> 0 THEN
    RAISE EXCEPTION 'B failed: the second call pruned % more rows', v_pruned;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. Only postgres and service_role may call it; anon and authenticated are
--    locked out, so the sweep is not a public DELETE by another name.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.purge_user_devices_dead_sessions()', 'EXECUTE') THEN
    RAISE EXCEPTION 'C failed: anon can EXECUTE purge_user_devices_dead_sessions';
  END IF;
  IF has_function_privilege('authenticated', 'public.purge_user_devices_dead_sessions()', 'EXECUTE') THEN
    RAISE EXCEPTION 'C failed: authenticated can EXECUTE purge_user_devices_dead_sessions';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.purge_user_devices_dead_sessions()', 'EXECUTE') THEN
    RAISE EXCEPTION 'C failed: service_role cannot EXECUTE purge_user_devices_dead_sessions';
  END IF;
END $$;

ROLLBACK;

SELECT 'prune-user-devices-dead-sessions: passed (fixtures, A exact prune of dead/expired/absent sessions, B idempotent, C anon/authenticated locked out, service_role allowed)' AS result;
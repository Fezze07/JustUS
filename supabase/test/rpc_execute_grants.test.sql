-- =============================================================================
-- Function EXECUTE grants: which roles may call which RPC
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rpc_execute_grants.test.sql
--
-- GRANT EXECUTE ... TO PUBLIC is the usual Supabase footgun: it silently makes
-- a function callable by anon. This file pins the grant matrix so that adding
-- a function, or widening a grant, has to be a deliberate change.
--
-- Three lists are asserted:
--   * client RPCs that authenticated users must be able to call;
--   * backend-only RPCs that authenticated users must NOT be able to call;
--   * the exhaustive set of functions anon can reach. Any function outside that
--     allowlist fails the test.
--
-- KNOWN DEFECT (logged in todo.md, deliberately not fixed here):
--   logs_cleanup(integer) is granted to PUBLIC, which includes anon. It is
--   not currently exploitable because RLS on the four log tables denies the
--   DELETE for every non-service_role role -- section 5 asserts that
--   compensating control explicitly, so it is documented rather than assumed.
--   It is listed in the anon allowlist below to keep this file green until the
--   grant is narrowed to postgres and service_role.
-- =============================================================================

BEGIN;

-- Try a statement and return the SQLSTATE if it raises, or NULL on success.
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
-- A: client RPCs are callable by authenticated, and not by anon
--
--    `authenticated` is simulated with a real JWT sub so that functions which
--    check auth.uid() behave as they do in production.
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9201, '00000000-0000-0000-0000-000000000201', 'a@rpc-test.local'),
  (9202, '00000000-0000-0000-0000-000000000202', 'b@rpc-test.local');
INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9201, 9201, 9202, 'accepted');

DO $$
DECLARE
  v_fn text[] := ARRAY[
    'public.partnership_accept(integer)',
    'public.user_current_id()',
    'public.partnership_generate_code()',
    'public.partnership_get_accepted_partner(integer)',
    'public.emoji_get_or_create(text)',
    'public.partnership_get_pending_invitations()',
    'public.partnership_is_member(integer)',
    'public.partnership_is_partner(integer)',
    'public.partnership_cancel_revert(integer)',
    'public.partnership_request_cancel(integer)',
    'public.partnership_get_cancellation()',
    'public.missyou_send()',
    'public.mood_set(text)'
  ];
  v_sig text;
  v_denied text := '';
BEGIN
  FOREACH v_sig IN ARRAY v_fn
  LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      v_denied := v_denied || v_sig || ', ';
    END IF;
  END LOOP;

  IF v_denied <> '' THEN
    RAISE EXCEPTION 'A failed: authenticated cannot EXECUTE these client RPCs: %', v_denied;
  END IF;
END $$;

-- A2: the RPCs that return somebody else's rows must be unreachable without a
--     session. The remaining client RPCs above are granted to PUBLIC but are
--     protected by RLS plus internal user_current_id() checks rather than by
--     the grant itself; that fragility is documented in section C's allowlist.
DO $$
DECLARE
  v_fn text[] := ARRAY[
    'public.partnership_get_pending_invitations()',
    'public.partnership_get_cancellation()',
    'public.partnership_request(text, text, integer)'
  ];
  v_sig text;
  v_offend text := '';
BEGIN
  FOREACH v_sig IN ARRAY v_fn
  LOOP
    IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      v_offend := v_offend || v_sig || ', ';
    END IF;
  END LOOP;

  IF v_offend <> '' THEN
    RAISE EXCEPTION 'A2 failed: anon can EXECUTE these user-data RPCs: %', v_offend;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B: backend-only RPCs are NOT callable by authenticated or anon
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_fn text[] := ARRAY[
    'public.debug_wipe_user_data(integer)',
    'public.partnership_expire_cancellations()',
    'public.partnership_get_cancellation_partner(integer)',
    'public.partnership_cancel_accept(integer, integer)',
    'public.partnership_get_names(integer)',
    'public.user_create_from_auth()',
    'public.device_purge_dead_sessions()',
    'public.game_update_question_status()'
  ];
  v_sig    text;
  v_offend text := '';
BEGIN
  FOREACH v_sig IN ARRAY v_fn
  LOOP
    IF has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      v_offend := v_offend || v_sig || ' (authenticated), ';
    END IF;
    IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      v_offend := v_offend || v_sig || ' (anon), ';
    END IF;
    IF NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
      v_offend := v_offend || v_sig || ' (service_role), ';
    END IF;
  END LOOP;

  IF v_offend <> '' THEN
    RAISE EXCEPTION 'B failed: backend-only RPCs with the wrong grants: %', v_offend;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C: the exhaustive anon allowlist. A function granted to anon that is not on
--    this list fails the test, which is the point of the file.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_anon_ok text[] := ARRAY[
    'public.partnership_accept(integer)',
    'public.logs_cleanup(integer)',          -- KNOWN DEFECT, see todo.md
    'public.user_current_id()',
    'public.drive_change_probe()',
    'public.partnership_generate_code()',
    'public.partnership_get_accepted_partner(integer)',
    'public.emoji_get_or_create(text)',
    'public.partnership_is_member(integer)',
    'public.partnership_is_partner(integer)',
    'public.partnership_reject(integer)',
    'public.missyou_send()',
    'public.util_set_updated_at()',
    'public.mood_set(text)',
    'public.util_update_updated_at()'
  ];
  r          record;
  v_sig      text;
  v_unlisted text := '';
  v_missing  text := '';
  v_total    int := 0;
BEGIN
  FOR r IN
    SELECT 'public.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')' AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
    ORDER BY 1
  LOOP
    v_total := v_total + 1;

    IF NOT (r.sig = ANY (v_anon_ok)) THEN
      v_unlisted := v_unlisted || r.sig || ', ';
    END IF;
  END LOOP;

  IF v_unlisted <> '' THEN
    RAISE EXCEPTION 'C failed: anon can EXECUTE functions that are not on the reviewed allowlist: %', v_unlisted;
  END IF;

  -- The reverse direction too: an allowlisted function that loses its anon
  -- grant should have this list updated rather than silently rot.
  FOREACH v_sig IN ARRAY v_anon_ok
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.oid = v_sig::regprocedure
        AND has_function_privilege('anon', p.oid, 'EXECUTE')
    ) THEN
      v_missing := v_missing || v_sig || ', ';
    END IF;
  END LOOP;

  IF v_missing <> '' THEN
    RAISE EXCEPTION 'C failed: these allowlisted functions are no longer anon-reachable, update the list: %', v_missing;
  END IF;

  -- Guard against a sweep that matched nothing.
  IF v_total <> array_length(v_anon_ok, 1) THEN
    RAISE EXCEPTION 'C failed: anon reaches % function(s) but the allowlist has %', v_total, array_length(v_anon_ok, 1);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D: service_role can execute every function in the schema. The backend runs on
--    service_role, so a missing grant here is an outage.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r     record;
  v_bad text := '';
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
    ORDER BY 1
  LOOP
    IF NOT has_function_privilege('service_role', r.sig, 'EXECUTE') THEN
      v_bad := v_bad || r.sig || ', ';
    END IF;
  END LOOP;

  IF v_bad <> '' THEN
    RAISE EXCEPTION 'D failed: service_role cannot EXECUTE: %', v_bad;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E: the compensating control for the known logs_cleanup defect. RLS denies
--    the underlying DELETEs to every non-service_role caller, so the PUBLIC
--    grant cannot currently be used to destroy log data.
--
--    If this section ever starts failing, the PUBLIC grant on
--    logs_cleanup has become a live unauthenticated data-deletion endpoint
--    and must be narrowed immediately.
-- ---------------------------------------------------------------------------
INSERT INTO public.logs_api_access (method, path, status_code, created_at) VALUES
  ('GET', '/rpc-grant-old', 200, now() - interval '200 days'),
  ('GET', '/rpc-grant-new', 200, now());
INSERT INTO public.logs_api_errors (path, method, created_at) VALUES
  ('/rpc-grant-old', 'GET', now() - interval '200 days');
INSERT INTO public.logs_security_events (type, path, created_at) VALUES
  ('rpc-grant-old', '/rpc-grant-old', now() - interval '200 days');
INSERT INTO public.logs_notifications (user_id, type, status, created_at) VALUES
  (9201, 'push', 'rpc-grant-old', now() - interval '200 days');

-- anon may call the function (that is the known defect) ...
SET LOCAL ROLE anon;
DO $$
BEGIN
  PERFORM public.logs_cleanup();
END $$;
RESET ROLE;

-- ... but RLS must have stopped every DELETE.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access WHERE path = '/rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: anon DELETED from logs_api_access. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_errors WHERE path = '/rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: anon DELETED from logs_api_errors. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_security_events WHERE type = 'rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: anon DELETED from logs_security_events. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_notifications WHERE status = 'rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: anon DELETED from logs_notifications. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
END $$;

-- The same must hold for a signed-in user, since the PUBLIC grant covers
-- authenticated as well.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000201"}';
DO $$
BEGIN
  PERFORM public.logs_cleanup();
END $$;
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access WHERE path = '/rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: authenticated DELETED from logs_api_access. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_notifications WHERE status = 'rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: authenticated DELETED from logs_notifications. The PUBLIC grant on logs_cleanup is now exploitable; revoke it from PUBLIC.';
  END IF;
END $$;

-- service_role, which legitimately needs it, must still be able to run the job.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  PERFORM public.logs_cleanup();
END $$;
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.logs_api_access WHERE path = '/rpc-grant-old') THEN
    RAISE EXCEPTION 'E failed: service_role could not run logs_cleanup; the retention job would fail';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access WHERE path = '/rpc-grant-new') THEN
    RAISE EXCEPTION 'E failed: service_role deleted log rows inside the retention window';
  END IF;
END $$;

ROLLBACK;

SELECT 'rpc-execute-grants: passed (A client RPCs, B backend-only RPCs, C exhaustive anon allowlist, D service_role reaches everything, E logs_cleanup RLS backstop)' AS result;
-- =============================================================================
-- cleanup_old_logs: parameterization and the single 90-day retention policy
-- (covers audit finding 5.1)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/retention_cleanup_old_logs.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
--
-- The previous revision of this test inserted the result of cleanup_old_logs()
-- into a timestamptz column. The function RETURNS void, so that could never
-- work. The default is therefore verified behaviourally instead: rows are
-- seeded either side of the 90-day boundary and the sweep is checked to remove
-- the 91-day rows while keeping the 89-day ones, which pins the effective
-- cutoff far more precisely than reading catalog metadata.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS). One row per table per
-- age tier: 120 days (older than any cutoff), 91 and 89 days (straddling the
-- 90-day default), 60 days, and 10 days.
-- ---------------------------------------------------------------------------
INSERT INTO public.logs_api_access (method, path, status_code, created_at) VALUES
  ('GET', '/retention-120', 200, now() - interval '120 days'),
  ('GET', '/retention-91',  200, now() - interval '91 days'),
  ('GET', '/retention-89',  200, now() - interval '89 days'),
  ('GET', '/retention-60',  200, now() - interval '60 days'),
  ('GET', '/retention-10',  200, now() - interval '10 days');

INSERT INTO public.logs_api_errors (path, method, created_at) VALUES
  ('/retention-120', 'GET', now() - interval '120 days'),
  ('/retention-91',  'GET', now() - interval '91 days'),
  ('/retention-89',  'GET', now() - interval '89 days'),
  ('/retention-60',  'GET', now() - interval '60 days'),
  ('/retention-10',  'GET', now() - interval '10 days');

INSERT INTO public.logs_security_events (type, path, created_at) VALUES
  ('retention-120', '/retention-120', now() - interval '120 days'),
  ('retention-91',  '/retention-91',  now() - interval '91 days'),
  ('retention-89',  '/retention-89',  now() - interval '89 days'),
  ('retention-60',  '/retention-60',  now() - interval '60 days'),
  ('retention-10',  '/retention-10',  now() - interval '10 days');

INSERT INTO public.logs_notifications (type, status, created_at) VALUES
  ('push', 'retention-120', now() - interval '120 days'),
  ('push', 'retention-91',  now() - interval '91 days'),
  ('push', 'retention-89',  now() - interval '89 days'),
  ('push', 'retention-60',  now() - interval '60 days'),
  ('push', 'retention-10',  now() - interval '10 days');

-- Pre-flight: a fixture that failed to insert would leave every "must be gone"
-- assertion satisfied for the wrong reason.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.logs_api_access     WHERE path LIKE '/retention-%') <> 5
     OR (SELECT count(*) FROM public.logs_api_errors     WHERE path LIKE '/retention-%') <> 5
     OR (SELECT count(*) FROM public.logs_security_events WHERE type LIKE 'retention-%') <> 5
     OR (SELECT count(*) FROM public.logs_notifications   WHERE status LIKE 'retention-%') <> 5 THEN
    RAISE EXCEPTION 'fixture failed: the log fixtures are incomplete';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A. The function is parameterized and its DEFAULT is exactly 90, matching the
--    Node retentionJob.js LOG_RETENTION_DAYS=90.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_default text;
  v_result  text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cleanup_old_logs'
      AND p.pronargs > 0
  ) THEN
    RAISE EXCEPTION 'A failed: cleanup_old_logs is missing or takes no parameter';
  END IF;

  -- btrim the rendered default so `DEFAULT 90` and `DEFAULT  90` both compare
  -- equal. A substring match would also accept 900 or 190.
  SELECT btrim(pg_get_expr(p.proargdefaults, 0)) INTO v_default
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'cleanup_old_logs'
    AND p.pronargs > 0;

  IF v_default IS NULL THEN
    RAISE EXCEPTION 'A failed: cleanup_old_logs has no DEFAULT on p_days';
  END IF;
  IF v_default IS DISTINCT FROM '90' THEN
    RAISE EXCEPTION 'A failed: DEFAULT p_days is %, expected 90', v_default;
  END IF;

  -- RETURNS void, so the cutoff cannot be observed through the return value.
  SELECT pg_get_function_result(p.oid) INTO v_result
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'cleanup_old_logs'
    AND p.pronargs > 0;

  IF v_result IS DISTINCT FROM 'void' THEN
    RAISE EXCEPTION 'A failed: cleanup_old_logs no longer RETURNS void (%); the test must be revisited',
      coalesce(v_result, 'NULL');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. The DEFAULT sweep removes strictly-older-than-90-days rows in all four
--    tables and leaves everything at 89 days or newer.
-- ---------------------------------------------------------------------------
SELECT public.cleanup_old_logs();

DO $$
BEGIN
  -- 120 and 91 days old: both beyond the default cutoff, both gone.
  IF EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path IN ('/retention-120', '/retention-91')) OR
     EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path IN ('/retention-120', '/retention-91')) OR
     EXISTS (SELECT 1 FROM public.logs_security_events WHERE type IN ('retention-120', 'retention-91'))  OR
     EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status IN ('retention-120', 'retention-91')) THEN
    RAISE EXCEPTION 'B failed: a row older than the 90-day default survived';
  END IF;

  -- 89, 60 and 10 days old: all inside the window, all retained.
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path = '/retention-89') OR
     NOT EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path = '/retention-89') OR
     NOT EXISTS (SELECT 1 FROM public.logs_security_events WHERE type = 'retention-89')  OR
     NOT EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status = 'retention-89') THEN
    RAISE EXCEPTION 'B failed: an 89-day row was deleted by the 90-day default';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path = '/retention-60') OR
     NOT EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path = '/retention-60') OR
     NOT EXISTS (SELECT 1 FROM public.logs_security_events WHERE type = 'retention-60')  OR
     NOT EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status = 'retention-60') THEN
    RAISE EXCEPTION 'B failed: a 60-day row was deleted by the 90-day default';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path = '/retention-10') OR
     NOT EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path = '/retention-10') OR
     NOT EXISTS (SELECT 1 FROM public.logs_security_events WHERE type = 'retention-10')  OR
     NOT EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status = 'retention-10') THEN
    RAISE EXCEPTION 'B failed: a 10-day row was deleted by the 90-day default';
  END IF;

  -- Every table must hold exactly the three surviving tiers.
  IF (SELECT count(*) FROM public.logs_api_access     WHERE path LIKE '/retention-%') <> 3
     OR (SELECT count(*) FROM public.logs_api_errors     WHERE path LIKE '/retention-%') <> 3
     OR (SELECT count(*) FROM public.logs_security_events WHERE type LIKE 'retention-%') <> 3
     OR (SELECT count(*) FROM public.logs_notifications   WHERE status LIKE 'retention-%') <> 3 THEN
    RAISE EXCEPTION 'B failed: an unexpected number of rows survived the default sweep';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. An EXPLICIT p_days=30 removes the 60-day rows too, keeping only the
--    10-day tier. The DEFAULT stays 90, so no off-schema cron can silently
--    delete logs younger than 90 days.
-- ---------------------------------------------------------------------------
SELECT public.cleanup_old_logs(30);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path IN ('/retention-60', '/retention-89')) OR
     EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path IN ('/retention-60', '/retention-89')) OR
     EXISTS (SELECT 1 FROM public.logs_security_events WHERE type IN ('retention-60', 'retention-89'))  OR
     EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status IN ('retention-60', 'retention-89')) THEN
    RAISE EXCEPTION 'C failed: a row older than 30 days survived the explicit sweep';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.logs_api_access     WHERE path = '/retention-10') OR
     NOT EXISTS (SELECT 1 FROM public.logs_api_errors     WHERE path = '/retention-10') OR
     NOT EXISTS (SELECT 1 FROM public.logs_security_events WHERE type = 'retention-10')  OR
     NOT EXISTS (SELECT 1 FROM public.logs_notifications   WHERE status = 'retention-10') THEN
    RAISE EXCEPTION 'C failed: the 10-day row was deleted by the explicit 30-day sweep';
  END IF;

  IF (SELECT count(*) FROM public.logs_api_access     WHERE path LIKE '/retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_api_errors     WHERE path LIKE '/retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_security_events WHERE type LIKE 'retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_notifications   WHERE status LIKE 'retention-%') <> 1 THEN
    RAISE EXCEPTION 'C failed: an unexpected number of rows survived the explicit sweep';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D. non-positive and NULL p_days must be rejected, so a bad argument can
--    never produce a cutoff that deletes everything.
--
--    The RAISE that reports failure MUST live outside the sub-block whose
--    handler would otherwise catch it. Raising inside the block guarded by its
--    own `EXCEPTION WHEN others` handler is a self-satisfying no-op: the test
--    can never fail.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.cleanup_old_logs(0);
  EXCEPTION WHEN others THEN
    v_rejected := true;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'D failed: cleanup_old_logs(0) was allowed';
  END IF;
END $$;

DO $$
DECLARE
  v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.cleanup_old_logs(-1);
  EXCEPTION WHEN others THEN
    v_rejected := true;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'D failed: cleanup_old_logs(-1) was allowed';
  END IF;
END $$;

DO $$
DECLARE
  v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.cleanup_old_logs(NULL);
  EXCEPTION WHEN others THEN
    v_rejected := true;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'D failed: cleanup_old_logs(NULL) was allowed';
  END IF;
END $$;

-- D-post. None of the rejected calls may have deleted anything.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.logs_api_access     WHERE path LIKE '/retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_api_errors     WHERE path LIKE '/retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_security_events WHERE type LIKE 'retention-%') <> 1
     OR (SELECT count(*) FROM public.logs_notifications   WHERE status LIKE 'retention-%') <> 1 THEN
    RAISE EXCEPTION 'D failed: a rejected call still deleted rows';
  END IF;
END $$;

ROLLBACK;

SELECT 'retention-cleanup-old-logs: passed (pre-flight, A parameterized + default 90 + RETURNS void, B default sweep across the 90-day boundary, C explicit-30, D guard for 0/-1/NULL, D-post)' AS result;
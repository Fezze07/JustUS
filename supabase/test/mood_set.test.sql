-- =============================================================================
-- mood_set returns the persisted row (covers audit finding 3.7)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/mood_set.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
-- =============================================================================

BEGIN;

INSERT INTO public.users (id, auth_id, email) VALUES
  (9301, '00000000-0000-0000-0000-000000000301', 'mood-set@test.local');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}';

DO $$
DECLARE
  v_returned  public.moods;
  v_persisted public.moods;
BEGIN
  v_returned := public.mood_set('🧪');

  SELECT * INTO v_persisted
    FROM public.moods
   WHERE id = v_returned.id;

  IF v_returned.id IS NULL OR v_persisted.id IS NULL THEN
    RAISE EXCEPTION 'A failed: mood_set did not return the inserted row';
  END IF;
  IF v_returned.user_id IS DISTINCT FROM 9301 THEN
    RAISE EXCEPTION 'A failed: returned user_id is %, expected 9301',
      v_returned.user_id;
  END IF;
  IF v_returned.created_at IS DISTINCT FROM v_persisted.created_at THEN
    RAISE EXCEPTION 'A failed: returned created_at does not match the persisted row';
  END IF;
  IF v_returned.created_at IS NULL
     OR v_returned.created_at > now() + interval '1 minute' THEN
    RAISE EXCEPTION 'A failed: created_at is not a server timestamp (%)',
      v_returned.created_at;
  END IF;
END $$;

ROLLBACK;

SELECT 'mood-set: passed (returns the persisted row, server-stamped created_at)' AS result;

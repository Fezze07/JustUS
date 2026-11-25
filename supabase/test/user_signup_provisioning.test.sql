-- =============================================================================
-- user_create_from_auth: signup metadata becomes the display name
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/user_signup_provisioning.test.sql
--
-- The client sends the chosen name as `{'username': name}` in the signUp
-- metadata. The trigger must store the trimmed value and only fall back to the
-- email local part when the metadata is missing or blank.
-- =============================================================================

BEGIN;

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-000000000401', 'named-local@justus.test', '{"username":"  Alice  "}'::jsonb),
  ('00000000-0000-0000-0000-000000000402', 'blank-local@justus.test', '{"username":"   "}'::jsonb),
  ('00000000-0000-0000-0000-000000000403', 'missing-local@justus.test', NULL);

DO $$
DECLARE
  v_named   text;
  v_blank   text;
  v_missing text;
BEGIN
  SELECT p.display_name INTO v_named
  FROM public.user_profiles p
  JOIN public.users u ON u.id = p.user_id
  WHERE u.auth_id = '00000000-0000-0000-0000-000000000401';

  SELECT p.display_name INTO v_blank
  FROM public.user_profiles p
  JOIN public.users u ON u.id = p.user_id
  WHERE u.auth_id = '00000000-0000-0000-0000-000000000402';

  SELECT p.display_name INTO v_missing
  FROM public.user_profiles p
  JOIN public.users u ON u.id = p.user_id
  WHERE u.auth_id = '00000000-0000-0000-0000-000000000403';

  IF v_named IS DISTINCT FROM 'Alice' THEN
    RAISE EXCEPTION 'A failed: the signup username was stored as %, expected Alice',
      coalesce(v_named, 'NULL');
  END IF;
  IF v_blank IS DISTINCT FROM 'blank-local' THEN
    RAISE EXCEPTION 'B failed: a blank username was stored as %, expected the email local part',
      coalesce(v_blank, 'NULL');
  END IF;
  IF v_missing IS DISTINCT FROM 'missing-local' THEN
    RAISE EXCEPTION 'C failed: missing metadata was stored as %, expected the email local part',
      coalesce(v_missing, 'NULL');
  END IF;
END $$;

ROLLBACK;

SELECT 'user-signup-provisioning: passed (A trimmed username, B blank fallback, C missing fallback)' AS result;

-- =============================================================================
-- drive_items.name UNIQUE constraint (finding 17.3)
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/drive_items_name_unique.test.sql
--
-- The constraint is what makes `POST /media/complete` upsert on retry instead
-- of inserting a second row: without it, the two rows share `name` and the
-- download resolver can no longer identify the file deterministically.
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
-- A: the constraint exists on public.drive_items(name).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_def
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND t.relname = 'drive_items'
    AND c.conname = 'drive_items_name_key';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'A failed: drive_items_name_key constraint is missing';
  END IF;

  IF v_def NOT LIKE 'UNIQUE (name)%' THEN
    RAISE EXCEPTION 'A failed: drive_items_name_key is not UNIQUE (name): %', v_def;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B: a duplicate name is rejected with 23505 (unique_violation), while a
--    different name still inserts. Both rows are removed by the rollback.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_state text;
  v_rows  int;
BEGIN
  INSERT INTO public.drive_items (type, name)
  VALUES ('image', 'uploads/9001/retry.jpg');

  v_state := pg_temp.rls_try(
    'INSERT INTO public.drive_items (type, name) VALUES (''image'', ''uploads/9001/retry.jpg'')');

  IF v_state IS DISTINCT FROM '23505' THEN
    RAISE EXCEPTION 'B failed: a duplicate name gave %, expected 23505 (unique_violation)',
      coalesce(v_state, 'no error (the duplicate was allowed)');
  END IF;

  INSERT INTO public.drive_items (type, name)
  VALUES ('image', 'uploads/9001/other.jpg');

  SELECT count(*) INTO v_rows
  FROM public.drive_items
  WHERE name IN ('uploads/9001/retry.jpg', 'uploads/9001/other.jpg');

  IF v_rows <> 2 THEN
    RAISE EXCEPTION 'B failed: expected 2 distinct rows, found %', v_rows;
  END IF;
END $$;

ROLLBACK;

SELECT 'drive-items-name-unique: passed (A constraint definition, B duplicate rejected at 23505)' AS result;

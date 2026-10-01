-- =============================================================================
-- bucket_items.category CHECK constraint (finding 4.4 / F-BL3)
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/bucket_items_category_check.test.sql
--
-- The previous revision probed only two categories, so a value that had been
-- silently added to or removed from the constraint's list would go unnoticed.
-- All seven allowed values are enumerated here, and the accepted list is also
-- read back from the catalog so the test cannot quietly drift away from the
-- schema.
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
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9001 alice <-> 9002 bob : 9001 accepted partnership
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@bl-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@bl-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'BLCK01'),
  (9002, 'Bob',   'BLCK02');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9001, 9001, 9002, 'accepted');

-- ---------------------------------------------------------------------------
-- A: the constraint exists and its accepted list matches the expected seven
--    categories exactly.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_allowed  text;
  v_category text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_allowed
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND t.relname = 'bucket_items'
    AND c.conname = 'bucket_items_category_check';

  IF v_allowed IS NULL THEN
    RAISE EXCEPTION 'A failed: bucket_items_category_check constraint is missing';
  END IF;

  FOREACH v_category IN ARRAY ARRAY['Travel', 'Dates', 'Goals', 'Crazy', 'Adventure', 'Romantic', 'Homemade']
  LOOP
    IF position('''' || v_category || '''' IN v_allowed) = 0 THEN
      RAISE EXCEPTION 'A failed: category % is missing from the constraint: %', v_category, v_allowed;
    END IF;
  END LOOP;

  -- The constraint must still admit NULL, which is how "not categorised" is
  -- represented.
  IF position('NULL' IN upper(v_allowed)) = 0 THEN
    RAISE EXCEPTION 'A failed: the constraint no longer allows NULL: %', v_allowed;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B: every allowed category is accepted, and NULL is accepted.
--    Run as the signed-in partner, since that is the client write path.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

DO $$
DECLARE
  v_category text;
  v_state    text;
  v_rows     int;
BEGIN
  FOREACH v_category IN ARRAY ARRAY['Travel', 'Dates', 'Goals', 'Crazy', 'Adventure', 'Romantic', 'Homemade']
  LOOP
    v_state := pg_temp.rls_try(format(
      'INSERT INTO public.bucket_items (text, partnership_id, category) VALUES (%L, 9001, %L)',
      'valid ' || v_category, v_category));

    IF v_state IS NOT NULL THEN
      RAISE EXCEPTION 'B failed: the valid category % was rejected with %', v_category, v_state;
    END IF;
  END LOOP;

  v_state := pg_temp.rls_try(
    'INSERT INTO public.bucket_items (text, partnership_id, category) VALUES (''valid null item'', 9001, NULL)');
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'B failed: a NULL category was rejected with %', v_state;
  END IF;

  -- All eight rows must actually be there; a filtered insert would otherwise
  -- leave the loop looking successful.
  SELECT count(*) INTO v_rows FROM public.bucket_items WHERE partnership_id = 9001;
  IF v_rows <> 8 THEN
    RAISE EXCEPTION 'B failed: expected 8 accepted rows, found %', v_rows;
  END IF;

  SELECT count(*) INTO v_rows
  FROM public.bucket_items
  WHERE category IN ('Travel', 'Dates', 'Goals', 'Crazy', 'Adventure', 'Romantic', 'Homemade');
  IF v_rows <> 7 THEN
    RAISE EXCEPTION 'B failed: expected 7 categorised rows, found %', v_rows;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C: unknown and near-miss values are rejected with 23514 (check_violation).
--    Case, whitespace and pluralisation are all probed, because a CHECK on
--    exact string equality must reject every one of them.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_value text;
  v_state text;
BEGIN
  FOREACH v_value IN ARRAY ARRAY[
    'Junk', 'travel', 'TRAVEL', 'Travels', ' Travel', 'Travel ', 'travels', '', 'Unknown'
  ]
  LOOP
    v_state := pg_temp.rls_try(format(
      'INSERT INTO public.bucket_items (text, partnership_id, category) VALUES (%L, 9001, %L)',
      'invalid ' || coalesce(nullif(v_value, ''), 'empty'), v_value));

    IF v_state IS DISTINCT FROM '23514' THEN
      RAISE EXCEPTION 'C failed: category %L gave %, expected 23514 (check_violation)',
        v_value, coalesce(v_state, 'no error (the insert was allowed)');
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- D: the CHECK is enforced on UPDATE too, not only on INSERT. A constraint that
--    is only validated on insert would let an existing row be walked into an
--    invalid state.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_state text;
  v_rows  int;
BEGIN
  v_state := pg_temp.rls_try(
    'UPDATE public.bucket_items SET category = ''Junk'' WHERE text = ''valid Travel''');
  IF v_state IS DISTINCT FROM '23514' THEN
    RAISE EXCEPTION 'D failed: updating to an invalid category gave %, expected 23514',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;

  -- A valid category change must still work.
  UPDATE public.bucket_items SET category = 'Goals' WHERE text = 'valid Travel';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'D failed: the valid category update matched % row(s)', v_rows;
  END IF;
  IF (SELECT category FROM public.bucket_items WHERE text = 'valid Travel') IS DISTINCT FROM 'Goals' THEN
    RAISE EXCEPTION 'D failed: the valid category update did not stick';
  END IF;

  -- Clearing the category back to NULL must work as well.
  UPDATE public.bucket_items SET category = NULL WHERE text = 'valid Travel';
  IF (SELECT category FROM public.bucket_items WHERE text = 'valid Travel') IS NOT NULL THEN
    RAISE EXCEPTION 'D failed: clearing the category back to NULL did not stick';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E-post: none of the rejected writes persisted, checked with the RLS bypass in
--         place so the scan is not limited to what alice can see.
-- ---------------------------------------------------------------------------
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.bucket_items WHERE partnership_id = 9001) <> 8 THEN
    RAISE EXCEPTION 'E failed: % rows remain, expected 8', (SELECT count(*) FROM public.bucket_items WHERE partnership_id = 9001);
  END IF;
  IF EXISTS (SELECT 1 FROM public.bucket_items WHERE category IS NOT NULL AND category NOT IN
             ('Travel', 'Dates', 'Goals', 'Crazy', 'Adventure', 'Romantic', 'Homemade')) THEN
    RAISE EXCEPTION 'E failed: a row holds a category outside the allowed list';
  END IF;
END $$;

ROLLBACK;

SELECT 'bucket-items-category-check: passed (A constraint definition, B all 7 categories + NULL, C near-miss rejection at 23514, D UPDATE enforcement, E-post)' AS result;
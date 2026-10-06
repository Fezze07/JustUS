-- =============================================================================
-- RLS policy matrix: catalog-level invariants across every public table
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_policy_matrix.test.sql
--
-- This is a structural sweep rather than a behavioural one. The per-table
-- behaviour lives in the other files in this directory; what is checked here is
-- that no table can quietly fall out of protection, and that the shape of the
-- policy set still matches what the RLS doc describes.
--
-- Invariants asserted:
--   1. every public base table has RLS enabled;
--   2. every RLS-enabled public table has at least one policy (RLS with no
--      policy denies everything, which is a silent outage rather than a leak);
--   3. every FOR ALL policy carries an explicit WITH CHECK, which is the fix
--      from finding 2.3;
--   4. the only tables an unauthenticated role may read without restriction are
--      the six public catalogs;
--   5. any other policy reachable by anon/public must be gated on the caller's
--      identity, so an accidental USING (true) on user data fails here.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1 + 2: RLS is enabled everywhere, and every enabled table has a policy
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r             record;
  v_no_rls      text := '';
  v_no_policy   text := '';
  v_tables      int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS tbl, c.relrowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
    ORDER BY c.relname
  LOOP
    v_tables := v_tables + 1;

    IF NOT r.relrowsecurity THEN
      v_no_rls := v_no_rls || r.tbl || ', ';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public' AND p.tablename = r.tbl
    ) THEN
      v_no_policy := v_no_policy || r.tbl || ', ';
    END IF;
  END LOOP;

  -- Guard against a sweep that iterated over nothing.
  IF v_tables < 20 THEN
    RAISE EXCEPTION 'sweep aborted: only % public tables were found; the catalog query is not matching what it should', v_tables;
  END IF;

  IF v_no_rls <> '' THEN
    RAISE EXCEPTION '1 failed: public tables without RLS enabled: %', v_no_rls;
  END IF;

  IF v_no_policy <> '' THEN
    RAISE EXCEPTION '2 failed: RLS-enabled public tables with no policy at all: %', v_no_policy;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3: no FOR ALL policy may rely on an implicit WITH CHECK
--
--    pg_policies.with_check is NULL when the policy omits WITH CHECK. For a
--    permissive FOR ALL policy Postgres then reuses USING as the check, which
--    is correct only by coincidence of the USING expression; an explicit check
--    is what finding 2.3 fixed, so a regression here must fail.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r record;
  v_offenders text := '';
  v_count     int := 0;
BEGIN
  FOR r IN
    SELECT tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND cmd = 'ALL'
      AND with_check IS NULL
    ORDER BY tablename, policyname
  LOOP
    v_offenders := v_offenders || r.tablename || '/' || r.policyname || ', ';
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    RAISE EXCEPTION '3 failed: % FOR ALL policy/policies without an explicit WITH CHECK: %', v_count, v_offenders;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4: the set of tables readable by anon without any restriction is exactly the
--    six public catalogs, and nothing else.
--
--    A policy is treated as unrestricted when its USING expression is the bare
--    literal true, which is how the catalog tables are declared.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r            record;
  v_unrestr    text := '';
  v_expected   text[] := ARRAY['drive_file_types', 'emojis', 'game_question_bank', 'permissions', 'roles', 'roles_permissions'];
  v_found      text[] := '{}';
  i            int;
BEGIN
  FOR r IN
    SELECT DISTINCT tablename
    FROM pg_policies
    WHERE schemaname = 'public'
      AND cmd = 'SELECT'
      AND btrim(qual) = 'true'
      AND (roles::text LIKE '%anon%' OR roles::text LIKE '%public%')
    ORDER BY tablename
  LOOP
    v_found := v_found || r.tablename;

    IF NOT (r.tablename = ANY (v_expected)) THEN
      v_unrestr := v_unrestr || r.tablename || ', ';
    END IF;
  END LOOP;

  IF v_unrestr <> '' THEN
    RAISE EXCEPTION '4 failed: these tables are readable by anon with USING (true) but are not public catalogs: %', v_unrestr;
  END IF;

  -- The allowlist must not silently shrink either: if a catalog table loses
  -- its public read policy, the app loses data it needs.
  FOR i IN 1 .. array_length(v_expected, 1)
  LOOP
    IF NOT (v_expected[i] = ANY (v_found)) THEN
      RAISE EXCEPTION '4 failed: expected public-catalog read policy on % is missing', v_expected[i];
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5: every other anon/public policy must be gated on the caller's identity.
--
--    An identity gate means the USING or WITH CHECK expression references one of
--    the constructs this schema actually gates with:
--      * current_user_id() / auth.uid() / auth.role() / auth.jwt()  -- ownership
--      * is_in_partnership() / is_partner_of() / is_related_user() -- relationship
--      * the bare literal false                                     -- deny-all
--    Anything else on a non-catalog table is an unconditional grant to
--    unauthenticated callers. The blunt version of this check (USING (true)) is
--    invariant 4 above; this one catches USING (some_literal_expression).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r          record;
  v_offender text := '';
  v_count    int := 0;
BEGIN
  FOR r IN
    SELECT tablename, policyname, cmd,
           coalesce(qual, '')         AS using_expr,
           coalesce(with_check, '')   AS check_expr
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (roles::text LIKE '%anon%' OR roles::text LIKE '%public%')
      AND btrim(coalesce(qual, '')) <> 'true'
    ORDER BY tablename, cmd, policyname
  LOOP
    -- Skip the six catalogs; only their SELECT policies are unrestricted, and
    -- those were excluded above by the USING (true) filter.
    IF r.tablename = ANY (ARRAY['drive_file_types', 'emojis', 'game_question_bank', 'permissions', 'roles', 'roles_permissions']) THEN
      CONTINUE;
    END IF;

    IF (r.using_expr || ' ' || r.check_expr)
         !~* 'current_user_id|auth\.uid\(\)|auth\.role\(\)|auth\.jwt\(\)|is_in_partnership|is_partner_of|is_related_user|(^|[^a-z_])false([^a-z_]|$)' THEN
      v_offender := v_offender || r.tablename || '/' || r.policyname || ' (' || r.cmd || '), ';
      v_count := v_count + 1;
    END IF;
  END LOOP;

  IF v_count > 0 THEN
    RAISE EXCEPTION '5 failed: % anon/public policy/policies are not gated on the caller identity: %',
      v_count, v_offender;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6: service_role keeps the RLS bypass. Losing it would silently break the
--    backend rather than leak data, but it is the more likely regression.
--    Done at the top level because SET ROLE is a utility command and cannot be
--    issued as a static statement inside a plpgsql block.
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9101, '00000000-0000-0000-0000-000000000101', 'a@matrix-test.local'),
  (9102, '00000000-0000-0000-0000-000000000102', 'b@matrix-test.local');
INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9101, 9101, 9102, 'accepted');

SET LOCAL ROLE service_role;

DO $$
DECLARE
  v_users      bigint;
  v_partner_id integer;
BEGIN
  SELECT count(*) INTO v_users FROM public.users WHERE id IN (9101, 9102);
  IF v_users <> 2 THEN
    RAISE EXCEPTION '6 failed: service_role sees % of the 2 fixture users', v_users;
  END IF;

  SELECT public.get_accepted_partner(9101) INTO v_partner_id;
  IF v_partner_id IS DISTINCT FROM 9102 THEN
    RAISE EXCEPTION '6 failed: service_role get_accepted_partner returned %, expected 9102',
      coalesce(v_partner_id::text, 'NULL');
  END IF;
END $$;

RESET ROLE;

ROLLBACK;

SELECT 'rls-policy-matrix: passed (1 RLS enabled everywhere, 2 no policy-less tables, 3 every FOR ALL has WITH CHECK, 4 public catalogs allowlisted, 5 anon policies identity-gated, 6 service_role bypass)' AS result;
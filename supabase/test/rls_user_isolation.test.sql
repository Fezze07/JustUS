-- =============================================================================
-- RLS: user & profile isolation  (guards finding 2.1)
--
-- Contract under test (docs/supabase/rls/doc.md § 1, § Implementation Status
-- "Strict User & Profile Isolation"):
--   * `users` is self-scoped for SELECT — no other user's row or email is
--     reachable by a direct query.
--   * `user_profiles` is readable for self and accepted partner only; pending
--     invitees and unrelated users are not.
--   * A pending invitation's counterpart is identifiable ONLY through
--     public.get_pending_invitations(), and that RPC must not carry an email.
--
-- ASSERTION RULES used throughout the supabase/test suite
--   1. Scalar comparisons use IS DISTINCT FROM. `x <> y` evaluates to NULL —
--      and `IF NULL` is not taken — so a function that starts returning NULL,
--      or a subquery that starts returning no rows, would pass silently.
--   2. A blocked statement must fail with a SPECIFIC SQLSTATE. Asserting only
--      "some error" would let a wrong reason (NOT NULL, FK, unique) stand in
--      for the RLS denial the test claims to prove.
--   3. Every negative test re-reads the table afterwards, proving the write
--      did not land.
--   4. Catalog introspection runs as the owner, never as `authenticated`,
--      because information_schema only shows what the current role may see —
--      a restricted role makes the check vacuously true.
--   5. Each file seeds its own fixture and ends in ROLLBACK, so files stay
--      independently runnable and leave no residue.
--
-- Run:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/test/rls_user_isolation.test.sql
--   scripts/run-sql-tests.sh rls_user_isolation
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9001 alice  <-> 9002 bob    : accepted partnership (9001)
--   9001 alice  <-> 9003 carol  : pending, alice sent        (9002)
--   9004 dave                    : no relationship at all
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@rls-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@rls-test.local'),
  (9003, '00000000-0000-0000-0000-000000000003', 'carol@rls-test.local'),
  (9004, '00000000-0000-0000-0000-000000000004', 'dave@rls-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'ALICE1'),
  (9002, 'Bob',   'BOB222'),
  (9003, 'Carol', 'CAROL3'),
  (9004, 'Dave',  'DAVE44');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9001, 9001, 9002, 'accepted'),
  (9002, 9001, 9003, 'pending');

-- ---------------------------------------------------------------------------
-- A. own rows are readable
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';

DO $$
BEGIN
  IF (SELECT count(*) FROM public.users WHERE id = 9001) <> 1 THEN
    RAISE EXCEPTION 'A failed: own users row not readable';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id = 9001) <> 1 THEN
    RAISE EXCEPTION 'A failed: own profile row not readable';
  END IF;
  IF (SELECT email FROM public.users WHERE id = 9001)
       IS DISTINCT FROM 'alice@rls-test.local' THEN
    RAISE EXCEPTION 'A failed: own users row returned the wrong row';
  END IF;
  IF public.current_user_id() IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'A failed: current_user_id() did not resolve the caller';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. an unrelated user is not readable in either table
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users         WHERE id = 9004) <> 0 THEN
    RAISE EXCEPTION 'B failed: unrelated users row is readable';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id = 9004) <> 0 THEN
    RAISE EXCEPTION 'B failed: unrelated profile row is readable';
  END IF;
  -- Same probe, addressed by the columns an attacker would actually use.
  IF (SELECT count(*) FROM public.users         WHERE email = 'dave@rls-test.local') <> 0 THEN
    RAISE EXCEPTION 'B failed: unrelated user reachable by email';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE partnership_code = 'DAVE44') <> 0 THEN
    RAISE EXCEPTION 'B failed: unrelated profile reachable by partnership_code';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C. the accepted partner's profile is readable, their users row is not
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id = 9002) <> 1 THEN
    RAISE EXCEPTION 'C failed: accepted partner profile not readable';
  END IF;
  IF (SELECT count(*) FROM public.users WHERE id = 9002) <> 0 THEN
    RAISE EXCEPTION 'C failed: partner users row should be self-only';
  END IF;
  IF (SELECT partner_id FROM public.v_active_partnership) IS DISTINCT FROM 9002 THEN
    RAISE EXCEPTION 'C failed: v_active_partnership did not resolve the accepted partner';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D. a pending invitation is visible through the dedicated RPC only (sender)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_invitation_id integer;
  v_partner_id    integer;
  v_display_name  text;
  v_is_received   boolean;
BEGIN
  SELECT invitation_id, partner_id, partner_display_name, is_received
    INTO v_invitation_id, v_partner_id, v_display_name, v_is_received
    FROM public.get_pending_invitations();

  IF v_invitation_id IS DISTINCT FROM 9002 THEN
    RAISE EXCEPTION 'D failed: RPC returned invitation_id %, expected 9002',
      coalesce(v_invitation_id::text, 'NULL');
  END IF;
  IF v_partner_id IS DISTINCT FROM 9003 THEN
    RAISE EXCEPTION 'D failed: RPC returned partner_id %, expected 9003',
      coalesce(v_partner_id::text, 'NULL');
  END IF;
  IF v_display_name IS DISTINCT FROM 'Carol' THEN
    RAISE EXCEPTION 'D failed: RPC returned partner_display_name %, expected Carol',
      coalesce(v_display_name, 'NULL');
  END IF;
  IF v_is_received IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'D failed: a sent invitation must report is_received = false';
  END IF;
  IF (SELECT count(*) FROM public.get_pending_invitations()) <> 1 THEN
    RAISE EXCEPTION 'D failed: alice has exactly one pending invitation';
  END IF;
END $$;

-- D2. recipient side of the same invitation (carol)
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000003"}';
DO $$
DECLARE
  v_invitation_id integer;
  v_partner_id    integer;
  v_is_received   boolean;
BEGIN
  SELECT invitation_id, partner_id, is_received
    INTO v_invitation_id, v_partner_id, v_is_received
    FROM public.get_pending_invitations();

  IF v_invitation_id IS DISTINCT FROM 9002 THEN
    RAISE EXCEPTION 'D2 failed: RPC returned the wrong invitation for the recipient';
  END IF;
  IF v_partner_id IS DISTINCT FROM 9001 THEN
    RAISE EXCEPTION 'D2 failed: RPC returned the wrong inviter for the recipient';
  END IF;
  IF v_is_received IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'D2 failed: a received invitation must report is_received = true';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E. the pending counterpart grants no direct full-row read access
-- ---------------------------------------------------------------------------
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000001"}';
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users         WHERE id = 9003) <> 0 THEN
    RAISE EXCEPTION 'E failed: pending sender users row is directly readable';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id = 9003) <> 0 THEN
    RAISE EXCEPTION 'E failed: pending sender profile row is directly readable';
  END IF;
  IF (SELECT count(*) FROM public.v_active_partnership) <> 1 THEN
    RAISE EXCEPTION 'E failed: a pending request must not produce an active partnership';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- F. email enumeration is impossible: the caller only ever sees their own row
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users) <> 1 THEN
    RAISE EXCEPTION 'F failed: users exposes %s row(s), expected only the caller''s',
      (SELECT count(*) FROM public.users)::text;
  END IF;
  IF (SELECT count(*) FROM public.users WHERE email = 'bob@rls-test.local') <> 0 THEN
    RAISE EXCEPTION 'F failed: lookup of another user by email succeeded';
  END IF;
  -- An existence oracle: does this address belong to anyone? It must not answer.
  IF (SELECT count(*) FROM public.users WHERE email LIKE '%@rls-test.local') <> 1 THEN
    RAISE EXCEPTION 'F failed: a prefix match on another user''s email leaked a row';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- G. no user may write another user's row
--
--   Two distinct mechanisms, and the test must distinguish them:
--     * a row-scoped policy (USING ...) makes the row INVISIBLE, so the
--       statement succeeds and matches 0 rows. Asserting 42501 here would be
--       wrong; asserting a changed row would be the real failure.
--     * a WITH CHECK on the new row raises 42501 (insufficient_privilege).
--       Any other SQLSTATE means RLS was not what stopped it.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.users SET email = 'hijacked@rls-test.local' WHERE id = 9002;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'G failed: the update reached % row(s) of another user', v_rows;
  END IF;
END $$;

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.user_profiles SET display_name = 'Hacked' WHERE user_id = 9002;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'G failed: the update reached % partner profile(s)', v_rows;
  END IF;
END $$;

-- No DELETE policy exists on either table, so the row is filtered out: the
-- statement is a no-op, and the caller's own row must survive it.
DO $$
DECLARE
  v_rows int;
BEGIN
  DELETE FROM public.users WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'G failed: delete reached % row(s) of users', v_rows;
  END IF;
END $$;

-- WITH CHECK on INSERT: a user must not be able to attach a users row to
-- somebody else's auth id.
DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    INSERT INTO public.users (auth_id, email)
    VALUES ('00000000-0000-0000-0000-000000000002', 'forged@rls-test.local');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: inserting a users row for another auth id gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- ...nor a profile row for somebody else.
DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    INSERT INTO public.user_profiles (user_id, display_name, partnership_code)
    VALUES (9002, 'Impostor', 'FORGE1');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: inserting a profile for another user gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- Re-pointing the caller's own row at a different primary key is the
-- ownership-transfer escape; WITH CHECK must reject it with 42501.
DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    UPDATE public.users SET id = 9005 WHERE id = 9001;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'G failed: reassigning the caller''s users.id gave %, expected 42501',
      coalesce(v_state, 'no error (the update was allowed)');
  END IF;
END $$;

-- G-post. The targets above are invisible to the caller by design, so checking
-- them as `authenticated` would read NULL and "pass" for the wrong reason.
-- Re-read every target with the RLS bypass in place.
RESET ROLE;
DO $$
BEGIN
  IF (SELECT email FROM public.users WHERE id = 9001)
       IS DISTINCT FROM 'alice@rls-test.local' THEN
    RAISE EXCEPTION 'G failed: the caller''s users row was modified';
  END IF;
  IF (SELECT email FROM public.users WHERE id = 9002)
       IS DISTINCT FROM 'bob@rls-test.local' THEN
    RAISE EXCEPTION 'G failed: the target users row was modified';
  END IF;
  IF (SELECT display_name FROM public.user_profiles WHERE user_id = 9002)
       IS DISTINCT FROM 'Bob' THEN
    RAISE EXCEPTION 'G failed: the target profile row was modified';
  END IF;
  IF (SELECT count(*) FROM public.users) <> 4 THEN
    RAISE EXCEPTION 'G failed: the users row count changed (a write leaked through)';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles) <> 4 THEN
    RAISE EXCEPTION 'G failed: the user_profiles row count changed (a write leaked through)';
  END IF;
  IF (SELECT count(*) FROM public.users WHERE email = 'forged@rls-test.local') <> 0
     OR (SELECT count(*) FROM public.user_profiles WHERE partnership_code = 'FORGE1') <> 0 THEN
    RAISE EXCEPTION 'G failed: a forged row was persisted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = 9001) THEN
    RAISE EXCEPTION 'G failed: a client deleted its own users row';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE auth_id = '00000000-0000-0000-0000-000000000001' AND id = 9001) THEN
    RAISE EXCEPTION 'G failed: the caller''s users row changed identity';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- H. get_pending_invitations must not carry the counterpart's email
--    Checked against the catalog, as the owner: information_schema hides rows
--    the current role may not see, so a restricted role would report nothing
--    and the assertion could never fail. pg_get_function_result is used because
--    information_schema.parameters does NOT list the OUT columns of a
--    RETURNS TABLE function at all.
-- ---------------------------------------------------------------------------
RESET ROLE;
DO $$
DECLARE
  v_signature text;
BEGIN
  v_signature := pg_get_function_result('public.get_pending_invitations()'::regprocedure);

  IF v_signature !~* 'email' THEN
    RETURN;
  END IF;

  RAISE EXCEPTION 'H failed: get_pending_invitations() exposes an email column: %',
    v_signature;
END $$;

-- The function must also be unreachable for anon, and reachable for
-- authenticated. Both are grant facts, not policy facts.
DO $$
DECLARE
  v_anon     boolean;
  v_auth     boolean;
  v_signature text;
BEGIN
  v_anon := has_function_privilege('anon', 'public.get_pending_invitations()', 'EXECUTE');
  v_auth := has_function_privilege('authenticated', 'public.get_pending_invitations()', 'EXECUTE');

  IF v_anon THEN
    RAISE EXCEPTION 'H failed: anon may EXECUTE get_pending_invitations()';
  END IF;
  IF NOT v_auth THEN
    RAISE EXCEPTION 'H failed: authenticated lost EXECUTE on get_pending_invitations()';
  END IF;
  -- SECURITY DEFINER is what keeps the partnership scan from being filtered by
  -- the caller's own RLS view of `partnerships`; the function is useless
  -- without it.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_pending_invitations'
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION 'H failed: get_pending_invitations is no longer SECURITY DEFINER';
  END IF;
  -- A SECURITY DEFINER function with an unpinned search_path is the standard
  -- escalation vector; the schema pins it to public.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_pending_invitations'
      AND (p.proconfig @> ARRAY['search_path=public'])
  ) THEN
    RAISE EXCEPTION 'H failed: get_pending_invitations does not pin search_path to public';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- I. `anon` (no session at all) can neither read nor write
-- ---------------------------------------------------------------------------
RESET request.jwt.claims;
SET LOCAL ROLE anon;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users) <> 0 THEN
    RAISE EXCEPTION 'I failed: users are visible without a session';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles) <> 0 THEN
    RAISE EXCEPTION 'I failed: profiles are visible without a session';
  END IF;
  IF (SELECT count(*) FROM public.v_active_partnership) <> 0 THEN
    RAISE EXCEPTION 'I failed: v_active_partnership is visible without a session';
  END IF;
END $$;

-- The RPC is not revoked at the GRANT level for anon, so "no rows" would be
-- the wrong assertion: an empty result would also satisfy it if the REVOKE
-- were dropped. It must be unreachable.
DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    PERFORM count(*) FROM public.get_pending_invitations();
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'I failed: anon calling get_pending_invitations gave %, expected 42501',
      coalesce(v_state, 'no error (anon could call the RPC)');
  END IF;
END $$;

DO $$
DECLARE
  v_state text;
BEGIN
  BEGIN
    INSERT INTO public.users (auth_id, email) VALUES (NULL, 'anon@rls-test.local');
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;

  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'I failed: anon insert into users gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;
END $$;

-- Like G, an UPDATE against a row the caller cannot see is silently filtered,
-- so the assertion is on the row count, not on an error.
DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.users SET email = 'anon-edit@rls-test.local' WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'I failed: anon update reached % users row(s)', v_rows;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- J. service_role retains full access (the RLS bypass must survive every
--    policy above, otherwise the backend would silently stop working)
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.users WHERE id IN (9001, 9002, 9003, 9004)) <> 4 THEN
    RAISE EXCEPTION 'J failed: service_role lost access to users';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id IN (9001, 9002, 9003, 9004)) <> 4 THEN
    RAISE EXCEPTION 'J failed: service_role lost access to user_profiles';
  END IF;
  IF (SELECT count(*) FROM public.users) <> 4 THEN
    RAISE EXCEPTION 'J failed: service_role must see every users row, not just the fixtures';
  END IF;
  -- A write through the bypass, so "it can read" is not mistaken for "it can act".
  INSERT INTO public.users (id, auth_id, email)
  VALUES (9099, '00000000-0000-0000-0000-000000000099', 'service@rls-test.local');
  UPDATE public.users SET email = 'service2@rls-test.local' WHERE id = 9099;
  DELETE FROM public.users WHERE id = 9099;
END $$;

ROLLBACK;

SELECT 'RLS user isolation: passed (A own rows, B unrelated, C partner, D/D2 pending RPC, E pending counterpart, F email enumeration, G cross-user writes, H RPC signature+grants, I anon, J service_role)' AS result;

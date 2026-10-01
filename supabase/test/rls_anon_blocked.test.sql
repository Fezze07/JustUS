-- =============================================================================
-- anon is blocked: an unauthenticated session reaches no user data
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/rls_anon_blocked.test.sql
--
-- The other tests in this directory prove per-table behaviour for a signed-in
-- user. This one covers the unauthenticated surface, which is the one an
-- attacker reaches first:
--
--   * every table carrying an anon/public policy is seeded as superuser and
--     then read as anon, so the "0 rows" result cannot be an artefact of the
--     table being empty;
--   * the five intentional public catalogs are asserted to be readable, so the
--     sweep cannot be made to pass by simply breaking every policy;
--   * anon must not be able to write to any seeded table.
--
-- The catalog read in rls_policy_matrix.test.sql already asserts the shape of
-- the policy set; this file asserts the behaviour that shape produces.
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
-- One row in every table that an anon policy could otherwise expose.
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9001, '00000000-0000-0000-0000-000000000001', 'alice@anon-test.local'),
  (9002, '00000000-0000-0000-0000-000000000002', 'bob@anon-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9001, 'Alice', 'ANON01'),
  (9002, 'Bob',   'ANON02');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9001, 9001, 9002, 'accepted');

INSERT INTO public.drive_items (id, type, name, partnership_id) VALUES
  (9001, 'image', 'anon-sweep-photo.png', 9001);

INSERT INTO public.bucket_items (id, text, partnership_id) VALUES
  (9001, 'anon-sweep-bucket', 9001);

INSERT INTO public.missyou (id, partnership_id) VALUES
  (9001, 9001);

INSERT INTO public.game_questions (id, partnership_id, question, user_id_a, user_id_b) VALUES
  (9001, 9001, 'anon-sweep-question', 9001, 9002);

INSERT INTO public.game_answers (game_id, user_id, selected_option) VALUES
  (9001, 9002, 1);

INSERT INTO public.moods (id, user_id) VALUES
  (9001, 9002);

INSERT INTO public.favorites (user_id, item_id) VALUES
  (9001, 9001);

INSERT INTO public.drive_item_reactions (user_id, item_id) VALUES
  (9001, 9001);

INSERT INTO public.user_devices (user_id, device_token, device_type) VALUES
  (9001, 'anon-sweep-device-token', 'mobile');

-- user_roles references roles, so it can only be seeded now that the roles
-- catalog row exists.
INSERT INTO public.logs_notifications (user_id, type, status) VALUES
  (9001, 'push', 'anon-sweep');

-- One row in each of the five public catalogs, so the anon-read assertions in
-- section C are not satisfied by an empty table.
INSERT INTO public.roles (name) VALUES ('anon-sweep-role');
INSERT INTO public.permissions (slug, description) VALUES ('anon-sweep-perm', 'anon sweep');
INSERT INTO public.roles_permissions (role_id, permission_id)
  SELECT r.id, p.id FROM public.roles r, public.permissions p
  WHERE r.name = 'anon-sweep-role' AND p.slug = 'anon-sweep-perm';
INSERT INTO public.drive_file_types (extension, mime_type) VALUES ('anonswp', 'application/octet-stream');
INSERT INTO public.emojis (emoji_char) VALUES ('anon-sweep-emoji');

-- user_roles references roles, so it is seeded only now that the roles catalog
-- row exists.
INSERT INTO public.user_roles (user_id, role_id)
  SELECT 9001, r.id FROM public.roles r WHERE r.name = 'anon-sweep-role';

-- ---------------------------------------------------------------------------
-- Pre-flight: confirm every seeded row is really present, with the RLS bypass
-- in place. Without this a failed insert would make the anon sweep pass for
-- the wrong reason.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r            record;
  v_expected   int;
  v_actual     bigint;
  v_bad        text := '';
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.users',                 2),
      ('public.user_profiles',         2),
      ('public.partnerships',          1),
      ('public.drive_items',           1),
      ('public.bucket_items',          1),
      ('public.missyou',               1),
      ('public.game_questions',        1),
      ('public.game_answers',          1),
      ('public.moods',                 1),
      ('public.favorites',             1),
      ('public.drive_item_reactions',  1),
      ('public.user_devices',          1),
      ('public.logs_notifications',    1)
    ) AS t(tbl, n)
  LOOP
    v_expected := r.n;
    EXECUTE format('SELECT count(*) FROM %s', r.tbl) INTO v_actual;

    IF v_actual < v_expected THEN
      v_bad := v_bad || r.tbl || ' (expected ' || v_expected || ', found ' || v_actual || '), ';
    END IF;
  END LOOP;

  -- user_roles is seeded from the roles catalog row inserted above.
  IF (SELECT count(*) FROM public.user_roles WHERE user_id = 9001) <> 1 THEN
    v_bad := v_bad || 'public.user_roles, ';
  END IF;

  IF v_bad <> '' THEN
    RAISE EXCEPTION 'fixture failed: under-seeded tables: %', v_bad;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A: as anon, every seeded user-data table reads empty
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;

DO $$
DECLARE
  r         record;
  v_leak    bigint;
  v_checked int := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.users',                 'alice@anon-test.local'),
      ('public.user_profiles',         'Alice'),
      ('public.partnerships',          NULL),
      ('public.drive_items',           'anon-sweep-photo.png'),
      ('public.bucket_items',          'anon-sweep-bucket'),
      ('public.missyou',               NULL),
      ('public.game_questions',        'anon-sweep-question'),
      ('public.game_answers',          NULL),
      ('public.moods',                 NULL),
      ('public.favorites',             NULL),
      ('public.drive_item_reactions',  NULL),
      ('public.user_devices',          'anon-sweep-device-token'),
      ('public.user_roles',            NULL),
      ('public.logs_notifications',    'anon-sweep')
    ) AS t(tbl, marker)
  LOOP
    v_checked := v_checked + 1;

    EXECUTE format('SELECT count(*) FROM %s', r.tbl) INTO v_leak;

    IF v_leak <> 0 THEN
      RAISE EXCEPTION 'A failed: anon can read % row(s) from %', v_leak, r.tbl;
    END IF;
  END LOOP;

  IF v_checked <> 14 THEN
    RAISE EXCEPTION 'A failed: the sweep only covered % table(s); expected 14', v_checked;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B: the two RLS-protected views are empty for anon too
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(*) FROM public.v_active_partnership) <> 0 THEN
    RAISE EXCEPTION 'B failed: v_active_partnership exposed rows to anon';
  END IF;
  IF (SELECT count(*) FROM public.v_drive_dashboard) <> 0 THEN
    RAISE EXCEPTION 'B failed: v_drive_dashboard exposed rows to anon';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C: the five public catalogs must still be readable, otherwise the sweep above
--    could be satisfied by breaking the schema rather than protecting it.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT count(*) FROM public.roles WHERE name = 'anon-sweep-role') <> 1 THEN
    RAISE EXCEPTION 'C failed: anon cannot read the roles catalog';
  END IF;
  IF (SELECT count(*) FROM public.permissions WHERE slug = 'anon-sweep-perm') <> 1 THEN
    RAISE EXCEPTION 'C failed: anon cannot read the permissions catalog';
  END IF;
  IF (SELECT count(*) FROM public.roles_permissions rp
      JOIN public.roles r ON r.id = rp.role_id
      WHERE r.name = 'anon-sweep-role') <> 1 THEN
    RAISE EXCEPTION 'C failed: anon cannot read the roles_permissions catalog';
  END IF;
  IF (SELECT count(*) FROM public.drive_file_types WHERE extension = 'anonswp') <> 1 THEN
    RAISE EXCEPTION 'C failed: anon cannot read the drive_file_types catalog';
  END IF;
  IF (SELECT count(*) FROM public.emojis WHERE emoji_char = 'anon-sweep-emoji') <> 1 THEN
    RAISE EXCEPTION 'C failed: anon cannot read the emojis catalog';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D: anon cannot write. RLS-filtered INSERTs raise 42501 on WITH CHECK, while
--    a filtered UPDATE/DELETE reports 0 rows; both are asserted.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_state text;
  v_rows  int;
BEGIN
  v_state := pg_temp.rls_try($q$
    INSERT INTO public.users (auth_id, email) VALUES (NULL, 'anon-write@anon-test.local')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: anon insert into users gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.user_profiles (user_id, display_name, partnership_code)
    VALUES (9001, 'Impostor', 'ANONXX')$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: anon insert into user_profiles gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.moods (user_id) VALUES (9001)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: anon insert into moods gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  v_state := pg_temp.rls_try($q$
    INSERT INTO public.favorites (user_id, item_id) VALUES (9001, 9001)$q$);
  IF v_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'D failed: anon insert into favorites gave %, expected 42501',
      coalesce(v_state, 'no error (the insert was allowed)');
  END IF;

  -- UPDATE/DELETE of an invisible row are silent no-ops, so the row count is
  -- the only meaningful assertion.
  UPDATE public.drive_items SET name = 'anon-edit.png' WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'D failed: anon update reached % drive_items row(s)', v_rows;
  END IF;

  DELETE FROM public.missyou WHERE id = 9001;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'D failed: anon delete reached % missyou row(s)', v_rows;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E-post: nothing was created, moved or removed, checked with the RLS bypass
--         in place.
-- ---------------------------------------------------------------------------
RESET ROLE;
DO $$
BEGIN
  IF (SELECT email FROM public.users WHERE email = 'anon-write@anon-test.local') IS NOT NULL THEN
    RAISE EXCEPTION 'E failed: an anon-inserted users row was persisted';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_profiles WHERE partnership_code = 'ANONXX') THEN
    RAISE EXCEPTION 'E failed: an anon-inserted profile was persisted';
  END IF;
  IF (SELECT name FROM public.drive_items WHERE id = 9001) IS DISTINCT FROM 'anon-sweep-photo.png' THEN
    RAISE EXCEPTION 'E failed: an anon update changed drive_items';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.missyou WHERE id = 9001) THEN
    RAISE EXCEPTION 'E failed: an anon delete removed a missyou row';
  END IF;
  IF (SELECT count(*) FROM public.users) <> 2
     OR (SELECT count(*) FROM public.partnerships) <> 1
     OR (SELECT count(*) FROM public.moods) <> 1
     OR (SELECT count(*) FROM public.favorites) <> 1 THEN
    RAISE EXCEPTION 'E failed: a row count changed, so a write leaked through';
  END IF;
END $$;

ROLLBACK;

SELECT 'rls-anon-blocked: passed (pre-flight, A 14 seeded tables read empty, B views empty, C public catalogs readable, D writes denied, E-post)' AS result;
-- =============================================================================
-- Drive reactions move the drive sync cursor (todo 20.11)
-- =============================================================================
-- Run against the Supabase database (psql, Supabase MCP execute_sql, or the
-- SQL editor as `postgres`). Everything runs inside a transaction that is
-- ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/drive_reaction_touch.test.sql
--
-- `v_drive_dashboard.reactions` aggregates `drive_item_reactions`, so a
-- reaction change must move the parent `drive_items.updated_at`; otherwise
-- `drive_change_probe()` and the `updated_at > checkpoint` incremental query
-- never see a reaction made while the app was closed.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9101 alice <-> 9102 bob : 9101 accepted partnership
--   items 9101/9102/9103 cover the INSERT, UPDATE and DELETE paths separately,
--   because now() is transaction-stable and one reused row cannot show a second
--   advance inside this single test transaction.
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9101, '00000000-0000-0000-0000-000000000101', 'alice@reaction-test.local'),
  (9102, '00000000-0000-0000-0000-000000000102', 'bob@reaction-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code) VALUES
  (9101, 'Alice', 'RXN4AA'),
  (9102, 'Bob',   'RXN4BB');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9101, 9101, 9102, 'accepted');

INSERT INTO public.emojis (id, emoji_char) VALUES
  (9101, 'rxn-test-a'),
  (9102, 'rxn-test-b');

INSERT INTO public.drive_items (id, type, name, partnership_id, created_at, updated_at) VALUES
  (9101, 'image', 'reaction-insert.png', 9101,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz),
  (9102, 'image', 'reaction-update.png', 9101,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz),
  (9103, 'image', 'reaction-delete.png', 9101,
   '2020-01-01T00:00:00Z'::timestamptz, '2020-01-01T00:00:00Z'::timestamptz);

-- ---------------------------------------------------------------------------
-- A: the trigger is installed and enabled, and its function exists.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_enabled "char";
BEGIN
  IF to_regprocedure('public.touch_drive_item_from_reaction()') IS NULL THEN
    RAISE EXCEPTION 'A failed: public.touch_drive_item_from_reaction() is missing';
  END IF;

  SELECT t.tgenabled INTO v_enabled
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'drive_item_reactions'
    AND t.tgname = 'touch_public_drive_items_from_reaction'
    AND NOT t.tgisinternal;

  IF v_enabled IS NULL THEN
    RAISE EXCEPTION 'A failed: touch_public_drive_items_from_reaction trigger is missing';
  END IF;
  IF v_enabled = 'D' THEN
    RAISE EXCEPTION 'A failed: touch_public_drive_items_from_reaction is disabled';
  END IF;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';

-- ---------------------------------------------------------------------------
-- B: a new reaction advances the parent's updated_at and the probe cursor.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_updated timestamptz;
  v_probe   timestamptz;
BEGIN
  INSERT INTO public.drive_item_reactions (user_id, item_id, emoji_id)
  VALUES (9101, 9101, 9101);

  SELECT updated_at INTO v_updated FROM public.drive_items WHERE id = 9101;
  IF v_updated IS NULL OR v_updated <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'B failed: the inserted reaction left drive_items.updated_at at %', v_updated;
  END IF;

  SELECT p.max_updated_at INTO v_probe FROM public.drive_change_probe() p;
  IF v_probe IS NULL OR v_probe <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'B failed: drive_change_probe().max_updated_at is still %', v_probe;
  END IF;

  IF (SELECT updated_at FROM public.drive_items WHERE id = 9102)
       IS DISTINCT FROM '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'B failed: the reaction touched an unrelated drive item';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- C: changing the emoji advances the parent's updated_at.
--    The reaction insert above already moved the row, and now() is
--    transaction-stable, so re-seed the parent while its updated_at trigger is
--    paused to give this section a pre-2020 baseline.
-- ---------------------------------------------------------------------------
INSERT INTO public.drive_item_reactions (user_id, item_id, emoji_id)
VALUES (9101, 9102, 9101);

RESET ROLE;
ALTER TABLE public.drive_items DISABLE TRIGGER set_public_drive_items_updated_at;
UPDATE public.drive_items
   SET updated_at = '2020-01-01T00:00:00Z'::timestamptz
 WHERE id = 9102;
ALTER TABLE public.drive_items ENABLE TRIGGER set_public_drive_items_updated_at;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';

DO $$
DECLARE
  v_rows    int;
  v_updated timestamptz;
  v_probe   timestamptz;
BEGIN
  UPDATE public.drive_item_reactions
     SET emoji_id = 9102
   WHERE user_id = 9101 AND item_id = 9102;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'C failed: the emoji change matched % row(s)', v_rows;
  END IF;

  SELECT updated_at INTO v_updated FROM public.drive_items WHERE id = 9102;
  IF v_updated IS NULL OR v_updated <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'C failed: the changed emoji left drive_items.updated_at at %', v_updated;
  END IF;

  SELECT p.max_updated_at INTO v_probe FROM public.drive_change_probe() p;
  IF v_probe IS NULL OR v_probe <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'C failed: drive_change_probe().max_updated_at is still %', v_probe;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D: deleting the reaction advances the parent's updated_at, so the chip
--    disappears on the next cold start without a realtime event.
-- ---------------------------------------------------------------------------
INSERT INTO public.drive_item_reactions (user_id, item_id, emoji_id)
VALUES (9101, 9103, 9101);

RESET ROLE;
ALTER TABLE public.drive_items DISABLE TRIGGER set_public_drive_items_updated_at;
UPDATE public.drive_items
   SET updated_at = '2020-01-01T00:00:00Z'::timestamptz
 WHERE id = 9103;
ALTER TABLE public.drive_items ENABLE TRIGGER set_public_drive_items_updated_at;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"00000000-0000-0000-0000-000000000101"}';

DO $$
DECLARE
  v_rows    int;
  v_updated timestamptz;
  v_probe   timestamptz;
BEGIN
  DELETE FROM public.drive_item_reactions
   WHERE user_id = 9101 AND item_id = 9103;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'D failed: the reaction delete matched % row(s)', v_rows;
  END IF;

  SELECT updated_at INTO v_updated FROM public.drive_items WHERE id = 9103;
  IF v_updated IS NULL OR v_updated <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'D failed: the deleted reaction left drive_items.updated_at at %', v_updated;
  END IF;

  SELECT p.max_updated_at INTO v_probe FROM public.drive_change_probe() p;
  IF v_probe IS NULL OR v_probe <= '2020-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'D failed: drive_change_probe().max_updated_at is still %', v_probe;
  END IF;
END $$;

ROLLBACK;

SELECT 'drive-reaction-touch: passed (A trigger installed, B insert bumps parent, C emoji update bumps parent, D delete bumps parent)' AS result;

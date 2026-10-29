-- =============================================================================
-- debug_wipe_couple_data: per-couple blast radius (todo 12.3)
-- =============================================================================
-- Run against the Supabase database (needs `psql`, Supabase MCP `execute_sql`,
-- or the SQL editor as `postgres`). Everything runs inside a transaction that
-- is ROLLED BACK, so it never leaves data behind.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/test/debug_wipe_couple_data.test.sql
--
-- Any failed assertion raises an exception and aborts the script.
--
-- The wipe is a debug-only, per-couple reset: it clears the accepted couple's
-- shared rows and both members' user-scoped rows, keeps the `partnerships` row
-- (the connection survives), and leaves pending invitations untouched. An
-- unpaired caller still gets their own user-scoped rows cleared.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures (inserted as superuser, which bypasses RLS)
--   9101 Alice <-> 9102 Bob   : partnership 9101 accepted
--   9103 Carol <-> 9104 Dave  : partnership 9102 pending
-- Carol is the unpaired case: no accepted partnership, only a pending
-- invitation. Her wipe must clear her own rows and leave Dave's untouched.
-- ---------------------------------------------------------------------------
INSERT INTO public.users (id, auth_id, email) VALUES
  (9101, '00000000-0000-0000-0000-000000009101', 'alice@wipe-test.local'),
  (9102, '00000000-0000-0000-0000-000000009102', 'bob@wipe-test.local'),
  (9103, '00000000-0000-0000-0000-000000009103', 'carol@wipe-test.local'),
  (9104, '00000000-0000-0000-0000-000000009104', 'dave@wipe-test.local');

INSERT INTO public.user_profiles (user_id, display_name, partnership_code, profile_pic_url) VALUES
  (9101, 'Alice', 'ALICE1', 'profile/9101/alice.jpg'),
  (9102, 'Bob',   'BOB222', 'profile/9102/bob.jpg'),
  (9103, 'Carol', 'CAROL3', 'profile/9103/carol.jpg'),
  (9104, 'Dave',  'DAVE44', 'profile/9104/dave.jpg');

INSERT INTO public.partnerships (id, user_id_1, user_id_2, status) VALUES
  (9101, 9101, 9102, 'accepted'),
  (9102, 9103, 9104, 'pending');

INSERT INTO public.drive_items (id, type, name, partnership_id) VALUES
  (9111, 'image', 'accepted-photo.png', 9101),
  (9112, 'image', 'pending-photo.png',  9102);

INSERT INTO public.bucket_items (id, text, partnership_id) VALUES
  (9121, 'accepted-bucket', 9101),
  (9122, 'pending-bucket',  9102);

INSERT INTO public.missyou (id, partnership_id) VALUES
  (9131, 9101),
  (9132, 9102);

INSERT INTO public.game_question_bank (question_code, locale, text) VALUES
  ('wipe_q_accepted', 'it', 'accepted-q'),
  ('wipe_q_pending',  'it', 'pending-q');

INSERT INTO public.game_questions (id, partnership_id, question_code, user_id_a, user_id_b) VALUES
  (9141, 9101, 'wipe_q_accepted', 9101, 9102),
  (9142, 9102, 'wipe_q_pending',  9103, 9104);

INSERT INTO public.game_answers (game_id, user_id, selected_option) VALUES
  (9141, 9101, 1),
  (9141, 9102, 2),
  (9142, 9103, 1),
  (9142, 9104, 2);

INSERT INTO public.favorites (user_id, item_id) VALUES
  (9101, 9111),
  (9102, 9111),
  (9103, 9112),
  (9104, 9112);

INSERT INTO public.drive_item_reactions (id, user_id, item_id, emoji_id) VALUES
  (9151, 9101, 9111, NULL),
  (9152, 9102, 9111, NULL),
  (9153, 9103, 9112, NULL),
  (9154, 9104, 9112, NULL);

INSERT INTO public.moods (id, user_id, partnership_id, mood_type_id) VALUES
  (9161, 9101, 9101, NULL),
  (9162, 9102, 9101, NULL),
  (9163, 9103, 9102, NULL),
  (9164, 9104, 9102, NULL);

INSERT INTO public.logs_notifications (id, type, user_id, status) VALUES
  (9171, 'push', 9101, 'sent'),
  (9172, 'push', 9102, 'sent'),
  (9173, 'push', 9103, 'sent'),
  (9174, 'push', 9104, 'sent');

-- ---------------------------------------------------------------------------
-- Pre-flight: confirm the fixtures exist in the intended state. Without this,
-- a fixture that failed to insert would make the "must be gone" assertions
-- pass for the wrong reason.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT status FROM public.partnerships WHERE id = 9101) IS DISTINCT FROM 'accepted' THEN
    RAISE EXCEPTION 'fixture failed: partnership 9101 is not accepted';
  END IF;
  IF (SELECT status FROM public.partnerships WHERE id = 9102) IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'fixture failed: partnership 9102 is not pending';
  END IF;
  IF (SELECT count(*) FROM public.users WHERE id IN (9101, 9102, 9103, 9104)) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: expected 4 users';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id IN (9101, 9102, 9103, 9104) AND profile_pic_url IS NOT NULL) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: expected 4 profile pictures';
  END IF;
  IF (SELECT count(*) FROM public.drive_items    WHERE id IN (9111, 9112)) <> 2
     OR (SELECT count(*) FROM public.bucket_items   WHERE id IN (9121, 9122)) <> 2
     OR (SELECT count(*) FROM public.missyou        WHERE id IN (9131, 9132)) <> 2
     OR (SELECT count(*) FROM public.game_questions WHERE id IN (9141, 9142)) <> 2
     OR (SELECT count(*) FROM public.game_answers   WHERE game_id IN (9141, 9142)) <> 4
     OR (SELECT count(*) FROM public.favorites      WHERE user_id IN (9101, 9102, 9103, 9104)) <> 4
     OR (SELECT count(*) FROM public.drive_item_reactions WHERE id IN (9151, 9152, 9153, 9154)) <> 4
     OR (SELECT count(*) FROM public.moods          WHERE id IN (9161, 9162, 9163, 9164)) <> 4
     OR (SELECT count(*) FROM public.logs_notifications WHERE id IN (9171, 9172, 9173, 9174)) <> 4 THEN
    RAISE EXCEPTION 'fixture failed: the domain-row fixtures are incomplete';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- A. partnered caller: Alice wipes the accepted couple (Alice + Bob)
-- ---------------------------------------------------------------------------
SELECT public.debug_wipe_couple_data(9101);

DO $$
BEGIN
  -- The partnership rows survive: the connection is kept.
  IF (SELECT count(*) FROM public.partnerships WHERE id IN (9101, 9102)) <> 2 THEN
    RAISE EXCEPTION 'A failed: a wipe deleted a partnership row';
  END IF;

  -- Accounts and profile rows survive; only the picture URL is cleared.
  IF (SELECT count(*) FROM public.users WHERE id IN (9101, 9102, 9103, 9104)) <> 4 THEN
    RAISE EXCEPTION 'A failed: a wipe deleted a user row';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id IN (9101, 9102)) <> 2 THEN
    RAISE EXCEPTION 'A failed: a wipe deleted a profile row';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id IN (9101, 9102) AND profile_pic_url IS NOT NULL) THEN
    RAISE EXCEPTION 'A failed: the couple''s profile pictures were not reset';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id IN (9103, 9104) AND profile_pic_url IS NOT NULL) <> 2 THEN
    RAISE EXCEPTION 'A failed: the pending pair''s profile pictures were reset';
  END IF;

  -- Accepted shared rows are gone.
  IF EXISTS (SELECT 1 FROM public.drive_items    WHERE id = 9111)
     OR EXISTS (SELECT 1 FROM public.bucket_items   WHERE id = 9121)
     OR EXISTS (SELECT 1 FROM public.missyou        WHERE id = 9131)
     OR EXISTS (SELECT 1 FROM public.game_questions WHERE id = 9141) THEN
    RAISE EXCEPTION 'A failed: an accepted-couple shared row survived';
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9141) <> 0 THEN
    RAISE EXCEPTION 'A failed: an accepted-couple game answer survived';
  END IF;

  -- Pending shared rows are not part of the couple and must survive.
  IF (SELECT count(*) FROM public.drive_items    WHERE id = 9112) <> 1
     OR (SELECT count(*) FROM public.bucket_items   WHERE id = 9122) <> 1
     OR (SELECT count(*) FROM public.missyou        WHERE id = 9132) <> 1
     OR (SELECT count(*) FROM public.game_questions WHERE id = 9142) <> 1
     OR (SELECT count(*) FROM public.game_answers   WHERE game_id = 9142) <> 2 THEN
    RAISE EXCEPTION 'A failed: a pending invitation''s shared row was wiped';
  END IF;

  -- Both members' user-scoped rows are gone.
  IF EXISTS (SELECT 1 FROM public.favorites WHERE user_id IN (9101, 9102))
     OR EXISTS (SELECT 1 FROM public.drive_item_reactions WHERE user_id IN (9101, 9102))
     OR EXISTS (SELECT 1 FROM public.moods WHERE user_id IN (9101, 9102))
     OR EXISTS (SELECT 1 FROM public.logs_notifications WHERE user_id IN (9101, 9102)) THEN
    RAISE EXCEPTION 'A failed: a couple member''s user-scoped row survived';
  END IF;

  -- The pending pair's user-scoped rows are untouched.
  IF (SELECT count(*) FROM public.favorites WHERE user_id IN (9103, 9104)) <> 2
     OR (SELECT count(*) FROM public.drive_item_reactions WHERE user_id IN (9103, 9104)) <> 2
     OR (SELECT count(*) FROM public.moods WHERE user_id IN (9103, 9104)) <> 2
     OR (SELECT count(*) FROM public.logs_notifications WHERE user_id IN (9103, 9104)) <> 2 THEN
    RAISE EXCEPTION 'A failed: the pending pair''s user-scoped rows were wiped';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B. unpaired caller: Carol has only a pending invitation, so only her own
--    user-scoped rows are cleared; Dave and the pending shared rows survive.
-- ---------------------------------------------------------------------------
SELECT public.debug_wipe_couple_data(9103);

DO $$
BEGIN
  IF (SELECT count(*) FROM public.partnerships WHERE id IN (9101, 9102)) <> 2 THEN
    RAISE EXCEPTION 'B failed: the unpaired wipe deleted a partnership row';
  END IF;
  IF (SELECT count(*) FROM public.user_profiles WHERE user_id IN (9103, 9104)) <> 2 THEN
    RAISE EXCEPTION 'B failed: the unpaired wipe deleted a profile row';
  END IF;
  IF (SELECT profile_pic_url FROM public.user_profiles WHERE user_id = 9103) IS NOT NULL THEN
    RAISE EXCEPTION 'B failed: the caller''s profile picture was not reset';
  END IF;
  IF (SELECT profile_pic_url FROM public.user_profiles WHERE user_id = 9104) IS NULL THEN
    RAISE EXCEPTION 'B failed: the pending partner''s profile picture was reset';
  END IF;

  -- The pending pair's shared rows are not a couple and must survive.
  IF (SELECT count(*) FROM public.drive_items    WHERE id = 9112) <> 1
     OR (SELECT count(*) FROM public.bucket_items   WHERE id = 9122) <> 1
     OR (SELECT count(*) FROM public.missyou        WHERE id = 9132) <> 1
     OR (SELECT count(*) FROM public.game_questions WHERE id = 9142) <> 1 THEN
    RAISE EXCEPTION 'B failed: the unpaired wipe deleted a pending shared row';
  END IF;

  -- Carol's own rows are gone; Dave's remain.
  IF EXISTS (SELECT 1 FROM public.game_answers WHERE game_id = 9142 AND user_id = 9103) THEN
    RAISE EXCEPTION 'B failed: the caller''s game answer survived';
  END IF;
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = 9142 AND user_id = 9104) <> 1 THEN
    RAISE EXCEPTION 'B failed: the pending partner''s game answer was deleted';
  END IF;
  IF EXISTS (SELECT 1 FROM public.favorites WHERE user_id = 9103)
     OR EXISTS (SELECT 1 FROM public.drive_item_reactions WHERE user_id = 9103)
     OR EXISTS (SELECT 1 FROM public.moods WHERE user_id = 9103)
     OR EXISTS (SELECT 1 FROM public.logs_notifications WHERE user_id = 9103) THEN
    RAISE EXCEPTION 'B failed: the caller''s user-scoped rows survived';
  END IF;
  IF (SELECT count(*) FROM public.favorites WHERE user_id = 9104) <> 1
     OR (SELECT count(*) FROM public.drive_item_reactions WHERE user_id = 9104) <> 1
     OR (SELECT count(*) FROM public.moods WHERE user_id = 9104) <> 1
     OR (SELECT count(*) FROM public.logs_notifications WHERE user_id = 9104) <> 1 THEN
    RAISE EXCEPTION 'B failed: the pending partner''s user-scoped rows were deleted';
  END IF;
END $$;

ROLLBACK;

SELECT 'debug-wipe-couple-data: passed (pre-flight, A partnered blast radius, B unpaired blast radius)' AS result;

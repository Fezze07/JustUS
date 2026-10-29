DROP FUNCTION IF EXISTS public.debug_wipe_user_data(integer);

CREATE OR REPLACE FUNCTION public.debug_wipe_couple_data (
  p_user_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_partnership_id int;
    v_user_ids int[];
BEGIN
    -- The couple is the accepted partnership; pending/cancelled rows are not a couple.
    SELECT id INTO v_partnership_id
    FROM partnerships
    WHERE (user_id_1 = p_user_id OR user_id_2 = p_user_id)
      AND status = 'accepted'
    LIMIT 1;

    SELECT array_agg(uid) INTO v_user_ids
    FROM (
        SELECT p_user_id AS uid
        UNION
        SELECT CASE WHEN user_id_1 = p_user_id THEN user_id_2 ELSE user_id_1 END
        FROM partnerships
        WHERE id = v_partnership_id
    ) members;

    IF v_partnership_id IS NOT NULL THEN
        DELETE FROM drive_items WHERE partnership_id = v_partnership_id;
        DELETE FROM bucket_items WHERE partnership_id = v_partnership_id;
        DELETE FROM game_questions WHERE partnership_id = v_partnership_id;
        DELETE FROM missyou WHERE partnership_id = v_partnership_id;
    END IF;

    DELETE FROM game_answers WHERE user_id = ANY(v_user_ids);
    DELETE FROM favorites WHERE user_id = ANY(v_user_ids);
    DELETE FROM drive_item_reactions WHERE user_id = ANY(v_user_ids);
    DELETE FROM moods WHERE user_id = ANY(v_user_ids);
    UPDATE user_profiles SET profile_pic_url = NULL WHERE user_id = ANY(v_user_ids);
    DELETE FROM logs_notifications WHERE user_id = ANY(v_user_ids);
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."debug_wipe_couple_data"(integer) TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."debug_wipe_couple_data"(integer) FROM PUBLIC, "anon", "authenticated";

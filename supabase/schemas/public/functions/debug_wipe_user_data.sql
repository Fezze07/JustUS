CREATE OR REPLACE FUNCTION public.debug_wipe_user_data (
  p_user_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
    v_partnership_id int;
BEGIN
    -- Get active partnership
    SELECT id INTO v_partnership_id 
    FROM partnerships 
    WHERE user_id_1 = p_user_id OR user_id_2 = p_user_id 
    LIMIT 1;

    IF v_partnership_id IS NOT NULL THEN
        -- Delete items related to partnership
        DELETE FROM drive_items WHERE partnership_id = v_partnership_id;
        DELETE FROM bucket_items WHERE partnership_id = v_partnership_id;
        DELETE FROM game_questions WHERE partnership_id = v_partnership_id;
        DELETE FROM game_answers WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );
        DELETE FROM missyou WHERE partnership_id = v_partnership_id;
        DELETE FROM favorites WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );
        DELETE FROM drive_item_reactions WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );
        
        -- Delete user-specific data for both partners
        DELETE FROM moods WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );
        
        -- Reset profile info (bio, pic) for both partners
        UPDATE user_profiles SET bio = NULL, profile_pic_url = NULL 
        WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );

        -- Delete logs related to these users
        DELETE FROM logs_notifications WHERE user_id IN (
            SELECT user_id_1 FROM partnerships WHERE id = v_partnership_id
            UNION
            SELECT user_id_2 FROM partnerships WHERE id = v_partnership_id
        );
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."debug_wipe_user_data"(integer) TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."debug_wipe_user_data"(integer) FROM PUBLIC;

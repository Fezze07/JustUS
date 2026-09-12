CREATE OR REPLACE FUNCTION public.get_partnership_names (
  p_user_id integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$DECLARE
    v_u1_name text;
    v_u2_name text;
    v_u1_id integer;
    v_u2_id integer;
BEGIN
    -- 1. Trova la partnership attiva (accepted o active)
    SELECT user_id_1, user_id_2 INTO v_u1_id, v_u2_id
    FROM partnerships
    WHERE (user_id_1 = p_user_id OR user_id_2 = p_user_id)
      AND (status = 'accepted')
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_u1_id IS NULL THEN
        RETURN jsonb_build_object('name1', 'Partner 1', 'name2', 'Partner 2');
    END IF;

    -- 2. Recupera i display_name dai profili
    SELECT display_name INTO v_u1_name
    FROM user_profiles
    WHERE user_id = v_u1_id;

    SELECT display_name INTO v_u2_name
    FROM user_profiles
    WHERE user_id = v_u2_id;

    RETURN jsonb_build_object(
        'name1', COALESCE(v_u1_name, 'Partner 1'),
        'name2', COALESCE(v_u2_name, 'Partner 2')
    );
END;$function$;

GRANT EXECUTE ON FUNCTION "public"."get_partnership_names"(integer) TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."get_partnership_names"(integer) FROM PUBLIC;

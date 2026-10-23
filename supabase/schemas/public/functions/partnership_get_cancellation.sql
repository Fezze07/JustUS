CREATE OR REPLACE FUNCTION public.partnership_get_cancellation ()
  RETURNS TABLE (
    partnership_id integer,
    partner_id integer,
    partner_display_name text,
    partner_profile_pic_url text,
    requested_by_me boolean
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
BEGIN
  -- Lazy expiry: a stale request must not keep the pair frozen for the reader.
  PERFORM public.partnership_expire_cancellations();

  v_caller_id := public.user_current_id();

  RETURN QUERY
  SELECT
    p.id,
    CASE
      WHEN p.user_id_1 = v_caller_id THEN p.user_id_2
      ELSE p.user_id_1
    END,
    up.display_name,
    up.profile_pic_url,
    p.cancel_requested_by = v_caller_id
  FROM public.partnerships p
    LEFT JOIN public.user_profiles up ON up.user_id = (
      CASE
        WHEN p.user_id_1 = v_caller_id THEN p.user_id_2
        ELSE p.user_id_1
      END
    )
  WHERE (p.user_id_1 = v_caller_id OR p.user_id_2 = v_caller_id)
    AND p.status = 'cancelled';
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_get_cancellation"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."partnership_get_cancellation"() TO "authenticated", "postgres", "service_role";

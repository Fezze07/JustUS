CREATE OR REPLACE FUNCTION public.partnership_cancel_accept (
  p_partnership_id integer,
  p_actor_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_partnership public.partnerships%ROWTYPE;
BEGIN
  SELECT * INTO v_partnership
  FROM public.partnerships
  WHERE id = p_partnership_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_partnership.status IS DISTINCT FROM 'cancelled'
     OR (p_actor_id IS DISTINCT FROM v_partnership.user_id_1 AND p_actor_id IS DISTINCT FROM v_partnership.user_id_2)
     OR p_actor_id IS NOT DISTINCT FROM v_partnership.cancel_requested_by THEN
    RAISE EXCEPTION 'API-VALIDATION-012: Only the partner who did not request cancellation may accept'
      USING ERRCODE = '42501';
  END IF;

  IF v_partnership.cancel_expires_at <= now() THEN
    RAISE EXCEPTION 'API-VALIDATION-014: The cancellation request has expired'
      USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.partnerships
   WHERE id = p_partnership_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_cancel_accept"(integer, integer) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."partnership_cancel_accept"(integer, integer) TO "postgres", "service_role";

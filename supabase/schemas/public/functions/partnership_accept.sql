CREATE OR REPLACE FUNCTION public.partnership_accept (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
  v_target public.partnerships%ROWTYPE;
BEGIN
  v_caller_id := public.user_current_id();

  SELECT * INTO v_target
  FROM public.partnerships
  WHERE id = p_partnership_id;

  IF FOUND
     AND v_target.status = 'pending'
     AND v_target.user_id_2 = v_caller_id
     AND EXISTS (
       SELECT 1
       FROM public.partnerships p2
       WHERE p2.id <> p_partnership_id
         AND p2.status IN ('accepted', 'cancelled')
         AND (p2.user_id_1 = v_caller_id OR p2.user_id_2 = v_caller_id)
     ) THEN
    RAISE EXCEPTION 'API-VALIDATION-012: A user may only be in one active partnership'
      USING ERRCODE = '42501';
  END IF;

  -- Revert to original behavior: only update status and anniversary_date
  UPDATE public.partnerships
  SET status = 'accepted', anniversary_date = current_date
  WHERE id = p_partnership_id
    AND user_id_2 = v_caller_id
    AND status = 'pending';
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."partnership_accept"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

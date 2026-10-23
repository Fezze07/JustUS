CREATE OR REPLACE FUNCTION public.partnership_request_cancel (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
  v_partnership public.partnerships%ROWTYPE;
BEGIN
  v_caller_id := public.user_current_id();

  SELECT * INTO v_partnership
  FROM public.partnerships
  WHERE id = p_partnership_id
    AND status = 'accepted'
    AND (user_id_1 = v_caller_id OR user_id_2 = v_caller_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'API-VALIDATION-010: Only a member of an accepted partnership can request its cancellation'
      USING ERRCODE = '42501';
  END IF;

  IF v_partnership.cancel_declined_at > now() - interval '24 hours' THEN
    RAISE EXCEPTION 'API-VALIDATION-013: This partnership was declined less than 24 hours ago';
  END IF;

  UPDATE public.partnerships
     SET status = 'cancelled',
         cancel_requested_by = v_caller_id,
         cancel_expires_at = now() + interval '7 days'
   WHERE id = p_partnership_id;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_request_cancel"(integer) FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."partnership_request_cancel"(integer) TO "authenticated", "postgres", "service_role";

CREATE OR REPLACE FUNCTION public.partnership_cancel_revert (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO 'public'
  AS $function$
BEGIN
  -- cancel_declined_at is left untouched: the guard trigger records a partner
  -- decline and keeps the stored value for a requester restore.
  UPDATE public.partnerships
     SET status = 'accepted',
         cancel_requested_by = NULL,
         cancel_expires_at = NULL
   WHERE id = p_partnership_id
     AND status = 'cancelled'
     AND (user_id_1 = public.user_current_id() OR user_id_2 = public.user_current_id());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'API-VALIDATION-011: Only a member of a cancelled partnership can revert it'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_cancel_revert"(integer) FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."partnership_cancel_revert"(integer) TO "authenticated", "postgres", "service_role";

CREATE OR REPLACE FUNCTION public.partnership_expire_cancellations ()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_count integer;
BEGIN
  -- cancel_declined_at is deliberately not written: an expiry is not a decline.
  UPDATE public.partnerships
     SET status = 'accepted',
         cancel_requested_by = NULL,
         cancel_expires_at = NULL
   WHERE status = 'cancelled'
     AND cancel_expires_at <= now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_expire_cancellations"() FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."partnership_expire_cancellations"() TO "postgres", "service_role";

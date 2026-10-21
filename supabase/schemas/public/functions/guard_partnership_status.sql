CREATE OR REPLACE FUNCTION public.guard_partnership_status()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
BEGIN
  v_caller_id := public.current_user_id();

  IF NEW.status IS DISTINCT FROM OLD.status
     AND v_caller_id IS NOT NULL
     AND v_caller_id IS DISTINCT FROM NEW.user_id_2 THEN
    RAISE EXCEPTION 'API-VALIDATION-008: Only the invited partner can accept a partnership request'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."guard_partnership_status"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."guard_partnership_status"() TO "postgres", "service_role";

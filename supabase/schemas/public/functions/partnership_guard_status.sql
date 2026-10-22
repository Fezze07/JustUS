CREATE OR REPLACE FUNCTION public.partnership_guard_status()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
BEGIN
  v_caller_id := public.user_current_id();

  IF NEW.user_id_1 IS DISTINCT FROM OLD.user_id_1
     OR NEW.user_id_2 IS DISTINCT FROM OLD.user_id_2 THEN
    RAISE EXCEPTION 'API-VALIDATION-009: Partnership members cannot be changed'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND v_caller_id IS NOT NULL
     AND v_caller_id IS DISTINCT FROM NEW.user_id_2 THEN
    RAISE EXCEPTION 'API-VALIDATION-008: Only the invited partner can accept a partnership request'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_guard_status"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."partnership_guard_status"() TO "postgres", "service_role";

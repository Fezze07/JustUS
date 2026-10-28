CREATE OR REPLACE FUNCTION public.users_guard_identity()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  IF NEW.auth_id IS DISTINCT FROM OLD.auth_id
     OR NEW.email IS DISTINCT FROM OLD.email THEN
    IF current_user IN ('postgres', 'service_role') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'API-VALIDATION-015: users.auth_id and users.email are read-only'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."users_guard_identity"() FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."users_guard_identity"() TO "postgres", "service_role";

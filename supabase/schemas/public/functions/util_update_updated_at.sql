CREATE OR REPLACE FUNCTION public.util_update_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."util_update_updated_at"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

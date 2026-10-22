CREATE OR REPLACE FUNCTION public.user_current_id()
  RETURNS integer
  LANGUAGE sql
  STABLE
  SET search_path TO 'public'
  AS $function$
  SELECT id FROM public.users WHERE auth_id = auth.uid() LIMIT 1;
$function$;

GRANT EXECUTE ON FUNCTION "public"."user_current_id"() TO PUBLIC, "authenticated", "postgres", "service_role";

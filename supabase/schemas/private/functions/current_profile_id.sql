CREATE OR REPLACE FUNCTION private.current_profile_id()
  RETURNS integer
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  select u.id
  from public.users u
  where u.auth_id::text = auth.uid()::text
  limit 1;
$function$;

GRANT EXECUTE ON FUNCTION "private"."current_profile_id"() TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "private"."current_profile_id"() FROM PUBLIC;

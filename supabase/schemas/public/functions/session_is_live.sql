CREATE OR REPLACE FUNCTION public.session_is_live(p_session_id uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM auth.sessions s
    WHERE s.id = p_session_id
      AND (s.not_after IS NULL OR s.not_after > now())
  );
$function$;

REVOKE ALL ON FUNCTION "public"."session_is_live"(uuid) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."session_is_live"(uuid) TO "postgres", "service_role";

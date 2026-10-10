CREATE OR REPLACE FUNCTION public.purge_user_devices_dead_sessions()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
  AS $function$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM public.user_devices ud
  WHERE ud.session_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM auth.sessions s
      WHERE s.id = ud.session_id
        AND (s.not_after IS NULL OR s.not_after > now())
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."purge_user_devices_dead_sessions"() FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."purge_user_devices_dead_sessions"() TO "postgres", "service_role";
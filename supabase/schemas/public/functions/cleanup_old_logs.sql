CREATE OR REPLACE FUNCTION public.cleanup_old_logs()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_cutoff timestamp with time zone := now() - interval '30 days';
BEGIN
  DELETE FROM public.logs_api_access WHERE created_at < v_cutoff;
  DELETE FROM public.logs_api_errors WHERE created_at < v_cutoff;
  DELETE FROM public.logs_security_events WHERE created_at < v_cutoff;
  DELETE FROM public.logs_notifications WHERE created_at < v_cutoff;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."cleanup_old_logs"() TO PUBLIC, "postgres", "service_role";

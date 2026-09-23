DROP FUNCTION IF EXISTS public.cleanup_old_logs();

CREATE OR REPLACE FUNCTION public.cleanup_old_logs(p_days integer DEFAULT 90)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_cutoff timestamp with time zone;
BEGIN
  IF p_days IS NULL OR p_days < 1 THEN
    RAISE EXCEPTION 'cleanup_old_logs: p_days must be a positive integer';
  END IF;
  v_cutoff := now() - make_interval(days => p_days);
  DELETE FROM public.logs_api_access WHERE created_at < v_cutoff;
  DELETE FROM public.logs_api_errors WHERE created_at < v_cutoff;
  DELETE FROM public.logs_security_events WHERE created_at < v_cutoff;
  DELETE FROM public.logs_notifications WHERE created_at < v_cutoff;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."cleanup_old_logs"(integer) TO PUBLIC, "postgres", "service_role";

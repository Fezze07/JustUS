CREATE OR REPLACE FUNCTION public.set_current_timestamp_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."set_current_timestamp_updated_at"() TO PUBLIC, "postgres", "service_role";

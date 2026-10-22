CREATE OR REPLACE FUNCTION public.partnership_reject (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  DELETE FROM public.partnerships
  WHERE id = p_partnership_id 
    AND (user_id_1 = public.user_current_id() OR user_id_2 = public.user_current_id()) 
    AND status = 'pending';
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."partnership_reject"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

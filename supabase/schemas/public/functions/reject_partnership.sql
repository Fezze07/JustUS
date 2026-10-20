CREATE OR REPLACE FUNCTION public.reject_partnership (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  DELETE FROM public.partnerships
  WHERE id = p_partnership_id 
    AND (user_id_1 = public.current_user_id() OR user_id_2 = public.current_user_id()) 
    AND status = 'pending';
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."reject_partnership"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

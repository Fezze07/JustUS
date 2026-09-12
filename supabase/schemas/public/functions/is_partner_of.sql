CREATE OR REPLACE FUNCTION public.is_partner_of (
  other_user_id integer
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO 'public'
  AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.partnerships 
    WHERE (user_id_1 = public.current_user_id() AND user_id_2 = other_user_id)
       OR (user_id_2 = public.current_user_id() AND user_id_1 = other_user_id)
  );
$function$;

GRANT EXECUTE ON FUNCTION "public"."is_partner_of"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

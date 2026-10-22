CREATE OR REPLACE FUNCTION public.partnership_is_partner (
  other_user_id integer
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO 'public'
  AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.partnerships
    WHERE status = 'accepted'
    AND ((user_id_1 = public.user_current_id() AND user_id_2 = other_user_id)
       OR (user_id_2 = public.user_current_id() AND user_id_1 = other_user_id))
  );
$function$;

GRANT EXECUTE ON FUNCTION "public"."partnership_is_partner"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

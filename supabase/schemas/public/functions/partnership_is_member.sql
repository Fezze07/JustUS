CREATE OR REPLACE FUNCTION public.partnership_is_member (
  p_partnership_id integer
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO 'public'
  AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.partnerships
    WHERE id = p_partnership_id
    AND status = 'accepted'
    AND (user_id_1 = public.user_current_id() OR user_id_2 = public.user_current_id())
  );
$function$;

GRANT EXECUTE ON FUNCTION "public"."partnership_is_member"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

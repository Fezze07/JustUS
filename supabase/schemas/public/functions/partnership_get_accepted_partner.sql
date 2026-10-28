CREATE OR REPLACE FUNCTION public.partnership_get_accepted_partner (
  target_user_id integer
)
  RETURNS TABLE (
    id integer
  )
  LANGUAGE sql
  STABLE
  SET search_path TO 'public'
  AS $function$
  SELECT
    CASE
      WHEN user_id_1 = target_user_id THEN user_id_2
      WHEN user_id_2 = target_user_id THEN user_id_1
    END AS id
  FROM public.partnerships
  WHERE (user_id_1 = target_user_id OR user_id_2 = target_user_id)
    AND status = 'accepted'
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_get_accepted_partner"(integer) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."partnership_get_accepted_partner"(integer) TO "authenticated", "postgres", "service_role";

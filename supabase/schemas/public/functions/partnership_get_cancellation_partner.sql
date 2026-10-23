CREATE OR REPLACE FUNCTION public.partnership_get_cancellation_partner (
  p_user_id integer
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  SELECT
    CASE
      WHEN user_id_1 = p_user_id THEN user_id_2
      WHEN user_id_2 = p_user_id THEN user_id_1
    END
  FROM public.partnerships
  WHERE (user_id_1 = p_user_id OR user_id_2 = p_user_id)
    AND status = 'cancelled'
  ORDER BY id DESC
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_get_cancellation_partner"(integer) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."partnership_get_cancellation_partner"(integer) TO "postgres", "service_role";

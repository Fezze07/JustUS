CREATE OR REPLACE FUNCTION public.get_game_stats (
  p_uid        bigint,
  p_partner_id bigint
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  AS $function$
  SELECT COUNT(*)::integer
  FROM (
    SELECT ga1.game_id
    FROM game_answers ga1
    JOIN game_answers ga2
      ON  ga1.game_id         = ga2.game_id
      AND ga1.selected_option = ga2.selected_option
    WHERE ga1.user_id = p_uid
      AND ga2.user_id = p_partner_id
  ) matched_games;
$function$;

GRANT EXECUTE ON FUNCTION "public"."get_game_stats"(bigint, bigint) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

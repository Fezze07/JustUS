CREATE OR REPLACE FUNCTION public.game_pick_question (
  p_partnership_id integer,
  p_locales text[]
)
  RETURNS public.game_question_bank
  LANGUAGE sql
  SECURITY INVOKER
  SET search_path TO 'public'
  AS $function$
  SELECT qb.*
  FROM public.game_question_bank qb
  WHERE qb.locale = ANY (p_locales)
    AND public.partnership_is_member(p_partnership_id)
  ORDER BY
    array_position(p_locales, qb.locale),
    EXISTS (
      SELECT 1
      FROM public.game_questions gq
      WHERE gq.partnership_id = p_partnership_id
        AND gq.question_code = qb.question_code
    ),
    random()
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.game_pick_question(integer, text[]) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION public.game_pick_question(integer, text[]) TO "authenticated", "postgres", "service_role";

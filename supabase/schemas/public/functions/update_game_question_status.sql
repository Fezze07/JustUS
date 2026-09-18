CREATE OR REPLACE FUNCTION public.update_game_question_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF (SELECT count(*) FROM public.game_answers WHERE game_id = NEW.game_id) >= 2 THEN
    UPDATE public.game_questions
    SET status = 'both_answered'
    WHERE id = NEW.game_id AND status IS DISTINCT FROM 'both_answered';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.update_game_question_status() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION public.update_game_question_status() TO "authenticated", "postgres", "service_role";

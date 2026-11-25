CREATE OR REPLACE FUNCTION public.game_get_or_create_question (
  p_partnership_id integer,
  p_locales text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_uid integer;
  v_u1 integer;
  v_u2 integer;
  v_question public.game_questions;
  v_bank public.game_question_bank;
  v_question_text text;
  v_user_a integer;
  v_user_b integer;
  v_has_answered boolean := false;
  v_partner_answered boolean := false;
  v_created boolean := false;
BEGIN
  v_uid := public.user_current_id();
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT p.user_id_1, p.user_id_2
  INTO v_u1, v_u2
  FROM public.partnerships p
  WHERE p.id = p_partnership_id
    AND p.status = 'accepted'
    AND (p.user_id_1 = v_uid OR p.user_id_2 = v_uid)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT gq.*
  INTO v_question
  FROM public.game_questions gq
  WHERE gq.partnership_id = p_partnership_id
    AND gq.status IS DISTINCT FROM 'both_answered'
  ORDER BY gq.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    SELECT qb.text
    INTO v_question_text
    FROM public.game_question_bank qb
    WHERE qb.question_code = v_question.question_code
      AND qb.locale = ANY (p_locales)
    ORDER BY array_position(p_locales, qb.locale)
    LIMIT 1;

    SELECT
      COALESCE(bool_or(ga.user_id = v_uid), false),
      COALESCE(bool_or(ga.user_id <> v_uid), false)
    INTO v_has_answered, v_partner_answered
    FROM public.game_answers ga
    WHERE ga.game_id = v_question.id;
  ELSE
    v_bank := public.game_pick_question(p_partnership_id, p_locales);
    IF v_bank.question_code IS NULL THEN
      RETURN NULL;
    END IF;

    IF random() < 0.5 THEN
      v_user_a := v_u1;
      v_user_b := v_u2;
    ELSE
      v_user_a := v_u2;
      v_user_b := v_u1;
    END IF;

    INSERT INTO public.game_questions (
      partnership_id,
      question_code,
      status,
      user_id_a,
      user_id_b
    )
    VALUES (
      p_partnership_id,
      v_bank.question_code,
      'pending',
      v_user_a,
      v_user_b
    )
    RETURNING * INTO v_question;

    v_question_text := v_bank.text;
    v_created := true;
  END IF;

  RETURN jsonb_build_object(
    'id', v_question.id,
    'question_code', v_question.question_code,
    'question', v_question_text,
    'status', v_question.status,
    'user_id_a', v_question.user_id_a,
    'user_id_b', v_question.user_id_b,
    'created', v_created,
    'has_answered', v_has_answered,
    'partner_answered', v_partner_answered
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.game_get_or_create_question(integer, text[]) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION public.game_get_or_create_question(integer, text[]) TO "authenticated", "postgres", "service_role";

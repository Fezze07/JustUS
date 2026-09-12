CREATE OR REPLACE FUNCTION public.get_or_create_emoji (
  p_emoji_char text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SET search_path TO 'public', 'pg_temp'
  AS $function$
DECLARE
  v_emoji_id bigint;
BEGIN
  INSERT INTO public.emojis (emoji_char) VALUES (p_emoji_char)
  ON CONFLICT (emoji_char) DO NOTHING
  RETURNING id INTO v_emoji_id;

  IF v_emoji_id IS NULL THEN
    SELECT id INTO v_emoji_id FROM public.emojis WHERE emoji_char = p_emoji_char;
  END IF;

  RETURN v_emoji_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."get_or_create_emoji"(text) TO PUBLIC, "authenticated", "postgres", "service_role";

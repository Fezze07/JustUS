CREATE OR REPLACE FUNCTION public.set_mood (
  p_emoji_char text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_emoji_id bigint;
BEGIN
  v_emoji_id := public.get_or_create_emoji(p_emoji_char);
  INSERT INTO public.moods (user_id, mood_type_id) VALUES (public.current_user_id(), v_emoji_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."set_mood"(text) TO PUBLIC, "authenticated", "postgres", "service_role";

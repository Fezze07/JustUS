CREATE OR REPLACE FUNCTION public.mood_set (
  p_emoji_char text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_emoji_id bigint;
BEGIN
  v_emoji_id := public.emoji_get_or_create(p_emoji_char);
  INSERT INTO public.moods (user_id, mood_type_id) VALUES (public.user_current_id(), v_emoji_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."mood_set"(text) TO PUBLIC, "authenticated", "postgres", "service_role";

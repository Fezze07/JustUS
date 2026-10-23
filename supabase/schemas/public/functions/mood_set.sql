CREATE OR REPLACE FUNCTION public.mood_set (
  p_emoji_char text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_emoji_id bigint;
  v_partnership_id integer;
BEGIN
  v_emoji_id := public.emoji_get_or_create(p_emoji_char);
  SELECT id INTO v_partnership_id
    FROM public.partnerships
   WHERE status = 'accepted'
     AND (user_id_1 = public.user_current_id() OR user_id_2 = public.user_current_id())
   LIMIT 1;
  INSERT INTO public.moods (user_id, mood_type_id, partnership_id)
    VALUES (public.user_current_id(), v_emoji_id, v_partnership_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."mood_set"(text) TO PUBLIC, "authenticated", "postgres", "service_role";

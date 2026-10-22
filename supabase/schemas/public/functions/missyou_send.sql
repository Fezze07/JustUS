CREATE OR REPLACE FUNCTION public.missyou_send()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_partnership_id integer;
BEGIN
  SELECT id INTO v_partnership_id FROM public.partnerships 
  WHERE (user_id_1 = public.user_current_id() OR user_id_2 = public.user_current_id()) AND status = 'accepted'
  LIMIT 1;

  IF v_partnership_id IS NULL THEN
    RAISE EXCEPTION 'API-VALIDATION-007: No active partnership found';
  END IF;

  INSERT INTO public.missyou (partnership_id) VALUES (v_partnership_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."missyou_send"() TO PUBLIC, "authenticated", "postgres", "service_role";

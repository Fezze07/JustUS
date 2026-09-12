CREATE OR REPLACE FUNCTION public.request_partnership (
  partner_email      text,
  partner_code       text,
  override_sender_id integer DEFAULT NULL::integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_partner_id integer;
  v_current_user_id integer;
  v_partnership_id integer;
BEGIN
  IF override_sender_id IS NOT NULL THEN
    v_current_user_id := override_sender_id;
  ELSE
    v_current_user_id := public.current_user_id();
  END IF;

  IF v_current_user_id IS NULL THEN
    RAISE EXCEPTION 'Utente non autenticato o ID non valido';
  END IF;

  IF EXISTS (SELECT 1 FROM public.partnerships WHERE (user_id_1 = v_current_user_id OR user_id_2 = v_current_user_id) AND status IN ('pending', 'accepted')) THEN
    RAISE EXCEPTION 'Hai gia una partnership o una richiesta attiva';
  END IF;

  SELECT u.id INTO v_partner_id 
  FROM public.users u
  JOIN public.user_profiles up ON u.id = up.user_id
  WHERE u.email = partner_email AND up.partnership_code = upper(partner_code);

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Email o Codice Partner non validi';
  END IF;

  IF v_partner_id = v_current_user_id THEN
    RAISE EXCEPTION 'Non puoi invitare te stesso';
  END IF;

  INSERT INTO public.partnerships (user_id_1, user_id_2, status)
  VALUES (v_current_user_id, v_partner_id, 'pending')
  RETURNING id INTO v_partnership_id;

  RETURN v_partnership_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."request_partnership"(text, text, integer) TO "authenticated", "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."request_partnership"(text, text, integer) FROM PUBLIC;

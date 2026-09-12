CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_user_id integer;
  v_role_id bigint;
BEGIN
  -- Inserimento nella tabella public.users
  INSERT INTO public.users (auth_id, email)
  VALUES (NEW.id, NEW.email)
  RETURNING id INTO v_user_id;

  -- Inserimento del profilo base con partnership_code generato
  INSERT INTO public.user_profiles (user_id, display_name, partnership_code)
  VALUES (v_user_id, split_part(NEW.email, '@', 1), public.generate_unique_partnership_code());

  -- Recupero ID del ruolo 'user' (dovrebbe essere 1 come configurato prima)
  SELECT id INTO v_role_id FROM public.roles WHERE name = 'user';
  
  -- Se il ruolo non esiste per qualche motivo, lo creiamo (fallback)
  IF v_role_id IS NULL THEN
    INSERT INTO public.roles (id, name) VALUES (1, 'user')
    ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_role_id;
  END IF;

  -- Associazione del ruolo all'utente
  INSERT INTO public.user_roles (user_id, role_id)
  VALUES (v_user_id, v_role_id)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."handle_new_auth_user"() TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."handle_new_auth_user"() FROM PUBLIC;

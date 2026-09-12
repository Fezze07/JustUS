CREATE OR REPLACE FUNCTION public.generate_unique_partnership_code()
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  new_code text;
  done bool;
BEGIN
  done := false;
  WHILE NOT done LOOP
    -- Genera un codice di 6 caratteri alfanumerici casuali
    new_code := upper(substring(md5(random()::text) from 1 for 6));
    -- Controlla unicità
    IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE partnership_code = new_code) THEN
      done := true;
    END IF;
  END LOOP;
  RETURN new_code;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."generate_unique_partnership_code"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

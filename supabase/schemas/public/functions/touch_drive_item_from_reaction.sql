CREATE OR REPLACE FUNCTION public.touch_drive_item_from_reaction()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  UPDATE public.drive_items
     SET updated_at = NOW()
   WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.item_id ELSE NEW.item_id END;

  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."touch_drive_item_from_reaction"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."touch_drive_item_from_reaction"() TO "authenticated", "postgres", "service_role";

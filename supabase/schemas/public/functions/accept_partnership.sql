CREATE OR REPLACE FUNCTION public.accept_partnership (
  p_partnership_id integer
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
BEGIN
  -- Revert to original behavior: only update status and anniversary_date
  UPDATE public.partnerships
  SET status = 'accepted', anniversary_date = current_date
  WHERE id = p_partnership_id 
    AND (user_id_1 = public.current_user_id() OR user_id_2 = public.current_user_id()) 
    AND status = 'pending';
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."accept_partnership"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

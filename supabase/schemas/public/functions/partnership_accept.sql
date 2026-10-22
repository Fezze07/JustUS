CREATE OR REPLACE FUNCTION public.partnership_accept (
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
    AND user_id_2 = public.user_current_id() 
    AND status = 'pending';
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."partnership_accept"(integer) TO PUBLIC, "authenticated", "postgres", "service_role";

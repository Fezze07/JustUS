CREATE OR REPLACE FUNCTION public.get_pending_invitations ()
  RETURNS TABLE (
    invitation_id integer,
    status character varying,
    created_at timestamp with time zone,
    partner_id integer,
    partner_display_name text,
    is_received boolean
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  SELECT
    p.id,
    p.status,
    p.created_at,
    (
      CASE
        WHEN p.user_id_2 = public.current_user_id() THEN p.user_id_1
        ELSE p.user_id_2
      END
    ),
    up.display_name,
    (p.user_id_2 = public.current_user_id())
  FROM public.partnerships p
    LEFT JOIN public.user_profiles up ON up.user_id = (
      CASE
        WHEN p.user_id_2 = public.current_user_id() THEN p.user_id_1
        ELSE p.user_id_2
      END
    )
  WHERE (p.user_id_1 = public.current_user_id() OR p.user_id_2 = public.current_user_id())
    AND p.status = 'pending'
  ORDER BY p.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION "public"."get_pending_invitations"() FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."get_pending_invitations"() TO "authenticated", "postgres", "service_role";

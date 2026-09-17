CREATE OR REPLACE FUNCTION private.is_related_user (
  target_user_id integer
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  select exists (
    select 1
    from public.partnerships p
    where p.status = 'accepted'
      and (
        (p.user_id_1 = private.current_profile_id() and p.user_id_2 = target_user_id)
        or
        (p.user_id_2 = private.current_profile_id() and p.user_id_1 = target_user_id)
      )
  );
$function$;

GRANT EXECUTE ON FUNCTION "private"."is_related_user"(integer) TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "private"."is_related_user"(integer) FROM PUBLIC;

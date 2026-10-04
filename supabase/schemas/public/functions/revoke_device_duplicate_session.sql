-- Revokes any existing session bound to the same user + device fingerprint,
-- keeping only the session identified by p_keep_session_id.
--
-- Rationale: PostgREST only exposes the public schema, so the backend cannot
-- DELETE from auth.sessions directly.  A SECURITY DEFINER function is the
-- officially-supported Supabase pattern to perform controlled cross-schema
-- writes from the service-role.  Once the old auth.sessions row is deleted,
-- the ON DELETE CASCADE on session_bindings automatically removes the stale
-- binding — no parallel revocation table needed.
--
-- Called by the backend immediately before upserting the new binding.

CREATE OR REPLACE FUNCTION public.revoke_device_duplicate_session(
  p_user_id        uuid,
  p_fingerprint    text,
  p_keep_session   uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM auth.sessions s
  WHERE s.user_id = p_user_id
    AND s.id != p_keep_session
    AND EXISTS (
      SELECT 1
      FROM public.session_bindings sb
      WHERE sb.session_id = s.id
        AND sb.device_fingerprint_hash = p_fingerprint
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

-- Only the service role (backend) may invoke this function.
REVOKE ALL ON FUNCTION "public"."revoke_device_duplicate_session"(uuid, text, uuid) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."revoke_device_duplicate_session"(uuid, text, uuid) TO "postgres", "service_role";

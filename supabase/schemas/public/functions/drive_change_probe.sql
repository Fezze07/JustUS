CREATE OR REPLACE FUNCTION public.drive_change_probe ()
  RETURNS TABLE (max_updated_at timestamp with time zone, item_count bigint)
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  SET search_path TO 'public'
  AS $function$
  -- Revalidation gate for the drive screen: ONE round trip instead of
  -- `select(updated_at) ... limit 1` + `count()`.
  --   * max(updated_at) -> detects inserts/updates since the client checkpoint
  --   * count(*)       -> detects server-side deletions, which the
  --                       `updated_at > checkpoint` cursor cannot see
  -- Reads `drive_items` directly (RLS + the same partnership filter the view
  -- uses) so the probe never materializes `v_drive_dashboard` (LEFT JOIN +
  -- per-row EXISTS + json_agg of reactions), which the client never needs here.
  SELECT max(d.updated_at), count(*)::bigint
  FROM public.drive_items d
  WHERE public.is_in_partnership(d.partnership_id);
$function$;

REVOKE ALL ON FUNCTION public.drive_change_probe() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.drive_change_probe() TO "authenticated", "postgres", "service_role";

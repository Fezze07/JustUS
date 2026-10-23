CREATE OR REPLACE FUNCTION public.partnership_guard_status()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_caller_id integer;
BEGIN
  v_caller_id := public.user_current_id();

  IF NEW.user_id_1 IS DISTINCT FROM OLD.user_id_1
     OR NEW.user_id_2 IS DISTINCT FROM OLD.user_id_2 THEN
    RAISE EXCEPTION 'API-VALIDATION-009: Partnership members cannot be changed'
      USING ERRCODE = '42501';
  END IF;

  -- The backend and the expiry job write without a user JWT.
  IF v_caller_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- No status change: the cancellation fields are read-only.
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF NEW.cancel_requested_by IS DISTINCT FROM OLD.cancel_requested_by
       OR NEW.cancel_expires_at IS DISTINCT FROM OLD.cancel_expires_at THEN
      RAISE EXCEPTION 'API-VALIDATION-012: The cancellation fields are read-only outside a cancellation transition'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
    IF v_caller_id IS DISTINCT FROM NEW.user_id_2 THEN
      RAISE EXCEPTION 'API-VALIDATION-008: Only the invited partner can accept a partnership request'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'accepted' AND NEW.status = 'cancelled' THEN
    IF (v_caller_id IS DISTINCT FROM OLD.user_id_1 AND v_caller_id IS DISTINCT FROM OLD.user_id_2)
       OR NEW.cancel_requested_by IS DISTINCT FROM v_caller_id
       OR NEW.cancel_expires_at IS NULL THEN
      RAISE EXCEPTION 'API-VALIDATION-010: Only a member can request cancellation, recording themselves and an expiry'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'cancelled' AND NEW.status = 'accepted' THEN
    IF (v_caller_id IS DISTINCT FROM OLD.user_id_1 AND v_caller_id IS DISTINCT FROM OLD.user_id_2)
       OR NEW.cancel_requested_by IS NOT NULL
       OR NEW.cancel_expires_at IS NOT NULL THEN
      RAISE EXCEPTION 'API-VALIDATION-011: Only a member can revert a cancellation, clearing the cancellation fields'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'cancelled' AND NEW.status = 'cancelled' THEN
    IF NEW.cancel_requested_by IS DISTINCT FROM OLD.cancel_requested_by
       OR NEW.cancel_expires_at IS DISTINCT FROM OLD.cancel_expires_at THEN
      RAISE EXCEPTION 'API-VALIDATION-012: The cancellation requester and expiry cannot be changed while cancelled'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'API-VALIDATION-012: Invalid partnership status transition from % to %', OLD.status, NEW.status
    USING ERRCODE = '42501';
END;
$function$;

REVOKE ALL ON FUNCTION "public"."partnership_guard_status"() FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."partnership_guard_status"() TO "postgres", "service_role";

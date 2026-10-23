CREATE TABLE "public"."partnerships" (
  "id"                  integer                  NOT NULL DEFAULT nextval('public.partnerships_id_seq'::regclass),
  "user_id_1"           integer,
  "user_id_2"           integer,
  "status"              character varying(50)    DEFAULT 'accepted'::character varying,
  "created_at"          timestamp with time zone DEFAULT now(),
  "anniversary_date"    date,
  "updated_at"          timestamp with time zone DEFAULT now(),
  "cancel_requested_by" integer,
  "cancel_expires_at"   timestamp with time zone,
  "cancel_declined_at"  timestamp with time zone,
  CONSTRAINT "partnerships_pkey" PRIMARY KEY (id),
  CONSTRAINT "partnerships_user1_id_user2_id_key" UNIQUE (user_id_1, user_id_2),
  CONSTRAINT "partnerships_user_id_1_fkey" FOREIGN KEY (user_id_1) REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT "partnerships_user_id_2_fkey" FOREIGN KEY (user_id_2) REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT "partnerships_cancel_requested_by_fkey" FOREIGN KEY (cancel_requested_by) REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT "partnerships_status_check" CHECK (status IN ('pending', 'accepted', 'cancelled')),
  CONSTRAINT "partnerships_cancel_requester_check" CHECK (cancel_requested_by IS NULL OR cancel_requested_by = user_id_1 OR cancel_requested_by = user_id_2),
  CONSTRAINT "partnerships_cancel_state_check" CHECK ((status = 'cancelled') = (cancel_requested_by IS NOT NULL) AND (status = 'cancelled') = (cancel_expires_at IS NOT NULL))
);

ALTER TABLE "public"."partnerships"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."partnerships_id_seq" OWNED BY "public"."partnerships"."id";

CREATE INDEX idx_partnerships_user2_id ON public.partnerships USING btree (user_id_2);

CREATE TRIGGER set_public_partnerships_updated_at
  BEFORE UPDATE ON public.partnerships
  FOR EACH ROW
  EXECUTE FUNCTION public.util_set_updated_at();

CREATE TRIGGER guard_public_partnerships_status
  BEFORE UPDATE ON public.partnerships
  FOR EACH ROW
  EXECUTE FUNCTION public.partnership_guard_status();

CREATE POLICY "partnerships_delete_own" ON "public"."partnerships"
  FOR DELETE
  TO "authenticated"
  USING (((user_id_1 = public.user_current_id()) OR (user_id_2 = public.user_current_id())) AND status = 'pending');

CREATE POLICY "partnerships_select_own" ON "public"."partnerships"
  FOR SELECT
  TO "authenticated"
  USING ((user_id_1 = public.user_current_id()) OR (user_id_2 = public.user_current_id()));

CREATE POLICY "partnerships_update_own" ON "public"."partnerships"
  FOR UPDATE
  TO "authenticated"
  USING ((user_id_1 = public.user_current_id()) OR (user_id_2 = public.user_current_id()))
  WITH CHECK ((user_id_1 = public.user_current_id()) OR (user_id_2 = public.user_current_id()));

REVOKE INSERT ON TABLE "public"."partnerships" FROM "anon";
GRANT DELETE, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partnerships" TO "anon", "authenticated", "postgres", "service_role";
GRANT INSERT ON TABLE "public"."partnerships" TO "authenticated", "postgres", "service_role";
REVOKE DELETE, TRUNCATE ON TABLE "public"."partnerships" FROM "anon";

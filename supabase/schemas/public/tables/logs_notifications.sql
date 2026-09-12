CREATE TABLE "public"."logs_notifications" (
  "id"         integer                  NOT NULL DEFAULT nextval('public.notifications_logs_id_seq'::regclass),
  "type"       character varying(50),
  "created_at" timestamp with time zone DEFAULT now(),
  "user_id"    integer,
  "status"     text,
  CONSTRAINT "notifications_logs_pkey" PRIMARY KEY (id),
  CONSTRAINT "logs_notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."logs_notifications"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."notifications_logs_id_seq" OWNED BY "public"."logs_notifications"."id";

CREATE INDEX idx_logs_notifications_user_id ON public.logs_notifications USING btree (user_id);

CREATE POLICY "notifications_select_own" ON "public"."logs_notifications"
  FOR SELECT
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."logs_notifications" TO "anon", "authenticated", "postgres", "service_role";

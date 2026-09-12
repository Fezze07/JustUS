CREATE TABLE "public"."users" (
  "id"         integer                  NOT NULL DEFAULT nextval('public.users_id_seq'::regclass),
  "email"      character varying(255),
  "created_at" timestamp with time zone DEFAULT now(),
  "updated_at" timestamp with time zone DEFAULT now(),
  "auth_id"    uuid,
  CONSTRAINT "users_auth_id_key" UNIQUE (auth_id),
  CONSTRAINT "users_email_key" UNIQUE (email),
  CONSTRAINT "users_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."users"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."users_id_seq" OWNED BY "public"."users"."id";

CREATE TRIGGER set_public_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "users_insert_self" ON "public"."users"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((( SELECT auth.uid() AS uid) = auth_id));

CREATE POLICY "users_insert_service_role" ON "public"."users"
  FOR INSERT
  TO "service_role"
  WITH CHECK (true);

CREATE POLICY "users_select_authenticated" ON "public"."users"
  FOR SELECT
  TO PUBLIC
  USING ((( SELECT auth.role() AS ROLE) = 'authenticated'::text));

CREATE POLICY "users_update_self" ON "public"."users"
  FOR UPDATE
  TO PUBLIC
  USING ((id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."users" TO "anon", "authenticated", "postgres", "service_role";

COMMENT ON COLUMN "public"."users"."auth_id" IS 'References auth.users(id)';

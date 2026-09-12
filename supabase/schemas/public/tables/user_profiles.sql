CREATE TABLE "public"."user_profiles" (
  "user_id"          integer                  NOT NULL,
  "display_name"     text,
  "profile_pic_url"  text,
  "created_at"       timestamp with time zone DEFAULT now(),
  "updated_at"       timestamp with time zone DEFAULT now(),
  "bio"              text,
  "partnership_code" text,
  CONSTRAINT "user_profiles_partnership_code_key" UNIQUE (partnership_code),
  CONSTRAINT "user_profiles_pkey" PRIMARY KEY (user_id),
  CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."user_profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER set_public_user_profiles_updated_at
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "profiles_insert_self" ON "public"."user_profiles"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((user_id = public.current_user_id()));

CREATE POLICY "profiles_select_authenticated" ON "public"."user_profiles"
  FOR SELECT
  TO PUBLIC
  USING ((( SELECT auth.role() AS ROLE) = 'authenticated'::text));

CREATE POLICY "profiles_update_self" ON "public"."user_profiles"
  FOR UPDATE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_profiles" TO "anon", "authenticated", "postgres", "service_role";

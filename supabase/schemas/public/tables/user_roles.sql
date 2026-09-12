CREATE TABLE "public"."user_roles" (
  "user_id"    integer                  NOT NULL,
  "role_id"    bigint                   NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  "updated_at" timestamp with time zone DEFAULT now(),
  CONSTRAINT "user_roles_pkey1" PRIMARY KEY (user_id, role_id),
  CONSTRAINT "user_roles_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE,
  CONSTRAINT "user_roles_user_id_fkey1" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."user_roles"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_user_roles_role_id ON public.user_roles USING btree (role_id);

CREATE TRIGGER set_public_user_roles_updated_at
  BEFORE UPDATE ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "Users can view their own roles" ON "public"."user_roles"
  FOR SELECT
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_roles" TO "anon", "authenticated", "postgres", "service_role";

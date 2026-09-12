CREATE TABLE "public"."partnerships" (
  "id"               integer                  NOT NULL DEFAULT nextval('public.partnerships_id_seq'::regclass),
  "user_id_1"        integer,
  "user_id_2"        integer,
  "status"           character varying(50)    DEFAULT 'accepted'::character varying,
  "created_at"       timestamp with time zone DEFAULT now(),
  "anniversary_date" date,
  "updated_at"       timestamp with time zone DEFAULT now(),
  CONSTRAINT "partnerships_pkey" PRIMARY KEY (id),
  CONSTRAINT "partnerships_user1_id_user2_id_key" UNIQUE (user_id_1, user_id_2),
  CONSTRAINT "partnerships_user_id_1_fkey" FOREIGN KEY (user_id_1) REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT "partnerships_user_id_2_fkey" FOREIGN KEY (user_id_2) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."partnerships"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."partnerships_id_seq" OWNED BY "public"."partnerships"."id";

CREATE INDEX idx_partnerships_user2_id ON public.partnerships USING btree (user_id_2);

CREATE TRIGGER set_public_partnerships_updated_at
  BEFORE UPDATE ON public.partnerships
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "partnerships_manage_own" ON "public"."partnerships"
  FOR ALL
  TO PUBLIC
  USING (((user_id_1 = public.current_user_id()) OR (user_id_2 = public.current_user_id())));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partnerships" TO "anon", "authenticated", "postgres", "service_role";

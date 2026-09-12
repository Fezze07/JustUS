CREATE TABLE "public"."moods" (
  "id"           integer                  NOT NULL DEFAULT nextval('public.moods_id_seq'::regclass),
  "user_id"      integer,
  "created_at"   timestamp with time zone DEFAULT now(),
  "mood_type_id" bigint,
  CONSTRAINT "moods_mood_type_id_fkey" FOREIGN KEY (mood_type_id) REFERENCES public.emojis(id) ON DELETE CASCADE,
  CONSTRAINT "moods_pkey" PRIMARY KEY (id),
  CONSTRAINT "moods_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."moods"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."moods_id_seq" OWNED BY "public"."moods"."id";

CREATE INDEX idx_moods_mood_type_id ON public.moods USING btree (mood_type_id);

CREATE INDEX idx_moods_user_id ON public.moods USING btree (user_id);

CREATE POLICY "moods_delete_own" ON "public"."moods"
  FOR DELETE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

CREATE POLICY "moods_manage_own" ON "public"."moods"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((user_id = public.current_user_id()));

CREATE POLICY "moods_related_access" ON "public"."moods"
  FOR SELECT
  TO PUBLIC
  USING (((user_id = public.current_user_id()) OR public.is_partner_of(user_id)));

CREATE POLICY "moods_update_own" ON "public"."moods"
  FOR UPDATE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."moods" TO "anon", "authenticated", "postgres", "service_role";

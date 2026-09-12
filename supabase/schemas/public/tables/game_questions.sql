CREATE TABLE "public"."game_questions" (
  "id"             integer                  NOT NULL DEFAULT nextval('public.game_questions_id_seq'::regclass),
  "created_at"     timestamp with time zone DEFAULT now(),
  "partnership_id" integer,
  "question"       text,
  "status"         text                     DEFAULT 'pending'::text,
  "user_id_a"      integer,
  "user_id_b"      integer,
  CONSTRAINT "game_questions_pkey" PRIMARY KEY (id),
  CONSTRAINT "game_questions_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES public.partnerships(id) ON DELETE CASCADE,
  CONSTRAINT "game_questions_user_id_a_fkey" FOREIGN KEY (user_id_a) REFERENCES public.users(id),
  CONSTRAINT "game_questions_user_id_b_fkey" FOREIGN KEY (user_id_b) REFERENCES public.users(id)
);

ALTER TABLE "public"."game_questions"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."game_questions_id_seq" OWNED BY "public"."game_questions"."id";

CREATE INDEX idx_game_questions_partnership_id ON public.game_questions USING btree (partnership_id);

CREATE INDEX idx_game_questions_user_id_a ON public.game_questions USING btree (user_id_a);

CREATE INDEX idx_game_questions_user_id_b ON public.game_questions USING btree (user_id_b);

CREATE POLICY "game_questions_related" ON "public"."game_questions"
  FOR ALL
  TO PUBLIC
  USING (public.is_in_partnership(partnership_id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."game_questions" TO "anon", "authenticated", "postgres", "service_role";

CREATE TABLE "public"."game_answers" (
  "game_id"         integer                  NOT NULL,
  "user_id"         integer                  NOT NULL,
  "selected_option" integer,
  "created_at"      timestamp with time zone DEFAULT now(),
  CONSTRAINT "game_answers_pkey" PRIMARY KEY (game_id, user_id),
  CONSTRAINT "game_answers_game_id_fkey" FOREIGN KEY (game_id) REFERENCES public.game_questions(id) ON DELETE CASCADE,
  CONSTRAINT "game_answers_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."game_answers"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_game_answers_user_id ON public.game_answers USING btree (user_id);

CREATE POLICY "game_answers_delete_own" ON "public"."game_answers"
  FOR DELETE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

CREATE POLICY "game_answers_manage_own" ON "public"."game_answers"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((user_id = public.current_user_id()));

CREATE POLICY "game_answers_related_select" ON "public"."game_answers"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.game_questions
  WHERE ((game_questions.id = game_answers.game_id) AND public.is_in_partnership(game_questions.partnership_id)))));

CREATE POLICY "game_answers_update_own" ON "public"."game_answers"
  FOR UPDATE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."game_answers" TO "anon", "authenticated", "postgres", "service_role";

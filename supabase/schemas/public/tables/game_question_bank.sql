CREATE TABLE "public"."game_question_bank" (
  "question_code" text                     NOT NULL,
  "locale"        text                     NOT NULL,
  "text"          text                     NOT NULL,
  "created_at"    timestamp with time zone DEFAULT now(),
  "updated_at"    timestamp with time zone DEFAULT now(),
  CONSTRAINT "game_question_bank_pkey" PRIMARY KEY ("question_code", "locale")
);

ALTER TABLE "public"."game_question_bank"
  ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER set_public_game_question_bank_updated_at
  BEFORE UPDATE ON public.game_question_bank
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "game_question_bank_read_all" ON "public"."game_question_bank"
  FOR SELECT
  TO PUBLIC
  USING (true);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."game_question_bank" TO "anon", "authenticated", "postgres", "service_role";

CREATE TABLE "public"."missyou" (
  "id"             integer                  NOT NULL DEFAULT nextval('public.missyou_id_seq'::regclass),
  "created_at"     timestamp with time zone DEFAULT now(),
  "partnership_id" integer,
  CONSTRAINT "missyou_pkey" PRIMARY KEY (id),
  CONSTRAINT "missyou_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES public.partnerships(id) ON DELETE CASCADE
);

ALTER TABLE "public"."missyou"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."missyou_id_seq" OWNED BY "public"."missyou"."id";

CREATE INDEX idx_missyou_partnership_id ON public.missyou USING btree (partnership_id);

CREATE POLICY "missyou_related" ON "public"."missyou"
  FOR ALL
  TO PUBLIC
  USING (public.is_in_partnership(partnership_id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."missyou" TO "anon", "authenticated", "postgres", "service_role";

CREATE TABLE "public"."bucket_items" (
  "id"             integer                  NOT NULL DEFAULT nextval('public.bucket_items_id_seq'::regclass),
  "text"           text                     NOT NULL,
  "done"           boolean                  DEFAULT false,
  "created_at"     timestamp with time zone DEFAULT now(),
  "category"       character varying(50),
  "partnership_id" integer,
  CONSTRAINT "bucket_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "bucket_items_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES public.partnerships(id) ON DELETE CASCADE
);

ALTER TABLE "public"."bucket_items"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."bucket_items_id_seq" OWNED BY "public"."bucket_items"."id";

CREATE INDEX idx_bucket_items_partnership_id ON public.bucket_items USING btree (partnership_id);

CREATE POLICY "bucket_items_partnership_access" ON "public"."bucket_items"
  FOR ALL
  TO PUBLIC
  USING (public.is_in_partnership(partnership_id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bucket_items" TO "anon", "authenticated", "postgres", "service_role";

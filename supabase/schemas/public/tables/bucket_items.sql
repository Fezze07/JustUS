CREATE TABLE "public"."bucket_items" (
  "id"             integer                  NOT NULL DEFAULT nextval('public.bucket_items_id_seq'::regclass),
  "text"           text                     NOT NULL,
  "done"           boolean                  DEFAULT false,
  "created_at"     timestamp with time zone DEFAULT now(),
  "updated_at"     timestamp with time zone DEFAULT now(),
  "category"       character varying(50),
  "partnership_id" integer,
  CONSTRAINT "bucket_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "bucket_items_category_check" CHECK (
    category IS NULL OR category IN ('Travel', 'Dates', 'Goals', 'Crazy', 'Adventure', 'Romantic', 'Homemade')
  ),
  CONSTRAINT "bucket_items_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES public.partnerships(id) ON DELETE CASCADE
);

ALTER TABLE "public"."bucket_items"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."bucket_items_id_seq" OWNED BY "public"."bucket_items"."id";

CREATE INDEX idx_bucket_items_partnership_id ON public.bucket_items USING btree (partnership_id);

CREATE TRIGGER set_public_bucket_items_updated_at
  BEFORE UPDATE ON public.bucket_items
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "bucket_items_partnership_access" ON "public"."bucket_items"
  FOR ALL
  TO PUBLIC
  USING (public.is_in_partnership(partnership_id))
  WITH CHECK (public.is_in_partnership(partnership_id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."bucket_items" TO "anon", "authenticated", "postgres", "service_role";

CREATE TABLE "public"."drive_items" (
  "id"             integer                  NOT NULL DEFAULT nextval('public.drive_items_id_seq'::regclass),
  "type"           character varying(50)    NOT NULL,
  "name"           text                     NOT NULL,
  "original_name"  text,
  "mime_type"      character varying(100),
  "size"           bigint,
  "metadata"       jsonb,
  "created_at"     timestamp with time zone DEFAULT now(),
  "updated_at"     timestamp with time zone DEFAULT now(),
  "partnership_id" integer,
  "file_type_id"   bigint,
  CONSTRAINT "drive_items_file_type_id_fkey" FOREIGN KEY (file_type_id) REFERENCES public.drive_file_types(id) ON DELETE SET NULL,
  CONSTRAINT "drive_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "drive_items_partnership_id_fkey" FOREIGN KEY (partnership_id) REFERENCES public.partnerships(id) ON DELETE CASCADE
);

ALTER TABLE "public"."drive_items"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."drive_items_id_seq" OWNED BY "public"."drive_items"."id";

CREATE INDEX idx_drive_items_file_type_id ON public.drive_items USING btree (file_type_id);

CREATE INDEX idx_drive_items_partnership_id ON public.drive_items USING btree (partnership_id);

CREATE TRIGGER set_public_drive_items_updated_at
  BEFORE UPDATE ON public.drive_items
  FOR EACH ROW
  EXECUTE FUNCTION public.set_current_timestamp_updated_at();

CREATE POLICY "drive_items_related" ON "public"."drive_items"
  FOR ALL
  TO PUBLIC
  USING (public.is_in_partnership(partnership_id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."drive_items" TO "anon", "authenticated", "postgres", "service_role";

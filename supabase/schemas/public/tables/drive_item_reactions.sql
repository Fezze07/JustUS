CREATE TABLE "public"."drive_item_reactions" (
  "id"         integer                  NOT NULL DEFAULT nextval('public.drive_reactions_id_seq'::regclass),
  "user_id"    integer,
  "item_id"    integer,
  "created_at" timestamp with time zone DEFAULT now(),
  "emoji_id"   bigint,
  CONSTRAINT "drive_item_reactions_user_id_item_id_key" UNIQUE (user_id, item_id),
  CONSTRAINT "drive_reactions_pkey" PRIMARY KEY (id),
  CONSTRAINT "drive_reactions_item_id_fkey" FOREIGN KEY (item_id) REFERENCES public.drive_items(id) ON DELETE CASCADE,
  CONSTRAINT "drive_item_reactions_emoji_id_fkey" FOREIGN KEY (emoji_id) REFERENCES public.emojis(id) ON DELETE CASCADE,
  CONSTRAINT "drive_reactions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."drive_item_reactions"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "public"."drive_reactions_id_seq" OWNED BY "public"."drive_item_reactions"."id";

CREATE INDEX idx_drive_item_reactions_emoji_id ON public.drive_item_reactions USING btree (emoji_id);

CREATE INDEX idx_drive_item_reactions_item_id ON public.drive_item_reactions USING btree (item_id);

CREATE POLICY "drive_item_reactions_delete_own" ON "public"."drive_item_reactions"
  FOR DELETE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

CREATE POLICY "drive_item_reactions_manage_own" ON "public"."drive_item_reactions"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((user_id = public.current_user_id()));

CREATE POLICY "drive_item_reactions_related_select" ON "public"."drive_item_reactions"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.drive_items
  WHERE ((drive_items.id = drive_item_reactions.item_id) AND public.is_in_partnership(drive_items.partnership_id)))));

CREATE POLICY "drive_item_reactions_update_own" ON "public"."drive_item_reactions"
  FOR UPDATE
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."drive_item_reactions" TO "anon", "authenticated", "postgres", "service_role";

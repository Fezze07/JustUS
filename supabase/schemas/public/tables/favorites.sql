CREATE TABLE "public"."favorites" (
  "user_id"    integer                  NOT NULL,
  "item_id"    integer                  NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  CONSTRAINT "drive_favorites_item_id_fkey" FOREIGN KEY (item_id) REFERENCES public.drive_items(id) ON DELETE CASCADE,
  CONSTRAINT "drive_favorites_pkey" PRIMARY KEY (user_id, item_id),
  CONSTRAINT "drive_favorites_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

ALTER TABLE "public"."favorites"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_favorites_item_id ON public.favorites USING btree (item_id);

CREATE POLICY "favorites_own" ON "public"."favorites"
  FOR ALL
  TO PUBLIC
  USING ((user_id = public.current_user_id()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."favorites" TO "anon", "authenticated", "postgres", "service_role";

CREATE VIEW "public"."v_drive_dashboard" WITH (security_invoker=true) AS  SELECT d.id,
    d.partnership_id,
    d.name,
    d.original_name,
    d.type,
    d.size,
    d.created_at,
    d.updated_at,
    ft.extension,
    ft.mime_type,
    ft.icon_slug,
    (EXISTS ( SELECT 1
           FROM public.favorites f
          WHERE ((f.item_id = d.id) AND (f.user_id = public.current_user_id())))) AS is_favorite,
    ( SELECT json_agg(json_build_object('user_id', r.user_id, 'emoji_char', e.emoji_char)) AS json_agg
           FROM (public.drive_item_reactions r
             JOIN public.emojis e ON ((e.id = r.emoji_id)))
          WHERE (r.item_id = d.id)) AS reactions
   FROM (public.drive_items d
     LEFT JOIN public.drive_file_types ft ON ((ft.id = d.file_type_id)))
  WHERE public.is_in_partnership(d.partnership_id);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."v_drive_dashboard" TO "anon", "authenticated", "postgres", "service_role";

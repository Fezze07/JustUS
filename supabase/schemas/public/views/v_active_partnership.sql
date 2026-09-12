CREATE VIEW "public"."v_active_partnership" WITH (security_invoker=true) AS  SELECT p.id AS partnership_id,
    p.status,
    p.anniversary_date,
    u.id AS partner_id,
    u.email AS partner_email,
    up.display_name AS partner_display_name,
    up.profile_pic_url AS partner_profile_pic_url,
    up.bio AS partner_bio,
    p.user_id_1 AS user_id_a,
    p.user_id_2 AS user_id_b,
    up1.display_name AS user_a_name,
    up2.display_name AS user_b_name
   FROM ((((public.partnerships p
     JOIN public.users u ON ((((u.id = p.user_id_1) OR (u.id = p.user_id_2)) AND (u.id <> ( SELECT public.current_user_id() AS current_user_id)))))
     JOIN public.user_profiles up ON ((up.user_id = u.id)))
     LEFT JOIN public.user_profiles up1 ON ((up1.user_id = p.user_id_1)))
     LEFT JOIN public.user_profiles up2 ON ((up2.user_id = p.user_id_2)))
  WHERE (((p.user_id_1 = ( SELECT public.current_user_id() AS current_user_id)) OR (p.user_id_2 = ( SELECT public.current_user_id() AS current_user_id))) AND ((p.status)::text = 'accepted'::text));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."v_active_partnership" TO "anon", "authenticated", "postgres", "service_role";

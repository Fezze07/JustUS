CREATE VIEW "public"."v_active_partnership" WITH (security_invoker=true) AS
 SELECT p.id AS partnership_id,
    p.status,
    p.anniversary_date,
    (
      CASE
        WHEN p.user_id_1 = public.current_user_id() THEN p.user_id_2
        ELSE p.user_id_1
      END
    ) AS partner_id,
    up.display_name AS partner_display_name,
    up.profile_pic_url AS partner_profile_pic_url,
    p.user_id_1 AS user_id_a,
    p.user_id_2 AS user_id_b
   FROM public.partnerships p
     JOIN public.user_profiles up ON up.user_id = (
       CASE
         WHEN p.user_id_1 = public.current_user_id() THEN p.user_id_2
         ELSE p.user_id_1
       END
     )
  WHERE ((p.user_id_1 = public.current_user_id()) OR (p.user_id_2 = public.current_user_id()))
    AND (p.status::text = 'accepted'::text);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."v_active_partnership" TO "anon", "authenticated", "postgres", "service_role";

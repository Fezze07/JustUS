CREATE SEQUENCE "public"."drive_reactions_id_seq" AS integer INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1 NO CYCLE;

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."drive_reactions_id_seq" TO "anon", "authenticated", "postgres", "service_role";

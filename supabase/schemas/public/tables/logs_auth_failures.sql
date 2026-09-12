CREATE TABLE "public"."logs_auth_failures" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "request_id"    text,
  "error_code"    text                     NOT NULL,
  "error_message" text,
  "path"          text,
  "user_id"       integer,
  "ip_address"    text,
  "reason"        text,
  "severity"      text                     NOT NULL DEFAULT 'HIGH'::text,
  "payload"       jsonb,
  "stack"         text,
  CONSTRAINT "logs_auth_failures_pkey" PRIMARY KEY (id),
  CONSTRAINT "logs_auth_failures_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
);

ALTER TABLE "public"."logs_auth_failures"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX logs_auth_failures_created_idx ON public.logs_auth_failures USING btree (created_at DESC);

CREATE INDEX logs_auth_failures_ip_idx ON public.logs_auth_failures USING btree (ip_address);

CREATE INDEX logs_auth_failures_user_idx ON public.logs_auth_failures USING btree (user_id);

CREATE POLICY "service_role_only" ON "public"."logs_auth_failures"
  FOR ALL
  TO PUBLIC
  USING ((( SELECT auth.role() AS ROLE) = 'service_role'::text));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."logs_auth_failures" TO "anon", "authenticated", "postgres", "service_role";

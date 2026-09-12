CREATE TABLE "public"."logs_api_access" (
  "id"          bigint                   GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME "public"."api_access_logs_id_seq") NOT NULL,
  "request_id"  uuid,
  "method"      text,
  "path"        text,
  "status_code" integer,
  "duration_ms" integer,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "device_id"   bigint,
  CONSTRAINT "api_access_logs_pkey" PRIMARY KEY (id),
  CONSTRAINT "logs_api_access_device_id_fkey" FOREIGN KEY (device_id) REFERENCES public.user_devices(id) ON DELETE SET NULL
);

ALTER TABLE "public"."logs_api_access"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_logs_api_access_device_id ON public.logs_api_access USING btree (device_id);

CREATE POLICY "backend_only_access_logs" ON "public"."logs_api_access"
  FOR ALL
  TO "authenticated"
  USING (false)
  WITH CHECK (false);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."logs_api_access" TO "anon", "authenticated", "postgres", "service_role";

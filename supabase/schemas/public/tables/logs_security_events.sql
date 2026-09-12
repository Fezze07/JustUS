CREATE TABLE "public"."logs_security_events" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME "public"."security_events_id_seq") NOT NULL,
  "request_id" uuid,
  "type"       text                     NOT NULL,
  "path"       text,
  "error_json" jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "device_id"  bigint,
  CONSTRAINT "security_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "logs_security_events_device_id_fkey" FOREIGN KEY (device_id) REFERENCES public.user_devices(id) ON DELETE SET NULL
);

ALTER TABLE "public"."logs_security_events"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_logs_security_events_device_id ON public.logs_security_events USING btree (device_id);

CREATE POLICY "backend_only_security_events" ON "public"."logs_security_events"
  FOR ALL
  TO "authenticated"
  USING (false)
  WITH CHECK (false);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."logs_security_events" TO "anon", "authenticated", "postgres", "service_role";

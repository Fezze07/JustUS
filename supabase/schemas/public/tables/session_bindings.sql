CREATE TABLE "public"."session_bindings" (
  "session_id"              uuid                     NOT NULL,
  "device_fingerprint_hash" text                     NOT NULL,
  "binding_secret"          text                     NOT NULL,
  "country_code"            text,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "last_seen_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "session_bindings_pkey" PRIMARY KEY ("session_id"),
  CONSTRAINT "session_bindings_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE
);

ALTER TABLE "public"."session_bindings"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "backend_only_session_bindings" ON "public"."session_bindings"
  FOR ALL
  TO "authenticated"
  USING (false)
  WITH CHECK (false);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."session_bindings" TO "anon", "authenticated", "postgres", "service_role";

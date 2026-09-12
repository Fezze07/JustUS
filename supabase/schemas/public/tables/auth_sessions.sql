CREATE TABLE "public"."auth_sessions" (
  "id"                      bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "user_id"                 integer                  NOT NULL,
  "auth_user_id"            uuid,
  "session_id"              text                     NOT NULL,
  "device_fingerprint_hash" text                     NOT NULL,
  "device_label"            text,
  "ip_address"              text,
  "ip_range"                text,
  "country_code"            text,
  "user_agent"              text,
  "user_agent_hash"         text,
  "request_profile_hash"    text,
  "binding_secret"          text,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "last_seen_at"            timestamp with time zone NOT NULL DEFAULT now(),
  "revoked_at"              timestamp with time zone,
  CONSTRAINT "auth_sessions_pkey" PRIMARY KEY (id),
  CONSTRAINT "auth_sessions_session_id_key" UNIQUE (session_id)
);

ALTER TABLE "public"."auth_sessions"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "backend_only_auth_sessions" ON "public"."auth_sessions"
  FOR ALL
  TO "authenticated"
  USING (false)
  WITH CHECK (false);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."auth_sessions" TO "anon", "authenticated", "postgres", "service_role";

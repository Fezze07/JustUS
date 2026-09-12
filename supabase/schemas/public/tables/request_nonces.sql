CREATE TABLE "public"."request_nonces" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "nonce"      text                     NOT NULL,
  "namespace"  text                     NOT NULL,
  "user_id"    integer,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at" timestamp with time zone NOT NULL,
  CONSTRAINT "request_nonces_nonce_key" UNIQUE (nonce),
  CONSTRAINT "request_nonces_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."request_nonces"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "backend_only_request_nonces" ON "public"."request_nonces"
  FOR ALL
  TO "authenticated"
  USING (false)
  WITH CHECK (false);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."request_nonces" TO "anon", "authenticated", "postgres", "service_role";

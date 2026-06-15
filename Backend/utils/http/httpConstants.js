const CORS_ALLOWED_HEADERS = [
  "Authorization",
  "Content-Type",
  "X-Request-Id",
  "X-Request-Timestamp",
  "X-Request-Nonce",
  "X-Request-Signature",
  "X-Idempotency-Key",
  "Idempotency-Key",
].join(", ");

const CORS_ALLOWED_METHODS = "GET,POST,PATCH,DELETE,OPTIONS";

module.exports = { CORS_ALLOWED_HEADERS, CORS_ALLOWED_METHODS };

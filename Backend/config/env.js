const { loadEnv } = require("./loadEnv");

loadEnv();

function parseNumber(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseList(value) {
  return (value ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

const env = {
  nodeEnv: process.env.NODE_ENV ?? "development",
  port: parseNumber(process.env.PORT, 5001),
  trustProxy: parseNumber(process.env.TRUST_PROXY, 1),
  requestTimeoutMs: parseNumber(process.env.REQUEST_TIMEOUT_MS, 15_000),
  bodyLimit: process.env.BODY_LIMIT ?? "1mb",
  allowedOrigins: parseList(process.env.ALLOWED_ORIGINS),
  supabaseUrl: process.env.SUPABASE_URL ?? "",
  supabaseAnonKey:
    process.env.SUPABASE_ANON_KEY ??
    process.env.SUPABASE_PUBLISHABLE_KEY ??
    "",
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
  maxAccessTokenLifetimeSec: parseNumber(process.env.MAX_ACCESS_TOKEN_LIFETIME_SEC, 900),
  turnstileSecretKey: process.env.TURNSTILE_SECRET_KEY ?? "",
  turnstileEnabled: Boolean(process.env.TURNSTILE_SECRET_KEY),
  r2AccountId: process.env.R2_ACCOUNT_ID ?? "",
  r2AccessKeyId: process.env.R2_ACCESS_KEY_ID ?? "",
  r2SecretAccessKey: process.env.R2_SECRET_ACCESS_KEY ?? "",
  r2Endpoint: process.env.R2_ENDPOINT ?? "",
  r2BucketName: process.env.R2_BUCKET_NAME ?? "",
  mediaUploadUrlExpiresSeconds: parseNumber(process.env.MEDIA_UPLOAD_URL_EXPIRES_SECONDS, 300),
  mediaDownloadUrlExpiresSeconds: parseNumber(process.env.MEDIA_DOWNLOAD_URL_EXPIRES_SECONDS, 300),
  maxUploadBytes: parseNumber(process.env.MAX_UPLOAD_BYTES, 15 * 1024 * 1024),
  largeUploadThresholdBytes: parseNumber(process.env.LARGE_UPLOAD_THRESHOLD_BYTES, 5 * 1024 * 1024),
  aiMaxTokens: parseNumber(process.env.AI_MAX_TOKENS, 160),
  aiTimeoutMs: parseNumber(process.env.AI_TIMEOUT_MS, 12_000),
  aiDailyTokenLimit: parseNumber(process.env.AI_DAILY_TOKEN_LIMIT, 4_000),
  aiCircuitBreakerThreshold: parseNumber(process.env.AI_CIRCUIT_BREAKER_THRESHOLD, 5),
  aiCircuitBreakerCooldownMs: parseNumber(process.env.AI_CIRCUIT_BREAKER_COOLDOWN_MS, 60_000),
  requestSigningMaxSkewMs: parseNumber(process.env.REQUEST_SIGNING_MAX_SKEW_MS, 5 * 60_000),
};

function requireEnv(keys, context) {
  const missing = keys.filter((key) => !process.env[key]);
  if (missing.length > 0) {
    throw new Error(
      `[env] Missing required environment variables for ${context}: ${missing.join(
        ", "
      )}`
    );
  }
}

module.exports = { env, requireEnv };

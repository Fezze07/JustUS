/**
 * retentionService.js
 *
 * Runs scheduled cleanup jobs to enforce data-retention policies:
 *   - security_events, api_access_logs, api_error_logs → delete after LOG_RETENTION_DAYS (default 90)
 *   - request_nonces → delete rows past their expires_at (default: daily sweep)
 *   - R2 incomplete multipart uploads → abort after MULTIPART_MAX_AGE_MS (default 48 h)
 *
 * Call `startRetentionJobs()` once at server startup.
 */

const {
  S3Client,
  ListMultipartUploadsCommand,
  AbortMultipartUploadCommand,
} = require("@aws-sdk/client-s3");
const { adminSupabase, env, logError, logInfo } = require("../../all_imports");

// ── Constants ────────────────────────────────────────────────────────────────

const LOG_RETENTION_DAYS = Number(process.env.LOG_RETENTION_DAYS) || 90;
const NONCE_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;      // every 6 h
const LOG_SWEEP_INTERVAL_MS   = 24 * 60 * 60 * 1000;      // every 24 h
const MULTIPART_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;  // every 6 h
const MULTIPART_MAX_AGE_MS = 48 * 60 * 60 * 1000;         // 48 h

// ── Nonce sweep ───────────────────────────────────────────────────────────────

async function sweepExpiredNonces() {
  try {
    const { error, count } = await adminSupabase
      .from("request_nonces")
      .delete({ count: "exact" })
      .lt("expires_at", new Date().toISOString());

    if (error) throw error;
    if (count > 0) {
      logInfo("retention.nonces", { deleted: count });
    }
  } catch (err) {
    await logError({ error: { message: err.message, name: err.name }, event: "retention.nonces.failed" });
  }
}

// ── Log sweep ─────────────────────────────────────────────────────────────────

async function sweepOldLogs() {
  const cutoff = new Date(Date.now() - LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const tables = ["logs_security_events", "logs_api_access", "logs_api_errors"];

  for (const table of tables) {
    try {
      const { error, count } = await adminSupabase
        .from(table)
        .delete({ count: "exact" })
        .lt("created_at", cutoff);

      if (error) throw error;
      if (count > 0) {
        logInfo("retention.logs", { table, deleted: count });
      }
    } catch (err) {
      await logError({ error: { message: err.message, name: err.name }, event: "retention.logs.failed", table });
    }
  }
}

// ── R2 multipart sweep ────────────────────────────────────────────────────────

function buildR2Client() {
  if (
    !env.r2AccessKeyId ||
    !env.r2SecretAccessKey ||
    !env.r2Endpoint ||
    !env.r2BucketName
  ) {
    return null;
  }
  return new S3Client({
    region: "auto",
    endpoint: env.r2Endpoint,
    credentials: {
      accessKeyId: env.r2AccessKeyId,
      secretAccessKey: env.r2SecretAccessKey,
    },
  });
}

async function sweepStalMultipartUploads() {
  const client = buildR2Client();
  if (!client) return; // R2 not configured — skip silently

  try {
    const list = await client.send(
      new ListMultipartUploadsCommand({ Bucket: env.r2BucketName })
    );

    const uploads = list.Uploads ?? [];
    const cutoff = Date.now() - MULTIPART_MAX_AGE_MS;
    let aborted = 0;

    for (const upload of uploads) {
      const initiated = upload.Initiated ? new Date(upload.Initiated).getTime() : 0;
      if (initiated < cutoff) {
        await client.send(
          new AbortMultipartUploadCommand({
            Bucket: env.r2BucketName,
            Key: upload.Key,
            UploadId: upload.UploadId,
          })
        );
        aborted++;
      }
    }

    if (aborted > 0) {
      logInfo("retention.r2_multipart", { aborted });
    }
  } catch (err) {
    await logError({ error: { message: err.message, name: err.name }, event: "retention.r2_multipart.failed" });
  }
}

// ── Startup ───────────────────────────────────────────────────────────────────

function startRetentionJobs() {
  // Run immediately on startup, then on schedule
  sweepExpiredNonces();
  sweepOldLogs();
  sweepStalMultipartUploads();

  setInterval(sweepExpiredNonces, NONCE_SWEEP_INTERVAL_MS);
  setInterval(sweepOldLogs, LOG_SWEEP_INTERVAL_MS);
  setInterval(sweepStalMultipartUploads, MULTIPART_SWEEP_INTERVAL_MS);

  logInfo("retention.started", {
    logRetentionDays: LOG_RETENTION_DAYS,
    nonceSweepIntervalH: NONCE_SWEEP_INTERVAL_MS / 3_600_000,
    r2MultipartMaxAgeH: MULTIPART_MAX_AGE_MS / 3_600_000,
  });
}

module.exports = { startRetentionJobs };

/**
 * retentionService.js
 *
 * Runs scheduled cleanup jobs to enforce data-retention policies:
 *   - security_events, api_access_logs, api_error_logs → delete after LOG_RETENTION_DAYS
 *   - request_nonces → delete rows past their expires_at (default: daily sweep)
 *   - R2 incomplete multipart uploads → abort after MULTIPART_MAX_AGE_MS (default 48 h)
 *   - R2 orphaned finalized objects → delete after ORPHAN_MAX_AGE_MS (default 24 h)
 *
 * Call `startRetentionJobs()` once at server startup.
 */

const {
  S3Client,
  ListMultipartUploadsCommand,
  AbortMultipartUploadCommand,
} = require("@aws-sdk/client-s3");
const {
  adminSupabase,
  env,
  listObjects,
  deleteObjects,
  logError,
  logInfo,
} = require("../../all_imports");

// ── Constants ────────────────────────────────────────────────────────────────

const LOG_RETENTION_DAYS = env.logRetentionDays;
const NONCE_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;      // every 6 h
const LOG_SWEEP_INTERVAL_MS   = 24 * 60 * 60 * 1000;      // every 24 h
const MULTIPART_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;  // every 6 h
const MULTIPART_MAX_AGE_MS = 48 * 60 * 60 * 1000;         // 48 h
const ORPHAN_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;      // every 6 h
const ORPHAN_MAX_AGE_MS = 24 * 60 * 60 * 1000;            // 24 h default N-days cutoff

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

// ── R2 orphaned-object sweep ─────────────────────────────────────────────────

async function fetchReferencedKeys() {
  const referenced = new Set();

  const drive = await adminSupabase
    .from("drive_items")
    .select("filename, metadata")
    .not("filename", "is", null);

  if (drive.error) throw drive.error;

  for (const row of drive.data || []) {
    if (row.filename) referenced.add(row.filename);
    const thumb = row.metadata?.thumbnail ?? row.metadata?.["thumbnail"];
    if (typeof thumb === "string" && thumb) referenced.add(thumb);
  }

  const profile = await adminSupabase
    .from("user_profiles")
    .select("profile_pic_url")
    .not("profile_pic_url", "is", null);

  if (profile.error) throw profile.error;

  for (const row of profile.data || []) {
    if (row.profile_pic_url) referenced.add(row.profile_pic_url);
  }

  return referenced;
}

async function sweepStaleOrphanObjects() {
  const client = buildR2Client();
  if (!client) return; // R2 not configured — skip silently

  try {
    const referenced = await fetchReferencedKeys();
    const cutoff = Date.now() - ORPHAN_MAX_AGE_MS;
    const orphans = [];
    const prefixes = ["uploads/", "profile/"];

    for (const prefix of prefixes) {
      const objects = await listObjects(prefix);
      for (const object of objects) {
        const age = object.lastModified ?? Date.now();
        if (!referenced.has(object.key) && age < cutoff) {
          orphans.push(object.key);
        }
      }
    }

    if (orphans.length > 0) {
      await deleteObjects(orphans);
      logInfo("retention.r2_orphans", { deleted: orphans.length });
    }
  } catch (err) {
    await logError({ error: { message: err.message, name: err.name }, event: "retention.r2_orphans.failed" });
  }
}

// ── Startup ───────────────────────────────────────────────────────────────────

function startRetentionJobs() {
  // Run immediately on startup, then on schedule
  sweepExpiredNonces();
  sweepOldLogs();
  sweepStalMultipartUploads();
  sweepStaleOrphanObjects();

  setInterval(sweepExpiredNonces, NONCE_SWEEP_INTERVAL_MS);
  setInterval(sweepOldLogs, LOG_SWEEP_INTERVAL_MS);
  setInterval(sweepStalMultipartUploads, MULTIPART_SWEEP_INTERVAL_MS);
  setInterval(sweepStaleOrphanObjects, ORPHAN_SWEEP_INTERVAL_MS);

  logInfo("retention.started", {
    logRetentionDays: LOG_RETENTION_DAYS,
    nonceSweepIntervalH: NONCE_SWEEP_INTERVAL_MS / 3_600_000,
    r2MultipartMaxAgeH: MULTIPART_MAX_AGE_MS / 3_600_000,
    r2OrphanMaxAgeH: ORPHAN_MAX_AGE_MS / 3_600_000,
  });
}

module.exports = { startRetentionJobs };

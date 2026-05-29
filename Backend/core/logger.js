// =============================================================================
// logger.js — Centralized structured logger for JustUs backend
// Routes log entries to the correct Supabase table based on type.
// Automatically sanitizes sensitive fields in production.
// =============================================================================

const { adminSupabase } = require("../all_imports");

const IS_PROD = process.env.NODE_ENV === "production";
const LOG_TO_DB = process.env.SUPABASE_LOG_TO_DB === "true";

// Fields that must never be persisted
const SENSITIVE_KEYS = new Set([
  "password", "token", "access_token", "refresh_token", "secret",
  "authorization", "cookie", "x-request-signature",
]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Recursively remove sensitive keys from a plain object */
function sanitizePayload(obj, depth = 0) {
  if (!obj || typeof obj !== "object" || depth > 4) return obj;
  if (Array.isArray(obj)) return obj.map((v) => sanitizePayload(v, depth + 1));

  const result = {};
  for (const [key, value] of Object.entries(obj)) {
    if (SENSITIVE_KEYS.has(key.toLowerCase())) {
      result[key] = "[REDACTED]";
    } else {
      result[key] = sanitizePayload(value, depth + 1);
    }
  }
  return result;
}

/** Serialize an error for logging — stack is stripped in production */
function serializeError(error) {
  if (!error) return undefined;
  return {
    message: error.message,
    name: error.name,
    code: error.code ?? undefined,
    stack: IS_PROD ? undefined : error.stack,
  };
}

/** Write a structured JSON line to stdout/stderr */
function write(level, event, payload = {}) {
  const entry = {
    ts: new Date().toISOString(),
    level,
    event,
    ...payload,
  };

  const line = JSON.stringify(entry);
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
}

/** Persist a record to a Supabase table; fails silently */
async function persistLog(table, record) {
  try {
    const { error } = await adminSupabase.from(table).insert(record);
    if (error) {
      write("error", "log.persist_failed", { table, error: serializeError(error) });
    }
  } catch (err) {
    write("error", "log.persist_exception", { table, error: serializeError(err) });
  }
}

// ---------------------------------------------------------------------------
// Public logging functions
// ---------------------------------------------------------------------------

/**
 * Log an API access event → api_access_logs
 * @param {object} record
 * @param {string}  record.request_id
 * @param {string}  record.method
 * @param {string}  record.path
 * @param {number}  record.status_code
 * @param {string}  [record.user_id]
 * @param {string}  [record.ip_address]
 * @param {number}  [record.duration_ms]
 */
async function logAccess(record) {
  write("info", "api.access", record);
  if (LOG_TO_DB) {
    await persistLog("logs_api_access", record);
  }
}

/**
 * Log an API error event → api_error_logs
 * @param {object} record
 * @param {string}  record.request_id
 * @param {string}  record.path
 * @param {string}  record.method
 * @param {string}  [record.user_id]
 * @param {string}  [record.ip_address]
 * @param {string}  record.error_code      — e.g. "AUTH-FAIL-001"
 * @param {string}  record.error_message
 * @param {string}  record.severity        — LOW | MEDIUM | HIGH | CRITICAL
 * @param {object}  [record.error]         — serialized error object
 * @param {object}  [record.payload]       — sanitized request body
 */
async function logError(record) {
  write("error", "api.error", record);
  if (LOG_TO_DB) {
    await persistLog("logs_api_errors", record);
  }
}

/**
 * Log a security event → logs_security_events
 * @param {object} record
 * @param {string}  record.request_id
 * @param {string}  record.type
 * @param {string}  record.path
 * @param {string}  [record.user_id]
 * @param {string}  [record.ip_address]
 * @param {string}  [record.severity]
 */
async function logSecurity(record) {
  write("warn", "security.event", record);
  if (LOG_TO_DB) {
    await persistLog("logs_security_events", record);
  }
}

/**
 * Log an authentication failure → logs_auth_failures
 * @param {object} record
 * @param {string}  record.request_id
 * @param {string}  record.path
 * @param {string}  [record.email]
 * @param {string}  [record.ip_address]
 * @param {string}  [record.reason]
 * @param {string}  [record.error_code]
 */
async function logAuthFailure(record) {
  write("warn", "auth.failure", record);
  if (LOG_TO_DB) {
    await persistLog("logs_auth_failures", record);
  }
}

/**
 * Log a notification event → logs_notifications
 * @param {object} record
 * @param {string}  [record.user_id]
 * @param {string}  [record.type]
 * @param {string}  [record.status]
 */
async function logNotification(record) {
  write("info", "notification.event", record);
  if (LOG_TO_DB) {
    await persistLog("logs_notifications", record);
  }
}

/**
 * Log a generic info event to stdout (structured JSON).
 * Use this instead of raw console.log(JSON.stringify(...)) in services.
 * Does NOT persist to the database — info events are console-only.
 *
 * @param {string} event - Event name (e.g. "retention.nonces")
 * @param {object} [payload] - Additional key/value pairs to include.
 */
function logInfo(event, payload = {}) {
  write("info", event, payload);
}

/**
 * Master log dispatcher:
 * Automatically routes to the right table based on error code prefix.
 *
 * @param {object} opts
 * @param {string}  opts.code         — e.g. "AUTH-FAIL-001"
 * @param {string}  opts.message
 * @param {string}  [opts.user_id]
 * @param {string}  [opts.endpoint]
 * @param {object}  [opts.payload]    — request body (will be sanitized)
 * @param {string}  [opts.stack]
 * @param {string}  [opts.severity]   — LOW | MEDIUM | HIGH | CRITICAL
 * @param {string}  [opts.request_id]
 * @param {string}  [opts.ip_address]
 */
async function logAppError(opts) {
  const base = buildBaseLogRecord(opts);
  const area = opts.code?.split("_")[0] ?? ""; // Note: changed from '-' to '_' to match AppError codes

  await routeLogByArea(area, base, opts.payload);
}

/**
 * Costruisce il record di log base con i campi comuni.
 * @param {object} opts - Opzioni di log.
 * @returns {object} Il record di log base.
 */
function buildBaseLogRecord(opts) {
  return {
    request_id: opts.request_id || null,
    error_code: opts.code,
    error_message: opts.message,
    user_id: opts.user_id || null,
    endpoint: opts.endpoint || null,
    severity: opts.severity || "LOW",
    ip_address: opts.ip_address || null,
    payload: opts.payload ? sanitizePayload(opts.payload) : null,
    stack: opts.stack || null,
  };
}

/**
 * Instrada il log alla funzione specifica in base all'area dell'errore.
 * @param {string} area - L'area dell'errore (es. AUTH, SEC).
 * @param {object} base - Il record di log base.
 * @param {object} rawPayload - Il payload originale non sanificato.
 */
async function routeLogByArea(area, base, rawPayload) {
  switch (area) {
    case "AUTH":
      await logAuthFailure({ ...base, email: rawPayload?.email ?? rawPayload?.identifier });
      break;
    case "SEC":
      await logSecurity({ ...base, type: base.error_code });
      break;
    default:
      await logError(base);
  }
}

module.exports = {
  logAccess,
  logError,
  logInfo,
  logSecurity,
  logAuthFailure,
  logNotification,
  logAppError,
  serializeError,
  sanitizePayload,
};

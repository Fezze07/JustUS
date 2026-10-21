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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * The log tables' request_id column is uuid — a non-uuid value rejects the whole row.
 * @param {string} value - The request id to validate.
 * @returns {string|null} The uuid, or null when the value is not one.
 */
function uuidOrNull(value) {
  return typeof value === "string" && UUID_RE.test(value) ? value : null;
}

/**
 * Recursively remove sensitive keys from a plain object.
 * @param {object} obj - The object to sanitize.
 * @param {number} [depth] - The current recursion depth.
 * @returns {object} The sanitized object.
 */
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

/**
 * Serialize an error for logging — stack is stripped in production.
 * @param {Error} error - The error to serialize.
 * @returns {object|undefined} The serialized error, or undefined when there is none.
 */
function serializeError(error) {
  if (!error) return undefined;
  return {
    message: error.message,
    name: error.name,
    code: error.code ?? undefined,
    stack: IS_PROD ? undefined : error.stack,
  };
}

/**
 * Write a structured JSON line to stdout/stderr.
 * @param {string} level - The log level (info, warn, error).
 * @param {string} event - The event name (es. "api.access").
 * @param {object} [payload] - Additional key/value pairs to include.
 */
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

/**
 * Persist a record to a Supabase table; fails silently.
 * @param {string} table - The target table.
 * @param {object} record - The record to insert.
 */
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

/**
 * Resolve the `user_devices` row behind an auth session — the device_id FK of the log tables.
 * @param {string} [sessionId] - The auth session id of the request.
 * @returns {Promise<number|null>} The device row id, or null when unknown.
 */
async function resolveDeviceId(sessionId) {
  if (!LOG_TO_DB || !sessionId) return null;
  try {
    const { data } = await adminSupabase
      .from("user_devices")
      .select("id")
      .eq("session_id", sessionId)
      .limit(1);
    return data?.[0]?.id ?? null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Public logging functions
// ---------------------------------------------------------------------------

/**
 * Log an API access event → logs_api_access.
 * @param {object} record - The event record.
 * @param {string} [record.request_id] - The request id (uuid).
 * @param {string} [record.method] - The HTTP method.
 * @param {string} [record.path] - The request path.
 * @param {number} [record.status_code] - The HTTP response status.
 * @param {number} [record.duration_ms] - The request duration in milliseconds.
 * @param {number} [record.device_id] - The user_devices row of the request.
 */
async function logAccess(record) {
  write("info", "api.access", record);
  if (LOG_TO_DB) {
    const dbRecord = {
      request_id: uuidOrNull(record.request_id),
      method: record.method || null,
      path: record.path || null,
      status_code: record.status_code ?? null,
      duration_ms: record.duration_ms ?? null,
      device_id: record.device_id ?? null,
    };
    await persistLog("logs_api_access", dbRecord);
  }
}

/**
 * Log an API error event → logs_api_errors.
 * @param {object} record - The event record.
 * @param {string} [record.request_id] - The request id (uuid).
 * @param {string} [record.path] - The request path.
 * @param {string} [record.method] - The HTTP method.
 * @param {string} [record.error_code] - The error code (es. "DB-WRITE-001").
 * @param {string} [record.error_message] - The error message.
 * @param {number} [record.user_id] - The profile id of the caller.
 * @param {string} [record.ip_address] - The caller IP.
 * @param {string} [record.severity] - LOW | MEDIUM | HIGH | CRITICAL.
 * @param {object} [record.error] - The serialized error object.
 * @param {object} [record.payload] - The request body (sanitized before it is stored).
 * @param {string} [record.stack] - The error stack.
 * @param {number} [record.device_id] - The user_devices row of the request.
 */
async function logError(record) {
  write("error", "api.error", record);
  if (LOG_TO_DB) {
    const errorPayload = record.payload ? sanitizePayload(record.payload) : null;
    const errorJson = {
      error_code: record.error_code,
      error_message: record.error_message,
      user_id: record.user_id || null,
      ip_address: record.ip_address || null,
      severity: record.severity || null,
      error: record.error || null,
      stack: record.stack || null,
      endpoint: record.path || null,
      payload: errorPayload,
    };
    const dbRecord = {
      request_id: uuidOrNull(record.request_id),
      path: record.path || null,
      method: record.method || null,
      device_id: record.device_id ?? null,
      error_json: errorJson,
    };
    await persistLog("logs_api_errors", dbRecord);
  }
}

/**
 * Log a security event → logs_security_events.
 * @param {object} record - The event record.
 * @param {string} [record.request_id] - The request id (uuid).
 * @param {string} [record.type] - The event type (es. "rate_limit").
 * @param {string} [record.path] - The request path.
 * @param {string} [record.error_code] - The error code (es. "SEC-BLOCK-001").
 * @param {string} [record.error_message] - The error message.
 * @param {number} [record.user_id] - The profile id of the caller.
 * @param {string} [record.ip_address] - The caller IP.
 * @param {string} [record.severity] - LOW | MEDIUM | HIGH | CRITICAL.
 * @param {object} [record.payload] - The request body (sanitized before it is stored).
 * @param {string} [record.stack] - The error stack.
 * @param {number} [record.retry_after_seconds] - The seconds to wait before a retry.
 * @param {number} [record.strike_level] - The strike level of the caller.
 * @param {number} [record.device_id] - The user_devices row of the request.
 */
async function logSecurity(record) {
  write("warn", "security.event", record);
  if (LOG_TO_DB) {
    const errorJson = {
      error_code: record.error_code,
      error_message: record.error_message,
      user_id: record.user_id || null,
      ip_address: record.ip_address || null,
      severity: record.severity || null,
      type: record.type || record.error_code || null,
      payload: record.payload ? sanitizePayload(record.payload) : null,
      stack: record.stack || null,
      endpoint: record.path || null,
      retry_after_seconds: record.retry_after_seconds ?? null,
      strike_level: record.strike_level ?? null,
    };
    const dbRecord = {
      request_id: uuidOrNull(record.request_id),
      type: record.type || record.error_code || "security.event",
      path: record.path || null,
      device_id: record.device_id ?? null,
      error_json: errorJson,
    };
    await persistLog("logs_security_events", dbRecord);
  }
}

/**
 * Log an authentication failure → logs_auth_failures.
 * @param {object} record - The event record.
 * @param {string} [record.request_id] - The request id.
 * @param {string} [record.error_code] - The error code (es. "AUTH-FAIL-001").
 * @param {string} [record.error_message] - The error message.
 * @param {string} [record.path] - The request path.
 * @param {number} [record.user_id] - The profile id of the caller.
 * @param {string} [record.ip_address] - The caller IP.
 * @param {string} [record.reason] - The failure reason.
 * @param {string} [record.severity] - LOW | MEDIUM | HIGH | CRITICAL.
 * @param {object} [record.payload] - The request body (sanitized before it is stored).
 * @param {string} [record.email] - The email of the caller, used when there is no payload.
 * @param {string} [record.stack] - The error stack.
 */
async function logAuthFailure(record) {
  write("warn", "auth.failure", record);
  if (LOG_TO_DB) {
    const dbRecord = {
      request_id: record.request_id || null,
      error_code: record.error_code || "AUTH-FAIL-001",
      error_message: record.error_message || record.reason || null,
      path: record.path || null,
      user_id: record.user_id || null,
      ip_address: record.ip_address || null,
      reason: record.reason || null,
      severity: record.severity || "HIGH",
      payload: record.payload ? sanitizePayload(record.payload) : (record.email ? { email: record.email } : null),
      stack: record.stack || null,
    };
    await persistLog("logs_auth_failures", dbRecord);
  }
}

/**
 * Log a notification event → logs_notifications.
 * @param {object} record - The event record.
 * @param {number} [record.user_id] - The profile id of the receiver.
 * @param {string} [record.type] - The notification type.
 * @param {string} [record.status] - The delivery status.
 */
async function logNotification(record) {
  write("info", "notification.event", record);
  if (LOG_TO_DB) {
    const dbRecord = {
      user_id: record.user_id ?? null,
      type: record.type ? String(record.type).slice(0, 50) : null,
      status: record.status || null,
    };
    await persistLog("logs_notifications", dbRecord);
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
 * @param {object} opts - The log options.
 * @param {string} opts.code - The error code (es. "AUTH-FAIL-001").
 * @param {string} opts.message - The error message.
 * @param {string} [opts.user_id] - The profile id of the caller.
 * @param {string} [opts.method] - The HTTP method.
 * @param {string} [opts.path] - The request path.
 * @param {number} [opts.device_id] - The user_devices row of the request.
 * @param {object} [opts.payload] - The request body (sanitized before it is stored).
 * @param {string} [opts.stack] - The error stack.
 * @param {string} [opts.severity] - LOW | MEDIUM | HIGH | CRITICAL.
 * @param {string} [opts.request_id] - The request id (uuid).
 * @param {string} [opts.ip_address] - The caller IP.
 */
async function logAppError(opts) {
  const base = buildBaseLogRecord(opts);
  const area = opts.code?.split("-")[0] ?? "";

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
    method: opts.method || null,
    path: opts.path || null,
    severity: opts.severity || "LOW",
    ip_address: opts.ip_address || null,
    device_id: opts.device_id ?? null,
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
      await logAuthFailure({
        ...base,
        email: rawPayload?.email ?? rawPayload?.identifier,
        payload: rawPayload,
      });
      break;
    case "SEC":
      await logSecurity({
        ...base,
        type: base.error_code,
        payload: rawPayload,
      });
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
  resolveDeviceId,
  serializeError,
  sanitizePayload,
};

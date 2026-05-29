// =============================================================================
// AppError — Centralized error class for JustUs backend
// Error code format: <AREA>-<TYPE>-<ID>
//   Areas: AUTH, DB, API, SEC, SYS
//   Types: FAIL, VALIDATION, TIMEOUT, NOT_FOUND, PERMISSION
// =============================================================================

const ERROR_CODES = {
  // AUTH
  AUTH_FAIL_001: { code: "AUTH-FAIL-001", status: 401, message: "Invalid or expired token" },
  AUTH_FAIL_002: { code: "AUTH-FAIL-002", status: 401, message: "Missing bearer token" },
  AUTH_FAIL_003: { code: "AUTH-FAIL-003", status: 401, message: "Session revoked" },
  AUTH_FAIL_004: { code: "AUTH-FAIL-004", status: 403, message: "Invalid role" },
  AUTH_FAIL_005: { code: "AUTH-FAIL-005", status: 403, message: "User profile or role not provisioned" },
  AUTH_FAIL_006: { code: "AUTH-FAIL-006", status: 401, message: "Device binding mismatch" },
  AUTH_PERMISSION_001: { code: "AUTH-PERMISSION-001", status: 403, message: "Missing required capability" },

  // DB
  DB_READ_001: { code: "DB-READ-001", status: 500, message: "Database read error" },
  DB_WRITE_001: { code: "DB-WRITE-001", status: 500, message: "Database write error" },
  DB_NOT_FOUND_001: { code: "DB-NOT_FOUND-001", status: 404, message: "Resource not found" },
  DB_TIMEOUT_001: { code: "DB-TIMEOUT-001", status: 503, message: "Database operation timed out" },

  // API
  API_VALIDATION_001: { code: "API-VALIDATION-001", status: 400, message: "Request validation failed" },
  API_NOT_FOUND_001: { code: "API-NOT_FOUND-001", status: 404, message: "Endpoint not found" },
  API_TIMEOUT_001: { code: "API-TIMEOUT-001", status: 504, message: "Request timed out" },
  API_FAIL_001: { code: "API-FAIL-001", status: 500, message: "Unexpected API error" },

  // SEC
  SEC_AUTH_001: { code: "SEC-AUTH-001", status: 403, message: "Security authorization failed" },
  SEC_AUTH_002: { code: "SEC-AUTH-002", status: 401, message: "Security binding failed" },
  SEC_BLOCK_001: { code: "SEC-BLOCK-001", status: 429, message: "Too many requests — access blocked" },
  SEC_BLOCK_002: { code: "SEC-BLOCK-002", status: 429, message: "Login temporarily blocked" },
  SEC_PERMISSION_001: { code: "SEC-PERMISSION-001", status: 403, message: "Origin not allowed" },

  // SYS
  SYS_FAIL_001: { code: "SYS-FAIL-001", status: 500, message: "Internal server error" },
  SYS_TIMEOUT_001: { code: "SYS-TIMEOUT-001", status: 504, message: "Internal operation timed out" },
  SYS_INTERNAL_001: { code: "SYS-INTERNAL-001", status: 500, message: "Internal logic error" },
};

/**
 * Centralized application error class.
 * @param {object} opts
 * @param {string}  opts.errorKey  - Key from ERROR_CODES (e.g. "AUTH_FAIL_001")
 * @param {string}  [opts.message] - Override the default message
 * @param {object}  [opts.details] - Extra details (sanitized in production)
 * @param {Error}   [opts.cause]   - Original error for stack chaining
 */
class AppError extends Error {
  constructor({ errorKey, message, details, cause } = {}) {
    const def = ERROR_CODES[errorKey] ?? ERROR_CODES.SYS_FAIL_001;

    super(message ?? def.message);

    this.name = "AppError";
    this.code = def.code;
    this.status = def.status;
    this.details = details ?? null;
    this.cause = cause ?? null;

    // Severity derived from status range
    this.severity = AppError.severityFor(def.status);

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, AppError);
    }
  }

  /** Maps HTTP status to a severity label */
  static severityFor(status) {
    if (status >= 500) return "HIGH";
    if (status === 429) return "MEDIUM";
    if (status >= 400) return "LOW";
    return "LOW";
  }

  /**
   * Create an AppError from an unknown caught value.
   * Preserves the original stack if available.
   */
  static from(err, errorKey = "SYS_FAIL_001", details = null) {
    if (err instanceof AppError) return err;
    return new AppError({
      errorKey,
      message: err?.message,
      details,
      cause: err,
    });
  }

  /** Expose error code constants for use in other modules */
  static CODES = ERROR_CODES;
}

module.exports = { AppError, ERROR_CODES };

// =============================================================================
// errorHandler.js — Global Express error handler middleware
//
// Response format (always):
//   { success: false, error: { code, message } }
//
// With ENABLE_ERROR_DETAILS=true also adds:
//   error.details — extra context
//   error.stack   — stack trace
// =============================================================================

const { AppError, logAppError, sanitizePayload } = require("../all_imports");

const ENABLE_ERROR_DETAILS = process.env.ENABLE_ERROR_DETAILS === "true";

async function errorHandler(err, req, res, _next) {
  let appError;
  if (err instanceof AppError) {
    appError = err;
  } else {
    let errorKey = "SYS_FAIL_001";
    if (err.name === "TimeoutError" || err.message?.toLowerCase().includes("timeout")) {
      errorKey = "SYS_TIMEOUT_001";
    }
    appError = AppError.from(err, errorKey);
  }

  await recordErrorLog(appError, req);

  if (res.headersSent) return;

  const body = buildErrorResponse(appError, req.requestId);
  res.status(appError.status).json(body);
}

/**
 * Registra l'errore nel sistema di logging.
 * @param {AppError} appError - L'errore formattato.
 * @param {import('express').Request} req - La richiesta Express.
 */
async function recordErrorLog(appError, req) {
  await logAppError({
    request_id: req.requestId ?? null,
    code: appError.code,
    message: appError.message,
    user_id: req.user?.profileId ?? null,
    method: req.method,
    path: req.originalUrl,
    device_id: req.deviceId ?? null,
    payload: ENABLE_ERROR_DETAILS ? sanitizePayload(req.body) : undefined,
    stack: ENABLE_ERROR_DETAILS ? appError.stack : undefined,
    severity: appError.severity,
    ip_address: req.ip ?? null,
  });
}

/**
 * Costruisce il corpo della risposta di errore in base a ENABLE_ERROR_DETAILS.
 * @param {AppError} appError - L'errore formattato.
 * @param {string} requestId - L'ID della richiesta per correlazione.
 * @returns {object} Il corpo della risposta JSON.
 */
function buildErrorResponse(appError, requestId) {
  const genericMessage = Object.values(AppError.CODES).find(c => c.code === appError.code)?.message
    || AppError.CODES.SYS_FAIL_001.message;

  const errorBody = {
    code: appError.code,
    message: ENABLE_ERROR_DETAILS ? appError.message : genericMessage,
  };

  if (ENABLE_ERROR_DETAILS) {
    if (appError.details) errorBody.details = appError.details;
    if (appError.stack) errorBody.stack = appError.stack;
  }

  return {
    success: false,
    request_id: requestId ?? null,
    error: errorBody,
  };
}

module.exports = errorHandler;

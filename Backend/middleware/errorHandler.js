// =============================================================================
// errorHandler.js — Global Express error handler middleware
//
// Response format (always):
//   { success: false, error: { code, message } }
//
// In DEBUG also adds:
//   error.details — extra context
//   error.stack   — stack trace
// =============================================================================

const { AppError, logAppError, sanitizePayload } = require("../all_imports");

const IS_PROD = process.env.NODE_ENV === "production";

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
    endpoint: `${req.method} ${req.originalUrl}`,
    payload: IS_PROD ? undefined : sanitizePayload(req.body),
    stack: appError.stack,
    severity: appError.severity,
    ip_address: req.ip ?? null,
  });
}

/**
 * Costruisce il corpo della risposta di errore in base all'ambiente (prod/dev).
 * @param {AppError} appError - L'errore formattato.
 * @param {string} requestId - L'ID della richiesta per correlazione.
 * @returns {object} Il corpo della risposta JSON.
 */
function buildErrorResponse(appError, requestId) {
  const genericMessage = Object.values(AppError.CODES).find(c => c.code === appError.code)?.message
    || AppError.CODES.SYS_FAIL_001.message;

  const errorBody = {
    code: appError.code,
    message: IS_PROD ? genericMessage : appError.message,
  };

  // In debug mode expose extra detail
  if (!IS_PROD) {
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

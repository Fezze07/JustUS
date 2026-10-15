// =============================================================================
// dbUtils.js — Centralized Supabase result unwrapping helpers
//
// Converts raw Supabase/PostgrestError objects into typed AppError instances
// so all DB failures surface through the unified error pipeline.
//
// Usage:
//   const { data, error } = await adminSupabase.from('...').select(...)
//   const row = assertDbSuccess({ data, error });          // throws on error
//
//   const { data, error } = await adminSupabase.rpc('...')
//   const result = wrapRpc({ data, error });               // throws AppError; the
//      // code comes from the RAISE (see rpcErrorKey), else API_VALIDATION_001.
// =============================================================================

const { AppError, ERROR_CODES } = require("../../all_imports");

/** Reverse catalog: an app error code resolves to its key. */
const CODE_TO_KEY = Object.fromEntries(
  Object.entries(ERROR_CODES).map(([key, def]) => [def.code, key])
);

/**
 * Reads the code out of a database raise.
 *
 * The RPC functions raise `'<CODE>: <developer text>'` so the code travels on
 * the Postgres message and the prose stays a developer-facing note. Returns
 * null when the message carries no code from the catalog, so callers keep the
 * generic fallback.
 */
function rpcErrorKey(message) {
  const code = String(message ?? "").split(":")[0].trim();
  return CODE_TO_KEY[code] ?? null;
}

/**
 * Asserts that a Supabase query succeeded and returns the data.
 * Throws an AppError if the query returned an error or null data when required.
 *
 * @param {{ data: any, error: any }} result - Destructured Supabase response.
 * @param {string} [errorKey="DB_READ_001"] - AppError key to throw on failure.
 * @param {string} [message] - Optional override message.
 * @returns {any} The data from the Supabase response.
 * @throws {AppError}
 */
function assertDbSuccess({ data, error }, errorKey = "DB_READ_001", message) {
  if (error) {
    throw new AppError({
      errorKey,
      message: message ?? error.message,
      cause: error,
    });
  }
  return data;
}

/**
 * Wraps a Supabase RPC call result, throwing an AppError if the RPC returned
 * an error. A raise carrying an app error code (see [rpcErrorKey]) keeps that
 * code so the client can localize it; anything else falls back to
 * API_VALIDATION_001 with the raw database message.
 *
 * @param {{ data: any, error: any }} result - Destructured Supabase RPC response.
 * @returns {any} The data from the RPC response.
 * @throws {AppError}
 */
function wrapRpc({ data, error }) {
  if (error) {
    const raw = String(error?.message ?? "");
    const errorKey = rpcErrorKey(raw);

    if (errorKey) {
      // Strip the code prefix: the message stays the developer-facing note.
      const sep = raw.indexOf(":");
      const message = (sep === -1 ? "" : raw.slice(sep + 1)).trim();
      throw new AppError({
        errorKey,
        message: message || undefined,
        cause: error,
      });
    }

    throw new AppError({
      errorKey: "API_VALIDATION_001",
      message: raw,
      cause: error,
    });
  }
  return data;
}

module.exports = { assertDbSuccess, wrapRpc };

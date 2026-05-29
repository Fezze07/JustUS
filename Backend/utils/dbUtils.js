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
//   const result = wrapRpc({ data, error });               // throws API_VALIDATION_001
// =============================================================================

const { AppError } = require("../all_imports");

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
 * Wraps a Supabase RPC call result, throwing API_VALIDATION_001 if the RPC
 * returned an error. This matches the pattern used for proxy-style RPCs where
 * the error message comes from the database function itself.
 *
 * @param {{ data: any, error: any }} result - Destructured Supabase RPC response.
 * @returns {any} The data from the RPC response.
 * @throws {AppError}
 */
function wrapRpc({ data, error }) {
  if (error) {
    throw new AppError({
      errorKey: "API_VALIDATION_001",
      message: error.message,
      cause: error,
    });
  }
  return data;
}

module.exports = { assertDbSuccess, wrapRpc };

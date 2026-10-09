// =============================================================================
// rateLimitKeys.js — Shared key extractors for createCompositeRateLimit
//
// Eliminates repeated inline arrow functions across route files.
//
// Usage:
//   const { ipKey, userKey, DEFAULT_WINDOW_MS } = require('../utils/rateLimitKeys');
//   createCompositeRateLimit({
//     name: 'my-route',
//     rules: [
//       { name: 'ip',   windowMs: DEFAULT_WINDOW_MS, max: 30, key: ipKey },
//       { name: 'user', windowMs: DEFAULT_WINDOW_MS, max: 10, key: userKey },
//     ],
//   });
// =============================================================================

/** Standard sliding window: 1 minute */
const DEFAULT_WINDOW_MS = 60_000;

/**
 * Rate-limit key by client IP address.
 * Falls back to undefined (rule is skipped) when IP is missing.
 * @param {import('express').Request} req
 * @returns {string | undefined}
 */
const ipKey = (req) => req.ip;

/**
 * Rate-limit key by authenticated user's profile ID.
 * Falls back to undefined (rule is skipped) when the user is not authenticated.
 * @param {import('express').Request} req
 * @returns {number | undefined}
 */
const userKey = (req) => req.user?.profileId;

/**
 * Rate-limit key by device fingerprint (from request body).
 * Useful for unauthenticated endpoints such as login-risk checks.
 * @param {import('express').Request} req
 * @returns {string | undefined}
 */
const deviceKey = (req) => req.body?.deviceFingerprint;

/**
 * Distinct-value extractor by email (from request body), lowercased and trimmed.
 * Set as a rule's `distinctValue` so `createCompositeRateLimit` caps how many
 * different emails one key (typically an IP) may present per window, instead of
 * counting every request — bounding enumeration and per-key map growth.
 * @param {import('express').Request} req
 * @returns {string | undefined}
 */
const emailValue = (req) => {
  const raw = req.body?.email;
  if (typeof raw !== "string") return undefined;
  const normalized = raw.trim().toLowerCase();
  return normalized || undefined;
};

module.exports = { DEFAULT_WINDOW_MS, ipKey, userKey, deviceKey, emailValue };

const { logSecurity, AppError } = require("../all_imports");

const buckets = new Map();
const penalties = new Map();

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function applyPenalty(name, key) {
  const penaltyKey = `${name}:${key}`;
  const current = penalties.get(penaltyKey) ?? {
    strikes: 0,
    bannedUntil: 0,
  };

  current.strikes += 1;

  if (current.strikes >= 4) {
    current.bannedUntil = Date.now() + 15 * 60_000;
  }

  penalties.set(penaltyKey, current);
  return current;
}

/**
 * Crea un middleware di rate limiting composito che applica diverse regole in sequenza.
 * @param {object} options - Opzioni di configurazione.
 * @param {string} options.name - Nome del limitatore per il logging.
 * @param {string} options.message - Messaggio di errore personalizzato.
 * @param {array} options.rules - Lista di regole da applicare.
 * @returns {import('express').RequestHandler} Middleware di rate limiting.
 */
function createCompositeRateLimit({ name, message, rules }) {
  return async (req, res, next) => {
    const now = Date.now();
    let result = { retryAfterSeconds: 0, penalty: null };

    for (const rule of rules) {
      const ruleResult = evaluateRule(rule, name, now, req);
      if (ruleResult.retryAfterSeconds > result.retryAfterSeconds) {
        result = ruleResult;
      }
    }

    if (result.retryAfterSeconds > 0) {
      return handleRateLimitViolation(req, res, next, result, name, message);
    }

    next();
  };
}

/**
 * Valuta una singola regola di rate limiting per la richiesta attuale.
 * @param {object} rule - La regola da valutare.
 * @param {string} name - Nome del limitatore genitore.
 * @param {number} now - Timestamp attuale.
 * @param {import('express').Request} req - Richiesta Express.
 * @returns {object} Risultato della valutazione (retryAfterSeconds, penalty).
 */
function evaluateRule(rule, name, now, req) {
  const key = rule.key(req);
  if (!key) return { retryAfterSeconds: 0, penalty: null };

  const penaltyKey = `${rule.name}:${key}`;
  const currentPenalty = penalties.get(`${name}:${penaltyKey}`);

  if (currentPenalty?.bannedUntil > now) {
    return {
      retryAfterSeconds: Math.ceil((currentPenalty.bannedUntil - now) / 1000),
      penalty: currentPenalty
    };
  }

  const bucketKey = `${name}:${rule.name}:${key}`;
  const existing = buckets.get(bucketKey);

  if (rule.distinctValue) {
    return evaluateDistinctRule(rule, name, now, req, bucketKey, penaltyKey, existing);
  }

  const state = existing && existing.resetAt > now
    ? existing
    : { count: 0, resetAt: now + rule.windowMs };

  state.count += 1;
  buckets.set(bucketKey, state);

  if (state.count > rule.max) {
    return rateLimitExceeded(state, name, now, penaltyKey);
  }

  return { retryAfterSeconds: 0, penalty: null };
}

/**
 * Distinct-value variant of `evaluateRule`: the bucket counts how many *different*
 * `rule.distinctValue(req)` values (e.g. email addresses) one key (e.g. an IP) has
 * presented inside the window, instead of counting requests. Asking about the same
 * value again is free — a legitimate user retrying one login is never penalised —
 * while a client enumerating many values trips the cap.
 * @param {object} rule - The rule to evaluate (must define `distinctValue`).
 * @param {string} name - The parent limiter name.
 * @param {number} now - Current timestamp.
 * @param {import('express').Request} req - Express request.
 * @param {string} bucketKey - Cache key for this rule/key pair.
 * @param {string} penaltyKey - Strike key shared across the parent limiter.
 * @param {object | undefined} existing - Existing bucket state, if any.
 * @returns {object} Evaluation result (retryAfterSeconds, penalty).
 */
function evaluateDistinctRule(rule, name, now, req, bucketKey, penaltyKey, existing) {
  const value = rule.distinctValue(req);
  if (!value) return { retryAfterSeconds: 0, penalty: null };

  const state = existing && existing.resetAt > now && existing.values
    ? existing
    : { count: 0, values: new Set(), resetAt: now + rule.windowMs };

  state.values.add(value);
  state.count = state.values.size;
  buckets.set(bucketKey, state);

  if (state.count > rule.max) {
    return rateLimitExceeded(state, name, now, penaltyKey);
  }

  return { retryAfterSeconds: 0, penalty: null };
}

/**
 * Shared "limit exceeded" branch: applies the strike penalty to the rule/key pair
 * and returns the retry window. Used by both the request-count and distinct-value
 * evaluators so a single value is the source of truth.
 * @param {object} state - The bucket state that exceeded `rule.max`.
 * @param {string} name - The parent limiter name.
 * @param {number} now - Current timestamp.
 * @param {string} penaltyKey - Strike key shared across the parent limiter.
 * @returns {object} Violation result (retryAfterSeconds, penalty).
 */
function rateLimitExceeded(state, name, now, penaltyKey) {
  const penalty = applyPenalty(name, penaltyKey);
  return {
    retryAfterSeconds: Math.ceil((state.resetAt - now) / 1000),
    penalty
  };
}

/**
 * Gestisce la violazione del limite di velocità (delay, log e risposta di errore).
 * @param {import('express').Request} req - Richiesta Express.
 * @param {import('express').Response} res - Risposta Express.
 * @param {import('express').NextFunction} next - Funzione next di Express.
 * @param {object} result - Risultato della violazione (retryAfterSeconds, penalty).
 * @param {string} name - Nome del limitatore.
 * @param {string} message - Messaggio di errore.
 */
async function handleRateLimitViolation(req, res, next, result, name, message) {
  const { retryAfterSeconds, penalty } = result;

  await applyRateLimitDelay(penalty);
  await logRateLimitEvent(req, retryAfterSeconds, penalty);

  res.set("Retry-After", String(retryAfterSeconds));
  return next(new AppError({
    errorKey: "SEC_BLOCK_001",
    message: message ?? "Too many requests",
    details: { strikeLevel: penalty?.strikes ?? 0 }
  }));
}

async function applyRateLimitDelay(penalty) {
  if (penalty?.strikes === 1) await delay(200);
  if (penalty?.strikes === 2) await delay(1_000);
}

async function logRateLimitEvent(req, retryAfterSeconds, penalty) {
  await logSecurity({
    request_id: req.requestId,
    type: "rate_limit",
    path: req.originalUrl,
    user_id: req.user?.profileId ?? null,
    ip_address: req.ip,
    retry_after_seconds: retryAfterSeconds,
    strike_level: penalty?.strikes ?? 0,
  });
}

// Sweep expired buckets and penalties every 15 minutes to prevent unbounded growth.
function _sweepRateLimitMaps() {
  const now = Date.now();
  for (const [k, v] of buckets) {
    if (v.resetAt <= now) buckets.delete(k);
  }
  for (const [k, v] of penalties) {
    if (v.bannedUntil <= 0 || v.bannedUntil <= now) penalties.delete(k);
  }
}
setInterval(_sweepRateLimitMaps, 15 * 60 * 1000).unref();

// Clears every bucket and penalty. The maps above are module-level, so without
// this the limits leak across Jest tests: a suite that fires N requests leaves
// the next test starting at N, and a suite whose request count happens to sit on
// the limit boundary passes until someone adds one more case. Test-only reset,
// mirroring resetCircuitState/resetQuotaState.
const resetRateLimitState = () => {
  buckets.clear();
  penalties.clear();
};

module.exports = {
  createCompositeRateLimit,
  resetRateLimitState,
};

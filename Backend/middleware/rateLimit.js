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
  const state = existing && existing.resetAt > now
    ? existing
    : { count: 0, resetAt: now + rule.windowMs };

  state.count += 1;
  buckets.set(bucketKey, state);

  if (state.count > rule.max) {
    const penalty = applyPenalty(name, penaltyKey);
    return {
      retryAfterSeconds: Math.ceil((state.resetAt - now) / 1000),
      penalty
    };
  }

  return { retryAfterSeconds: 0, penalty: null };
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

module.exports = {
  createCompositeRateLimit,
};

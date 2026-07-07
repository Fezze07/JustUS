const { AppError } = require("../../all_imports");
const { URL } = require("url");
const { CORS_ALLOWED_HEADERS, CORS_ALLOWED_METHODS } = require("./httpConstants");

/**
 * Configura gli header CORS e gestisce le richieste preflight OPTIONS.
 * @param {import('express').Request} req - L'oggetto della richiesta Express.
 * @param {import('express').Response} res - L'oggetto della risposta Express.
 * @param {import('express').NextFunction} next - La funzione next di Express.
 * @param {string[]} allowedOrigins - Lista delle origini consentite.
 * @returns {void}
 */
function handleCors(req, res, next, allowedOrigins) {
  const origin = req.get("origin");
  if (!origin) {
    return next();
  }

  if (_isOriginAllowed(origin, allowedOrigins)) {
    res.header("Access-Control-Allow-Origin", origin);
    res.header("Vary", "Origin");
    res.header("Access-Control-Allow-Headers", CORS_ALLOWED_HEADERS);
    res.header("Access-Control-Allow-Methods", CORS_ALLOWED_METHODS);

    if (req.method === "OPTIONS") {
      return res.status(204).end();
    }
    return next();
  }

  return next(
    new AppError({ errorKey: "SEC_AUTH_001", message: "Origin not allowed" })
  );
}

/** Verifica se un'origine è consentita, supportando wildcard `://*` e IP privati in dev */
function _isOriginAllowed(origin, allowedOrigins) {
  if (allowedOrigins.length === 0) return true;
  if (allowedOrigins.includes("*")) return true;
  if (allowedOrigins.includes(origin)) return true;

  for (const allowed of allowedOrigins) {
    if (allowed.endsWith("://*")) {
      const prefix = allowed.slice(0, -4);
      if (origin.startsWith(prefix)) return true;
    }
  }

  if (process.env.NODE_ENV === "development" && _isPrivateOrigin(origin)) {
    return true;
  }

  return false;
}

/** Verifica se un'origine è su localhost o IP privato */
function _isPrivateOrigin(origin) {
  try {
    const url = new URL(origin);
    const host = url.hostname;
    if (host === "localhost" || host === "127.0.0.1" || host === "::1") return true;
    return (
      host.startsWith("192.168.")
    );
  } catch (_) {
    return false;
  }
}

module.exports = { handleCors };

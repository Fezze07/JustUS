const { AppError } = require("../../all_imports");
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

  if (allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
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

module.exports = { handleCors };

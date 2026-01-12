const rateLimit = require("express-rate-limit");

// login: molto restrittivo
const loginLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 min
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, code: "E429", msg: "Troppi tentativi di login. Riprova più tardi" }
});

const requestCodeLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 min
  max: 5,
  message: { ok: false, code: "E429", msg: "Troppi tentativi di recupero codice" }
});

const registerLimiter = rateLimit({
  windowMs: 30 * 60 * 1000, // 30 min
  max: 3,
  message: { ok: false, code: "E429", msg: "Troppe registrazioni da questo IP" }
});

module.exports = { loginLimiter, requestCodeLimiter, registerLimiter }; 
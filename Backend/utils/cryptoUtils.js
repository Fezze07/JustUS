const crypto = require("crypto");

/**
 * Genera un hash SHA256 di una stringa.
 * @param {string} value - Il valore da hashare.
 * @returns {string} L'hash in formato hex.
 */
function sha256(value) {
  return crypto.createHash("sha256").update(String(value ?? "")).digest("hex");
}

/**
 * Genera un HMAC SHA256 usando una chiave segreta.
 * @param {string} secret - La chiave segreta.
 * @param {string} message - Il messaggio da firmare.
 * @returns {string} L'HMAC in formato hex.
 */
function hmacSha256(secret, message) {
  return crypto.createHmac("sha256", String(secret ?? "")).update(String(message ?? "")).digest("hex");
}

module.exports = { sha256, hmacSha256 };

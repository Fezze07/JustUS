/**
 * Decodifica i claims (payload) di un token JWT senza verificarne la firma.
 * @param {string} token - Il token JWT da decodificare.
 * @param {object} user - L'oggetto utente di fallback fornito da Supabase.
 * @returns {object} I claims decodificati.
 */
function decodeTokenClaims(token, user) {
  try {
    const payload = token.split(".")[1];
    return JSON.parse(Buffer.from(payload, "base64").toString());
  } catch (_e) {
    // Fallback se la decodifica fallisce, sebbene improbabile per un token verificato
    return {
      sub: user.id,
      email: user.email,
      role: user.aud || "authenticated",
    };
  }
}

/**
 * Valida la durata della vita del token rispetto alla policy di sicurezza.
 * @param {object} claims - I claims del token.
 * @param {number} maxLifetimeSec - La durata massima consentita in secondi.
 * @throws {Error} Se il token supera la durata massima consentita.
 */
function validateTokenLifetime(claims, maxLifetimeSec) {
  const issuedAt = Number(claims.iat ?? 0);
  const expiresAt = Number(claims.exp ?? 0);
  
  if (issuedAt && expiresAt) {
    const tokenLifetime = expiresAt - issuedAt;
    if (tokenLifetime > maxLifetimeSec) {
      throw new Error("Token lifetime exceeds policy");
    }
  }
}

module.exports = { decodeTokenClaims, validateTokenLifetime };

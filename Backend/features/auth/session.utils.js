const { AppError } = require("../../all_imports");

/**
 * Valida i vincoli della sessione (fingerprint, IP, User-Agent).
 * @param {object} sessionBinding - I dati della sessione salvati nel database.
 * @param {object} clientContext - Il contesto del client attuale.
 * @throws {AppError} Se uno dei vincoli di sicurezza non è rispettato.
 */
function validateSessionBinding(sessionBinding, clientContext) {
  checkRevocation(sessionBinding);
  checkDeviceFingerprint(sessionBinding, clientContext);
  checkUserAgent(sessionBinding, clientContext);
}

function checkRevocation(sessionBinding) {
  if (sessionBinding?.revoked_at) {
    throw new AppError({ errorKey: "AUTH_FAIL_003" });
  }
}

function checkDeviceFingerprint(sessionBinding, clientContext) {
  if (
    sessionBinding?.device_fingerprint_hash &&
    clientContext.deviceFingerprint &&
    sessionBinding.device_fingerprint_hash !== clientContext.deviceFingerprintHash
  ) {
    throw new AppError({ errorKey: "AUTH_FAIL_006" });
  }
}

function checkUserAgent(sessionBinding, clientContext) {
  if (
    sessionBinding?.user_agent_hash &&
    clientContext.clientUserAgent &&
    sessionBinding.user_agent_hash !== clientContext.clientUserAgentHash
  ) {
    throw new AppError({ errorKey: "AUTH_FAIL_006", message: "Client binding mismatch. Please login again." });
  }
}

/**
 * Verifica se l'indirizzo IP del client è cambiato rispetto alla sessione registrata.
 * @param {object} sessionBinding - I dati della sessione salvati nel database.
 * @param {object} clientContext - Il contesto del client attuale.
 * @returns {boolean} True se l'IP è cambiato.
 */
function isIpRangeChanged(sessionBinding, clientContext) {
  return (
    sessionBinding?.ip_range &&
    clientContext.ipRange &&
    sessionBinding.ip_range !== clientContext.ipRange
  );
}

module.exports = { validateSessionBinding, isIpRangeChanged };

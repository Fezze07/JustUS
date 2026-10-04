const { AppError } = require("../../all_imports");

/**
 * Valida i vincoli della sessione (fingerprint).
 * @param {object} sessionBinding - I dati della sessione salvati nel database.
 * @param {object} clientContext - Il contesto del client attuale.
 * @throws {AppError} Se uno dei vincoli di sicurezza non è rispettato.
 */
function validateSessionBinding(sessionBinding, clientContext) {
  checkDeviceFingerprint(sessionBinding, clientContext);
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

module.exports = { validateSessionBinding };

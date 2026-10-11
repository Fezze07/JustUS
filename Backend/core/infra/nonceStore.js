const { adminSupabase } = require("../../all_imports");

const consumedNonces = new Map();

function getNonceKey({ namespace, userId, nonce }) {
  return `${namespace}:${userId ?? "anonymous"}:${nonce}`;
}

async function consumeNonce({ namespace, userId, nonce, expiresAt }) {
  const key = getNonceKey({ namespace, userId, nonce });
  const now = Date.now();
  const existing = consumedNonces.get(key);
  if (existing && existing > now) {
    return false;
  }

  try {
    const { error } = await adminSupabase.from("request_nonces").insert({
      nonce,
      namespace,
      user_id: userId ?? null,
      expires_at: new Date(expiresAt).toISOString(),
    });
    if (error && error.code === "23505") {
      return false;
    }
  } catch {
    // DB unreachable: fall back to memory-only protection for this instance.
  }

  consumedNonces.set(key, expiresAt);
  return true;
}

// Sweep expired nonces from memory every 10 minutes to prevent unbounded growth.
function _sweepExpiredNonces() {
  const now = Date.now();
  for (const [key, expiresAt] of consumedNonces) {
    if (expiresAt <= now) consumedNonces.delete(key);
  }
}
setInterval(_sweepExpiredNonces, 10 * 60 * 1000).unref();

module.exports = {
  consumeNonce,
};

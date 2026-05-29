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

  consumedNonces.set(key, expiresAt);

  try {
    await adminSupabase.from("request_nonces").insert({
      nonce,
      namespace,
      user_id: userId ?? null,
      expires_at: new Date(expiresAt).toISOString(),
    });
  } catch (error) {
    const duplicate =
      typeof error?.message === "string" &&
      error.message.toLowerCase().includes("duplicate");
    if (duplicate) {
      return false;
    }
  }

  return true;
}

module.exports = {
  consumeNonce,
};

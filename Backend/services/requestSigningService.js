const crypto = require("crypto");
const { sha256, hmacSha256 } = require("../all_imports");

function generateBindingSecret() {
  return crypto.randomBytes(32).toString("hex");
}

function canonicalizeRequest({ method, path, timestamp, nonce, bodyHash }) {
  return [
    String(method ?? "").toUpperCase(),
    String(path ?? ""),
    String(timestamp ?? ""),
    String(nonce ?? ""),
    String(bodyHash ?? ""),
  ].join(".");
}

function computeBodyHash(payload) {
  if (payload === undefined || payload === null) {
    return sha256("");
  }

  if (typeof payload === "string") {
    return sha256(payload);
  }

  return sha256(JSON.stringify(payload));
}

function signRequest({ secret, method, path, timestamp, nonce, payload }) {
  const bodyHash = computeBodyHash(payload);
  const canonical = canonicalizeRequest({
    method,
    path,
    timestamp,
    nonce,
    bodyHash,
  });

  return {
    bodyHash,
    canonical,
    signature: hmacSha256(secret, canonical),
  };
}

module.exports = {
  generateBindingSecret,
  canonicalizeRequest,
  computeBodyHash,
  signRequest,
};

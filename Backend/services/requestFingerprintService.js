const crypto = require("crypto");

function sha256(value) {
  return crypto.createHash("sha256").update(String(value ?? "")).digest("hex");
}

function hmacSha256(secret, value) {
  return crypto
    .createHmac("sha256", String(secret ?? ""))
    .update(String(value ?? ""))
    .digest("hex");
}

function ipToSoftRange(ipAddress) {
  const value = String(ipAddress ?? "").trim();
  if (!value) {
    return "unknown";
  }

  if (value.includes(":")) {
    return value.split(":").slice(0, 4).join(":");
  }

  const octets = value.split(".");
  if (octets.length !== 4) {
    return value;
  }

  return `${octets[0]}.${octets[1]}.${octets[2]}.0/24`;
}

function buildClientContext(req) {
  const deviceFingerprint = req.get("x-device-fingerprint") || "";
  const clientUserAgent = req.get("x-client-user-agent") || req.get("user-agent") || "";
  const clientUserAgentHash =
    req.get("x-client-user-agent-hash") || sha256(clientUserAgent);
  const acceptLanguage = req.get("accept-language") || "";
  const headerConsistency = sha256(
    [
      req.get("accept") || "",
      req.get("accept-encoding") || "",
      req.get("sec-ch-ua-platform") || "",
      req.get("sec-ch-ua-mobile") || "",
      acceptLanguage,
    ].join("|")
  );

  return {
    deviceFingerprint,
    deviceFingerprintHash: sha256(deviceFingerprint),
    clientUserAgent,
    clientUserAgentHash,
    ipRange: ipToSoftRange(req.ip),
    acceptLanguage,
    headerConsistency,
    behaviorPatternHash: sha256(
      [
        deviceFingerprint,
        clientUserAgentHash,
        ipToSoftRange(req.ip),
        acceptLanguage,
        headerConsistency,
      ].join("|")
    ),
  };
}

module.exports = {
  sha256,
  hmacSha256,
  ipToSoftRange,
  buildClientContext,
};

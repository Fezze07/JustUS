const {
  env,
  consumeNonce,
  signRequest,
  AppError,
} = require("../all_imports");

function requireSignedRequest(namespace) {
  return async (req, res, next) => {
    try {
      const bindingSecret = req.sessionBinding?.bindingSecret;
      if (!bindingSecret) {
        throw new AppError({ errorKey: "SEC_AUTH_002", message: "Session binding required" });
      }

      const headers = extractAndValidateHeaders(req);
      validateTimestamp(headers.timestamp);
      verifySignature(req, headers, bindingSecret);

      const nonceAccepted = await consumeNonce({
        namespace,
        userId: req.user?.profileId,
        nonce: headers.nonce,
        expiresAt: headers.timestamp + env.requestSigningMaxSkewMs,
      });

      if (!nonceAccepted) {
        throw new AppError({ errorKey: "SEC_BLOCK_001", message: "Replay request detected" });
      }

      next();
    } catch (err) {
      next(err);
    }
  };
}

function extractAndValidateHeaders(req) {
  const timestamp = req.get("x-request-timestamp");
  const nonce = req.get("x-request-nonce");
  const signature = req.get("x-request-signature");

  if (!timestamp || !nonce || !signature) {
    throw new AppError({ errorKey: "SEC_AUTH_002", message: "Missing signed request headers" });
  }

  return { timestamp: Number.parseInt(timestamp, 10), nonce, signature };
}

function validateTimestamp(timestamp) {
  if (!Number.isFinite(timestamp)) {
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "Invalid request timestamp" });
  }

  const skewMs = Math.abs(Date.now() - timestamp);
  if (skewMs > env.requestSigningMaxSkewMs) {
    throw new AppError({ errorKey: "SEC_AUTH_002", message: "Signed request expired" });
  }
}

function verifySignature(req, { timestamp, nonce, signature }, secret) {
  const { signature: expectedSignature } = signRequest({
    secret,
    method: req.method,
    path: req.originalUrl.split("?")[0],
    timestamp,
    nonce,
    payload: req.body,
  });

  if (expectedSignature !== signature) {
    throw new AppError({ errorKey: "SEC_AUTH_002", message: "Invalid request signature" });
  }
}

module.exports = requireSignedRequest;

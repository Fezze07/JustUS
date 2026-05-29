const { env, consumeNonce, AppError } = require("../all_imports");

function requireFreshNonce(namespace) {
  return async (req, res, next) => {
    const timestampHeader = req.get("x-request-timestamp");
    const nonce = req.get("x-request-nonce");

    if (!timestampHeader || !nonce) {
      return next(new AppError({ errorKey: "API_VALIDATION_001", message: "Missing nonce headers" }));
    }

    const timestamp = Number.parseInt(timestampHeader, 10);
    if (!Number.isFinite(timestamp)) {
      return next(new AppError({ errorKey: "API_VALIDATION_001", message: "Invalid nonce timestamp" }));
    }

    const skewMs = Math.abs(Date.now() - timestamp);
    if (skewMs > env.requestSigningMaxSkewMs) {
      return next(new AppError({ errorKey: "SEC_AUTH_001", message: "Request timestamp expired" }));
    }

    const accepted = await consumeNonce({
      namespace,
      userId: req.user?.profileId ?? null,
      nonce,
      expiresAt: timestamp + env.requestSigningMaxSkewMs,
    });

    if (!accepted) {
      return next(new AppError({ errorKey: "SEC_BLOCK_001", message: "Duplicate request nonce" }));
    }

    next();
  };
}

module.exports = requireFreshNonce;

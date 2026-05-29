const { getEntry, saveEntry } = require("../all_imports");

function withIdempotency(namespace) {
  return (req, res, next) => {
    const idempotencyKey =
      req.get("Idempotency-Key") || req.get("X-Idempotency-Key");
    if (!idempotencyKey) {
      return next();
    }

    const lookup = {
      namespace,
      key: idempotencyKey,
      userId: req.user?.profileId,
    };
    const cached = getEntry(lookup);
    if (cached) {
      return res.status(cached.statusCode).json(cached.body);
    }

    const originalJson = res.json.bind(res);
    res.json = (body) => {
      saveEntry(lookup, {
        statusCode: res.statusCode,
        body,
      });
      return originalJson(body);
    };

    next();
  };
}

module.exports = withIdempotency;

const { logAccess } = require("../all_imports");

function requestLogger() {
  return (req, res, next) => {
    res.on("finish", () => {
      void logAccess({
        request_id: req.requestId,
        method: req.method,
        path: req.originalUrl,
        status_code: res.statusCode,
        user_id: req.user?.profileId ?? null,
        auth_user_id: req.user?.id ?? null,
        ip_address: req.ip,
        duration_ms: Date.now() - req.startedAt,
        user_agent: req.get("user-agent") ?? null,
      });
    });

    next();
  };
}

module.exports = requestLogger;

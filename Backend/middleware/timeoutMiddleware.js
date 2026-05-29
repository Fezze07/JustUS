const { AppError } = require("../all_imports");

function timeoutMiddleware(timeoutMs) {
  return (req, res, next) => {
    req.setTimeout(timeoutMs);
    res.setTimeout(timeoutMs, () => {
      if (!res.headersSent) {
        next(new AppError({ errorKey: "API_TIMEOUT_001", message: "Request timeout" }));
      }
    });
    next();
  };
}

module.exports = timeoutMiddleware;

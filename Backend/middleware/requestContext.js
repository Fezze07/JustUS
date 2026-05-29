const crypto = require("crypto");

function requestContext(req, _res, next) {
  req.requestId = req.headers["x-request-id"] || crypto.randomUUID();
  req.startedAt = Date.now();
  next();
}

module.exports = requestContext;

const crypto = require("crypto");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function requestContext(req, _res, next) {
  const header = req.headers["x-request-id"];
  // The log tables' request_id column is uuid: a non-uuid header would reject the log row.
  req.requestId = UUID_RE.test(String(header ?? "")) ? header : crypto.randomUUID();
  req.startedAt = Date.now();
  next();
}

module.exports = requestContext;

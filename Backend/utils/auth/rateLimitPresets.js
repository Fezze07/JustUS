const { createCompositeRateLimit, DEFAULT_WINDOW_MS, ipKey, userKey } = require("../../all_imports");

function createIpUserRateLimit({ name, message, ipMax, userMax, windowMs = DEFAULT_WINDOW_MS }) {
  const rules = [
    { name: "ip", windowMs, max: ipMax, key: ipKey },
  ];
  if (userMax != null && userMax > 0) {
    rules.push({ name: "user", windowMs: DEFAULT_WINDOW_MS, max: userMax, key: userKey });
  }
  return createCompositeRateLimit({ name, message, rules });
}

function createIpOnlyRateLimit(opts) {
  return createIpUserRateLimit(opts);
}

module.exports = {
  createIpUserRateLimit,
  createIpOnlyRateLimit,
};

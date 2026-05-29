const responses = new Map();

function buildKey({ namespace, key, userId }) {
  return `${namespace}:${userId ?? "anonymous"}:${key}`;
}

function getEntry(payload) {
  const cacheKey = buildKey(payload);
  const entry = responses.get(cacheKey);
  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) {
    responses.delete(cacheKey);
    return null;
  }
  return entry;
}

function saveEntry(payload, response) {
  const cacheKey = buildKey(payload);
  responses.set(cacheKey, {
    ...response,
    expiresAt: Date.now() + 24 * 60 * 60_000,
  });
}

module.exports = {
  getEntry,
  saveEntry,
};

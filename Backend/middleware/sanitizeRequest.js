function sanitizeValue(value) {
  if (Array.isArray(value)) {
    return value.map(sanitizeValue);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, sanitizeValue(nested)])
    );
  }

  if (typeof value === "string") {
    // eslint-disable-next-line no-control-regex
    return value.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  }

  return value;
}

function sanitizeRequest() {
  return (req, _res, next) => {
    if (req.body) {
      req.body = sanitizeValue(req.body);
    }
    if (req.params) {
      req.params = sanitizeValue(req.params);
    }
    if (req.query) {
      req.query = sanitizeValue(req.query);
    }
    next();
  };
}

module.exports = sanitizeRequest;

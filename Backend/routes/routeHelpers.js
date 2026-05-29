const {
  authenticateToken,
  authorizeCapabilities,
  requireFreshNonce,
  requireSignedRequest,
  validateRequest,
} = require("../all_imports");

function chain(...segments) {
  return segments.flat().filter(Boolean);
}

function authenticated() {
  return [authenticateToken];
}

function capability(requiredCapability) {
  return [authorizeCapabilities(requiredCapability)];
}

function signed(namespace) {
  return [requireSignedRequest(namespace)];
}

function freshNonce(namespace) {
  return [requireFreshNonce(namespace)];
}

function validated(schema) {
  return [validateRequest(schema)];
}

function limited(middleware) {
  return [middleware];
}

module.exports = {
  chain,
  authenticated,
  capability,
  signed,
  freshNonce,
  validated,
  limited,
};

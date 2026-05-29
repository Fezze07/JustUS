const { hasCapability, AppError } = require("../all_imports");

function authorizeCapabilities(...requiredCapabilities) {
  return (req, res, next) => {
    const capabilities = req.user?.capabilities ?? [];
    const missing = requiredCapabilities.filter(
      (capability) => !hasCapability(capabilities, capability)
    );

    if (missing.length > 0) {
      return next(new AppError({
        errorKey: "SEC_AUTH_001",
        message: "Missing capability",
        details: { missing }
      }));
    }

    next();
  };
}

module.exports = authorizeCapabilities;

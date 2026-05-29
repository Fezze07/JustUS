// =============================================================================
// validateRequest.js — Zod schema validation middleware
// Throws AppError(API_VALIDATION_001) on failure instead of inline res.json
// =============================================================================

const { AppError } = require("../all_imports");

function validateRequest({ body, params, query }) {
  return (req, _res, next) => {
    const errors = [];

    if (body) {
      const parsed = body.safeParse(req.body);
      if (!parsed.success) errors.push(...parsed.error.issues);
      else req.body = parsed.data;
    }

    if (params) {
      const parsed = params.safeParse(req.params);
      if (!parsed.success) errors.push(...parsed.error.issues);
      else req.params = parsed.data;
    }

    if (query) {
      const parsed = query.safeParse(req.query);
      if (!parsed.success) errors.push(...parsed.error.issues);
      else req.query = parsed.data;
    }

    if (errors.length > 0) {
      const issues = errors.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      }));

      return next(
        new AppError({
          errorKey: "API_VALIDATION_001",
          details: { issues },
        })
      );
    }

    next();
  };
}

module.exports = validateRequest;

/**
 * Wraps a controller function to catch async errors and pass them to the next middleware.
 */
const asyncHandler = (fn) => (req, res, next) => {
  return Promise.resolve(fn(req, res, next)).catch(next);
};

module.exports = { asyncHandler };

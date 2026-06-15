/**
 * Wraps a controller function to catch async errors and pass them to the next middleware.
 */
const asyncHandler = (fn) => (req, res, next) => {
  return Promise.resolve(fn(req, res, next)).catch(next);
};

/**
 * Wraps a controller with a custom error callback (e.g. for circuit breaker failure logging)
 */
const asyncHandlerWithCallback = (fn, onErr) => (req, res, next) => {
  return Promise.resolve(fn(req, res, next)).catch(err => {
    if (onErr) onErr(err);
    next(err);
  });
};

module.exports = { asyncHandler, asyncHandlerWithCallback };

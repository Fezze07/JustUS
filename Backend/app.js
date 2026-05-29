const express = require("express");
const helmet = require("helmet");
const {
  env,
  requestContext,
  requestLogger,
  sanitizeRequest,
  timeoutMiddleware,
  errorHandler,
  handleCors,
} = require("./all_imports");

const createApiRouter = require("./routes/api");
const authCallbackRoutes = require("./routes/authCallbacks");

function createApp() {
  const app = express();

  app.disable("x-powered-by");
  app.set("trust proxy", env.trustProxy);
  app.use(requestContext);
  app.use(timeoutMiddleware(env.requestTimeoutMs));
  app.use(configureSecurityHeaders());
  app.use((req, res, next) => handleCors(req, res, next, env.allowedOrigins));
  app.use(
    express.json({
      limit: env.bodyLimit,
    })
  );
  app.use(express.urlencoded({ extended: false, limit: env.bodyLimit }));
  app.use(sanitizeRequest());
  app.use(requestLogger());

  app.use("/auth", authCallbackRoutes);
  app.use("/api", createApiRouter());
  app.use(errorHandler);

  return app;
}

/**
 * Configura gli header di sicurezza tramite Helmet.
 * @returns {import('express').RequestHandler} Middleware Helmet configurato.
 */
function configureSecurityHeaders() {
  return helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'none'"],
        baseUri: ["'none'"],
        frameAncestors: ["'none'"],
        formAction: ["'self'"],
      },
    },
    crossOriginResourcePolicy: false,
    hsts:
      env.nodeEnv === "production"
        ? {
          maxAge: 31536000,
          includeSubDomains: true,
          preload: true,
        }
        : false,
    referrerPolicy: {
      policy: "no-referrer",
    },
  });
}

module.exports = {
  createApp,
};

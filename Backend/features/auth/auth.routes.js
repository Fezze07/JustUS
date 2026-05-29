const express = require("express");
const router = express.Router();
const {
  updateDeviceToken,
  checkLoginRiskController,
  registerFailedLoginController,
  syncSessionController,
  invitePartnerController,
  refreshTokenController,
  createCompositeRateLimit,
  ipKey,
  userKey,
  deviceKey,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");

const {
  updateDeviceTokenSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionSyncSchema,
  inviteSchema,
  refreshTokenSchema,
} = require("./auth.schemas");

const {
  chain,
  authenticated,
  freshNonce,
  signed,
  validated,
  limited,
} = require("../../routes/routeHelpers");

const authRateLimit = createCompositeRateLimit({
  name: "auth.device-token",
  message: "Too many device token updates",
  rules: [
    { name: "ip",   windowMs: DEFAULT_WINDOW_MS, max: 20, key: ipKey },
    { name: "user", windowMs: DEFAULT_WINDOW_MS, max: 10, key: userKey },
  ],
});

const authRefreshRateLimit = createCompositeRateLimit({
  name: "auth.refresh",
  message: "Too many token refresh attempts",
  rules: [
    { name: "ip", windowMs: DEFAULT_WINDOW_MS, max: 10, key: ipKey },
  ],
});

const loginRiskRateLimit = createCompositeRateLimit({
  name: "auth.login-risk",
  message: "Too many auth risk checks",
  rules: [
    { name: "ip",     windowMs: DEFAULT_WINDOW_MS, max: 20, key: ipKey },
    { name: "device", windowMs: DEFAULT_WINDOW_MS, max: 10, key: deviceKey },
  ],
});

router.post(
  "/device-token",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    signed("auth-device-token"),
    validated({ body: updateDeviceTokenSchema })
  ),
  updateDeviceToken
);

router.post(
  "/login-risk-check",
  ...chain(
    limited(loginRiskRateLimit),
    validated({ body: loginRiskSchema })
  ),
  checkLoginRiskController
);

router.post(
  "/login-attempt",
  ...chain(
    limited(loginRiskRateLimit),
    validated({ body: loginAttemptSchema })
  ),
  registerFailedLoginController
);

router.post(
  "/session-sync",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    freshNonce("auth-session-sync"),
    validated({ body: sessionSyncSchema })
  ),
  syncSessionController
);

router.post(
  "/invite",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    validated({ body: inviteSchema })
  ),
  invitePartnerController
);

router.post(
  "/refresh",
  ...chain(
    limited(authRefreshRateLimit),
    validated({ body: refreshTokenSchema })
  ),
  refreshTokenController
);

module.exports = router;

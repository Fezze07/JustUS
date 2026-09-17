const express = require("express");
const router = express.Router();
const {
  updateDeviceToken,
  checkLoginRiskController,
  registerFailedLoginController,
  syncSessionController,
  invitePartnerController,
  createCompositeRateLimit,
  ipKey,
  deviceKey,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");

const {
  updateDeviceTokenSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionSyncSchema,
  inviteSchema,
} = require("./auth.schemas");

const {
  chain,
  authenticated,
  freshNonce,
  signed,
  validated,
  limited,
} = require("../../routes/routeHelpers");

const { createIpUserRateLimit } = require("../../utils/auth/rateLimitPresets");

const authRateLimit = createIpUserRateLimit({
  name: "auth.device-token",
  message: "Too many device token updates",
  ipMax: 20,
  userMax: 10,
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

module.exports = router;

const express = require("express");
const router = express.Router();
const {
  updateDeviceToken,
  revokeDeviceToken,
  checkLoginRiskController,
  registerFailedLoginController,
  bindSessionController,
  invitePartnerController,
  createCompositeRateLimit,
  withIdempotency,
  ipKey,
  deviceKey,
  emailValue,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");

const {
  updateDeviceTokenSchema,
  revokeDeviceTokenSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionBindSchema,
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
    // Cap distinct emails per IP so the unsigned endpoints cannot be used to
    // enumerate addresses or inflate counters for many keys from one source.
    { name: "ip-email", windowMs: DEFAULT_WINDOW_MS, max: 5, key: ipKey, distinctValue: emailValue },
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
  "/device-token-revoke",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    signed("auth-device-token-revoke"),
    validated({ body: revokeDeviceTokenSchema })
  ),
  revokeDeviceToken
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
    withIdempotency("auth-login-attempt"),
    validated({ body: loginAttemptSchema })
  ),
  registerFailedLoginController
);

router.post(
  "/session-bind",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    freshNonce("auth-session-bind"),
    validated({ body: sessionBindSchema })
  ),
  bindSessionController
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

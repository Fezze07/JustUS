const express = require("express");
const router = express.Router();
const {
  updateInstallationId,
  revokeInstallationId,
  revokeOtherInstallationIds,
  checkLoginRiskController,
  registerFailedLoginController,
  bindSessionController,
  invitePartnerController,
  inviteUserController,
  createCompositeRateLimit,
  withIdempotency,
  ipKey,
  deviceKey,
  emailValue,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");

const {
  updateInstallationSchema,
  revokeInstallationSchema,
  loginRiskSchema,
  loginAttemptSchema,
  sessionBindSchema,
  inviteSchema,
  inviteUserSchema,
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
  name: "auth.installation-id",
  message: "Too many installation id updates",
  ipMax: 20,
  userMax: 10,
});

// Invites dispatch a real email, so the per-user cap is tight: one account
// cannot use the route to spray the "Invite user" template at many addresses.
const inviteUserRateLimit = createIpUserRateLimit({
  name: "auth.invite-user",
  message: "Too many partner invitation emails",
  ipMax: 10,
  userMax: 5,
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
  "/installation-id",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    signed("auth-installation-id"),
    validated({ body: updateInstallationSchema })
  ),
  updateInstallationId
);

router.post(
  "/installation-id-revoke",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    signed("auth-installation-id-revoke"),
    validated({ body: revokeInstallationSchema })
  ),
  revokeInstallationId
);

router.post(
  "/installation-id-revoke-all",
  ...chain(
    authenticated(),
    limited(authRateLimit),
    signed("auth-installation-id-revoke-all"),
    validated({ body: revokeInstallationSchema })
  ),
  revokeOtherInstallationIds
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

router.post(
  "/invite-user",
  ...chain(
    authenticated(),
    limited(inviteUserRateLimit),
    signed("auth-invite-user"),
    validated({ body: inviteUserSchema })
  ),
  inviteUserController
);

module.exports = router;

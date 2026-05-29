const express = require("express");
const router = express.Router();
const {
  wipeUserDataController,
  createCompositeRateLimit,
  userKey,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");
const {
  chain,
  authenticated,
  limited,
} = require("../../routes/routeHelpers");

const userRateLimit = createCompositeRateLimit({
  name: "user.actions",
  message: "Too many user data requests",
  rules: [
    { name: "user", windowMs: DEFAULT_WINDOW_MS, max: 5, key: userKey },
  ],
});

router.post(
  "/wipe",
  ...chain(
    authenticated(),
    limited(userRateLimit)
  ),
  wipeUserDataController
);

module.exports = router;

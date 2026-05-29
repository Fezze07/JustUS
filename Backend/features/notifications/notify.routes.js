const express = require("express");

const router = express.Router();
const {
  sendNotificationController,
  createCompositeRateLimit,
  ipKey,
  userKey,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");
const {
  chain,
  authenticated,
  validated,
  limited,
} = require("../../routes/routeHelpers");
const { notifySchema, paramsSchema } = require("./notify.schemas");

const notifyRateLimit = createCompositeRateLimit({
  name: "notify.send",
  message: "Too many notification requests",
  rules: [
    { name: "ip",   windowMs: DEFAULT_WINDOW_MS, max: 30, key: ipKey },
    { name: "user", windowMs: DEFAULT_WINDOW_MS, max: 12, key: userKey },
  ],
});

router.post(
  "/:type",
  ...chain(
    authenticated(),
    limited(notifyRateLimit),
    validated({ body: notifySchema, params: paramsSchema })
  ),
  sendNotificationController
);
router.post(
  "/partner",
  ...chain(
    authenticated(),
    limited(notifyRateLimit),
    validated({ body: notifySchema })
  ),
  sendNotificationController
);

module.exports = router;

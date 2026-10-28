const express = require("express");

const router = express.Router();
const {
  sendNotificationController,
} = require("../../all_imports");
const { createIpUserRateLimit } = require("../../utils/auth/rateLimitPresets");
const {
  chain,
  authenticated,
  validated,
  limited,
} = require("../../routes/routeHelpers");
const { notifySchema } = require("./notify.schemas");

const notifyRateLimit = createIpUserRateLimit({
  name: "notify.send",
  message: "Too many notification requests",
  ipMax: 30,
  userMax: 12,
});

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

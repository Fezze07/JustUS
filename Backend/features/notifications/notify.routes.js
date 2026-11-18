const express = require("express");

const router = express.Router();
const {
  sendNotificationController,
  createCompositeRateLimit,
} = require("../../all_imports");
const { createIpUserRateLimit } = require("../../utils/auth/rateLimitPresets");
const {
  chain,
  authenticated,
  signed,
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

// A reminder can only be sent once per cooldown while the partner has not
// answered. The rule is key-scoped so no other notification consumes it.
const reminderRateLimit = createCompositeRateLimit({
  name: "notify.reminder",
  message: "Reminder already sent recently",
  rules: [
    {
      name: "user",
      windowMs: 30 * 60_000,
      max: 1,
      key: (req) =>
        req.body?.notificationKey === "answerReminder"
          ? req.user?.profileId
          : undefined,
    },
  ],
});

router.post(
  "/partner",
  ...chain(
    authenticated(),
    limited(notifyRateLimit),
    limited(reminderRateLimit),
    signed("notify-send"),
    validated({ body: notifySchema })
  ),
  sendNotificationController
);

module.exports = router;

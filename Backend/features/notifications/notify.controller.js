const { asyncHandler, dispatchNotification } = require("../../all_imports");

const sendNotificationController = asyncHandler(async (req, res) => {
  const result = await dispatchNotification({
    type: req.params.type || "partner",
    senderId: req.user.profileId,
    payload: req.body,
  });

  // 202 = accepted but not delivered (no registered devices)
  const status = result.deviceCount === 0 ? 202 : 200;
  res.status(status).json(result);
});

module.exports = { sendNotificationController };

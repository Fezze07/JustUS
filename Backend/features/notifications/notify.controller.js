const { asyncHandler, dispatchNotification } = require("../../all_imports");

const sendNotificationController = asyncHandler(async (req, res) => {
  const result = await dispatchNotification({
    type: req.params.type || "partner",
    senderId: req.user.profileId,
    payload: req.body,
  });

  res.json(result);
});

module.exports = { sendNotificationController };

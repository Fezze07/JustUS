const { asyncHandler, dispatchNotification, AppError } = require("../../all_imports");

const sendNotificationController = asyncHandler(async (req, res) => {
  const result = await dispatchNotification({
    type: req.params.type || "partner",
    senderId: req.user.profileId,
    payload: req.body,
  });

  if (result.deviceCount === 0) {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Partner not found or without a valid token",
    });
  }

  console.log(`[notify] Dispatch result:`, JSON.stringify(result));
  res.status(200).json(result);
});

module.exports = { sendNotificationController };

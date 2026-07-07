const { asyncHandler, dispatchNotification, AppError } = require("../../all_imports");

const sendNotificationController = asyncHandler(async (req, res) => {
  const result = await dispatchNotification({
    type: req.params.type || "partner",
    senderId: req.user.profileId,
    payload: req.body,
  });

  // Verbose log for debugging background-notification issues
  console.log(`[notify] Dispatch result: delivered=${result.delivered} failed=${result.failed} devices=${result.deviceCount} invalidRemoved=${result.invalidTokensRemoved} configured=${result.configured ?? true}`);

  if (result.deviceCount === 0) {
    const isPartner = (req.params.type || "partner") === "partner";
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: isPartner
        ? "Partner not found or without a valid token"
        : "Recipient not found or without a valid token",
    });
  }

  res.status(200).json(result);
});

module.exports = { sendNotificationController };


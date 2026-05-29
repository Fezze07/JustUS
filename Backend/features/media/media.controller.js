const {
  asyncHandler,
  createPresignedUpload,
  registerCompletedUpload,
  getSignedDownloadUrl,
} = require("../../all_imports");

const presignUploadController = asyncHandler(async (req, res) => {
  const result = await createPresignedUpload({
    user: req.user,
    payload: req.body,
  });

  res.json({
    success: true,
    ...result,
  });
});

const completeUploadController = asyncHandler(async (req, res) => {
  const result = await registerCompletedUpload({
    user: req.user,
    payload: req.body,
  });

  res.json(result);
});

const redirectToSignedDownloadController = asyncHandler(async (req, res) => {
  const url = await getSignedDownloadUrl({
    userId: req.user.profileId,
    filename: req.query.filename,
  });
  res.redirect(url);
});

module.exports = {
  presignUploadController,
  completeUploadController,
  redirectToSignedDownloadController,
};

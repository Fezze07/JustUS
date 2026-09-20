const {
  asyncHandler,
  adminSupabase,
  AppError,
  isConfigured,
  deleteObject,
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

const deleteMediaController = asyncHandler(async (req, res) => {
  const { id } = req.body;
  const userId = req.user.profileId;

  const { data: item, error } = await adminSupabase
    .from("drive_items")
    .select("id, user_id, partner_id, filename")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new AppError({
      errorKey: "DB_READ_001",
      message: "Failed to read drive item",
      details: error,
    });
  }

  if (!item) {
    throw new AppError({
      errorKey: "DB_NOT_FOUND_001",
      message: "Drive item not found",
    });
  }

  if (item.user_id !== userId && item.partner_id !== userId) {
    throw new AppError({
      errorKey: "AUTH_FAIL_004",
      message: "Forbidden: no access to this media",
    });
  }

  if (item.filename && isConfigured()) {
    await deleteObject(item.filename);
  }

  const { error: deleteError } = await adminSupabase
    .from("drive_items")
    .delete()
    .eq("id", id);

  if (deleteError) {
    throw new AppError({
      errorKey: "DB_WRITE_001",
      message: "Failed to delete drive item",
      details: deleteError,
    });
  }

  res.json({ success: true, message: "Drive item deleted" });
});

module.exports = {
  presignUploadController,
  completeUploadController,
  redirectToSignedDownloadController,
  deleteMediaController,
};

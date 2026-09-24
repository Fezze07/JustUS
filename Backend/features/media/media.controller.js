const {
  asyncHandler,
  adminSupabase,
  AppError,
  isConfigured,
  deleteObject,
  createPresignedUpload,
  registerCompletedUpload,
  getSignedDownloadUrl,
  logError,
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

const purgeR2Object = async (item, userId) => {
  if (!isConfigured()) return;

  const keys = [item.filename, item.metadata?.thumbnail ?? null].filter(Boolean);

  for (const key of keys) {
    try {
      await deleteObject(key);
    } catch (r2Error) {
      await logError({
        event: "media.delete.r2_cleanup_failed",
        error: { message: r2Error?.message, name: r2Error?.name },
        user_id: userId,
        details: { drive_item_id: item.id, filename: key },
      });
    }
  }
};

const deleteMediaController = asyncHandler(async (req, res) => {
  const { id } = req.body;
  const userId = req.user.profileId;

  const { data: item, error } = await adminSupabase
    .from("drive_items")
    .select("id, user_id, partner_id, filename, metadata")
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
    return res.json({ success: true, message: "Drive item already deleted" });
  }

  if (item.user_id !== userId && item.partner_id !== userId) {
    throw new AppError({
      errorKey: "AUTH_FAIL_004",
      message: "Forbidden: no access to this media",
    });
  }

  const { error: deleteError } = await adminSupabase
    .from("drive_items")
    .delete()
    .eq("id", id)
    .or(`user_id.eq.${userId},partner_id.eq.${userId}`);

  if (deleteError) {
    throw new AppError({
      errorKey: "DB_WRITE_001",
      message: "Failed to delete drive item",
      details: deleteError,
    });
  }

  await purgeR2Object(item, userId);

  res.json({ success: true, message: "Drive item deleted" });
});

module.exports = {
  presignUploadController,
  completeUploadController,
  redirectToSignedDownloadController,
  deleteMediaController,
};

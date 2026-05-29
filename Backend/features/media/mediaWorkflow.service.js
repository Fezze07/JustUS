const {
  adminSupabase,
  env,
  createUploadUrl,
  createDownloadUrl,
  isConfigured,
  getPartnerId,
  AppError,
  assertDbSuccess,
} = require("../../all_imports");

function ensureStorageConfigured() {
  if (!isConfigured()) {
    throw new AppError({ errorKey: "SYS_FAIL_001", message: "Storage not configured" });
  }
}

async function createPresignedUpload({ user, payload }) {
  ensureStorageConfigured();

  if (
    payload.size > env.largeUploadThresholdBytes &&
    !user.capabilities?.includes("can_upload_large")
  ) {
    throw new AppError({
      errorKey: "AUTH_PERMISSION_001",
      message: "Large uploads require additional capability",
    });
  }

  const result = await createUploadUrl({
    userId: user.profileId,
    ...payload,
  });

  return {
    uploadUrl: result.uploadUrl,
    filename: result.key,
    expiresIn: result.expiresIn,
  };
}

async function registerCompletedUpload({ user, payload }) {
  const {
    filename,
    originalName,
    mimeType,
    size,
    type,
    metadata,
    kind,
  } = payload;

  const expectedUserSegment = `/${user.profileId}/`;
  if (!filename.includes(expectedUserSegment)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Invalid storage key" });
  }

  if (kind === "profile") {
    assertDbSuccess(
      await adminSupabase
        .from("user_profiles")
        .update({ profile_pic_url: filename })
        .eq("user_id", user.profileId),
      "DB_WRITE_001"
    );

    return {
      success: true,
      filename,
    };
  }

  const partnerId = await getPartnerId(user.profileId);
  const item = assertDbSuccess(
    await adminSupabase
      .from("drive_items")
      .insert({
        user_id: user.profileId,
        partner_id: partnerId,
        type,
        filename,
        original_name: originalName,
        mime_type: mimeType,
        size,
        metadata: {
          ...metadata,
          source: "backend-signed-url",
        },
      })
      .select()
      .single(),
    "DB_WRITE_001"
  );

  return {
    success: true,
    item,
  };
}

async function getSignedDownloadUrl({ userId, filename }) {
  ensureStorageConfigured();

  const { data: media, error } = await adminSupabase
    .from("drive_items")
    .select("id, user_id, partner_id")
    .eq("filename", filename)
    .single();

  if (error || !media) {
    throw new AppError({ errorKey: "DB_NOT_FOUND_001", message: "Media not found in database" });
  }

  if (media.user_id !== userId && media.partner_id !== userId) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Forbidden: No access to this media" });
  }

  return createDownloadUrl(filename);
}

module.exports = {
  createPresignedUpload,
  registerCompletedUpload,
  getSignedDownloadUrl,
};

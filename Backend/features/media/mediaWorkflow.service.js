const {
  adminSupabase,
  env,
  createUploadUrl,
  createDownloadUrl,
  isConfigured,
  getPartnershipId,
  getPartnerId,
  isPartnershipMember,
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

function isOwnedStorageKey(key, userId) {
  if (typeof key !== "string") return false;
  const segments = key.split("/");
  return (
    segments.length >= 2 &&
    segments[segments.length - 1].length > 0 &&
    segments[segments.length - 2] === String(userId)
  );
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

  if (!isOwnedStorageKey(filename, user.profileId)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Invalid storage key" });
  }

  const thumbnail = metadata?.thumbnail;
  if (thumbnail != null && !isOwnedStorageKey(thumbnail, user.profileId)) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Invalid thumbnail storage key" });
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

  const partnershipId = await getPartnershipId(user.profileId);
  if (partnershipId == null) {
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "No partner found" });
  }
  const item = assertDbSuccess(
    await adminSupabase
      .from("drive_items")
      .insert({
        partnership_id: partnershipId,
        type,
        name: filename,
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

const STORAGE_KEY_ROOTS = new Set(["uploads", "users", "profile"]);

function parseStorageKeyOwner(key) {
  if (typeof key !== "string") return null;
  const segments = key.split("/");
  const ownerId = Number(segments[1]);
  if (
    segments.length < 3 ||
    !segments[2] ||
    !STORAGE_KEY_ROOTS.has(segments[0]) ||
    !Number.isInteger(ownerId) ||
    ownerId <= 0
  ) {
    return null;
  }
  return ownerId;
}

async function findDriveItem(filename) {
  for (const column of ["name", "metadata->>thumbnail"]) {
    const row = assertDbSuccess(
      await adminSupabase
        .from("drive_items")
        .select("partnership_id")
        .eq(column, filename)
        .limit(1)
        .maybeSingle(),
      "DB_READ_001"
    );
    if (row) return row;
  }
  return null;
}

async function findProfileOwner(filename) {
  const row = assertDbSuccess(
    await adminSupabase
      .from("user_profiles")
      .select("user_id")
      .eq("profile_pic_url", filename)
      .limit(1)
      .maybeSingle(),
    "DB_READ_001"
  );
  return row?.user_id ?? null;
}

async function canAccessDriveItem(partnershipId, ownerId, userId) {
  if (!(await isPartnershipMember(partnershipId, userId))) return false;
  return ownerId === userId || isPartnershipMember(partnershipId, ownerId);
}

async function canAccessProfilePicture(profileOwnerId, ownerId, userId) {
  if (profileOwnerId !== ownerId) return false;
  if (profileOwnerId === userId) return true;

  const partnerId = await getPartnerId(userId);
  return partnerId != null && Number(partnerId) === profileOwnerId;
}

async function getSignedDownloadUrl({ userId, filename }) {
  ensureStorageConfigured();

  const keyOwner = parseStorageKeyOwner(filename);
  if (keyOwner == null) {
    throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Invalid media key" });
  }

  const driveItem = await findDriveItem(filename);
  if (driveItem && (await canAccessDriveItem(driveItem.partnership_id, keyOwner, userId))) {
    return createDownloadUrl(filename);
  }

  const profileOwner = await findProfileOwner(filename);
  if (
    profileOwner != null &&
    (await canAccessProfilePicture(Number(profileOwner), keyOwner, userId))
  ) {
    return createDownloadUrl(filename);
  }

  if (!driveItem && profileOwner == null) {
    throw new AppError({ errorKey: "DB_NOT_FOUND_001", message: "Media not found in database" });
  }

  throw new AppError({ errorKey: "AUTH_FAIL_004", message: "Forbidden: No access to this media" });
}

module.exports = {
  createPresignedUpload,
  registerCompletedUpload,
  getSignedDownloadUrl,
};

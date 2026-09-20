const {
  adminSupabase,
  AppError,
  asyncHandler,
  env,
  isConfigured,
  getPartnerId,
  logError,
  deleteObjectsByPrefix,
} = require("../../all_imports");

async function deleteUserR2Objects(userId) {
  if (!isConfigured() || !userId) return;

  const prefixes = new Set([`uploads/${userId}/`, `profile/${userId}/`]);

  try {
    const partnerId = await getPartnerId(userId);
    if (partnerId) {
      prefixes.add(`uploads/${partnerId}/`);
      prefixes.add(`profile/${partnerId}/`);
    }
  } catch (err) {
    logError({
      event: "wipe.r2.partner_resolve_failed",
      error: { message: err?.message, name: err?.name },
      user_id: userId,
    });
  }

  for (const prefix of prefixes) {
    await deleteObjectsByPrefix(prefix);
  }
}

/**
 * Controller per eliminare permanentemente i dati utente.
 * Chiama la funzione RPC 'debug_wipe_user_data' come admin, poi rimuove
 * gli oggetti R2 residui sotto i prefissi dell'utente e del partner.
 */
const wipeUserDataController = asyncHandler(async (req, res) => {
  const userId = req.user.profileId;

  if (!userId) {
    throw new AppError({
      errorKey: "AUTH_FAIL_001",
      message: "User ID not found in token",
    });
  }

  const { error } = await adminSupabase.rpc("debug_wipe_user_data", {
    p_user_id: userId,
  });

  if (error) {
    throw new AppError({
      errorKey: "DB_WRITE_001",
      message: "Failed to wipe user data",
      details: error,
    });
  }

  try {
    await deleteUserR2Objects(userId);
  } catch (r2Error) {
    if (env.nodeEnv !== "test") {
      logError({
        event: "wipe.r2.cleanup_failed",
        error: { message: r2Error?.message, name: r2Error?.name },
        user_id: userId,
      });
    }
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "Failed to wipe storage files",
      details: r2Error,
    });
  }

  res.json({ success: true, message: "User data wiped successfully" });
});

module.exports = {
  deleteUserR2Objects,
  wipeUserDataController,
};
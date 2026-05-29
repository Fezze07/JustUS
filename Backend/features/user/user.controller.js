const { adminSupabase, AppError, asyncHandler } = require("../../all_imports");

/**
 * Controller per eliminare permanentemente i dati utente.
 * Chiama la funzione RPC 'debug_wipe_user_data' come admin.
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

  res.json({ success: true, message: "User data wiped successfully" });
});

module.exports = {
  wipeUserDataController,
};

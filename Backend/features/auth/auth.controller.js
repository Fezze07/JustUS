// =============================================================================
// auth.controller.js — Authentication route handlers
// =============================================================================

const {
  adminSupabase,
  checkLoginRisk,
  recordFailedLogin,
  clearFailedLogins,
  trackSession,
  AppError,
  assertDbSuccess,
  asyncHandler,
  wrapRpc,
} = require("../../all_imports");

// Sniffs the device type from the client user-agent when the body sent none.
// ios must win over macos: iPhone UAs also carry "Mac OS X".
function detectDeviceType(deviceType, clientUserAgent) {
  if (deviceType || !clientUserAgent) return deviceType;
  const ua = clientUserAgent.toLowerCase();
  const hit = (needles) => needles.some((needle) => ua.includes(needle));
  if (hit(["android"])) return "android";
  if (hit(["ios", "iphone", "ipad"])) return "ios";
  if (hit(["macintosh", "mac os", "macos", "darwin"])) return "macos";
  if (hit(["web", "browser"])) return "web";
  return deviceType;
}

const updateInstallationId = asyncHandler(async (req, res) => {
  const { installationId, locale } = req.body;
  const userId = req.user.profileId;
  const clientUserAgent =
    req.get("x-client-user-agent") || req.get("user-agent") || null;
  const deviceType = detectDeviceType(req.body.deviceType, clientUserAgent);
  const lastIp = req.ip;

  assertDbSuccess(
    await adminSupabase.from("user_devices").upsert(
      {
        user_id: userId,
        installation_id: installationId,
        user_agent: clientUserAgent,
        device_type: deviceType,
        last_ip: lastIp,
        session_id: req.auth?.claims?.session_id ?? null,
        ...(locale && { locale }),
      },
      { onConflict: "installation_id" }
    ),
    "DB_WRITE_001"
  );

  res.json({ success: true });
});

const revokeInstallationId = asyncHandler(async (req, res) => {
  const { installationId } = req.body;
  const userId = req.user.profileId;

  // Scoped to the caller: `installation_id` is UNIQUE, so an unscoped delete
  // could remove a row another account has already re-registered on this device.
  const { error: deleteError } = await adminSupabase
    .from("user_devices")
    .delete()
    .eq("installation_id", installationId)
    .eq("user_id", userId);

  if (deleteError) {
    throw new AppError({
      errorKey: "DB_WRITE_001",
      message: "Failed to revoke installation id",
      details: deleteError,
    });
  }

  res.json({ success: true });
});

const revokeOtherInstallationIds = asyncHandler(async (req, res) => {
  const { installationId } = req.body;
  const userId = req.user.profileId;

  const { error: deleteError } = await adminSupabase
    .from("user_devices")
    .delete()
    .eq("user_id", userId)
    .neq("installation_id", installationId);

  if (deleteError) {
    throw new AppError({
      errorKey: "DB_WRITE_001",
      message: "Failed to revoke other installation ids",
      details: deleteError,
    });
  }

  res.json({ success: true });
});

const checkLoginRiskController = asyncHandler(async (req, res) => {
  const result = checkLoginRisk({
    email: req.body.email,
    deviceFingerprint: req.body.deviceFingerprint,
    ipAddress: req.ip,
  });

  if (result.blocked) {
    throw new AppError({
      errorKey: "SEC_BLOCK_002",
      message: "Login temporarily blocked",
      details: {
        retryAfterMs: result.retryAfterMs,
        strikeLevel: result.strikeLevel,
      }
    });
  }

  res.json({
    success: true,
    strikeLevel: result.strikeLevel,
  });
});

const registerFailedLoginController = asyncHandler(async (req, res) => {
  const result = await recordFailedLogin({
    email: req.body.email,
    deviceFingerprint: req.body.deviceFingerprint,
    ipAddress: req.ip,
    reason: req.body.reason,
  });

  if (result.blockedUntil) {
    throw new AppError({
      errorKey: "SEC_BLOCK_002",
      message: "Too many failed attempts",
      details: {
        failures: result.failures,
        strikeLevel: result.strikeLevel,
        blockedUntil: result.blockedUntil,
      }
    });
  }

  res.json({
    success: true,
    failures: result.failures,
    strikeLevel: result.strikeLevel,
  });
});

const bindSessionController = asyncHandler(async (req, res) => {
  const sessionResult = await trackSession({
    userId: req.user.profileId,
    authUserId: req.user.id,
    sessionId: req.auth?.claims?.session_id ?? null,
    deviceFingerprint: req.body.deviceFingerprint,
    countryCode: req.get("cf-ipcountry") || req.get("x-vercel-ip-country") || null,
  });

  clearFailedLogins({
    email: req.user.publicEmail,
    deviceFingerprint: req.body.deviceFingerprint,
    ipAddress: req.ip,
  });

  res.json({
    success: true,
    anomalies: sessionResult.anomalies,
    bindingSecret: sessionResult.bindingSecret,
  });
});

async function resolveRequestedPartnerOrNull(email, partnershipCode) {
  try {
    const user = assertDbSuccess(
      await adminSupabase
        .from("users")
        .select("id, email")
        .ilike("email", email.trim())
        .maybeSingle(),
      "DB_READ_001"
    );

    if (!user) return null;

    const profile = assertDbSuccess(
      await adminSupabase
        .from("user_profiles")
        .select("user_id, display_name, partnership_code")
        .eq("user_id", user.id)
        .eq("partnership_code", partnershipCode.trim())
        .maybeSingle(),
      "DB_READ_001"
    );

    if (!profile) return null;

    return { ...user, displayName: profile.display_name };
  } catch (_) {
    return null;
  }
}

const invitePartnerController = asyncHandler(async (req, res) => {
  const { email, partnershipCode } = req.body;
  const user = req.user;

  const recipient = await resolveRequestedPartnerOrNull(email, partnershipCode);
  if (recipient && Number(recipient.id) === Number(user.profileId)) {
    throw new AppError({ errorKey: "API_VALIDATION_006", message: "Cannot invite yourself" });
  }

  const data = wrapRpc(
    await adminSupabase.rpc("request_partnership", {
      partner_email: email,
      partner_code: partnershipCode,
      override_sender_id: user.profileId,
    })
  );

  res.json({ success: true, data });
});

// Account-only invite: creates the Auth account of a partner who has no JustUs
// account yet and lets GoTrue send the "Invite user" email. No partnership row
// is written here; once the invitee registers, the pairing still travels
// through invitePartnerController with email + 6-char code.
const inviteUserController = asyncHandler(async (req, res) => {
  const { email, redirectTo } = req.body;

  const { error } = await adminSupabase.auth.admin.inviteUserByEmail(
    email.trim(),
    redirectTo ? { redirectTo } : undefined
  );

  if (error) {
    // GoTrue refuses an address that already has a confirmed account; an
    // invited-but-unconfirmed address is re-invited instead of refused.
    if (error.code === "email_exists" || error.code === "user_already_exists") {
      throw new AppError({ errorKey: "API_VALIDATION_002" });
    }

    throw new AppError({
      errorKey: "API_FAIL_001",
      message: `Invite email dispatch failed: ${error.message}`,
      cause: error,
    });
  }

  res.json({ success: true });
});

module.exports = {
  updateInstallationId,
  revokeInstallationId,
  revokeOtherInstallationIds,
  checkLoginRiskController,
  registerFailedLoginController,
  bindSessionController,
  invitePartnerController,
  inviteUserController,
};

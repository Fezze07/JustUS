// =============================================================================
// auth.controller.js — Authentication route handlers
// =============================================================================

const {
  adminSupabase,
  authSupabase,
  checkLoginRisk,
  recordFailedLogin,
  clearFailedLogins,
  trackSession,
  AppError,
  assertDbSuccess,
  asyncHandler,
  wrapRpc,
} = require("../../all_imports");

const updateDeviceToken = asyncHandler(async (req, res) => {
  const { deviceToken, locale } = req.body;
  const userId = req.user.profileId;
  const clientUserAgent =
    req.get("x-client-user-agent") || req.get("user-agent") || null;

  let deviceType = req.body.deviceType;
  if (!deviceType && clientUserAgent) {
    const ua = clientUserAgent.toLowerCase();
    if (ua.includes("android")) {
      deviceType = "android";
    } else if (ua.includes("ios") || ua.includes("iphone") || ua.includes("ipad")) {
      deviceType = "ios";
    } else if (ua.includes("macintosh") || ua.includes("mac os") || ua.includes("macos") || ua.includes("darwin")) {
      deviceType = "macos";
    } else if (ua.includes("web") || ua.includes("browser")) {
      deviceType = "web";
    }
  }
  const lastIp = req.ip;

  assertDbSuccess(
    await adminSupabase.from("user_devices").upsert(
      {
        user_id: userId,
        device_token: deviceToken,
        user_agent: clientUserAgent,
        device_type: deviceType,
        last_ip: lastIp,
        ...(locale && { locale }),
      },
      { onConflict: "device_token" }
    ),
    "DB_WRITE_001"
  );

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

const syncSessionController = asyncHandler(async (req, res) => {
  const sessionResult = await trackSession({
    userId: req.user.profileId,
    authUserId: req.user.id,
    sessionId: req.auth?.claims?.session_id ?? null,
    deviceFingerprint: req.body.deviceFingerprint,
    deviceLabel: req.body.deviceLabel,
    ipAddress: req.ip,
    countryCode: req.get("cf-ipcountry") || req.get("x-vercel-ip-country") || null,
    userAgent: req.get("x-client-user-agent") || req.get("user-agent") || null,
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
    throw new AppError({ errorKey: "API_VALIDATION_001", message: "Non puoi invitare te stesso" });
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

const refreshTokenController = asyncHandler(async (req, res) => {
  const { refreshToken } = req.body;
  
  const { data, error } = await authSupabase.auth.refreshSession({ refresh_token: refreshToken });
  
  if (error || !data.session) {
    throw new AppError({ errorKey: "AUTH_FAIL_001", message: "Session expired or invalid refresh token", cause: error });
  }

  res.json({
    success: true,
    accessToken: data.session.access_token,
    refreshToken: data.session.refresh_token
  });
});

module.exports = {
  updateDeviceToken,
  checkLoginRiskController,
  registerFailedLoginController,
  syncSessionController,
  invitePartnerController,
  refreshTokenController,
};

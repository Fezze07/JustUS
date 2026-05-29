const {
  adminSupabase,
  logSecurity,
  API_V1_PATHS,
  buildClientContext,
  ipToSoftRange,
  generateBindingSecret,
  sha256,
} = require("../../all_imports");

const loginAttempts = new Map();

function buildAttemptKey({ email, deviceFingerprint, ipAddress }) {
  const normalizedEmail = String(email ?? "").trim().toLowerCase();
  const normalizedDevice = String(deviceFingerprint ?? "").trim().toLowerCase();
  return [
    sha256(normalizedEmail || "anonymous"),
    sha256(normalizedDevice || "unknown-device"),
    ipAddress || "unknown-ip",
  ].join(":");
}

function getAttemptState(key, now = Date.now()) {
  const existing = loginAttempts.get(key);
  if (!existing || existing.expiresAt <= now) {
    const fresh = {
      failures: 0,
      strikeLevel: 0,
      blockedUntil: 0,
      expiresAt: now + 15 * 60_000,
    };
    loginAttempts.set(key, fresh);
    return fresh;
  }
  return existing;
}

function checkLoginRisk(payload) {
  const key = buildAttemptKey(payload);
  const state = getAttemptState(key);
  const now = Date.now();
  const retryAfterMs = Math.max(state.blockedUntil - now, 0);

  return {
    blocked: retryAfterMs > 0,
    retryAfterMs,
    strikeLevel: state.strikeLevel,
  };
}

async function recordFailedLogin({ email, deviceFingerprint, ipAddress, reason: _reason }) {
  const key = buildAttemptKey({ email, deviceFingerprint, ipAddress });
  const state = getAttemptState(key);
  state.failures += 1;

  updateStrikeLevel(state);

  loginAttempts.set(key, state);

  if (state.strikeLevel > 0) {
    await logSecurity({
      type: "login_anomaly",
      path: API_V1_PATHS.authLoginAttempt,
      ip_address: ipAddress ?? null,
      retry_after_seconds: state.blockedUntil > Date.now()
          ? Math.ceil((state.blockedUntil - Date.now()) / 1000)
          : 0,
    });
  }

  return {
    failures: state.failures,
    strikeLevel: state.strikeLevel,
    blockedUntil: state.blockedUntil || null,
  };
}

function updateStrikeLevel(state) {
  if (state.failures >= 3) state.strikeLevel = Math.max(state.strikeLevel, 1);
  if (state.failures >= 5) {
    state.strikeLevel = Math.max(state.strikeLevel, 2);
    state.blockedUntil = Date.now() + 10 * 60_000;
  }
  if (state.failures >= 8) {
    state.strikeLevel = 3;
    state.blockedUntil = Date.now() + 30 * 60_000;
  }
}

function clearFailedLogins({ email, deviceFingerprint, ipAddress }) {
  const key = buildAttemptKey({ email, deviceFingerprint, ipAddress });
  loginAttempts.delete(key);
}

async function trackSession(params) {
  const { userId, sessionId, ipAddress } = params;
  const clientContext = buildClientContextFromParams(params);
  const sessionKey = sessionId || `${userId}:${clientContext.deviceFingerprintHash}`;
  
  let bindingSecret = generateBindingSecret();
  
  try {
    const previous = await fetchPreviousSession(sessionKey);
    if (previous?.binding_secret) {
      bindingSecret = previous.binding_secret;
    }

    const payload = buildSessionPayload(params, clientContext, sessionKey, bindingSecret);
    await adminSupabase.from("auth_sessions").upsert(payload, { onConflict: "session_id" });

    const anomalies = detectSessionAnomalies(previous, params, clientContext);
    for (const anomaly of anomalies) {
      await logSecurity({
        type: anomaly,
        path: API_V1_PATHS.authSessionSync,
        user_id: userId,
        ip_address: ipAddress ?? null,
      });
    }

    return { anomalies, bindingSecret, clientContext };
  } catch {
    return { anomalies: [], bindingSecret, clientContext };
  }
}

function buildClientContextFromParams({ deviceFingerprint, userAgent, ipAddress }) {
  return buildClientContext({
    ip: ipAddress,
    get(header) {
      const h = String(header).toLowerCase();
      if (h === "x-device-fingerprint") return deviceFingerprint;
      if (h === "x-client-user-agent" || h === "user-agent") return userAgent;
      if (h === "x-client-user-agent-hash") return sha256(userAgent);
      return "";
    },
  });
}

async function fetchPreviousSession(sessionKey) {
  const { data } = await adminSupabase
    .from("auth_sessions")
    .select("ip_address, country_code, last_seen_at, binding_secret, ip_range, user_agent_hash, request_profile_hash")
    .eq("session_id", sessionKey)
    .order("last_seen_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data;
}

function buildSessionPayload(params, context, sessionKey, secret) {
  return {
    user_id: params.userId,
    auth_user_id: params.authUserId,
    session_id: sessionKey,
    device_fingerprint_hash: context.deviceFingerprintHash,
    device_label: params.deviceLabel ?? null,
    ip_address: params.ipAddress ?? null,
    ip_range: ipToSoftRange(params.ipAddress),
    country_code: params.countryCode ?? null,
    user_agent: params.userAgent ?? null,
    user_agent_hash: context.clientUserAgentHash,
    request_profile_hash: context.behaviorPatternHash,
    binding_secret: secret,
    last_seen_at: new Date().toISOString(),
  };
}

function detectSessionAnomalies(prev, current, context) {
  const anomalies = [];
  if (!prev) return anomalies;

  if (prev.ip_address !== current.ipAddress) {
    anomalies.push("ip_changed");
  }
  if (current.countryCode && prev.country_code !== current.countryCode) {
    anomalies.push("country_changed");
  }
  if (prev.request_profile_hash !== context.behaviorPatternHash) {
    anomalies.push("behavior_pattern_changed");
  }
  return anomalies;
}

const resetAuthRiskState = () => {
  loginAttempts.clear();
};

module.exports = {
  checkLoginRisk,
  recordFailedLogin,
  clearFailedLogins,
  trackSession,
  resetAuthRiskState,
};

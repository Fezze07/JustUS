const {
  adminSupabase,
  logSecurity,
  API_V1_PATHS,
  buildClientContext,
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

/**
 * Binds a new Supabase session to a device fingerprint, enforcing the rule
 * that one device may hold exactly one active session at a time.
 *
 * Flow:
 *  1. Read any previous binding for this session (for anomaly detection).
 *  2. Revoke any stale session that shares the same user + device fingerprint
 *     (different session_id).  The SECURITY DEFINER RPC deletes from
 *     auth.sessions; ON DELETE CASCADE removes the old session_bindings row.
 *  3. Upsert the new binding with a fresh binding_secret.
 */
async function trackSession(params) {
  const { userId, authUserId, sessionId } = params;
  const clientContext = buildClientContextFromParams(params);

  // Each new session gets a fresh binding_secret — never reuse a previous one.
  const bindingSecret = generateBindingSecret();

  try {
    const [previous] = await Promise.all([
      fetchPreviousBinding(sessionId),
      revokeStaleDeviceSession(authUserId, clientContext.deviceFingerprintHash, sessionId),
    ]);

    const payload = buildSessionPayload(clientContext, sessionId, bindingSecret, authUserId, params);
    await adminSupabase.from("session_bindings").upsert(payload, { onConflict: "session_id" });

    const anomalies = detectSessionAnomalies(previous, params);
    for (const anomaly of anomalies) {
      await logSecurity({
        type: anomaly,
        path: API_V1_PATHS.authSessionBind,
        user_id: userId,
      });
    }

    return { anomalies, bindingSecret, clientContext };
  } catch {
    return { anomalies: [], bindingSecret, clientContext };
  }
}

function buildClientContextFromParams({ deviceFingerprint }) {
  return buildClientContext({
    ip: null,
    get(header) {
      const h = String(header).toLowerCase();
      if (h === "x-device-fingerprint") return deviceFingerprint;
      return "";
    },
  });
}

/**
 * Calls the SECURITY DEFINER Postgres function that deletes any auth.sessions
 * row bound to the same (user_id, device_fingerprint_hash) except the current
 * session.  ON DELETE CASCADE removes the corresponding session_bindings row.
 *
 * We use an RPC because PostgREST only exposes the public schema; direct
 * writes to auth.sessions require SECURITY DEFINER access.
 */
async function revokeStaleDeviceSession(authUserId, fingerprintHash, keepSessionId) {
  if (!authUserId || !fingerprintHash || !keepSessionId) return;

  await adminSupabase.rpc("revoke_device_duplicate_session", {
    p_user_id:     authUserId,
    p_fingerprint: fingerprintHash,
    p_keep_session: keepSessionId,
  });
}

async function fetchPreviousBinding(sessionId) {
  if (!sessionId) return null;
  const { data } = await adminSupabase
    .from("session_bindings")
    .select("country_code, last_seen_at")
    .eq("session_id", sessionId)
    .maybeSingle();
  return data;
}

function buildSessionPayload(context, sessionId, secret, _authUserId, params) {
  return {
    session_id: sessionId,
    device_fingerprint_hash: context.deviceFingerprintHash,
    country_code: params.countryCode ?? null,
    binding_secret: secret,
    last_seen_at: new Date().toISOString(),
  };
}

function detectSessionAnomalies(prev, current) {
  const anomalies = [];
  if (!prev) return anomalies;

  if (current.countryCode && prev.country_code !== current.countryCode) {
    anomalies.push("country_changed");
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

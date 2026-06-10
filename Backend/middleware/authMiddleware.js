const {
  env,
  adminSupabase,
  authSupabase,
  logSecurity,
  logAuthFailure,
  AppError,
  buildClientContext,
  hmacSha256,
  resolveCapabilities,
  normalizeRole,
  decodeTokenClaims,
  validateTokenLifetime,
  validateSessionBinding,
  isIpRangeChanged,
} = require("../all_imports");

async function verifyToken(token) {
  const {
    data: { user },
    error,
  } = await authSupabase.auth.getUser(token);

  if (error || !user) {
    throw error || new Error("Invalid token");
  }

  const claims = decodeTokenClaims(token, user);
  validateTokenLifetime(claims, env.maxAccessTokenLifetimeSec);

  return { claims, user };
}


async function authenticateToken(req, res, next) {
  const token = extractBearerToken(req);

  if (!token) {
    return next(new AppError({ errorKey: "AUTH_FAIL_002" }));
  }

  try {
    const verified = await verifyToken(token);
    if (verified.claims.role !== "authenticated") {
      return next(new AppError({ errorKey: "AUTH_FAIL_004" }));
    }

    const clientContext = buildClientContext(req);
    const { profile, sessionBinding } = await resolveProfileAndSession(verified, clientContext);

    if (!profile) {
      return next(new AppError({ errorKey: "AUTH_FAIL_005" }));
    }

    validateSessionBinding(sessionBinding, clientContext);

    if (isIpRangeChanged(sessionBinding, clientContext)) {
      await logSecurity({
        request_id: req.requestId,
        type: "ip_range_changed",
        path: req.originalUrl,
        user_id: profile.id,
        ip_address: req.ip,
      });
    }

    req.auth = { token, claims: verified.claims, clientContext };
    req.user = buildUserObject(verified.user, profile);
    applyResponseWatermark(res, req);
    req.sessionBinding = buildSessionBinding(sessionBinding);

    next();
  } catch (error) {
    handleAuthError(error, req, next);
  }
}

function extractBearerToken(req) {
  const authHeader = req.headers.authorization;
  return authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
}

async function resolveProfileAndSession(verified, clientContext) {
  let profile;
  let sessionBinding;

  if (verified.claims.session_id) {
    [profile, sessionBinding] = await Promise.all([
      fetchUserProfile(verified.user.id),
      fetchSessionBinding(verified, null, clientContext),
    ]);
  } else {
    profile = await fetchUserProfile(verified.user.id);
    if (profile) {
      sessionBinding = await fetchSessionBinding(verified, profile, clientContext);
    }
  }

  return { profile, sessionBinding };
}

function applyResponseWatermark(res, req) {
  const watermarkSeed = "justus-watermark";
  res.set(
    "X-Response-Watermark",
    hmacSha256(watermarkSeed, `${req.user.profileId}:${req.requestId}`).slice(0, 24)
  );
}

function buildSessionBinding(sessionBinding) {
  return sessionBinding ? {
    sessionId: sessionBinding.session_id,
    bindingSecret: sessionBinding.binding_secret,
  } : null;
}

/**
 * Gestisce gli errori di autenticazione, loggandoli e passando il controllo al middleware di errore.
 * @param {Error} error - L'errore catturato.
 * @param {import('express').Request} req - La richiesta Express.
 * @param {import('express').NextFunction} next - La funzione next di Express.
 */
async function handleAuthError(error, req, next) {
  await logAuthFailure({
    request_id: req.requestId,
    error_code: "AUTH-FAIL-001",
    path: req.originalUrl,
    ip_address: req.ip,
    reason: error?.message,
    severity: "HIGH",
  });

  if (error instanceof AppError) {
    return next(error);
  }
  return next(new AppError({ errorKey: "AUTH_FAIL_001", cause: error }));
}

/**
 * Recupera il profilo utente dal database admin (bypass RLS).
 * @param {string} authId - L'ID di autenticazione di Supabase.
 * @returns {Promise<object|null>} Il profilo utente o null se non trovato.
 */
async function fetchUserProfile(authId) {
  const { data: profile } = await adminSupabase
    .from("users")
    .select(`
      id, 
      email, 
      auth_id, 
      user_profiles(display_name),
      user_roles!inner(roles!inner(name))
    `)
    .eq("auth_id", authId)
    .maybeSingle();
  return profile;
}

/**
 * Recupera i dati di legame della sessione dal database.
 * @param {object} verified - I dati del token verificato.
 * @param {object} profile - Il profilo utente.
 * @param {object} clientContext - Il contesto del client attuale.
 * @returns {Promise<object|null>} I dati della sessione o null.
 */
async function fetchSessionBinding(verified, profile, clientContext) {
  try {
    const { data } = await adminSupabase
      .from("auth_sessions")
      .select("session_id, device_fingerprint_hash, ip_range, user_agent_hash, request_profile_hash, binding_secret, revoked_at")
      .eq("session_id", verified.claims.session_id ?? `${profile.id}:${clientContext.deviceFingerprintHash}`)
      .maybeSingle();
    return data ?? null;
  } catch (_) {
    return null;
  }
}

/**
 * Costruisce l'oggetto utente da allegare alla richiesta.
 * @param {object} supabaseUser - L'oggetto utente di Supabase.
 * @param {object} profile - Il profilo utente del database interno.
 * @returns {object} L'oggetto utente formattato.
 */
function buildUserObject(supabaseUser, profile) {
  const appRole = profile.user_roles?.[0]?.roles?.name || "user";
  const username = profile.user_profiles?.display_name || profile.email?.split('@')[0] || "User";

  return {
    ...supabaseUser,
    profileId: profile.id,
    username: username,
    publicEmail: profile.email,
    role: normalizeRole(appRole),
    capabilities: resolveCapabilities(appRole, []),
  };
}

module.exports = authenticateToken;

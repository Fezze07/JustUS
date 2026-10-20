const request = require("supertest");
const { createQueryBuilder } = require("./support/mockSupabase");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
}));

jest.mock("../config/db", () => ({
  adminSupabase: {
    from: jest.fn(),
    rpc: jest.fn(),
    auth: {
      admin: {
        inviteUserByEmail: jest.fn(),
      },
    },
  },
  authSupabase: {
    auth: {
      getUser: jest.fn(),
    },
  },
  createUserScopedClient: jest.fn(),
}));

jest.mock("../middleware/authMiddleware", () =>
  jest.fn((req, _res, next) => {
    req.user = {
      id: "auth-user-1",
      profileId: 42,
      publicEmail: "user@example.com",
      capabilities: ["can_media_upload"],
      role: "user",
    };
    req.auth = { claims: { session_id: "session-1" } };
    next();
  })
);

jest.mock("../middleware/requireSignedRequest", () =>
  jest.fn(() => (_req, _res, next) => next())
);

jest.mock("../middleware/requireFreshNonce", () =>
  jest.fn(() => (_req, _res, next) => next())
);

const {
  adminSupabase,
  resetAuthRiskState,
  resetRateLimitState,
} = require("../all_imports");
const { createApp } = require("../app");

describe("auth routes", () => {
  beforeEach(() => {
    resetAuthRiskState();
    resetRateLimitState();
    adminSupabase.from.mockReset();
    adminSupabase.rpc.mockReset();
    adminSupabase.auth.admin.inviteUserByEmail.mockReset();
  });

  test("rejects invalid login risk payloads", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/login-risk-check")
      .send({ email: "not-an-email" });

    expect(response.status).toBe(400);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("caps how many distinct emails one IP may probe", async () => {
    const app = createApp();
    const deviceFingerprint = "device-fingerprint-enum";

    for (let i = 1; i <= 5; i += 1) {
      const response = await request(app)
        .post("/api/v1/auth/login-risk-check")
        .send({ email: `probe-${i}@example.com`, deviceFingerprint });

      expect(response.status).toBe(200);
    }

    // The 6th distinct email from the same IP trips the per-IP cap, bounding
    // address enumeration and per-key counter inflation on the unsigned route.
    const blocked = await request(app)
      .post("/api/v1/auth/login-risk-check")
      .send({ email: "probe-6@example.com", deviceFingerprint });

    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe("SEC-BLOCK-001");
  });

  test("does not penalise repeated checks for the same email", async () => {
    const app = createApp();
    const payload = {
      email: "repeat@example.com",
      deviceFingerprint: "device-fingerprint-repeat",
    };

    for (let i = 0; i < 6; i += 1) {
      const response = await request(app)
        .post("/api/v1/auth/login-risk-check")
        .send(payload);

      expect(response.status).toBe(200);
    }
  });

  test("blocks repeated failed login attempts", async () => {
    const app = createApp();
    const payload = {
      email: "user@example.com",
      deviceFingerprint: "device-fingerprint-123",
      reason: "bad password",
    };

    for (let attempt = 1; attempt <= 4; attempt += 1) {
      const response = await request(app)
        .post("/api/v1/auth/login-attempt")
        .send(payload);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
    }

    const blockedResponse = await request(app)
      .post("/api/v1/auth/login-attempt")
      .send(payload);

    expect(blockedResponse.status).toBe(429);
    expect(blockedResponse.body.error.code).toBe("SEC-BLOCK-002");

    const riskResponse = await request(app)
      .post("/api/v1/auth/login-risk-check")
      .send({
        email: payload.email,
        deviceFingerprint: payload.deviceFingerprint,
      });

    expect(riskResponse.status).toBe(429);
    expect(riskResponse.body.error.code).toBe("SEC-BLOCK-002");
  });

  test("counts a replayed failed login attempt once", async () => {
    const app = createApp();
    const payload = {
      email: "replay@example.com",
      deviceFingerprint: "device-fingerprint-replay",
      reason: "invalid_credentials",
    };

    const first = await request(app)
      .post("/api/v1/auth/login-attempt")
      .set("X-Idempotency-Key", "replay-key-1")
      .send(payload);

    expect(first.status).toBe(200);
    expect(first.body.failures).toBe(1);

    // Same idempotency key = same logical report: the strike counter must not
    // move, otherwise a single failed login could be counted twice.
    const replay = await request(app)
      .post("/api/v1/auth/login-attempt")
      .set("X-Idempotency-Key", "replay-key-1")
      .send(payload);

    expect(replay.status).toBe(200);
    expect(replay.body).toEqual(first.body);

    const riskAfterReplay = await request(app)
      .post("/api/v1/auth/login-risk-check")
      .send({
        email: payload.email,
        deviceFingerprint: payload.deviceFingerprint,
      });

    expect(riskAfterReplay.status).toBe(200);
    expect(riskAfterReplay.body.strikeLevel).toBe(0);

    // Distinct keys still count, and the 5th distinct attempt escalates.
    for (let attempt = 2; attempt <= 4; attempt += 1) {
      const response = await request(app)
        .post("/api/v1/auth/login-attempt")
        .set("X-Idempotency-Key", `replay-key-${attempt}`)
        .send(payload);

      expect(response.status).toBe(200);
      expect(response.body.failures).toBe(attempt);
    }

    const blocked = await request(app)
      .post("/api/v1/auth/login-attempt")
      .set("X-Idempotency-Key", "replay-key-5")
      .send(payload);

    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe("SEC-BLOCK-002");
  });

  test("registers the installation id with the caller's session id", async () => {
    const userDevicesQuery = createQueryBuilder();

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return userDevicesQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/installation-id")
      .send({
        installationId: "fid-that-is-long-enough-0001",
        locale: "it",
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(userDevicesQuery.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: 42,
        installation_id: "fid-that-is-long-enough-0001",
        session_id: "session-1",
        locale: "it",
      }),
      { onConflict: "installation_id" }
    );
  });

  test("sniffs the device type from the user-agent, but an explicit deviceType wins", async () => {
    const userDevicesQuery = createQueryBuilder();

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return userDevicesQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();

    // iPhone UAs also contain "Mac OS X" — ios must win over macos.
    await request(app)
      .post("/api/v1/auth/installation-id")
      .set("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
      .send({ installationId: "fid-that-is-long-enough-0002" });

    expect(userDevicesQuery.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({ device_type: "ios" }),
      { onConflict: "installation_id" }
    );

    await request(app)
      .post("/api/v1/auth/installation-id")
      .set("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")
      .send({ installationId: "fid-that-is-long-enough-0003", deviceType: "web" });

    expect(userDevicesQuery.upsert).toHaveBeenLastCalledWith(
      expect.objectContaining({ device_type: "web" }),
      { onConflict: "installation_id" }
    );
  });

  test("rejects an empty installation id", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/installation-id")
      .send({ installationId: "" });

    // Clients without FCM send an empty string; min(16) rejects it so the
    // globally-unique installation_id column never gets a shared row.
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("revokes only the caller's own installation id row", async () => {
    const userDevicesQuery = createQueryBuilder();

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return userDevicesQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke")
      .send({ installationId: "fid-that-is-long-enough-0001" });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(userDevicesQuery.delete).toHaveBeenCalledWith();
    // Scoping by user_id matters: installation_id is UNIQUE, so a stale client
    // could otherwise delete the row a second account just registered.
    expect(userDevicesQuery.eq).toHaveBeenCalledWith(
      "installation_id",
      "fid-that-is-long-enough-0001",
    );
    expect(userDevicesQuery.eq).toHaveBeenCalledWith("user_id", 42);
  });

  test("reports a failed installation id revoke instead of swallowing it", async () => {
    const failingBuilder = {
      delete: jest.fn(() => failingBuilder),
      eq: jest.fn(() => failingBuilder),
      then: (resolve) =>
        resolve({ data: null, error: { message: "delete rejected" } }),
    };

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return failingBuilder;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke")
      .send({ installationId: "fid-that-is-long-enough-0001" });

    expect(response.status).toBe(500);
    expect(response.body.error.code).toBe("DB-WRITE-001");
  });

  test("rejects a malformed installation id revoke payload", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke")
      .send({ installationId: "too-short" });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("revoke-all keeps only the caller's own installation id row", async () => {
    const userDevicesQuery = createQueryBuilder();
    const keepInstallationId = "fid-kept-by-the-caller-0001";

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return userDevicesQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke-all")
      .send({ installationId: keepInstallationId });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(userDevicesQuery.delete).toHaveBeenCalledWith();
    // Every other row dies with the revoked sessions, but the caller's own
    // registration must survive so its push delivery is not interrupted.
    expect(userDevicesQuery.eq).toHaveBeenCalledWith("user_id", 42);
    expect(userDevicesQuery.neq).toHaveBeenCalledWith("installation_id", keepInstallationId);
  });

  test("reports a failed revoke-all instead of swallowing it", async () => {
    const failingBuilder = {
      delete: jest.fn(() => failingBuilder),
      eq: jest.fn(() => failingBuilder),
      neq: jest.fn(() => failingBuilder),
      then: (resolve) =>
        resolve({ data: null, error: { message: "delete rejected" } }),
    };

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return failingBuilder;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke-all")
      .send({ installationId: "fid-that-is-long-enough-0001" });

    expect(response.status).toBe(500);
    expect(response.body.error.code).toBe("DB-WRITE-001");
  });

  test("rejects a malformed revoke-all payload", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/installation-id-revoke-all")
      .send({ installationId: "too-short" });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("binds a session and returns a fresh binding secret", async () => {
    const sessionBindingsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          country_code: "IT",
          last_seen_at: new Date().toISOString(),
        },
        error: null,
      }),
      upsert: jest.fn().mockResolvedValue({ data: null, error: null }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "session_bindings") {
        return sessionBindingsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    // revoke_device_duplicate_session is called in parallel with fetchPreviousBinding
    adminSupabase.rpc.mockResolvedValue({ data: 0, error: null });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/session-bind")
      .set("X-Device-Fingerprint", "device-fingerprint-123")
      .send({
        deviceFingerprint: "device-fingerprint-123",
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(typeof response.body.bindingSecret).toBe("string");
    expect(response.body.bindingSecret.length).toBeGreaterThan(0);
    expect(Array.isArray(response.body.anomalies)).toBe(true);

    expect(adminSupabase.rpc).toHaveBeenCalledWith(
      "revoke_device_duplicate_session",
      expect.objectContaining({
        p_user_id: "auth-user-1",
        p_keep_session: "session-1",
        p_fingerprint: expect.any(String),
      })
    );
  });

  test("revokes stale duplicate session for same user and device fingerprint on new login", async () => {
    const sessionBindingsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
      upsert: jest.fn().mockResolvedValue({ data: null, error: null }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "session_bindings") return sessionBindingsQuery;
      throw new Error(`Unexpected table: ${table}`);
    });

    adminSupabase.rpc.mockResolvedValue({ data: 1, error: null });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/session-bind")
      .set("X-Device-Fingerprint", "device-fingerprint-456")
      .send({ deviceFingerprint: "device-fingerprint-456" });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(adminSupabase.rpc).toHaveBeenCalledWith("revoke_device_duplicate_session", {
      p_user_id: "auth-user-1",
      p_fingerprint: expect.any(String),
      p_keep_session: "session-1",
    });
  });


  test("proxies partner invite requests through the RPC layer", async () => {
    adminSupabase.rpc.mockResolvedValue({
      data: 99,
      error: null,
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite")
      .send({
        email: "partner@example.com",
        partnershipCode: "ABC123",
      });

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      success: true,
      data: 99,
    });
    expect(adminSupabase.rpc).toHaveBeenCalledWith("request_partnership", {
      partner_email: "partner@example.com",
      partner_code: "ABC123",
      override_sender_id: 42,
    });
  });

  test("surfaces the RPC error code raised by request_partnership", async () => {
    adminSupabase.rpc.mockResolvedValue({
      data: null,
      error: { message: "API-VALIDATION-005: Invalid partner email or code" },
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite")
      .send({
        email: "partner@example.com",
        partnershipCode: "ABC123",
      });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-005");
    expect(response.body.error.message).toBe("Invalid partner email or code");
  });

  test("dispatches the Supabase invite email for a new partner address", async () => {
    adminSupabase.auth.admin.inviteUserByEmail.mockResolvedValue({
      data: { user: { id: "invited-user-1" } },
      error: null,
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite-user")
      .send({
        email: "new-partner@example.com",
        redirectTo: "justus://auth/callback",
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(adminSupabase.auth.admin.inviteUserByEmail).toHaveBeenCalledWith(
      "new-partner@example.com",
      { redirectTo: "justus://auth/callback" }
    );
  });

  test("omits redirectTo when the client sends none", async () => {
    adminSupabase.auth.admin.inviteUserByEmail.mockResolvedValue({
      data: { user: { id: "invited-user-2" } },
      error: null,
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite-user")
      .send({ email: "new-partner@example.com" });

    expect(response.status).toBe(200);
    expect(adminSupabase.auth.admin.inviteUserByEmail).toHaveBeenCalledWith(
      "new-partner@example.com",
      undefined
    );
  });

  test("refuses an invite when the address already has an account", async () => {
    adminSupabase.auth.admin.inviteUserByEmail.mockResolvedValue({
      data: { user: null },
      error: {
        code: "email_exists",
        message: "A user with this email address has already been registered",
      },
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite-user")
      .send({ email: "existing@example.com" });

    // GoTrue is the authority on "already registered": the 422 is remapped to
    // a 409 the client can translate into "ask your partner for their code".
    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe("API-VALIDATION-002");
  });

  test("reports an unexpected invite dispatch failure as a server error", async () => {
    adminSupabase.auth.admin.inviteUserByEmail.mockResolvedValue({
      data: { user: null },
      error: { code: "unexpected_failure", message: "smtp refused" },
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/invite-user")
      .send({ email: "new-partner@example.com" });

    expect(response.status).toBe(500);
    expect(response.body.error.code).toBe("API-FAIL-001");
  });

  test("rejects a malformed invite payload", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/invite-user")
      .send({ email: "not-an-email" });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
    expect(adminSupabase.auth.admin.inviteUserByEmail).not.toHaveBeenCalled();
  });
});

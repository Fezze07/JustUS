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
      capabilities: ["can_ai_call", "can_media_upload"],
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

  test("revokes only the caller's own device token row", async () => {
    const userDevicesQuery = createQueryBuilder();

    adminSupabase.from.mockImplementation((table) => {
      if (table === "user_devices") {
        return userDevicesQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/device-token-revoke")
      .send({ deviceToken: "fcm-token-that-is-long-enough" });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(userDevicesQuery.delete).toHaveBeenCalledWith();
    // Scoping by user_id matters: device_token is UNIQUE, so a stale client
    // could otherwise delete the row a second account just registered.
    expect(userDevicesQuery.eq).toHaveBeenCalledWith(
      "device_token",
      "fcm-token-that-is-long-enough",
    );
    expect(userDevicesQuery.eq).toHaveBeenCalledWith("user_id", 42);
  });

  test("reports a failed device token revoke instead of swallowing it", async () => {
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
      .post("/api/v1/auth/device-token-revoke")
      .send({ deviceToken: "fcm-token-that-is-long-enough" });

    expect(response.status).toBe(500);
    expect(response.body.error.code).toBe("DB-WRITE-001");
  });

  test("rejects a malformed device token revoke payload", async () => {
    const app = createApp();

    const response = await request(app)
      .post("/api/v1/auth/device-token-revoke")
      .send({ deviceToken: "too-short" });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
  });

  test("syncs a backend session and returns a binding secret", async () => {
    const authSessionsQuery = createQueryBuilder({
      maybeSingle: jest.fn().mockResolvedValue({
        data: {
          ip_address: "10.0.0.1",
          country_code: "IT",
          binding_secret: "binding-secret-123",
          request_profile_hash: "old-profile-hash",
        },
        error: null,
      }),
      upsert: jest.fn().mockResolvedValue({ data: null, error: null }),
    });

    adminSupabase.from.mockImplementation((table) => {
      if (table === "auth_sessions") {
        return authSessionsQuery;
      }
      throw new Error(`Unexpected table: ${table}`);
    });

    const app = createApp();
    const response = await request(app)
      .post("/api/v1/auth/session-sync")
      .set("X-Device-Fingerprint", "device-fingerprint-123")
      .set("X-Client-User-Agent", "justus/test")
      .send({
        deviceFingerprint: "device-fingerprint-123",
        deviceLabel: "android-client",
      });

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.bindingSecret).toBe("binding-secret-123");
    expect(Array.isArray(response.body.anomalies)).toBe(true);
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
});

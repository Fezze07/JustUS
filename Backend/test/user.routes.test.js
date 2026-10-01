const request = require("supertest");

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
    next();
  })
);

jest.mock("../features/media/r2.service", () => ({
  isConfigured: jest.fn(() => true),
  deleteObjectsByPrefix: jest.fn(async () => 0),
}));

jest.mock("../utils/misc/partnershipUtils", () => ({
  getPartnerId: jest.fn(async () => 77),
}));

const {
  authenticateToken,
  adminSupabase,
  deleteObjectsByPrefix,
  resetRateLimitState,
} = require("../all_imports");
const { createApp } = require("../app");

describe("user routes", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // /wipe sits behind userRateLimit (max 5 requests per minute per profileId)
    // and the buckets are module-level, so every test would otherwise start at
    // the previous test's count. With 5 cases that suite sat exactly on the
    // limit boundary and the 6th test would have failed with an unrelated 429.
    resetRateLimitState();
    // `clearAllMocks` resets recorded calls but NOT implementations, so the
    // `.mockRejectedValue` installed by the "R2 cleanup fails" case used to
    // stick for the rest of the file and turn every later wipe into a 500.
    deleteObjectsByPrefix.mockResolvedValue(0);
    authenticateToken.mockImplementation((req, _res, next) => {
      req.user = {
        id: "auth-user-1",
        profileId: 42,
        publicEmail: "user@example.com",
        capabilities: ["can_ai_call", "can_media_upload"],
        role: "user",
      };
      next();
    });
  });

  test("wipes user data through the versioned users endpoint", async () => {
    adminSupabase.rpc.mockResolvedValue({ error: null });
    const app = createApp();

    const response = await request(app).post("/api/v1/users/wipe").send({});

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(adminSupabase.rpc).toHaveBeenCalledWith("debug_wipe_user_data", {
      p_user_id: 42,
    });
  });

  test("deletes R2 objects under the user and partner prefixes after a wipe", async () => {
    adminSupabase.rpc.mockResolvedValue({ error: null });
    const app = createApp();

    const response = await request(app).post("/api/v1/users/wipe").send({});

    expect(response.status).toBe(200);
    expect(deleteObjectsByPrefix).toHaveBeenCalledTimes(4);
    for (const prefix of [
      "uploads/42/",
      "profile/42/",
      "uploads/77/",
      "profile/77/",
    ]) {
      expect(deleteObjectsByPrefix).toHaveBeenCalledWith(prefix);
    }
  });

  test("returns a declared storage error when R2 wipe cleanup fails", async () => {
    adminSupabase.rpc.mockResolvedValue({ error: null });
    deleteObjectsByPrefix.mockRejectedValue(new Error("R2 boom"));
    const app = createApp();

    const response = await request(app).post("/api/v1/users/wipe").send({});

    expect(response.status).toBe(500);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("SYS-FAIL-001");
  });

  test("returns a declared DB error when wipe RPC fails", async () => {
    adminSupabase.rpc.mockResolvedValue({ error: { message: "failure" } });
    const app = createApp();

    const response = await request(app).post("/api/v1/users/wipe").send({});

    expect(response.status).toBe(500);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("DB-WRITE-001");
  });

  test("returns a declared auth error when the profile id is missing", async () => {
    authenticateToken.mockImplementation((req, _res, next) => {
      req.user = {
        id: "auth-user-1",
        profileId: null,
      };
      next();
    });

    const app = createApp();
    const response = await request(app).post("/api/v1/users/wipe").send({});

    expect(response.status).toBe(401);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-001");
  });

  // Pins userRateLimit's budget (max 5 per minute per profileId), which was
  // previously implied only by the suite's own request count.
  test("rate limits repeated wipe attempts for the same user", async () => {
    adminSupabase.rpc.mockResolvedValue({ error: null });
    const app = createApp();

    for (let i = 0; i < 5; i++) {
      const res = await request(app).post("/api/v1/users/wipe").send({});
      expect(res.status).toBe(200);
    }

    const blocked = await request(app).post("/api/v1/users/wipe").send({});

    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe("SEC-BLOCK-001");
    // The refused attempt must not have wiped anything.
    expect(adminSupabase.rpc).toHaveBeenCalledTimes(5);
  });
});

const request = require("supertest");
const { createQueryBuilder } = require("./support/mockSupabase");
const { signRequest } = require("../all_imports");

// Mocking dependencies
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

// Mocking controllers to avoid business logic side effects
jest.mock("../features/ai/ai.controller", () => ({
  generateQuestionController: jest.fn((req, res) => res.status(200).json({ success: true, question: "test" })),
}));

jest.mock("../features/auth/auth.controller", () => ({
  invitePartnerController: jest.fn((req, res) => res.status(200).json({ success: true })),
  updateDeviceToken: jest.fn((req, res) => res.status(200).json({ success: true })),
  revokeDeviceToken: jest.fn((req, res) => res.status(200).json({ success: true })),
  checkLoginRiskController: jest.fn((req, res) => res.status(200).json({ success: true })),
  registerFailedLoginController: jest.fn((req, res) => res.status(200).json({ success: true })),
  syncSessionController: jest.fn((req, res) => res.status(200).json({ success: true, bindingSecret: "secret-123", anomalies: [] })),
  webCallbackController: jest.fn((req, res) => res.status(200).send("ok")),
  inviteCallbackController: jest.fn((req, res) => res.status(200).send("ok")),
}));

const { adminSupabase, authSupabase, resetRateLimitState } = require("../all_imports");
const { createApp } = require("../app");

// Helper to generate a mock JWT that authMiddleware can decode
function generateMockJWT(payload) {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" }), "utf8").toString("base64url");
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  return `${header}.${body}.signature`;
}

describe("Security Integration Tests", () => {
  let app;

  beforeAll(() => {
    app = createApp();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    // /ai/question sits behind aiRateLimit (ip 10/min, user 6/min) and the
    // buckets are module-level, so without this each test starts where the
    // previous one stopped and a later assertion can fail with an unrelated 429.
    resetRateLimitState();
  });

  describe("Authentication Middleware (JWT & Binding)", () => {
    const validUserPayload = {
      sub: "auth-user-1",
      email: "user@example.com",
      role: "authenticated",
      session_id: "session-123",
      iat: Math.floor(Date.now() / 1000) - 10,
      exp: Math.floor(Date.now() / 1000) + 300, // 5 minutes (well within 15 min limit)
    };

    const mockProfile = {
      id: 42,
      email: "user@example.com",
      auth_id: "auth-user-1",
      user_profiles: { display_name: "TestUser" },
      user_roles: [{ roles: { name: "user" } }],
    };

    const validInvitePayload = {
      email: "partner@example.com",
      partnershipCode: "ABC123",
    };

    test("PASS: Valid token and correct device binding", async () => {
      const token = generateMockJWT(validUserPayload);
      
      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: { id: "auth-user-1", email: "user@example.com" } },
        error: null,
      });

      adminSupabase.from.mockImplementation((table) => {
        if (table === "users") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({ data: mockProfile, error: null }),
          });
        }
        if (table === "auth_sessions") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({
              data: {
                session_id: "session-123",
                device_fingerprint_hash: "27bb7491278d5a3730469518b6264ddc70f665f98a0045c119f08c59bc0c07ff", // Full hash of 'device-123'
                binding_secret: "secret-123",
                expires_at: new Date(Date.now() + 86400000).toISOString(),
                revoked_at: null,
              },
              error: null,
            }),
          });
        }
        return createQueryBuilder();
      });

      const response = await request(app)
        .post("/api/v1/auth/invite")
        .set("Authorization", `Bearer ${token}`)
        .set("X-Device-Fingerprint", "device-123")
        .send(validInvitePayload);

      expect(response.status).toBe(200);
      expect(response.headers["x-response-watermark"]).toBeDefined();
    });

    test("FAIL: Missing Authorization header", async () => {
      const response = await request(app).post("/api/v1/auth/invite").send(validInvitePayload);
      expect(response.status).toBe(401);
      expect(response.body.error.code).toBe("AUTH-FAIL-002");
    });

    test("FAIL: Expired or Invalid JWT", async () => {
      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: null },
        error: { message: "JWT expired" },
      });

      const response = await request(app)
        .post("/api/v1/auth/invite")
        .set("Authorization", "Bearer expired-token")
        .send(validInvitePayload);

      expect(response.status).toBe(401);
      expect(response.body.error.code).toBe("AUTH-FAIL-001");
    });

    test("FAIL: Token lifetime policy violation", async () => {
      const longLivedPayload = {
        ...validUserPayload,
        iat: Math.floor(Date.now() / 1000) - 100000,
        exp: Math.floor(Date.now() / 1000) + 100000,
      };
      const token = generateMockJWT(longLivedPayload);

      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: { id: "auth-user-1" } },
        error: null,
      });

      const response = await request(app)
        .post("/api/v1/auth/invite")
        .set("Authorization", `Bearer ${token}`)
        .send(validInvitePayload);

      expect(response.status).toBe(401);
      expect(response.body.error.code).toBe("AUTH-FAIL-001");
    });

    test("FAIL: Device fingerprint mismatch", async () => {
      const token = generateMockJWT(validUserPayload);
      
      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: { id: "auth-user-1" } },
        error: null,
      });

      adminSupabase.from.mockImplementation((table) => {
        if (table === "users") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({ data: mockProfile, error: null }),
          });
        }
        if (table === "auth_sessions") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({
              data: {
                session_id: "session-123",
                device_fingerprint_hash: "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e",
                binding_secret: "secret-123",
                expires_at: new Date(Date.now() + 86400000).toISOString(),
                revoked_at: null,
              },
              error: null,
            }),
          });
        }
        return createQueryBuilder();
      });

      const response = await request(app)
        .post("/api/v1/auth/invite")
        .set("Authorization", `Bearer ${token}`)
        .set("X-Device-Fingerprint", "device-123") // Hash is 27bb... which won't match
        .send(validInvitePayload);

      expect(response.status).toBe(401);
      expect(response.body.error.code).toBe("AUTH-FAIL-006");
    });

    // A token that verifies cryptographically and passes the lifetime and
    // device-binding checks must still be rejected when the SERVER-side session
    // has been revoked or has expired. Without these cases a revoked session
    // keeps working until the JWT itself expires.
    describe("server-side session state", () => {
      const baseSession = {
        session_id: "session-123",
        // Full hash of 'device-123', matching the X-Device-Fingerprint below.
        device_fingerprint_hash:
          "27bb7491278d5a3730469518b6264ddc70f665f98a0045c119f08c59bc0c07ff",
        binding_secret: "secret-123",
        revoked_at: null,
      };

      // Returns a request function for a token that is cryptographically
      // valid, within its lifetime, and whose device binding matches — so the
      // ONLY reason it can be rejected is the server-side session state.
      const requestWithSession = (session) => {
        const token = generateMockJWT(validUserPayload);

        authSupabase.auth.getUser.mockResolvedValue({
          data: { user: { id: "auth-user-1" } },
          error: null,
        });

        adminSupabase.from.mockImplementation((table) => {
          if (table === "users") {
            return createQueryBuilder({
              maybeSingle: jest.fn().mockResolvedValue({ data: mockProfile, error: null }),
            });
          }
          if (table === "auth_sessions") {
            return createQueryBuilder({
              maybeSingle: jest.fn().mockResolvedValue({ data: session, error: null }),
            });
          }
          return createQueryBuilder();
        });

        return () =>
          request(createApp())
            .post("/api/v1/auth/invite")
            .set("Authorization", `Bearer ${token}`)
            .set("X-Device-Fingerprint", "device-123")
            .send(validInvitePayload);
      };

      test("PASS: a live, unrevoked, unexpired session is accepted", async () => {
        const send = requestWithSession({
          ...baseSession,
          expires_at: new Date(Date.now() + 86400000).toISOString(),
        });

        // Control case: proves the 401s below come from the session state and
        // not from a fixture that can never authenticate in the first place.
        expect((await send()).status).not.toBe(401);
      });

      test("FAIL: Revoked session is rejected even though the JWT is valid", async () => {
        const send = requestWithSession({
          ...baseSession,
          expires_at: new Date(Date.now() + 86400000).toISOString(),
          revoked_at: new Date().toISOString(),
        });

        expect((await send()).status).toBe(401);
      });

      // KNOWN SECURITY BUG (recorded, not fixed here).
      //
      // `authMiddleware.fetchSessionBinding` selects revoked_at but NOT
      // expires_at, so a server-side session that has expired is never
      // rejected. Access therefore survives session expiry for as long as the
      // JWT itself is valid, defeating logout/rotation paths that only close
      // the session row.
      //
      // `test.failing` keeps the suite green while this bug is open and turns
      // RED automatically once the middleware starts checking expires_at —
      // at which point this must be promoted to a plain `test`.
      test.failing(
        "FAIL: Expired server-side session is rejected",
        async () => {
          const send = requestWithSession({
            ...baseSession,
            expires_at: new Date(Date.now() - 60000).toISOString(),
            revoked_at: null,
          });

          expect((await send()).status).toBe(401);
        },
      );
    });
  });

  describe("Request Signing Middleware (requireSignedRequest)", () => {
    const validUserPayload = {
      sub: "auth-user-1",
      role: "authenticated",
      session_id: "session-123",
      iat: Math.floor(Date.now() / 1000) - 10,
      exp: Math.floor(Date.now() / 1000) + 300,
    };

    const mockProfile = {
      id: 42,
      auth_id: "auth-user-1",
      user_roles: [{ roles: { name: "user" } }],
    };

    const setupAuthSuccess = () => {
      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: { id: "auth-user-1" } },
        error: null,
      });

      adminSupabase.from.mockImplementation((table) => {
        if (table === "users") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({ data: mockProfile, error: null }),
          });
        }
        if (table === "auth_sessions") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({
              data: {
                session_id: "session-123",
                binding_secret: "secret-123",
                expires_at: new Date(Date.now() + 86400000).toISOString(),
                revoked_at: null,
              },
              error: null,
            }),
          });
        }
        if (table === "request_nonces") {
          return createQueryBuilder({
            insert: jest.fn().mockResolvedValue({ data: {}, error: null }),
          });
        }
        return createQueryBuilder();
      });
    };

    test("PASS: Correct HMAC signature and fresh nonce", async () => {
      setupAuthSuccess();
      const token = generateMockJWT(validUserPayload);
      const timestamp = Date.now();
      const nonce = "unique-nonce-1";
      const payload = {}; // AI schema expects optional type

      const { signature } = signRequest({
        secret: "secret-123",
        method: "POST",
        path: "/api/v1/ai/question",
        timestamp,
        nonce,
        payload,
      });

      const response = await request(app)
        .post("/api/v1/ai/question")
        .set("Authorization", `Bearer ${token}`)
        .set("x-request-timestamp", timestamp.toString())
        .set("x-request-nonce", nonce)
        .set("x-request-signature", signature)
        .send(payload);

      expect(response.status).toBe(200);
    });

    test("FAIL: Invalid HMAC signature", async () => {
      setupAuthSuccess();
      const token = generateMockJWT(validUserPayload);

      const response = await request(app)
        .post("/api/v1/ai/question")
        .set("Authorization", `Bearer ${token}`)
        .set("x-request-timestamp", Date.now().toString())
        .set("x-request-nonce", "nonce-1")
        .set("x-request-signature", "invalid-signature")
        .send({});

      expect(response.status).toBe(401);
      expect(response.body.error.message).toContain("Invalid request signature");
    });

    // Replay protection has TWO layers in consumeNonce: an in-process Map and
    // the `request_nonces` unique index. This test covers the in-process layer,
    // which is the one that actually fires for a replay inside one process.
    //
    // The previous version of this case also mocked a Postgres 23505 unique
    // violation and appeared to cover the DB layer, but it never did: the second
    // request is short-circuited by the in-memory Map before the insert is
    // reached, so the mocked violation was dead code. The DB layer has its own
    // case below, which is currently failing.
    test("FAIL: Replay of an identical signed request is rejected", async () => {
      setupAuthSuccess();
      const token = generateMockJWT(validUserPayload);
      const timestamp = Date.now();
      const nonce = "reused-nonce";
      const payload = {};

      const { signature } = signRequest({
        secret: "secret-123",
        method: "POST",
        path: "/api/v1/ai/question",
        timestamp,
        nonce,
        payload,
      });

      const send = () =>
        request(app)
          .post("/api/v1/ai/question")
          .set("Authorization", `Bearer ${token}`)
          .set("x-request-timestamp", timestamp.toString())
          .set("x-request-nonce", nonce)
          .set("x-request-signature", signature)
          .send(payload);

      expect((await send()).status).toBe(200);

      const replay = await send();

      expect(replay.status).toBe(429);
      expect(replay.body.error.message).toContain("Replay request detected");
    });

    // KNOWN SECURITY BUG (recorded, not fixed here).
    //
    // `consumeNonce` detects the duplicate only inside a `catch`, but the
    // supabase-js client RESOLVES a Postgres constraint violation as
    // `{ data: null, error: { code: "23505" } }` instead of rejecting, so the
    // catch never runs and a duplicate insert is reported as success. The
    // database layer therefore rejects nothing, and replay protection collapses
    // onto the per-process Map — which is empty after a restart and empty on
    // every other instance behind the load balancer.
    //
    // The request below uses a FRESH nonce so the in-memory Map cannot be what
    // refuses it: the database is the only remaining defence, and it lets the
    // replay through (200 instead of 429).
    //
    // `test.failing` keeps the suite green while this bug is open and turns RED
    // automatically once consumeNonce inspects the resolved `error`.
    test.failing(
      "FAIL: A replay is refused by the database when the in-process nonce cache misses",
      async () => {
        setupAuthSuccess();

        // Make the database report the duplicate exactly the way supabase-js
        // does: resolved with an `error`, never rejected.
        adminSupabase.from.mockImplementation((table) => {
          if (table === "request_nonces") {
            return {
              insert: jest.fn().mockResolvedValue({
                data: null,
                error: {
                  code: "23505",
                  message:
                    'duplicate key value violates unique constraint "request_nonces_pkey"',
                },
              }),
            };
          }
          if (table === "users") {
            return createQueryBuilder({ maybeSingle: jest.fn().mockResolvedValue({ data: mockProfile, error: null }) });
          }
          if (table === "auth_sessions") {
            return createQueryBuilder({
              maybeSingle: jest.fn().mockResolvedValue({
                data: {
                  session_id: "session-123",
                  binding_secret: "secret-123",
                  expires_at: new Date(Date.now() + 86400000).toISOString(),
                  revoked_at: null,
                },
                error: null,
              }),
            });
          }
          return createQueryBuilder();
        });

        const token = generateMockJWT(validUserPayload);
        const timestamp = Date.now();
        const nonce = "db-duplicate-nonce";
        const payload = {};

        const { signature } = signRequest({
          secret: "secret-123",
          method: "POST",
          path: "/api/v1/ai/question",
          timestamp,
          nonce,
          payload,
        });

        const response = await request(app)
          .post("/api/v1/ai/question")
          .set("Authorization", `Bearer ${token}`)
          .set("x-request-timestamp", timestamp.toString())
          .set("x-request-nonce", nonce)
          .set("x-request-signature", signature)
          .send(payload);

        expect(response.status).toBe(429);
      },
    );
  });

  describe("Authorization (Capabilities)", () => {
    test("FAIL: Missing capability 'can_ai_call'", async () => {
      authSupabase.auth.getUser.mockResolvedValue({
        data: { user: { id: "limited-user" } },
        error: null,
      });

      adminSupabase.from.mockImplementation((table) => {
        if (table === "users") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({
              data: {
                id: 101,
                user_roles: [{ roles: { name: "guest" } }],
              },
              error: null,
            }),
          });
        }
        if (table === "auth_sessions") {
          return createQueryBuilder({
            maybeSingle: jest.fn().mockResolvedValue({
              data: {
                session_id: "session-limited",
                binding_secret: "secret-limited",
                expires_at: new Date(Date.now() + 86400000).toISOString(),
                revoked_at: null,
              },
              error: null,
            }),
          });
        }
        return createQueryBuilder();
      });

      const token = generateMockJWT({ 
        sub: "limited-user", 
        role: "authenticated", 
        session_id: "session-limited",
        iat: Math.floor(Date.now()/1000), 
        exp: Math.floor(Date.now()/1000)+300 
      });

      const timestamp = Date.now();
      const nonce = "nonce-cap-1";
      const { signature } = signRequest({
        secret: "secret-limited",
        method: "POST",
        path: "/api/v1/ai/question",
        timestamp,
        nonce,
        payload: {},
      });

      const response = await request(app)
        .post("/api/v1/ai/question")
        .set("Authorization", `Bearer ${token}`)
        .set("x-request-timestamp", timestamp.toString())
        .set("x-request-nonce", nonce)
        .set("x-request-signature", signature)
        .send({});

      expect(response.status).toBe(403);
      expect(response.body.error.code).toBe("SEC-AUTH-001");
    });
  });
});

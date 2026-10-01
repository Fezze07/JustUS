const request = require("supertest");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
}));

// The notify rate limiter is keyed by BOTH `req.user.profileId` and `req.ip`, and
// its buckets live in module-level state shared by every test in this file.
//
// The IP rule (notify.send, 30/min) is the trap: supertest always reports the
// same loopback address, so that bucket is global to the file no matter how the
// tests are written. Before the reset below this suite fired exactly 30 requests
// and therefore passed with ZERO headroom — adding a single case made every
// later assertion fail with an unrelated 429. Unique profileIds solve the per-user
// rule; only resetRateLimitState() solves the IP one.
jest.mock("../middleware/authMiddleware", () => {
  return jest.fn((req, res, next) => {
    if (!req.headers.authorization) {
      // Using the actual class to ensure instanceof checks pass if needed
      const { AppError } = require("../all_imports");
      return next(new AppError({ errorKey: "AUTH_FAIL_002" }));
    }
    const profileId = Number(req.headers["x-test-profile-id"] ?? 1);
    req.user = {
      id: `auth-user-${profileId}`,
      profileId,
      publicEmail: `user${profileId}@example.com`,
      capabilities: [],
      role: "user",
    };
    next();
  });
});

// The controller is mocked because it talks to Supabase + R2, which have no
// test double here. The mock is asserted on below so the tests still prove the
// route actually reaches the handler instead of dying in a middleware.
jest.mock("../features/notifications/notify.controller", () => ({
  sendNotificationController: jest.fn((req, res) => {
    res.status(200).json({ success: true });
  }),
}));

const { resetRateLimitState } = require("../all_imports");
const { sendNotificationController } = jest.requireMock(
  "../features/notifications/notify.controller",
);

const { createApp } = require("../app");

// Matches notifySchema: { notificationKey, params?, receiverId? }.
// The previous fixture sent { title, body }, which no longer matches the
// schema at all — it "passed" by failing on a missing `notificationKey`, i.e.
// for an unrelated reason.
const validPayload = (overrides = {}) => ({
  notificationKey: "notify.partner.miss_you",
  params: { name: "Alex" },
  ...overrides,
});

describe("notify routes", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    resetRateLimitState();
  });

  test("rejects unauthenticated requests", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/notify/partner")
      .send(validPayload());

    expect(response.status).toBe(401);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("AUTH-FAIL-002");
    // Auth runs before the limiter and the controller.
    expect(sendNotificationController).not.toHaveBeenCalled();
  });

  test("delivers a schema-valid notification and reaches the controller", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "1001")
      .send(validPayload({ receiverId: 77 }));

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    // The positive path must reach the handler; otherwise this suite would
    // still pass with a route that never notifies anyone.
    expect(sendNotificationController).toHaveBeenCalledTimes(1);
    expect(sendNotificationController.mock.calls[0][0].user.profileId).toBe(
      1001,
    );
    expect(sendNotificationController.mock.calls[0][0].body.notificationKey).toBe(
      "notify.partner.miss_you",
    );
  });

  test("rejects a payload with no notificationKey and never calls the controller", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "1002")
      .send({ params: { name: "Alex" } });

    expect(response.status).toBe(400);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
    // Validation runs before the controller, so a rejected payload must not
    // have produced a notification.
    expect(sendNotificationController).not.toHaveBeenCalled();
  });

  test("rejects an over-long notificationKey (schema bound is 80)", async () => {
    const app = createApp();
    const response = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "1003")
      .send(validPayload({ notificationKey: "x".repeat(81) }));

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-001");
    expect(sendNotificationController).not.toHaveBeenCalled();
  });

  test("blocks users who exceed the notification rate limit", async () => {
    const app = createApp();
    // Dedicated profileId so this test owns its whole 12/minute bucket.
    const profileId = "2001";

    // The rate limit for notify.send is 12 requests per minute per user.
    for (let i = 0; i < 12; i++) {
      const res = await request(app)
        .post("/api/v1/notify/partner")
        .set("Authorization", "Bearer fake-token")
        .set("x-test-profile-id", profileId)
        .send(validPayload());

      expect(res.status).toBe(200);
    }

    // The 13th request should be blocked
    const blockedResponse = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", profileId)
      .send(validPayload());

    expect(blockedResponse.status).toBe(429);
    expect(blockedResponse.body.success).toBe(false);
    expect(blockedResponse.body.error.code).toBe("SEC-BLOCK-001");
    // A blocked request must advertise when the caller may retry.
    expect(blockedResponse.headers["retry-after"]).toBeDefined();
    // Exactly 12 notifications were delivered: the 13th must not have reached
    // the controller, otherwise the limiter is not actually gating delivery.
    expect(sendNotificationController).toHaveBeenCalledTimes(12);
  });

  test("the rate limit is per user, not global", async () => {
    const app = createApp();

    // Exhaust one user's bucket...
    for (let i = 0; i < 12; i++) {
      await request(app)
        .post("/api/v1/notify/partner")
        .set("Authorization", "Bearer fake-token")
        .set("x-test-profile-id", "3001")
        .send(validPayload());
    }
    const blocked = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "3001")
      .send(validPayload());
    expect(blocked.status).toBe(429);

    // ...a different user must be unaffected by it.
    const other = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "3002")
      .send(validPayload());
    expect(other.status).toBe(200);
  });

  // notify.send is createIpUserRateLimit({ ipMax: 30, userMax: 12 }): the user
  // rule is exercised above, the IP rule was not exercised at all. It is pinned
  // here because it is the constraint that caps how many requests this whole
  // file may make — supertest reports one loopback IP, so the 30/minute IP
  // bucket is shared by every test here.
  test("the IP rule caps the limiter at 30 requests per minute across users", async () => {
    const app = createApp();

    const statusFor = async (profileId) => {
      const res = await request(app)
        .post("/api/v1/notify/partner")
        .set("Authorization", "Bearer fake-token")
        .set("x-test-profile-id", String(profileId))
        .send(validPayload());
      return res.status;
    };

    // A distinct user per request, so the per-user rule (12/min) can never be
    // the one producing the 429 and the IP rule is isolated as the cause.
    for (let i = 0; i < 30; i++) {
      expect(await statusFor(4000 + i)).toBe(200);
    }

    // The 31st request is over the IP budget even though its user is brand new.
    const blocked = await request(app)
      .post("/api/v1/notify/partner")
      .set("Authorization", "Bearer fake-token")
      .set("x-test-profile-id", "4099")
      .send(validPayload());

    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe("SEC-BLOCK-001");
    expect(sendNotificationController).toHaveBeenCalledTimes(30);
  });
});
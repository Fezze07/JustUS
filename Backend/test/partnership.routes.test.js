const request = require("supertest");
const { createQueryBuilder } = require("./support/mockSupabase");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logError: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
  resolveDeviceId: jest.fn().mockResolvedValue(null),
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
      id: "auth-user-uuid",
      profileId: 42,
      publicEmail: "user@example.com",
      capabilities: [],
      role: "user",
    };
    next();
  })
);

jest.mock("../middleware/requireSignedRequest", () =>
  jest.fn(() => (_req, _res, next) => next())
);

jest.mock("../features/media/r2.service", () => ({
  deleteObjectsByPrefix: jest.fn(async () => 0),
}));

jest.mock("../features/notifications/notification.service", () => ({
  sendNotificationToUser: jest.fn(async () => undefined),
}));

const { adminSupabase, resetRateLimitState } = require("../all_imports");
const { deleteObjectsByPrefix } = require("../features/media/r2.service");
const { sendNotificationToUser } = require("../features/notifications/notification.service");
const { createApp } = require("../app");

const cancelledRow = (overrides = {}) => ({
  id: 5,
  user_id_1: 42,
  user_id_2: 77,
  status: "cancelled",
  cancel_requested_by: 77,
  cancel_expires_at: "2099-01-01T00:00:00Z",
  ...overrides,
});

const mockPartnershipRow = (row) => {
  const query = createQueryBuilder({
    maybeSingle: jest.fn().mockResolvedValue({ data: row, error: null }),
  });
  adminSupabase.from.mockReturnValue(query);
  return query;
};

const postAccept = () =>
  request(createApp())
    .post("/api/v1/partnership/cancel/accept")
    .send({ partnershipId: 5 });

describe("POST /api/v1/partnership/cancel/accept", () => {
  beforeEach(() => {
    adminSupabase.from.mockReset();
    adminSupabase.rpc.mockReset();
    adminSupabase.rpc.mockResolvedValue({ data: null, error: null });
    deleteObjectsByPrefix.mockClear();
    sendNotificationToUser.mockClear();
    // cancelRateLimit is createIpUserRateLimit({ ipMax: 30, userMax: 10 }) and
    // its buckets are module-level, so a previous run must not leak into this one.
    resetRateLimitState();
  });

  test("accepts as the non-requester member and sends the profile id to the RPC", async () => {
    mockPartnershipRow(cancelledRow());

    const response = await postAccept();

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ success: true });
    expect(adminSupabase.rpc).toHaveBeenCalledWith("partnership_cancel_accept", {
      p_partnership_id: 5,
      p_actor_id: 42,
    });
    expect(deleteObjectsByPrefix).toHaveBeenCalledWith("uploads/42/");
    expect(deleteObjectsByPrefix).toHaveBeenCalledWith("uploads/77/");
    expect(sendNotificationToUser).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 77, title: "cancellationAccepted" })
    );
  });

  test("rejects the requester with API-VALIDATION-012 and calls no RPC", async () => {
    mockPartnershipRow(cancelledRow({ cancel_requested_by: 42 }));

    const response = await postAccept();

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-012");
    expect(adminSupabase.rpc).not.toHaveBeenCalled();
  });

  test("rejects a non-member with API-VALIDATION-012 and calls no RPC", async () => {
    mockPartnershipRow(cancelledRow({ user_id_1: 77, user_id_2: 99 }));

    const response = await postAccept();

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-012");
    expect(adminSupabase.rpc).not.toHaveBeenCalled();
  });

  test("expires an overdue request and returns API-VALIDATION-014", async () => {
    mockPartnershipRow(cancelledRow({ cancel_expires_at: "2020-01-01T00:00:00Z" }));

    const response = await postAccept();

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe("API-VALIDATION-014");
    expect(adminSupabase.rpc).toHaveBeenCalledWith("partnership_expire_cancellations");
    expect(adminSupabase.rpc).not.toHaveBeenCalledWith(
      "partnership_cancel_accept",
      expect.anything()
    );
  });
});

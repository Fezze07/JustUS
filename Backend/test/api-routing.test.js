const request = require("supertest");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
}));

const { createApp } = require("../app");

describe("API routing", () => {
  test("serves health endpoints only under /api/v1", async () => {
    const app = createApp();

    const rootHealth = await request(app).get("/api/v1");
    expect(rootHealth.status).toBe(200);
    expect(rootHealth.text).toContain("Server JustUS attivo");

    const ping = await request(app).get("/api/v1/ping");
    expect(ping.status).toBe(200);
    expect(ping.body).toEqual({ status: "ok" });

    const legacyPing = await request(app).get("/ping");
    expect(legacyPing.status).toBe(404);
  });

  test("returns API_NOT_FOUND_001 for unknown /api/v1 routes", async () => {
    const app = createApp();

    const response = await request(app).get("/api/v1/does-not-exist");

    expect(response.status).toBe(404);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("API-NOT_FOUND-001");
  });

  test("keeps HTML callback pages outside the API namespace", async () => {
    const app = createApp();

    const authCallback = await request(app).get("/auth/callback");
    expect(authCallback.status).toBe(200);
    expect(authCallback.text).toContain("Email");

    const inviteCallback = await request(app).get("/auth/invite-callback");
    expect(inviteCallback.status).toBe(200);
    expect(inviteCallback.text).toContain("Invito");
  });
});

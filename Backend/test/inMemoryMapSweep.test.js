jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
  resolveDeviceId: jest.fn().mockResolvedValue(null),
}));

const {
  recordFailedLogin,
  resetAuthRiskState,
  sweepExpiredLoginAttempts,
} = require("../features/auth/authRisk.service");
const {
  getEntry,
  saveEntry,
  sweepExpiredResponses,
} = require("../core/infra/idempotencyStore");

const START = 1_700_000_000_000;
const MINUTE = 60_000;

describe("in-memory map sweeps", () => {
  let nowSpy;

  beforeEach(() => {
    resetAuthRiskState();
    sweepExpiredResponses(Number.MAX_SAFE_INTEGER);
    nowSpy = jest.spyOn(Date, "now").mockReturnValue(START);
  });

  afterEach(() => {
    nowSpy.mockRestore();
  });

  test("removes expired login attempts and keeps live ones", async () => {
    await recordFailedLogin({
      email: "expired@example.com",
      deviceFingerprint: "device-expired",
      ipAddress: "203.0.113.1",
    });

    nowSpy.mockReturnValue(START + 16 * MINUTE);
    await recordFailedLogin({
      email: "live@example.com",
      deviceFingerprint: "device-live",
      ipAddress: "203.0.113.2",
    });

    expect(sweepExpiredLoginAttempts()).toBe(1);

    nowSpy.mockReturnValue(START + 17 * MINUTE);
    const live = await recordFailedLogin({
      email: "live@example.com",
      deviceFingerprint: "device-live",
      ipAddress: "203.0.113.2",
    });
    expect(live.failures).toBe(2);
  });

  test("removes expired idempotency responses and keeps live ones", () => {
    const expiredLookup = { namespace: "sweep", key: "expired", userId: 42 };
    const liveLookup = { namespace: "sweep", key: "live", userId: 42 };

    saveEntry(expiredLookup, { statusCode: 200, body: { stale: true } });

    nowSpy.mockReturnValue(START + 24 * 60 * MINUTE + 1);
    saveEntry(liveLookup, { statusCode: 201, body: { fresh: true } });

    expect(sweepExpiredResponses()).toBe(1);
    expect(getEntry(expiredLookup)).toBeNull();
    expect(getEntry(liveLookup)).toEqual({
      statusCode: 201,
      body: { fresh: true },
      expiresAt: START + 48 * 60 * MINUTE + 1,
    });
  });

  test("registers unref'ed sweep intervals for both maps", () => {
    jest.resetModules();
    const unref = jest.fn();
    const setIntervalSpy = jest
      .spyOn(global, "setInterval")
      .mockReturnValue({ unref });

    require("../features/auth/authRisk.service");
    require("../core/infra/idempotencyStore");

    expect(setIntervalSpy).toHaveBeenCalledTimes(2);
    expect(setIntervalSpy).toHaveBeenNthCalledWith(1, expect.any(Function), 15 * MINUTE);
    expect(setIntervalSpy).toHaveBeenNthCalledWith(2, expect.any(Function), 15 * MINUTE);
    expect(unref).toHaveBeenCalledTimes(2);
  });
});

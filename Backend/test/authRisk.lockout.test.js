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
  checkLoginRisk,
  recordFailedLogin,
  resetAuthRiskState,
  sweepExpiredLoginAttempts,
} = require("../features/auth/authRisk.service");

const START = 1_700_000_000_000;
const MINUTE = 60_000;
const FAILURE = {
  email: "lockout@example.com",
  deviceFingerprint: "device-lockout-123",
  ipAddress: "203.0.113.9",
};

describe("login lockout expiry", () => {
  let nowSpy;

  beforeEach(() => {
    resetAuthRiskState();
    nowSpy = jest.spyOn(Date, "now").mockReturnValue(START);
  });

  afterEach(() => {
    nowSpy.mockRestore();
  });

  async function fail(times) {
    for (let i = 0; i < times; i++) {
      await recordFailedLogin(FAILURE);
    }
  }

  test("a 10-minute block set at minute 14 still blocks after minute 15", async () => {
    await fail(4);

    nowSpy.mockReturnValue(START + 14 * MINUTE);
    await fail(1);

    nowSpy.mockReturnValue(START + 15 * MINUTE);
    expect(sweepExpiredLoginAttempts()).toBe(0);
    expect(checkLoginRisk(FAILURE).blocked).toBe(true);

    nowSpy.mockReturnValue(START + 24 * MINUTE - 1);
    expect(checkLoginRisk(FAILURE).blocked).toBe(true);

    nowSpy.mockReturnValue(START + 24 * MINUTE);
    expect(checkLoginRisk(FAILURE).blocked).toBe(false);
  });

  test("a 30-minute block set at 14:59 survives the original 15-minute lifetime", async () => {
    await fail(7);

    nowSpy.mockReturnValue(START + 14 * MINUTE + 59_000);
    await fail(1);

    nowSpy.mockReturnValue(START + 15 * MINUTE);
    expect(sweepExpiredLoginAttempts()).toBe(0);
    expect(checkLoginRisk(FAILURE).blocked).toBe(true);

    nowSpy.mockReturnValue(START + 44 * MINUTE + 58_000);
    expect(checkLoginRisk(FAILURE).blocked).toBe(true);

    nowSpy.mockReturnValue(START + 44 * MINUTE + 59_000);
    expect(checkLoginRisk(FAILURE).blocked).toBe(false);
  });
});

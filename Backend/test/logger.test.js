jest.mock("../all_imports", () => ({
  adminSupabase: { from: jest.fn() },
}));

process.env.SUPABASE_LOG_TO_DB = "true";

const { AppError } = require("../core/errors/AppError");
const { adminSupabase } = require("../all_imports");
const {
  logAccess,
  logAppError,
  logAuthFailure,
  logError,
  logNotification,
  logSecurity,
  resolveDeviceId,
} = require("../core/logger");

const inserts = [];

adminSupabase.from.mockImplementation((table) => ({
  insert: jest.fn((record) => {
    inserts.push({ table, record });
    return Promise.resolve({ error: null });
  }),
  select: jest.fn(() => ({
    eq: jest.fn(() => ({
      limit: jest.fn(() => Promise.resolve({ data: [{ id: 42 }] })),
    })),
  })),
}));

const TABLE_BY_AREA = {
  AUTH: "logs_auth_failures",
  SEC: "logs_security_events",
};

// Column sets of the live tables (supabase/schemas/public/tables/logs_*.sql)
const TABLE_COLUMNS = {
  logs_api_access: ["request_id", "method", "path", "status_code", "duration_ms", "device_id"],
  logs_api_errors: ["request_id", "path", "method", "error_json", "device_id"],
  logs_security_events: ["request_id", "type", "path", "error_json", "device_id"],
  logs_auth_failures: [
    "request_id", "error_code", "error_message", "path", "user_id",
    "ip_address", "reason", "severity", "payload", "stack",
  ],
  logs_notifications: ["user_id", "type", "status"],
};

const UUID = "11111111-2222-4333-8444-555555555555";

function expectedTable(key) {
  return TABLE_BY_AREA[key.split("_")[0]] ?? "logs_api_errors";
}

function columnsOf(insert) {
  return Object.keys(insert.record).sort();
}

function expectedColumns(table) {
  return [...TABLE_COLUMNS[table]].sort();
}

beforeEach(() => {
  inserts.length = 0;
  jest.spyOn(console, "log").mockImplementation(() => {});
  jest.spyOn(console, "error").mockImplementation(() => {});
});

describe("logAppError area routing", () => {
  test("routes AUTH-FAIL-001 to logs_auth_failures", async () => {
    await logAppError({ code: "AUTH-FAIL-001", message: "Invalid token" });

    expect(inserts).toHaveLength(1);
    expect(inserts[0].table).toBe("logs_auth_failures");
    expect(inserts[0].record.error_code).toBe("AUTH-FAIL-001");
  });

  test("routes SEC-BLOCK-001 to logs_security_events", async () => {
    await logAppError({ code: "SEC-BLOCK-001", message: "Blocked" });

    expect(inserts).toHaveLength(1);
    expect(inserts[0].table).toBe("logs_security_events");
    expect(inserts[0].record.type).toBe("SEC-BLOCK-001");
    expect(inserts[0].record.error_json?.error_code).toBe("SEC-BLOCK-001");
  });

  test.each(Object.entries(AppError.CODES))(
    "routes %s to the table for its area",
    async (key, def) => {
      await logAppError({ code: def.code, message: def.message });

      expect(inserts).toHaveLength(1);
      expect(inserts[0].table).toBe(expectedTable(key));
      if (key.split("_")[0] === "AUTH") {
        expect(inserts[0].record.error_code).toBe(def.code);
      } else if (key.split("_")[0] === "SEC") {
        expect(inserts[0].record.type).toBe(def.code);
        expect(inserts[0].record.error_json?.error_code).toBe(def.code);
      } else {
        expect(inserts[0].record.error_json?.error_code).toBe(def.code);
      }
    }
  );
});

describe("every insert matches its table columns", () => {
  test("logAccess writes exactly the logs_api_access columns", async () => {
    await logAccess({
      request_id: UUID,
      method: "GET",
      path: "/api/v1/drive",
      status_code: 200,
      duration_ms: 12,
      device_id: 7,
      user_id: 3,
      ip_address: "1.2.3.4",
    });

    expect(inserts[0].table).toBe("logs_api_access");
    expect(columnsOf(inserts[0])).toEqual(expectedColumns("logs_api_access"));
    expect(inserts[0].record.device_id).toBe(7);
  });

  test("logError writes exactly the logs_api_errors columns", async () => {
    await logError({
      request_id: UUID,
      method: "POST",
      path: "/api/v1/partners",
      error_code: "DB-WRITE-001",
      error_message: "boom",
      user_id: 3,
      ip_address: "1.2.3.4",
      severity: "HIGH",
      device_id: 7,
      payload: { password: "secret" },
    });

    expect(inserts[0].table).toBe("logs_api_errors");
    expect(columnsOf(inserts[0])).toEqual(expectedColumns("logs_api_errors"));
    expect(inserts[0].record.method).toBe("POST");
    expect(inserts[0].record.path).toBe("/api/v1/partners");
    expect(inserts[0].record.error_json.payload).toEqual({ password: "[REDACTED]" });
  });

  test("logSecurity writes exactly the logs_security_events columns", async () => {
    await logSecurity({
      request_id: UUID,
      type: "rate_limit",
      path: "/api/v1/drive",
      user_id: 3,
      ip_address: "1.2.3.4",
      retry_after_seconds: 30,
      strike_level: 2,
      device_id: 7,
    });

    expect(inserts[0].table).toBe("logs_security_events");
    expect(columnsOf(inserts[0])).toEqual(expectedColumns("logs_security_events"));
    expect(inserts[0].record.device_id).toBe(7);
    expect(inserts[0].record.error_json.retry_after_seconds).toBe(30);
  });

  test("logAuthFailure writes exactly the logs_auth_failures columns", async () => {
    await logAuthFailure({
      request_id: UUID,
      error_code: "AUTH-FAIL-001",
      error_message: "Invalid token",
      path: "/api/v1/auth/login",
      user_id: 3,
      ip_address: "1.2.3.4",
      reason: "expired",
      severity: "HIGH",
      payload: { password: "secret" },
      stack: "Error: x",
    });

    expect(inserts[0].table).toBe("logs_auth_failures");
    expect(columnsOf(inserts[0])).toEqual(expectedColumns("logs_auth_failures"));
    expect(inserts[0].record.payload).toEqual({ password: "[REDACTED]" });
  });

  test("logNotification writes exactly the logs_notifications columns", async () => {
    await logNotification({ user_id: 3, type: "partner", status: "sent", extra: "dropped" });

    expect(inserts[0].table).toBe("logs_notifications");
    expect(columnsOf(inserts[0])).toEqual(expectedColumns("logs_notifications"));
  });

  test("logNotification caps type at the varchar(50) column limit", async () => {
    await logNotification({ user_id: 3, type: "x".repeat(80), status: "sent" });

    expect(inserts[0].record.type).toHaveLength(50);
  });

  test("a non-uuid request_id is nulled instead of rejecting the whole row", async () => {
    await logAccess({ request_id: "not-a-uuid", method: "GET", path: "/x" });

    expect(inserts[0].record.request_id).toBeNull();
  });
});

describe("resolveDeviceId", () => {
  test("returns the device row id of the session", async () => {
    await expect(resolveDeviceId(UUID)).resolves.toBe(42);
  });

  test("returns null without a session id", async () => {
    await expect(resolveDeviceId(null)).resolves.toBeNull();
  });
});

jest.mock("../all_imports", () => ({
  adminSupabase: { from: jest.fn() },
}));

process.env.SUPABASE_LOG_TO_DB = "true";

const { AppError } = require("../core/errors/AppError");
const { adminSupabase } = require("../all_imports");
const { logAppError } = require("../core/logger");

const inserts = [];

adminSupabase.from.mockImplementation((table) => ({
  insert: jest.fn((record) => {
    inserts.push({ table, record });
    return Promise.resolve({ error: null });
  }),
}));

const TABLE_BY_AREA = {
  AUTH: "logs_auth_failures",
  SEC: "logs_security_events",
};

function expectedTable(key) {
  return TABLE_BY_AREA[key.split("_")[0]] ?? "logs_api_errors";
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
  });

  test("routes SEC-BLOCK-001 to logs_security_events", async () => {
    await logAppError({ code: "SEC-BLOCK-001", message: "Blocked" });

    expect(inserts).toHaveLength(1);
    expect(inserts[0].table).toBe("logs_security_events");
  });

  test.each(Object.entries(AppError.CODES))(
    "routes %s to the table for its area",
    async (key, def) => {
      await logAppError({ code: def.code, message: def.message });

      expect(inserts).toHaveLength(1);
      expect(inserts[0].table).toBe(expectedTable(key));
      expect(inserts[0].record.error_code).toBe(def.code);
    }
  );
});

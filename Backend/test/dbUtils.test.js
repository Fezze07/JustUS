// wrapRpc: the code carried by a database RAISE becomes the API error code.
// The RPC functions raise '<CODE>: <developer text>', so the client can
// localize the failure instead of showing a raw Postgres message.
const { AppError, ERROR_CODES } = require("../core/errors/AppError");

jest.mock("../all_imports", () => ({
  AppError: require("../core/errors/AppError").AppError,
  ERROR_CODES: require("../core/errors/AppError").ERROR_CODES,
}));

const { wrapRpc } = require("../utils/db/dbUtils");

describe("wrapRpc", () => {
  test("return the data when the RPC succeeded", () => {
    expect(wrapRpc({ data: 99, error: null })).toBe(99);
  });

  test.each([
    ["API-VALIDATION-003: User not authenticated or invalid ID", "API-VALIDATION-003"],
    ["API-VALIDATION-004: Partnership request already exists", "API-VALIDATION-004"],
    ["API-VALIDATION-005: Invalid partner email or code", "API-VALIDATION-005"],
    ["API-VALIDATION-006: Cannot invite yourself", "API-VALIDATION-006"],
    ["API-VALIDATION-007: No active partnership found", "API-VALIDATION-007"],
  ])("maps %s to %s", (dbMessage, expectedCode) => {
    let thrown;
    try {
      wrapRpc({ data: null, error: { message: dbMessage } });
    } catch (err) {
      thrown = err;
    }

    expect(thrown).toBeInstanceOf(AppError);
    expect(thrown.code).toBe(expectedCode);
    // The code prefix is stripped: the message stays the developer note.
    expect(thrown.message).toBe(dbMessage.split(": ")[1]);
  });

  test("keeps the catalog message when the raise carries only the code", () => {
    let thrown;
    try {
      wrapRpc({ data: null, error: { message: "API-VALIDATION-007" } });
    } catch (err) {
      thrown = err;
    }

    expect(thrown.code).toBe("API-VALIDATION-007");
    expect(thrown.message).toBe(ERROR_CODES.API_VALIDATION_007.message);
  });

  test("falls back to API-VALIDATION-001 on an unrecognized raise", () => {
    let thrown;
    try {
      wrapRpc({ data: null, error: { message: "division by zero" } });
    } catch (err) {
      thrown = err;
    }

    expect(thrown.code).toBe("API-VALIDATION-001");
    expect(thrown.message).toBe("division by zero");
  });

  test("falls back when the message is missing", () => {
    let thrown;
    try {
      wrapRpc({ data: null, error: {} });
    } catch (err) {
      thrown = err;
    }

    expect(thrown.code).toBe("API-VALIDATION-001");
  });
});

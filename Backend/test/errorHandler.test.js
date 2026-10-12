const mockLogAppError = jest.fn();
const mockAppError = require("../core/errors/AppError").AppError;

jest.mock("../all_imports", () => ({
  AppError: mockAppError,
  logAppError: (...args) => mockLogAppError(...args),
  sanitizePayload: jest.requireActual("../core/logger").sanitizePayload,
}));

const { AppError } = require("../core/errors/AppError");

function loadHandler({ nodeEnv, details } = {}) {
  delete process.env.NODE_ENV;
  delete process.env.ENABLE_ERROR_DETAILS;
  if (nodeEnv !== undefined) process.env.NODE_ENV = nodeEnv;
  if (details !== undefined) process.env.ENABLE_ERROR_DETAILS = details;

  let handler;
  jest.isolateModules(() => {
    handler = require("../middleware/errorHandler");
  });
  return handler;
}

function makeRes() {
  return {
    headersSent: false,
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

function makeReq() {
  return {
    requestId: "req-1",
    method: "POST",
    originalUrl: "/api/v1/partners",
    body: { email: "a@b.c", password: "secret" },
    ip: "1.2.3.4",
    user: { profileId: "user-1" },
  };
}

const RAW_MESSAGE = "duplicate key value violates unique constraint users_pkey at /srv/app/db.js:42";

beforeEach(() => {
  process.env.NODE_ENV = "test";
  delete process.env.ENABLE_ERROR_DETAILS;
});

afterEach(() => {
  process.env.NODE_ENV = "test";
  delete process.env.ENABLE_ERROR_DETAILS;
});

describe("errorHandler response exposure", () => {
  test("NODE_ENV unset, details off: 500 body carries code and message only", async () => {
    const res = makeRes();
    const err = new AppError({
      errorKey: "DB_WRITE_001",
      message: RAW_MESSAGE,
      details: { sql: "insert into users ..." },
    });

    await loadHandler()(err, makeReq(), res, () => {});

    expect(res.statusCode).toBe(500);
    expect(res.body.error).toEqual({ code: "DB-WRITE-001", message: "Database write error" });
    expect(res.body.error).not.toHaveProperty("details");
    expect(res.body.error).not.toHaveProperty("stack");
    expect(JSON.stringify(res.body)).not.toContain("/srv/app/db.js");
  });

  test("NODE_ENV=staging, details off: unexpected error leaks no message, details or stack", async () => {
    const res = makeRes();

    await loadHandler({ nodeEnv: "staging" })(
      new Error('relation "users" does not exist at /srv/app/db.js:42'),
      makeReq(),
      res,
      () => {}
    );

    expect(res.body.error.code).toBe("SYS-FAIL-001");
    expect(res.body.error.message).toBe("Internal server error");
    expect(res.body.error).not.toHaveProperty("details");
    expect(res.body.error).not.toHaveProperty("stack");
    expect(JSON.stringify(res.body)).not.toContain("/srv/app/db.js");
  });

  test("ENABLE_ERROR_DETAILS=true exposes raw message, details and stack even in production", async () => {
    const res = makeRes();
    const err = new AppError({
      errorKey: "DB_WRITE_001",
      message: RAW_MESSAGE,
      details: { sql: "insert into users ..." },
    });

    await loadHandler({ nodeEnv: "production", details: "true" })(err, makeReq(), res, () => {});

    expect(res.body.error.message).toBe(RAW_MESSAGE);
    expect(res.body.error.details).toEqual({ sql: "insert into users ..." });
    expect(typeof res.body.error.stack).toBe("string");
  });
});

describe("errorHandler log record exposure", () => {
  test("details off: payload and stack are not written to the log record", async () => {
    const res = makeRes();

    await loadHandler({ nodeEnv: "staging" })(new Error("boom"), makeReq(), res, () => {});

    expect(mockLogAppError).toHaveBeenCalledTimes(1);
    const record = mockLogAppError.mock.calls[0][0];
    expect(record.payload).toBeUndefined();
    expect(record.stack).toBeUndefined();
    expect(record.request_id).toBe("req-1");
    expect(record.user_id).toBe("user-1");
    expect(record.code).toBe("SYS-FAIL-001");
  });

  test("details on: payload is sanitized and the stack is written", async () => {
    const res = makeRes();

    await loadHandler({ details: "true" })(new Error("boom"), makeReq(), res, () => {});

    const record = mockLogAppError.mock.calls[0][0];
    expect(record.payload).toEqual({ email: "a@b.c", password: "[REDACTED]" });
    expect(typeof record.stack).toBe("string");
  });
});

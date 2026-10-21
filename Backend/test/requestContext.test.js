jest.mock("../all_imports", () => ({}));

const requestContext = require("../middleware/requestContext");

const UUID = "11111111-2222-4333-8444-555555555555";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function run(headers) {
  const req = { headers };
  const next = jest.fn();
  requestContext(req, {}, next);
  return req;
}

describe("requestContext request id", () => {
  test("keeps a client supplied uuid", () => {
    expect(run({ "x-request-id": UUID }).requestId).toBe(UUID);
  });

  test("replaces a non-uuid header, the log tables store request_id as uuid", () => {
    const req = run({ "x-request-id": "not-a-uuid" });

    expect(req.requestId).not.toBe("not-a-uuid");
    expect(req.requestId).toMatch(UUID_RE);
  });

  test("generates a uuid when the header is missing", () => {
    expect(run({}).requestId).toMatch(UUID_RE);
  });
});

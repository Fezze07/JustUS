// Express 5 exposes req.query as a prototype getter with no setter, so the
// parsed/sanitized object must be installed with defineProperty; a plain
// `req.query = ...` is a silent no-op in these CommonJS modules.
const express = require("express");
const request = require("supertest");
const { z } = require("zod");

jest.mock("../all_imports", () => ({
  AppError: require("../core/errors/AppError").AppError,
}));

const validateRequest = require("../middleware/validateRequest");
const sanitizeRequest = require("../middleware/sanitizeRequest");

function errorResponder(err, _req, res, _next) {
  res.status(err.status ?? 500).json({ code: err.code });
}

function makeApp(...middleware) {
  const app = express();
  app.get(
    "/query",
    ...middleware,
    (req, res) => res.json({ query: req.query, pageType: typeof req.query.page })
  );
  app.use(errorResponder);
  return app;
}

describe("validateRequest query write-back", () => {
  const pageSchema = z.object({ page: z.coerce.number().int() });

  test("the handler receives the coerced number", async () => {
    const response = await request(makeApp(validateRequest({ query: pageSchema })))
      .get("/query")
      .query({ page: "3" });

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ query: { page: 3 }, pageType: "number" });
  });

  test("unknown keys are stripped before the handler runs", async () => {
    const response = await request(makeApp(validateRequest({ query: pageSchema })))
      .get("/query")
      .query({ page: "3", extra: "x" });

    expect(response.body.query).toEqual({ page: 3 });
  });

  test("an invalid query still fails with API-VALIDATION-001", async () => {
    const response = await request(makeApp(validateRequest({ query: pageSchema })))
      .get("/query")
      .query({ page: "nope" });

    expect(response.status).toBe(400);
    expect(response.body.code).toBe("API-VALIDATION-001");
  });
});

describe("sanitizeRequest query write-back", () => {
  test("strips control characters and trims query values", async () => {
    const response = await request(makeApp(sanitizeRequest())).get(
      "/query?q=%00%1Fhe%7Fllo%20"
    );

    expect(response.status).toBe(200);
    expect(response.body.query.q).toBe("hello");
  });

  test("the route validator can replace the sanitized object", async () => {
    const app = makeApp(
      sanitizeRequest(),
      validateRequest({ query: z.object({ q: z.string().min(1).max(20) }) })
    );

    const response = await request(app).get("/query?q=%00%20he%7Fllo%20");

    expect(response.body.query).toEqual({ q: "hello" });
  });
});

const { handleCors } = require("../utils/http/corsUtils");

function callHandleCors(origin, allowedOrigins) {
  return new Promise((resolve) => {
    const headers = {};
    const res = {
      header(key, value) {
        headers[key] = value;
      },
      status(code) {
        res.statusCode = code;
        return res;
      },
      end() {
        resolve({ error: null, headers });
      },
    };
    const req = {
      method: "GET",
      get: (name) =>
        name.toLowerCase() === "origin" ? origin : undefined,
    };
    handleCors(
      req,
      res,
      (error) => resolve({ error, headers }),
      allowedOrigins
    );
  });
}

describe("handleCors", () => {
  test("an empty allowlist rejects a public origin", async () => {
    const { error, headers } = await callHandleCors(
      "https://evil.example",
      []
    );

    expect(error.code).toBe("SEC-AUTH-001");
    expect(headers["Access-Control-Allow-Origin"]).toBeUndefined();
  });

  test("an empty allowlist still allows localhost in development", async () => {
    const previous = process.env.NODE_ENV;
    process.env.NODE_ENV = "development";
    try {
      const { error, headers } = await callHandleCors(
        "http://localhost:3000",
        []
      );

      expect(error).toBeUndefined();
      expect(headers["Access-Control-Allow-Origin"]).toBe(
        "http://localhost:3000"
      );
    } finally {
      process.env.NODE_ENV = previous;
    }
  });

  test("an explicit allowlist still admits a listed origin", async () => {
    const { error, headers } = await callHandleCors("https://app.example", [
      "https://app.example",
    ]);

    expect(error).toBeUndefined();
    expect(headers["Access-Control-Allow-Origin"]).toBe("https://app.example");
  });
});

const {
  canonicalizeRequest,
  computeBodyHash,
  generateBindingSecret,
  signRequest,
} = require("../all_imports");

// requestSigningService is the trust anchor of the whole write API: every
// mutating route verifies an HMAC built from these primitives, so a change that
// alters the canonical form silently invalidates every shipped client.

const SECRET = "secret-123";
const BASE = {
  secret: SECRET,
  method: "POST",
  path: "/api/v1/ai/question",
  timestamp: 1_700_000_000_000,
  nonce: "nonce-1",
  payload: { type: "romantico" },
};

describe("computeBodyHash", () => {
  test("hashes an object via its JSON serialisation", () => {
    expect(computeBodyHash({ a: 1, b: "x" })).toBe(computeBodyHash({ a: 1, b: "x" }));
    expect(computeBodyHash({ a: 1, b: "x" })).not.toBe(computeBodyHash({ a: 1, b: "y" }));
  });

  // undefined/null hash the empty string rather than throwing: the Flutter
  // client sends an empty body on some endpoints, and a throw there would be a
  // 500 with no useful cause.
  test("treats a missing payload as the empty body", () => {
    expect(computeBodyHash(undefined)).toBe(computeBodyHash(null));
    expect(computeBodyHash(undefined)).toBe(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
  });

  // ...but an EMPTY OBJECT is not the empty body. express.json() hands the
  // server `{}` for an empty JSON body, so a client that signs a missing payload
  // (or `null`) instead of `{}` gets a 401 that looks like a signing bug.
  test("distinguishes an empty-object payload from a missing one", () => {
    expect(computeBodyHash({})).not.toBe(computeBodyHash(undefined));
    expect(computeBodyHash({})).toBe(
      "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    );
  });

  test("hashes a string payload as-is instead of JSON-quoting it", () => {
    expect(computeBodyHash("raw")).not.toBe(computeBodyHash({ raw: undefined }));
    expect(computeBodyHash("raw")).toBe(computeBodyHash("raw"));
  });

  // Key order is the one thing JSON.stringify does NOT normalise, so a client
  // that builds its payload with the keys in a different order gets a different
  // signature for the same request. Pinned so the constraint stays visible.
  test("is sensitive to property order", () => {
    expect(computeBodyHash({ a: 1, b: 2 })).not.toBe(computeBodyHash({ b: 2, a: 1 }));
  });
});

describe("canonicalizeRequest", () => {
  test("joins the fields with dots and uppercases the method", () => {
    const canonical = canonicalizeRequest({
      method: "post",
      path: "/api/v1/ai/question",
      timestamp: 123,
      nonce: "n",
      bodyHash: "h",
    });

    expect(canonical).toBe("POST./api/v1/ai/question.123.n.h");
  });

  test("renders missing fields as empty strings instead of undefined", () => {
    const canonical = canonicalizeRequest({});

    expect(canonical).toBe("....");
    expect(canonical).not.toContain("undefined");
  });
});

describe("signRequest", () => {
  test("returns the body hash and canonical form alongside the signature", () => {
    const { bodyHash, canonical, signature } = signRequest(BASE);

    expect(bodyHash).toBe(computeBodyHash(BASE.payload));
    expect(canonical).toBe(
      `POST./api/v1/ai/question.${BASE.timestamp}.${BASE.nonce}.${bodyHash}`
    );
    expect(signature).toMatch(/^[0-9a-f]{64}$/);
  });

  test("is deterministic for the same inputs", () => {
    expect(signRequest(BASE).signature).toBe(signRequest(BASE).signature);
  });

  // Each of these is a field the server re-derives from the request, so a
  // signature that survived a change to any one of them would be a signature
  // that verifies on a different request.
  test.each([
    ["secret", { secret: "other-secret" }],
    ["method", { method: "PUT" }],
    ["path", { path: "/api/v1/media/delete" }],
    ["timestamp", { timestamp: BASE.timestamp + 1 }],
    ["nonce", { nonce: "nonce-2" }],
    ["payload", { payload: { type: "competitivo" } }],
  ])("changes the signature when %s changes", (_field, override) => {
    expect(signRequest({ ...BASE, ...override }).signature).not.toBe(
      signRequest(BASE).signature
    );
  });

  test("produces a usable signature when the payload key is absent entirely", () => {
    const { payload: _omitted, ...withoutPayload } = BASE;

    expect(signRequest(BASE).signature).toMatch(/^[0-9a-f]{64}$/);
    // `payload: undefined` and a missing key must canonicalise identically,
    // since express.json() hands the server either shape for an empty body.
    expect(signRequest({ ...BASE, payload: undefined }).signature).toBe(
      signRequest(withoutPayload).signature
    );
  });
});

describe("generateBindingSecret", () => {
  test("returns a 32-byte hex secret", () => {
    expect(generateBindingSecret()).toMatch(/^[0-9a-f]{64}$/);
  });

  test("never repeats", () => {
    const secrets = new Set(
      Array.from({ length: 50 }, () => generateBindingSecret())
    );

    expect(secrets.size).toBe(50);
  });
});

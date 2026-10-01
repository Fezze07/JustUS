const { hmacSha256, sha256 } = require("../all_imports");

// cryptoUtils backs request signing, the response watermark and the device
// fingerprint. Known-answer tests, because every one of those is a value the
// server and the Flutter client must agree on byte for byte — a silent change
// here would show up as a wall of unexplained 401s rather than a failing build.

describe("sha256", () => {
  // NIST/RFC test vectors.
  test.each([
    ["", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"],
    ["abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],
    [
      "The quick brown fox jumps over the lazy dog",
      "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
    ],
  ])("hashes %j to the known digest", (input, expected) => {
    expect(sha256(input)).toBe(expected);
  });

  test("hashes the UTF-8 bytes, not the JS string units", () => {
    // "città" is 5 UTF-16 units but 6 UTF-8 bytes; hashing the wrong encoding
    // produces a fingerprint the client can never reproduce.
    expect(sha256("città")).toBe(
      "74486d610c94568c13bdf76de467bf3fb915a5f6023979874dcd4cca877c0649"
    );
    expect(sha256("città")).not.toBe(sha256("citta"));
  });

  test("coerces a missing value to the empty string", () => {
    expect(sha256(undefined)).toBe(sha256(""));
    expect(sha256(null)).toBe(sha256(""));
  });
});

describe("hmacSha256", () => {
  // RFC 4231 test case 2.
  test("matches the RFC 4231 vector", () => {
    expect(hmacSha256("Jefe", "what do ya want for nothing?")).toBe(
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    );
  });

  test("returns a 64-character hex digest", () => {
    expect(hmacSha256("secret-123", "message")).toMatch(/^[0-9a-f]{64}$/);
  });

  test("changes when either the key or the message changes", () => {
    const base = hmacSha256("secret-123", "message");

    expect(hmacSha256("secret-124", "message")).not.toBe(base);
    expect(hmacSha256("secret-123", "messagf")).not.toBe(base);
  });

  // Signature verification is a plain !== in requireSignedRequest, so the case
  // of the hex output is part of the contract with the client.
  test("emits lower-case hex", () => {
    expect(hmacSha256("secret-123", "message")).toBe(
      hmacSha256("secret-123", "message").toLowerCase()
    );
  });

  test("coerces missing key and message to empty strings", () => {
    expect(hmacSha256(undefined, "message")).toBe(hmacSha256("", "message"));
    expect(hmacSha256("secret-123", undefined)).toBe(hmacSha256("secret-123", ""));
  });
});

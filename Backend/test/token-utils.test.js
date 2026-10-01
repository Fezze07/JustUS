const { decodeTokenClaims, validateTokenLifetime } = require("../all_imports");

// tokenUtils decides whether a Supabase JWT is short-lived enough for this
// backend. authenticateToken calls validateTokenLifetime for EVERY request, so a
// regression here either locks every user out or silently drops the policy.

const nowSec = () => Math.floor(Date.now() / 1000);

const encodeJwt = (claims) => {
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const body = Buffer.from(JSON.stringify(claims)).toString("base64url");
  return `${header}.${body}.signature`;
};

describe("validateTokenLifetime", () => {
  const MAX = 900;

  test("accepts a token exactly at the policy limit", () => {
    const iat = nowSec();

    expect(() => validateTokenLifetime({ iat, exp: iat + MAX }, MAX)).not.toThrow();
  });

  test("accepts a token shorter than the policy limit", () => {
    const iat = nowSec();

    expect(() => validateTokenLifetime({ iat, exp: iat + 60 }, MAX)).not.toThrow();
  });

  test("rejects a token longer than the policy limit", () => {
    const iat = nowSec();

    expect(() => validateTokenLifetime({ iat, exp: iat + MAX + 1 }, MAX)).toThrow(
      /Token lifetime exceeds policy/
    );
  });

  // The check is `iat -> exp`, not the time left before expiry: a token issued
  // 800s ago that expires in 100s is still inside the policy, even though only
  // 100s of usability remain.
  test("measures iat to exp, not the remaining validity", () => {
    const iat = nowSec() - 800;

    expect(() => validateTokenLifetime({ iat, exp: iat + MAX }, MAX)).not.toThrow();
    expect(() => validateTokenLifetime({ iat, exp: iat + MAX + 1 }, MAX)).toThrow(
      /Token lifetime exceeds policy/
    );
  });

  // Documented gap, kept as-is deliberately: authSupabase.auth.getUser() has
  // already rejected a token with no usable expiry by the time this runs, so the
  // missing-claim case is unreachable in practice. The assertions below exist to
  // pin that decision so a future change to the policy has to be deliberate.
  test.each([
    ["both claims missing", {}],
    ["iat missing", { exp: nowSec() + 1_000_000 }],
    ["exp missing", { iat: nowSec() }],
    ["claims are zero", { iat: 0, exp: 0 }],
  ])("does not throw when %s", (_label, claims) => {
    expect(() => validateTokenLifetime(claims, MAX)).not.toThrow();
  });

  test("coerces string claims", () => {
    // Supabase issues numeric claims, but a hand-built token in a test or an
    // upstream change to string claims must not silently bypass the policy.
    const iat = String(nowSec());

    expect(() =>
      validateTokenLifetime({ iat, exp: Number(iat) + MAX + 1 }, MAX)
    ).toThrow(/Token lifetime exceeds policy/);
  });
});

describe("decodeTokenClaims", () => {
  test("decodes the payload of a base64url token", () => {
    const claims = decodeTokenClaims(
      encodeJwt({ sub: "auth-user-1", role: "authenticated", session_id: "s1" }),
      { id: "fallback", email: "fallback@example.com" }
    );

    expect(claims).toEqual({
      sub: "auth-user-1",
      role: "authenticated",
      session_id: "s1",
    });
  });

  test("decodes a token whose payload contains non-ASCII characters", () => {
    const claims = decodeTokenClaims(encodeJwt({ sub: "u1", email: "città@example.com" }), {
      id: "fallback",
      email: "fallback@example.com",
    });

    expect(claims.email).toBe("città@example.com");
  });

  // Reached only when the token is unparseable, which in practice means
  // authSupabase accepted a token this function cannot read. The fallback keeps
  // authenticateToken running instead of crashing, so its shape matters.
  test("falls back to the Supabase user when the payload cannot be parsed", () => {
    const claims = decodeTokenClaims("not-a-jwt", {
      id: "auth-user-9",
      email: "user@example.com",
      aud: "authenticated",
    });

    expect(claims).toEqual({
      sub: "auth-user-9",
      email: "user@example.com",
      role: "authenticated",
    });
  });

  test("falls back to 'authenticated' when the user has no aud", () => {
    const claims = decodeTokenClaims("garbage", { id: "auth-user-9" });

    expect(claims.role).toBe("authenticated");
    expect(claims.sub).toBe("auth-user-9");
  });
});

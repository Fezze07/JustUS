const {
  hasCapability,
  normalizeCapabilities,
  normalizeRole,
  resolveCapabilities,
} = require("../all_imports");

// authorization.service decides what every authenticated caller may do.
// authenticateToken stamps its output on req.user, and authorizeCapabilities
// reads it on each gated route, so these functions sit directly on the path
// between a role in the database and access to the media/AI APIs.

describe("normalizeRole", () => {
  test.each(["user", "premium", "moderator", "system", "guest", "ai-worker"])(
    "keeps the known role %s",
    (role) => {
      expect(normalizeRole(role)).toBe(role);
    }
  );

  test("is case and whitespace insensitive", () => {
    expect(normalizeRole("  PREMIUM  ")).toBe("premium");
  });

  // Unknown roles must collapse to the least-privileged one, never to a default
  // that grants access.
  test.each([
    ["an unknown role", "superadmin"],
    ["a role removed from the app", "admin"],
    ["an empty string", ""],
    ["null", null],
    ["undefined", undefined],
  ])("maps %s to guest", (_label, role) => {
    expect(normalizeRole(role)).toBe("guest");
  });
});

describe("normalizeCapabilities", () => {
  test("passes an array through, trimming and dropping blanks", () => {
    expect(normalizeCapabilities([" can_ai_call ", "", "  ", "can_media_upload"])).toEqual([
      "can_ai_call",
      "can_media_upload",
    ]);
  });

  test("splits a comma-separated string", () => {
    expect(normalizeCapabilities("can_ai_call, can_media_upload")).toEqual([
      "can_ai_call",
      "can_media_upload",
    ]);
  });

  test("drops empty segments from a string", () => {
    expect(normalizeCapabilities("can_ai_call,,  ,can_media_upload")).toEqual([
      "can_ai_call",
      "can_media_upload",
    ]);
  });

  test("returns an empty list for anything else", () => {
    expect(normalizeCapabilities(undefined)).toEqual([]);
    expect(normalizeCapabilities(null)).toEqual([]);
    expect(normalizeCapabilities(42)).toEqual([]);
    expect(normalizeCapabilities({ can_ai_call: true })).toEqual([]);
  });
});

describe("resolveCapabilities", () => {
  test("gives a role its defaults when there are no custom capabilities", () => {
    expect(resolveCapabilities("premium", [])).toEqual(
      expect.arrayContaining(["can_upload_large", "can_ai_call", "can_media_upload"])
    );
  });

  test("grants a guest nothing by default", () => {
    expect(resolveCapabilities("guest", [])).toEqual([]);
  });

  test("merges custom capabilities on top of the role defaults", () => {
    const resolved = resolveCapabilities("user", ["can_moderate_content"]);

    expect(resolved).toEqual(
      expect.arrayContaining(["can_ai_call", "can_media_upload", "can_moderate_content"])
    );
  });

  // An unknown role collapses to guest, so a custom list must still be able to
  // grant a capability without the role default leaking back in.
  test("does not fall back to the 'user' defaults for an unknown role", () => {
    expect(resolveCapabilities("superadmin", [])).toEqual([]);
    expect(resolveCapabilities("superadmin", ["can_ai_call"])).toEqual(["can_ai_call"]);
  });

  test("de-duplicates a capability the role already grants", () => {
    expect(resolveCapabilities("user", ["can_ai_call"])).toEqual(
      expect.arrayContaining(["can_ai_call"])
    );
    expect(resolveCapabilities("user", ["can_ai_call"]).filter((c) => c === "can_ai_call")).toHaveLength(1);
  });
});

describe("hasCapability", () => {
  test("finds a granted capability", () => {
    expect(hasCapability(["can_ai_call", "can_media_upload"], "can_ai_call")).toBe(true);
  });

  test("does not match by prefix or substring", () => {
    expect(hasCapability(["can_ai"], "can_ai_call")).toBe(false);
    expect(hasCapability(["can_ai_call_all"], "can_ai_call")).toBe(false);
  });

  test("is false for an absent, empty or non-array capability list", () => {
    expect(hasCapability([], "can_ai_call")).toBe(false);
    expect(hasCapability(undefined, "can_ai_call")).toBe(false);
    expect(hasCapability("can_ai_call", "can_ai_call")).toBe(false);
  });
});

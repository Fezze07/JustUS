// Cross-side guard: every backend error code must have a Flutter handler and
// both ARB strings. Runs in Jest so a backend-only code cannot silently ship.
const fs = require("fs");
const path = require("path");
const { ERROR_CODES } = require("../core/errors/AppError");

const repoRoot = path.resolve(__dirname, "../..");
const read = (relative) => fs.readFileSync(path.join(repoRoot, relative), "utf8");

const dart = read("Flutter/lib/core/error_handling/error_codes.dart");
const arbEn = JSON.parse(read("Flutter/lib/core/localization/intl_en.arb"));
const arbIt = JSON.parse(read("Flutter/lib/core/localization/intl_it.arb"));

const constants = Object.fromEntries(
  [...dart.matchAll(/static const String (\w+)\s*=\s*'([^']+)';/g)].map(
    ([, name, code]) => [name, code]
  )
);

const switchBody = dart.slice(
  dart.indexOf("static String userMessage"),
  dart.indexOf("static bool requiresReauth")
);
const handled = new Set(
  [...switchBody.matchAll(/case (\w+):/g)].map(([, name]) => constants[name])
);

const arbKey = (code) =>
  "error_" +
  code
    .split(/[-_]/)
    .map((part, index) =>
      index === 0 ? part.toLowerCase() : part[0] + part.slice(1).toLowerCase()
    )
    .join("");

describe("error code drift", () => {
  test("every backend code has a Flutter handler and both translations", () => {
    const missing = Object.values(ERROR_CODES)
      .map((def) => def.code)
      .filter(
        (code) => !handled.has(code) || !arbEn[arbKey(code)] || !arbIt[arbKey(code)]
      );

    expect(missing).toEqual([]);
  });

  test("Flutter has no server code outside the backend catalog or the RPC allowlist", () => {
    const backendCodes = new Set(Object.values(ERROR_CODES).map((def) => def.code));
    const serverCodesBlock = dart.match(
      /static const List<String> serverCodes = \[([\s\S]*?)\];/
    )[1];
    const rpcCodes = new Set(
      [...serverCodesBlock.matchAll(/\b\w+\b/g)]
        .map(([name]) => constants[name])
        .filter(Boolean)
    );
    const clientOnly = new Set(["AUTH-FAIL-CRED", "AUTH-FAIL-CURRENT", "401"]);

    const unexplained = [...handled].filter(
      (code) =>
        !backendCodes.has(code) &&
        !rpcCodes.has(code) &&
        !clientOnly.has(code) &&
        !code.startsWith("LOCAL-")
    );

    expect(unexplained).toEqual([]);
  });
});

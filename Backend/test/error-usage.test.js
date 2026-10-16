// Guardrail: backend source raises only AppError, never a raw Error/Exception.
//
// A plain `throw new Error(...)` bypasses ERROR_CODES, so errorHandler can only
// answer with a generic 500 and no stable code for the client to localize. Use
// `throw new AppError({ errorKey: "AREA_TYPE_ID", message })` instead.

const fs = require("fs");
const path = require("path");

const BACKEND_ROOT = path.join(__dirname, "..");
const SKIP_DIRS = new Set(["node_modules", "test", ".git", "coverage"]);

function jsFilesUnder(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) {
        jsFilesUnder(path.join(dir, entry.name), acc);
      }
    } else if (entry.name.endsWith(".js")) {
      acc.push(path.join(dir, entry.name));
    }
  }
  return acc;
}

// `// throw new Error` examples in comments must not register as violations.
const stripComments = (src) =>
  src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

// Any `throw new X(...)` / `throw X(...)` whose class is not AppError. A bare
// `throw err;` rethrow has no call and is intentionally not matched.
const FORBIDDEN_THROW = /throw\s+(?:new\s+)?(?!AppError\b)([A-Za-z_$][\w$]*)\s*\(/;

describe("backend error usage", () => {
  test("the detector flags raw Errors and allows AppError", () => {
    expect(FORBIDDEN_THROW.test('throw new Error("x");')).toBe(true);
    expect(FORBIDDEN_THROW.test('throw Error("x");')).toBe(true);
    expect(FORBIDDEN_THROW.test('throw new AppError({ errorKey: "X" });')).toBe(
      false
    );
    expect(FORBIDDEN_THROW.test("throw err;")).toBe(false);
  });

  test("every backend throw uses AppError, never a raw Error", () => {
    const files = jsFilesUnder(BACKEND_ROOT);
    expect(files.length).toBeGreaterThan(20); // mis-rooted scan guard

    const violations = [];
    for (const file of files) {
      const rel = path.relative(BACKEND_ROOT, file).replace(/\\/g, "/");
      stripComments(fs.readFileSync(file, "utf8"))
        .split("\n")
        .forEach((line, index) => {
          const match = FORBIDDEN_THROW.exec(line);
          if (match) {
            violations.push(
              `${rel}:${index + 1} throws ${match[1]}(...) — use ` +
                "AppError({ errorKey })"
            );
          }
        });
    }

    expect(violations).toEqual([]);
  });
});

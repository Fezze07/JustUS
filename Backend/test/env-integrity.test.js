// `.env.test` is committed (see the .gitignore exception) because config/env.js
// throws on a missing required variable, which takes the whole Jest run down
// with a 0-test "suite failed to run". These cases guard the variables that
// failure mode depends on, so a new required variable in env.js cannot land
// without its test-env entry being noticed.

// Touching a getter on all_imports is what actually pulls config/env.js (and
// therefore loadEnv() -> dotenv) into this module registry. Doing it at module
// scope rather than inside a test keeps it order-independent, and it is the real
// version of "does the backend module graph even load?" - merely requiring
// all_imports proves nothing, because every one of its 138 entries is a lazy
// getter that is never evaluated.
const { env } = require("../all_imports");

const fs = require("fs");
const path = require("path");

const ENV_TEST = path.join(__dirname, "..", "..", ".env.test");
const ENV_EXAMPLE = path.join(__dirname, "..", "..", ".env.example");

// Keys from a `KEY=value` line, ignoring comments and blank lines.
function keysDeclaredIn(file) {
  return fs
    .readFileSync(file, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((line) => line.split("=")[0].trim())
    .filter((key) => /^[A-Z0-9_]+$/.test(key));
}

describe("Environment Integrity", () => {
  test("Required environment variables are set", () => {
    expect(process.env.ENV).toBe("test");
    expect(process.env.NODE_ENV).toBe("test");
  });

  test("Loading Backend/all_imports does not throw and exposes a config surface", () => {
    const allImports = require("../all_imports");

    expect(allImports).toBeDefined();
    expect(typeof allImports).toBe("object");
  });

  test("the backend env module resolves the committed .env.test", () => {
    expect(fs.existsSync(ENV_TEST)).toBe(true);
    expect(keysDeclaredIn(ENV_TEST).length).toBeGreaterThan(0);
    // env.js reads these through requireNonEmpty/requirePositiveNumber, so they
    // are the ones whose absence aborts the run instead of failing an assertion.
    expect(env.dataDir).toBeTruthy();
    expect(env.supabaseAnonKey).toBeTruthy();
    expect(env.maxAccessTokenLifetimeSec).toBeGreaterThan(0);
    expect(env.logRetentionDays).toBeGreaterThan(0);
  });

  // The drift alarm. A variable added to .env.example must get a .env.test
  // entry, because config/env.js reads its configuration from that file and a
  // missing required one aborts the entire suite.
  test("every variable in .env.example is declared in .env.test", () => {
    const missing = keysDeclaredIn(ENV_EXAMPLE).filter(
      (key) => !keysDeclaredIn(ENV_TEST).includes(key)
    );

    expect(missing).toEqual([]);
  });

  // env.js throws for these four at require time, so a missing entry is a total
  // suite failure rather than a readable assertion failure.
  test.each([
    "JUSTUS_DATA_DIR",
    "LOG_RETENTION_DAYS",
    "MAX_ACCESS_TOKEN_LIFETIME_SEC",
    "SUPABASE_ANON_KEY",
  ])("hard-required variable %s is set", (key) => {
    expect(process.env[key]).toBeTruthy();
  });

  test("the numeric knobs parse as positive integers", () => {
    for (const key of [
      "REQUEST_SIGNING_MAX_SKEW_MS",
      "MAX_ACCESS_TOKEN_LIFETIME_SEC",
      "LOG_RETENTION_DAYS",
    ]) {
      expect(Number.isInteger(Number(process.env[key]))).toBe(true);
      expect(Number(process.env[key])).toBeGreaterThan(0);
    }
  });

  // .env.test is committed, so a paste of real credentials here would be a
  // permanent leak and would make the suite talk to production.
  test("no test credential points at a real host", () => {
    expect(env.supabaseUrl).toMatch(/\.test\.local$|localhost/);
    expect(env.r2Endpoint).toMatch(/\.test\.local$|localhost/);
    expect(process.env.SUPABASE_LOG_TO_DB).toBe("false");
  });
});

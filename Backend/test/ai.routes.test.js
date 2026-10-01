const request = require("supertest");

jest.mock("../core/logger", () => ({
  logAppError: jest.fn().mockResolvedValue(undefined),
  logAccess: jest.fn().mockResolvedValue(undefined),
  logSecurity: jest.fn().mockResolvedValue(undefined),
  logAuthFailure: jest.fn().mockResolvedValue(undefined),
  sanitizePayload: jest.fn((payload) => payload),
  serializeError: jest.fn((error) => error?.message ?? String(error)),
}));

// axios is auto-mocked, so the upstream AI provider (and the mock-ai container
// started by scripts/test-all.sh) is never contacted here: every case below
// drives the provider response directly through axios.post.
jest.mock("axios");
const axios = require("axios");

jest.mock("../config/db", () => ({
  adminSupabase: {
    from: jest.fn(),
    rpc: jest.fn(),
  },
  authSupabase: {
    auth: {
      getUser: jest.fn(),
    },
  },
  createUserScopedClient: jest.fn(),
}));

jest.mock("../middleware/authMiddleware", () =>
  jest.fn((req, _res, next) => {
    req.user = {
      id: "auth-user-1",
      profileId: 42,
      publicEmail: "user@example.com",
      capabilities: ["can_media_upload", "can_ai_call"],
      role: "user",
    };
    next();
  })
);

jest.mock("../middleware/requireSignedRequest", () =>
  jest.fn(() => (_req, _res, next) => next())
);

jest.mock("../middleware/idempotencyMiddleware", () =>
  jest.fn(() => (_req, _res, next) => next())
);

const {
  env,
  resetCircuitState,
  resetQuotaState,
  resetRateLimitState,
} = require("../all_imports");
const { createApp } = require("../app");

// A response shaped exactly like an OpenRouter chat completion.
const upstreamCompletion = (content) => ({
  status: 200,
  data: {
    choices: [{ message: { content } }],
  },
});

describe("ai routes", () => {
  const askQuestion = (app) => request(app).post("/api/v1/ai/question").send({});

  let originalDailyLimit;
  let originalCircuitThreshold;

  beforeEach(() => {
    resetCircuitState();
    resetQuotaState();
    // aiRateLimit allows 6 requests/min per user and its buckets are module-level,
    // so without this reset every test starts at the previous test's count.
    resetRateLimitState();
    if (originalDailyLimit === undefined) {
      originalDailyLimit = env.aiDailyTokenLimit;
      originalCircuitThreshold = env.aiCircuitBreakerThreshold;
    }
    env.aiDailyTokenLimit = originalDailyLimit;
    env.aiCircuitBreakerThreshold = originalCircuitThreshold;
  });

  test("returns the question parsed out of the upstream completion", async () => {
    axios.post.mockResolvedValue(
      upstreamCompletion(
        JSON.stringify({ question: "Chi dei due organizza meglio una suite di test?" })
      )
    );

    const app = createApp();
    const response = await askQuestion(app);

    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
    expect(response.body.question).toBe("Chi dei due organizza meglio una suite di test?");
    expect(response.body.estimatedTokens).toBeGreaterThan(0);
  });

  test("unwraps a question the upstream wrapped in a markdown code fence", async () => {
    // Models frequently answer with ```json ... ``` despite being told not to;
    // cleanAiResponse has to strip it or the endpoint 500s.
    axios.post.mockResolvedValue(
      upstreamCompletion(
        '```json\n{"question":"Chi dei due porta i piatti?"}\n```'
      )
    );

    const app = createApp();
    const response = await askQuestion(app);

    expect(response.status).toBe(200);
    expect(response.body.question).toBe("Chi dei due porta i piatti?");
  });

  test("blocks requests when the daily AI quota is exceeded", async () => {
    // createAiQuestion reserves a fixed 120 tokens per call, so a limit below
    // that refuses every request.
    env.aiDailyTokenLimit = 100;

    const app = createApp();
    const response = await askQuestion(app);

    expect(response.status).toBe(429);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("SEC-BLOCK-001");
  });

  test("returns a fallback payload when the AI circuit is open", async () => {
    for (let failure = 0; failure < env.aiCircuitBreakerThreshold; failure += 1) {
      // Drive the breaker through the real service rather than poking the
      // circuit directly, so the onFailure wiring is part of what is covered.
      axios.post.mockRejectedValueOnce(new Error("Simulated axios network error"));
      await askQuestion(createApp());
    }

    const app = createApp();
    const response = await askQuestion(app);

    expect(response.status).toBe(500);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("SYS-FAIL-001");
    expect(response.body.error.details.fallbackQuestion).toBeDefined();
  });

  test("opens the circuit only after the configured number of failures", async () => {
    // Two failures below the threshold must NOT trip the breaker: the request
    // that trips it is the one that reports a declared failure, and only the
    // request AFTER it gets the fallback.
    env.aiCircuitBreakerThreshold = 2;

    axios.post.mockRejectedValue(new Error("Simulated axios network error"));

    const app = createApp();

    const first = await askQuestion(app);
    expect(first.status).toBe(500);
    expect(first.body.error.code).toBe("SYS-FAIL-001");
    expect(first.body.error.details?.fallbackQuestion).toBeUndefined();

    const second = await askQuestion(app);
    expect(second.status).toBe(500);
    expect(second.body.error.code).toBe("SYS-FAIL-001");
    expect(second.body.error.details?.fallbackQuestion).toBeUndefined();

    const third = await askQuestion(app);
    expect(third.status).toBe(500);
    expect(third.body.error.code).toBe("SYS-FAIL-001");
    expect(third.body.error.details.fallbackQuestion).toBeDefined();
  });

  test("recovers the circuit after a single upstream success", async () => {
    axios.post.mockRejectedValue(new Error("Simulated axios network error"));

    const app = createApp();
    await askQuestion(app);

    axios.post.mockResolvedValue(
      upstreamCompletion(JSON.stringify({ question: "Chi dei due si sveglia prima?" }))
    );

    const recovered = await askQuestion(app);
    expect(recovered.status).toBe(200);

    // onSuccess must have closed the circuit, so the next failure starts a
    // fresh count instead of inheriting the earlier one.
    axios.post.mockRejectedValue(new Error("Simulated axios network error"));
    const afterSuccess = await askQuestion(app);
    expect(afterSuccess.status).toBe(500);
    expect(afterSuccess.body.error.details?.fallbackQuestion).toBeUndefined();
  });

  test("fails with a declared error when the upstream returns no usable content", async () => {
    // 200 OK but an empty choices array: no fallback question either, because
    // the circuit is still closed.
    axios.post.mockResolvedValue({ status: 200, data: { choices: [] } });

    const app = createApp();
    const response = await askQuestion(app);

    expect(response.status).toBe(500);
    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe("SYS-FAIL-001");
    expect(response.body.error.details?.fallbackQuestion).toBeUndefined();
  });
});

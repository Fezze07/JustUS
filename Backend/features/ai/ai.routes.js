const express = require("express");

const router = express.Router();
const {
  createCompositeRateLimit,
  generateQuestionController,
  withIdempotency,
  ipKey,
  userKey,
  DEFAULT_WINDOW_MS,
} = require("../../all_imports");
const {
  chain,
  authenticated,
  capability,
  signed,
  validated,
  limited,
} = require("../../routes/routeHelpers");
const { aiSchema } = require("./ai.schemas");

const aiRateLimit = createCompositeRateLimit({
  name: "ai",
  message: "AI rate limit exceeded",
  rules: [
    { name: "ip",       windowMs: DEFAULT_WINDOW_MS,      max: 10, key: ipKey },
    { name: "user",     windowMs: DEFAULT_WINDOW_MS,      max: 6,  key: userKey },
    { name: "endpoint", windowMs: 10 * DEFAULT_WINDOW_MS, max: 20, key: () => "generate-question" },
  ],
});

router.post(
  "/question",
  ...chain(
    authenticated(),
    capability("can_ai_call"),
    limited(aiRateLimit),
    withIdempotency("ai-question"),
    signed("ai-question"),
    validated({ body: aiSchema })
  ),
  generateQuestionController
);

module.exports = router;

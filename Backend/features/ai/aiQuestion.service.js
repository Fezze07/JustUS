const {
  generateAIQuestion,
  tipiDomanda,
  estimateTokenCount,
  reserveAiTokens,
  canExecute,
  onFailure,
  onSuccess,
  logSecurity,
  AppError,
} = require("../../all_imports");

async function createAiQuestion({ user, type, ipAddress, endpointPath }) {
  const chosenType =
    type && tipiDomanda.includes(type)
      ? type
      : tipiDomanda[Math.floor(Math.random() * tipiDomanda.length)];

  const circuitState = canExecute("ai-question");
  if (!circuitState.allowed) {
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "AI temporarily unavailable",
      details: {
        fallbackQuestion: "Chi dei due sceglierebbe la meta migliore per una vacanza?",
        retryAfterMs: circuitState.retryAfterMs,
      },
    });
  }

  const budgetCheck = reserveAiTokens(user.profileId, 120);
  if (!budgetCheck.allowed) {
    await logSecurity({
      type: "ai_quota_exceeded",
      path: endpointPath,
      user_id: user.profileId,
      ip_address: ipAddress,
    });
    throw new AppError({
      errorKey: "SEC_BLOCK_001",
      message: "Daily AI quota exceeded",
      details: { remainingTokens: budgetCheck.remaining },
    });
  }

  const payload = await generateAIQuestion(chosenType);
  const usedTokens = estimateTokenCount(payload.question);
  onSuccess("ai-question");

  return {
    success: true,
    question: payload.question,
    remainingTokens: budgetCheck.remaining ?? 0,
    estimatedTokens: usedTokens,
  };
}

module.exports = {
  createAiQuestion,
  onAiQuestionFailure: onFailure,
};

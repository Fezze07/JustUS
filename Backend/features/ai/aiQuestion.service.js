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
  adminSupabase,
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

  const partnerNames = await getPartnerNames(user.profileId);
  const payload = await generateAIQuestion(chosenType, partnerNames);
  const usedTokens = estimateTokenCount(payload.question);
  onSuccess("ai-question");

  return {
    success: true,
    question: payload.question,
    remainingTokens: budgetCheck.remaining ?? 0,
    estimatedTokens: usedTokens,
  };
}

/**
 * Ottiene i nomi dei partner per un dato profilo.
 * @param {number} profileId - L'ID del profilo dell'utente.
 * @returns {Promise<{name1: string, name2: string}>} I nomi dei due partner.
 */
async function getPartnerNames(profileId) {
  try {
    // Utilizza la funzione PostgreSQL centralizzata via RPC
    const { data, error } = await adminSupabase.rpc("get_partnership_names", {
      p_user_id: profileId,
    });

    if (error || !data) {
      return { name1: "Partner 1", name2: "Partner 2" };
    }

    return {
      name1: data.name1,
      name2: data.name2,
    };
  } catch (_error) {
    return { name1: "Partner 1", name2: "Partner 2" };
  }
}

module.exports = {
  createAiQuestion,
  getPartnerNames,
  onAiQuestionFailure: onFailure,
};

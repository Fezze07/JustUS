const { env } = require("../../all_imports");

const aiDailyUsage = new Map();

function getDayKey() {
  return new Date().toISOString().slice(0, 10);
}

function reserveAiTokens(userId, tokens) {
  const dayKey = getDayKey();
  const key = `${userId}:${dayKey}`;
  const current = aiDailyUsage.get(key) ?? 0;
  if (current + tokens > env.aiDailyTokenLimit) {
    return {
      allowed: false,
      remaining: Math.max(env.aiDailyTokenLimit - current, 0),
    };
  }

  aiDailyUsage.set(key, current + tokens);
  return {
    allowed: true,
    remaining: Math.max(env.aiDailyTokenLimit - (current + tokens), 0),
    total: current + tokens,
  };
}

const resetQuotaState = () => {
  aiDailyUsage.clear();
};

module.exports = {
  reserveAiTokens,
  resetQuotaState,
};

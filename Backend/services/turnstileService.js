const crypto = require("crypto");
const axios = require("axios");
const { env } = require("../all_imports");

async function verifyTurnstileToken({ token, remoteIp }) {
  if (!env.turnstileEnabled) {
    return { success: true, skipped: true };
  }

  const response = await axios.post(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    {
      secret: env.turnstileSecretKey,
      response: token,
      remoteip: remoteIp,
      idempotency_key: crypto.randomUUID(),
    },
    {
      timeout: 10_000,
      headers: {
        "Content-Type": "application/json",
      },
    }
  );

  return response.data;
}

module.exports = { verifyTurnstileToken };

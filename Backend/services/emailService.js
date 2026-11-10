// =============================================================================
// emailService.js — Transactional email via the Resend HTTP API
//
// Used only for the partner invite. Supabase Auth keeps its own SMTP (Resend)
// for sign-up confirmation and password reset; the invite must not touch Auth.
// =============================================================================

const { AppError, env } = require("../all_imports");
const { buildInviteEmail } = require("../templates/inviteEmail");

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const SENDER = "JustUS <team@mail.justus.serverfede.eu>";

async function sendPartnerInviteEmail(email) {
  if (!env.resendApiKey) {
    throw new AppError({
      errorKey: "SYS_FAIL_001",
      message: "RESEND_API_KEY is not configured; cannot send the partner invite email.",
    });
  }

  let response;

  try {
    response = await globalThis.fetch(RESEND_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: SENDER,
        to: [email],
        subject: "Il tuo partner ti ha invitato su JustUS",
        html: buildInviteEmail({
          email,
          inviteUrl: `${env.appUrl}/auth/invite`,
          appUrl: env.appUrl,
        }),
      }),
      // Do not outlive the request: a hung Resend call must fail, not linger.
      signal: globalThis.AbortSignal.timeout(env.requestTimeoutMs),
    });
  } catch (cause) {
    throw new AppError({
      errorKey: "API_FAIL_001",
      message: "Invite email dispatch failed",
      cause,
    });
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new AppError({
      errorKey: "API_FAIL_001",
      message: `Invite email dispatch failed (${response.status}): ${detail.slice(0, 500)}`,
    });
  }
}

module.exports = { sendPartnerInviteEmail };

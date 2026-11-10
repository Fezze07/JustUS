// =============================================================================
// templates/inviteEmail.js — Plain partner-invite email (no Auth side effects)
//
// The link points to the informational landing page, never to a Supabase Auth
// verify URL: opening the email must not create or confirm an account.
// =============================================================================

const { escapeHtml } = require("./htmlEscape");

// eslint-disable-next-line max-lines-per-function -- email HTML is one block
function buildInviteEmail({ email, inviteUrl, appUrl }) {
  return `<!DOCTYPE html>
<html lang="it">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Invito Speciale su Just Us</title>
</head>
<body style="margin: 0; padding: 0; background-color: #020103; font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
    <table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #020103;">
        <tr>
            <td align="center" style="padding: 60px 20px;">

                <table border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 480px; background-color: #0d0a16; border-radius: 24px; border: 1px solid #251f35; box-shadow: 0 20px 40px rgba(0,0,0,0.4);">

                    <tr>
                        <td align="center" style="padding: 48px 40px 32px 40px;">
                            <table border="0" cellpadding="0" cellspacing="0">
                                <tr>
                                    <td style="background: linear-gradient(135deg, #bc61f5 0%, #7d35f2 100%); padding: 1px; border-radius: 12px;">
                                        <div style="background-color: #0d0a16; padding: 10px 22px; border-radius: 11px;">
                                            <span style="color: #ffffff; font-size: 20px; font-weight: 900; letter-spacing: -1px; display: block;">Just Us</span>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <tr>
                        <td style="padding: 0 48px; text-align: center;">
                            <h1 style="color: #ffffff; font-size: 28px; font-weight: 800; margin: 0 0 16px 0; letter-spacing: -0.8px; line-height: 1.2;">
                                Ti stanno aspettando!
                            </h1>
                            <p style="color: #a19bbd; font-size: 16px; line-height: 1.6; margin: 0 0 40px 0;">
                                Ehi! Qualcuno di speciale ti ha invitato a unirti a <strong style="color: #ffffff;">Just Us</strong> usando il tuo indirizzo <strong style="color: #ffffff;">${escapeHtml(email)}</strong>.<br><br>
                                È il momento di creare il vostro spazio riservato per condividere tutto quello che vi passa per la testa. Scarica l'app, registrati con questa email e conferma l'indirizzo che riceverai.
                            </p>
                        </td>
                    </tr>

                    <tr>
                        <td align="center" style="padding: 0 48px 48px 48px;">
                            <table border="0" cellpadding="0" cellspacing="0" width="100%">
                                <tr>
                                    <td align="center" bgcolor="#bc61f5" style="border-radius: 14px;">
                                        <a href="${escapeHtml(inviteUrl)}" target="_blank" style="display: block; padding: 20px 0; font-size: 16px; font-weight: 700; color: #ffffff; text-decoration: none; border-radius: 14px;">
                                            Scopri come iniziare
                                        </a>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <tr>
                        <td style="padding: 32px 48px; background-color: #120e1f; border-bottom-left-radius: 24px; border-bottom-right-radius: 24px; border-top: 1px solid #251f35;">
                            <p style="color: #6a648a; font-size: 11px; line-height: 1.5; margin: 0; text-align: center;">
                                Se non sai di cosa si tratta, ignora pure questa mail. <br>
                                Visita <a href="${escapeHtml(appUrl)}" style="color: #bc61f5; text-decoration: none;">${escapeHtml(appUrl)}</a> per saperne di più.
                            </p>
                            <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-top: 24px;">
                                <tr>
                                    <td align="center">
                                        <p style="color: #433e5a; font-size: 10px; margin: 0; text-transform: uppercase; letter-spacing: 2px; font-weight: 700;">
                                            JUST US &bull; ${new Date().getFullYear()}
                                        </p>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                </table>

            </td>
        </tr>
    </table>
</body>
</html>`;
}

module.exports = { buildInviteEmail };

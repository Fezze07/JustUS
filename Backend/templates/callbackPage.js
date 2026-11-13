// =============================================================================
// templates/callbackPage.js — Shared HTML template for auth callback pages
//
// Produces a dark-mode, mobile-friendly status page shown when a deep link
// falls back to the browser (e.g. email confirmation, partner invite).
//
// Usage:
//   const { buildCallbackPage } = require('../templates/callbackPage');
//   res.status(200).send(buildCallbackPage({
//     title: 'Email Confermata!',
//     body:  'Puoi chiudere questa pagina e tornare all\'app JustUs.',
//     icon:  '✅',
//   }));
// =============================================================================

const { escapeHtml } = require("./htmlEscape");

/**
 * Builds a self-contained HTML page for auth callback responses.
 *
 * @param {object} opts
 * @param {string}  opts.title  - Heading shown to the user (e.g. "Email Confermata!")
 * @param {string}  opts.body   - Paragraph text below the heading.
 * @param {string}  [opts.icon] - Emoji icon shown above the heading. Defaults to ✅.
 * @param {string}  [opts.lang] - HTML lang attribute. Defaults to "it".
 * @param {string}  [opts.pageTitle] - Browser tab title. Defaults to "JustUS".
 * @returns {string} A complete HTML document string.
 */

// eslint-disable-next-line max-lines-per-function -- page markup is one block
function buildCallbackPage({ title, body, icon = "✅", lang = "it", pageTitle = "JustUS" }) {
    return `<!DOCTYPE html>
<html lang="${lang}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${escapeHtml(pageTitle)}</title>
    <style>
        * { box-sizing: border-box; }
        body {
            margin: 0;
            padding: 60px 20px;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            background-color: #020103;
            color: #ffffff;
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            text-align: center;
        }
        .card {
            width: 100%;
            max-width: 480px;
            background-color: #0d0a16;
            border: 1px solid #251f35;
            border-radius: 24px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
            overflow: hidden;
        }
        .header { padding: 48px 40px 32px; }
        .logo {
            display: inline-block;
            padding: 1px;
            border-radius: 12px;
            background: linear-gradient(135deg, #bc61f5 0%, #7d35f2 100%);
            font-size: 20px;
            font-weight: 900;
            letter-spacing: -1px;
        }
        .logo span {
            display: block;
            padding: 10px 22px;
            border-radius: 11px;
            background-color: #0d0a16;
        }
        .content { padding: 0 48px 48px; }
        .icon { font-size: 48px; line-height: 1; margin-bottom: 20px; }
        h1 {
            margin: 0 0 16px;
            font-size: 28px;
            font-weight: 800;
            letter-spacing: -0.8px;
            line-height: 1.2;
            color: #ffffff;
        }
        p {
            margin: 0;
            color: #a19bbd;
            font-size: 16px;
            line-height: 1.6;
        }
        .footer {
            padding: 32px 48px;
            background-color: #120e1f;
            border-top: 1px solid #251f35;
        }
        .footer p {
            color: #433e5a;
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
    </style>
</head>
<body>
    <div class="card">
        <div class="header">
            <div class="logo"><span>JustUS</span></div>
        </div>
        <div class="content">
            <div class="icon">${escapeHtml(icon)}</div>
            <h1>${escapeHtml(title)}</h1>
            <p>${escapeHtml(body)}</p>
        </div>
        <div class="footer">
            <p>JUST US &bull; ${new Date().getFullYear()}</p>
        </div>
    </div>
</body>
</html>`;
}

module.exports = { buildCallbackPage };

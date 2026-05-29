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

/**
 * Builds a self-contained HTML page for auth callback responses.
 *
 * @param {object} opts
 * @param {string}  opts.title  - Heading shown to the user (e.g. "Email Confermata!")
 * @param {string}  opts.body   - Paragraph text below the heading.
 * @param {string}  [opts.icon] - Emoji icon shown above the heading. Defaults to ✅.
 * @param {string}  [opts.lang] - HTML lang attribute. Defaults to "it".
 * @param {string}  [opts.pageTitle] - Browser tab title. Defaults to "JustUs".
 * @returns {string} A complete HTML document string.
 */

function buildCallbackPage({ title, body, icon = "✅", lang = "it", pageTitle = "JustUs" }) {
    return `<!DOCTYPE html>
<html lang="${lang}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${escapeHtml(pageTitle)}</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #121212; color: #ffffff; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; text-align: center; }
        .container { background-color: #1e1e1e; padding: 40px; border-radius: 12px; box-shadow: 0 8px 16px rgba(0,0,0,0.5); max-width: 400px; width: 90%; }
        h1 { color: #4CAF50; font-size: 24px; margin-bottom: 16px; }
        p  { font-size: 16px; line-height: 1.5; margin-bottom: 24px; color: #cccccc; }
        .icon { font-size: 48px; margin-bottom: 16px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">${icon}</div>
        <h1>${escapeHtml(title)}</h1>
        <p>${escapeHtml(body)}</p>
    </div>
</body>
</html>`;
}

/** Minimal HTML escaping to prevent XSS if dynamic values are ever user-supplied. */
function escapeHtml(str) {
    return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

module.exports = { buildCallbackPage };

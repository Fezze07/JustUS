// =============================================================================
// templates/htmlEscape.js — Shared HTML escaping for server-rendered templates
// =============================================================================

/** Minimal HTML escaping to prevent XSS if dynamic values are ever user-supplied. */
function escapeHtml(str) {
  return String(str).replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ]
  );
}

module.exports = { escapeHtml };

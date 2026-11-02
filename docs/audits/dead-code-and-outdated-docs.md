# Dead Code & Outdated Documentation Audit

## Executive Summary

This audit evaluates the JustUS codebase for obsolete dependencies, stale documentation references, unused configuration items, deprecated utilities, and dead code declarations.

All findings are backed by empirical code search and file analysis across the Node.js backend, Flutter frontend, and Supabase schema layers.

---

## Findings Matrix Summary

No open findings. All issues recorded in this audit have been resolved; the item-by-item status lives in `todo.md` (Phase 7 — Dead code & docs hygiene).

---

## Resolved Items

| Item | Resolution |
| :--- | :--- |

While refreshing `README.md`, the same pass corrected other claims that had drifted from the code: repository-root env file resolution (`.env` / `.env.test` / `JUSTUS_ENV_FILE`) plus the variables that have no code default, the real test entry point (`npm run validate` → `scripts/test-all.sh`; the mock-AI server and Docker Compose file listed at the time were later deleted), Node/Flutter version constraints from `pubspec.yaml` and the ESLint/Jest toolchain, audio & PDF support in the shared drive, the tokenized light/dark theming and it/en localization, the backend/Flutter directory layout including `supabase/schemas/**`, and the Turnstile flow (Managed widget in the app, validated by Supabase Auth — the Node backend never verifies tokens, per `todo.md` 2.4).

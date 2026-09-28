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
| Ollama / Llama 3.2 AI engine references in `README.md` (feature bullet, tech-stack entry, prerequisite list) | `README.md` now documents the active **OpenRouter** chat-completions gateway (`Backend/config/aiConfig.js`): free-model fallback chain, per-user daily token quota, circuit breaker; Ollama removed from prerequisites and replaced by an `OPENROUTER_API_KEY` requirement |

While refreshing `README.md`, the same pass corrected other claims that had drifted from the code: repository-root env file resolution (`.env` / `.env.test` / `JUSTUS_ENV_FILE`) plus the variables that have no code default, the real test entry points (`npm run validate` → `scripts/test-all.sh`, `test/mock-ai/server.js`, `scripts/docker-compose.test.yml`), Node/Flutter version constraints from `pubspec.yaml` and the ESLint/Jest toolchain, audio & PDF support in the shared drive, the tokenized light/dark theming and it/en localization, the backend/Flutter directory layout including `supabase/schemas/**`, and the Turnstile flow (Managed widget in the app, validated by Supabase Auth — the Node backend never verifies tokens, per `todo.md` 2.4).

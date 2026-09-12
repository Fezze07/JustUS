# Dead Code & Outdated Documentation Audit

## Executive Summary

This audit evaluates the JustUS codebase for obsolete dependencies, stale documentation references, unused configuration items, deprecated utilities, and dead code declarations.

All findings are backed by empirical code search and file analysis across the Node.js backend, Flutter frontend, and Supabase schema layers.

---

## Findings Matrix Summary

| Category | Item | Location | Current Status | Risk / Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Outdated Docs** | Ollama / Llama 3.2 AI Engine References | [`README.md:23`](file:///f:/JustUS/README.md#L23), [`README.md:57`](file:///f:/JustUS/README.md#L57), [`README.md:67`](file:///f:/JustUS/README.md#L67) | **STALE** (Architecture migrated to OpenRouter AI Gateway in `aiConfig.js`) | Medium (Misleads setup prerequisites) |
| **Unused Dependency** | `multer` package | [`Backend/package.json:24`](file:///f:/JustUS/Backend/package.json#L24) | **DEAD DEPENDENCY** (Zero imports/requires in `Backend/`) | Low (Unnecessary npm bundle bloat) |
| **Unused Extension Helpers** | `maybeGt` & `toSingle` | [`shared/utils/extensions/supabase_query_extensions.dart`](file:///f:/JustUS/Flutter/lib/shared/utils/extensions/supabase_query_extensions.dart#L20-L35) | **DEAD CODE** (Zero callers across Flutter app) | Low (Dead code deadweight) |
| **Unused Capability** | `can_send_email` | [`Backend/features/auth/authorization.service.js:25`](file:///f:/JustUS/Backend/features/auth/authorization.service.js#L25) | **DECLARED BUT UNUSED** (Zero route middleware checks) | Low (Configuration noise) |
| **Inconsistent DB Function** | `cleanup_old_logs()` | [`supabase/schemas/public/functions/cleanup_old_logs.sql`](file:///f:/JustUS/supabase/schemas/public/functions/cleanup_old_logs.sql) | **PARTIALLY OBSOLETE** (30-day SQL cutoff conflicts with active Node 90-day retention) | Medium (Risk of data loss if executed) |

---

## Detailed Investigation

### 1. `multer` Dependency Analysis

* **File**: [`Backend/package.json`](file:///f:/JustUS/Backend/package.json#L24)
* **Declared Version**: `"multer": "^2.3.0"`
* **Evidence**:
  - Direct grep search for `multer` across `Backend/` returned **0 results** in source files (`.js`).
  - Media file uploads are handled directly via pre-signed Cloudflare R2 upload URLs or Supabase Storage SDK (`drive_repository.dart` / `drive.controller.js`), completely bypassing local HTTP multipart parsing.
* **Classification**: **DEAD DEPENDENCY**.
* **Remediation**: Remove `"multer"` from `Backend/package.json` (`npm uninstall multer`).

---

### 2. Ollama / Llama 3.2 AI Engine Documentation References

* **File**: [`README.md`](file:///f:/JustUS/README.md)
* **Stale Lines**:
  - Line 23: `Every 24 hours, a new question is generated using the integrated Llama 3.2 AI engine.`
  - Line 57: `- **AI Engine**: Ollama (Running Llama 3.2:3b locally or on-server).`
  - Line 67: `- Ollama (for AI features)`
* **Actual Code Implementation**:
  - [`Backend/config/aiConfig.js`](file:///f:/JustUS/Backend/config/aiConfig.js#L27-L36) uses **OpenRouter API Gateway**:
    ```javascript
    const MODELS = [
      "openrouter/free",
      "openai/gpt-oss-120b:free",
      "nvidia/nemotron-3-super:free"
    ];
    const url = "https://openrouter.ai/api/v1/chat/completions";
    ```
* **Classification**: **STALE DOCUMENTATION**.
* **Remediation**: Update `README.md` to reflect the active OpenRouter AI Gateway integration (`https://openrouter.ai`) and remove Ollama as an installation prerequisite.

---

### 3. Supabase Query Extension Dead Methods

* **File**: [`Flutter/lib/shared/utils/extensions/supabase_query_extensions.dart`](file:///f:/JustUS/Flutter/lib/shared/utils/extensions/supabase_query_extensions.dart#L20-L38)
* **Dead Methods**:
  - `maybeGt(String column, Object? value)` (Line 20) — 0 usages in `lib/`.
  - `toSingle()` (Line 35) — 0 usages in `lib/` (Repositories invoke Postgrest's native `.maybeSingle()` directly).
* **Classification**: **DEAD CODE**.
* **Remediation**: Delete `maybeGt` and `toSingle` from `supabase_query_extensions.dart`.

---

### 4. `can_send_email` System Capability

* **File**: [`Backend/features/auth/authorization.service.js`](file:///f:/JustUS/Backend/features/auth/authorization.service.js#L25)
* **Code Reference**: `"can_send_email"` assigned to `system` role.
* **Evidence**:
  - Project-wide search confirms `can_send_email` is never evaluated by `authorizeCapabilities` middleware or referenced in any controller/service.
  - As established in the Email Audit, no email dispatch mechanism exists in Node.js.
* **Classification**: **UNUSED CAPABILITY DECLARATION**.
* **Remediation**: Remove `can_send_email` from `authorization.service.js`.

---

### 5. `cleanup_old_logs()` SQL Function

* **File**: [`supabase/schemas/public/functions/cleanup_old_logs.sql`](file:///f:/JustUS/supabase/schemas/public/functions/cleanup_old_logs.sql)
* **Evidence**:
  - Hardcodes a 30-day cutoff (`now() - interval '30 days'`), while the active Node backend `retentionJob.js` defaults to a 90-day retention window (`LOG_RETENTION_DAYS = 90`).
  - Is not registered in any active `pg_cron` schedule migration.
* **Classification**: **OBSOLETE / INCONSISTENT SQL DEFINITION**.
* **Remediation**: Update `cleanup_old_logs.sql` to accept an explicit retention parameter defaulting to 90 days, matching `LOG_RETENTION_DAYS`.

---

## Recommended Cleanup Action Plan

1. **`Backend/package.json`**:
   - Run `npm uninstall multer` in `Backend/`.
2. **`README.md`**:
   - Replace Ollama/Llama 3.2 references with OpenRouter AI Gateway documentation.
3. **`supabase_query_extensions.dart`**:
   - Remove unused `maybeGt` and `toSingle` extension methods.
4. **`authorization.service.js`**:
   - Remove dead `can_send_email` string.

# Error-Handling Infrastructure & Flow Analysis

## Overview

This document provides a reverse-engineering analysis of the error-handling system in the JustUS application across the Flutter client, Node.js/Express backend server, and Supabase PostgreSQL logging architecture.

---

## End-to-End Error Flow Map

The complete lifecycle of an error from occurrence to logging and user presentation is mapped below:

```
[ Error Source ]
  (Database failure, Exception, HTTP Status, Network error, Validation failure)
                       │
                       ▼
[ Catch / Resolution Layer ]
  (Backend: asyncHandler / try-catch ──► AppError.from(err, errorKey))
  (Frontend: BaseRepository / _safeCall ──► ResultWrapper<T>)
                       │
                       ▼
[ Classification & Error Code Mapping ]
  (Backend: ERROR_CODES dictionary ──► HTTP Status + Severity)
  (Frontend: ErrorCodes.dart ──► Local / Remote Code Normalization)
                       │
                       ▼
[ Transport / Serialization Layer ]
  (Backend errorHandler.js ──► JSON: { success: false, request_id, error: { code, message, details, stack } })
  (DEBUG: exposes details & stack | PROD: sanitizes message & strips stack)
                       │
                       ▼
[ Client Parsing & UI Routing ]
  (ApiService ──► AppError.fromJson(json))
  (ErrorHandler.handle() ──► UI Decision Branch)
      ├── requiresReauth ──────► Reauthentication Dialog ──► Redirect /login
      ├── isCritical ──────────► Modal Error Dialog (DialogUtils.showError)
      └── Standard Error ──────► Global Floating Red Snackbar / Overlay Toast
                       │
                       ▼
[ Logging & Retention ]
  (Backend logger.js ──► Route by Code Area Prefix)
      ├── "AUTH" ────► logs_auth_failures
      ├── "SEC" ─────► logs_security_events
      └── Default ───► logs_api_errors
  (Frontend AnsiLogger ──► Console stdout with color tags)
```

---

## Error Model Specifications

### 1. Backend `AppError` ([`AppError.js`](file:///f:/JustUS/Backend/core/errors/AppError.js))
- Extends native JavaScript `Error`.
- Structured Error Codes following format `<AREA>-<TYPE>-<ID>` (e.g. `AUTH-FAIL-001`, `DB-WRITE-001`, `SEC-BLOCK-001`).
- **Severity Mapping**:
  - `status >= 500` $\rightarrow$ `HIGH`
  - `status === 429` $\rightarrow$ `MEDIUM`
  - `status >= 400` $\rightarrow$ `LOW`

### 2. Frontend `AppError` ([`app_error.dart`](file:///f:/JustUS/Flutter/lib/core/error_handling/app_error.dart))
- Implements Dart `Exception`.
- Factory `AppError.fromJson(json)` parses backend JSON error envelope.
- Method `userMessage(loc)` maps error code to localized string via `ErrorCodes.userMessage(code, loc)`.
- Flag `requiresReauth`: True for `AUTH-FAIL-001`, `002`, `003`, `006`.
- Flag `isCritical`: True if `requiresReauth` or `SEC-BLOCK-001` / `SEC-BLOCK-002`.

---

## User Presentation Controls

| Error Type | Presentation Mechanism | Behavior / Appearance |
|---|---|---|
| **Reauthentication Required** (`requiresReauth`) | Modal Alert Dialog | Barrier non-dismissible dialog explaining session expiration. Action button navigates to `/login` and wipes route stack. |
| **Critical System / Security Block** (`isCritical`) | Red Critical Dialog | Displayed via `DialogUtils.showError()`. Shows title, message, error code, and expandable debug details if present. |
| **Non-Critical API / Network Errors** | Floating Overlay Toast / Snackbar | Displayed via global `OverlayEntry`. Renders at bottom of screen above software keyboard in red background (`Colors.red.shade800`). Automatically auto-dismisses after 4s in production; remains open indefinitely in debug mode until closed manually. |

---

## Backend Logging Infrastructure & Supabase Tables

All structured logs are handled by [`logger.js`](file:///f:/JustUS/Backend/core/logger.js) and dispatched based on `SUPABASE_LOG_TO_DB === "true"`.

| Table Name | Trigger / Log Function | Logged Data Fields | Sensitive Data Handling |
|---|---|---|---|
| `logs_api_access` | `logAccess(record)` | `request_id`, `method`, `path`, `status_code`, `user_id`, `ip_address`, `duration_ms` | No payload logged. |
| `logs_api_errors` | `logError(record)` / `logAppError` | `request_id`, `error_code`, `error_message`, `severity`, `user_id`, `endpoint`, `payload`, `stack`, `ip_address` | Body sanitized via `sanitizePayload()`. Stack stripped in production. |
| `logs_auth_failures` | `logAuthFailure(record)` | `request_id`, `path`, `email`, `ip_address`, `reason`, `error_code` | Email included, credentials/passwords stripped by `sanitizePayload()`. |
| `logs_security_events` | `logSecurity(record)` | `request_id`, `type`, `path`, `user_id`, `ip_address`, `severity` | Logs security events (e.g. rate limit violations, IP range shifts). |
| `logs_notifications` | `logNotification(record)` | `user_id`, `type`, `status` | Delivery audit trail. |

---

## Discovered Vulnerabilities, Inconsistencies & Defective Patterns

### 1. BUG: Error Code Prefix Mismatch in `logAppError` Dispatcher
- **Finding**: In [`logger.js:198`](file:///f:/JustUS/Backend/core/logger.js#L198), `logAppError` attempts to split error codes by underscore `_`:
  `const area = opts.code?.split("_")[0] ?? "";`
- **Impact**: All standard `AppError` codes use hyphens `-` (e.g. `AUTH-FAIL-001`, `SEC-BLOCK-001`). `split("_")[0]` returns the full string `"AUTH-FAIL-001"` instead of `"AUTH"`. As a result, the `switch (area)` statement fails to match `"AUTH"` or `"SEC"`, falling through to `default:` and writing **ALL authentication and security errors into `logs_api_errors` instead of `logs_auth_failures` or `logs_security_events`**.
- **Confidence**: **HIGH**

### 2. BUG: In-Memory Provider Contamination & Swallowed Exceptions in `AuthState`
- **Finding**: In `AuthState.login()` and `AuthState.init()`, certain secondary fetch failures (such as partner details or FCM device token updates) wrap network calls in silent `try { ... } catch (_)` blocks without rethrowing or notifying the UI.
- **Impact**: Secondary failures leave `AuthState` in a partially populated state without alerting the user.
- **Confidence**: **HIGH**

### 3. BUG: UI Thread Crash Risk on Overlay Snackbar Placement
- **Finding**: In [`error_handler.dart:158-167`](file:///f:/JustUS/Flutter/lib/core/error_handling/error_handler.dart#L158-L167), `_showSnackBar()` checks `SchedulerBinding.instance.schedulerPhase` to defer execution if triggered during build/layout. However, `handleGlobal` calls `WidgetsBinding.instance.addPostFrameCallback`, but if an exception occurs inside a build method, `handle` called directly from UI widgets can attempt to manipulate `Overlay` state if `context` is stale.
- **Confidence**: **MEDIUM**

### 4. INCONSISTENCY: Development Debug Leak via `details` Parameter
- **Finding**: In `errorHandler.js:70-74`, in non-production environments (`NODE_ENV !== "production"`), `errorBody.details` and `errorBody.stack` are attached directly to the JSON HTTP response.
- **Impact**: Staging or test environments exposing debug mode can leak internal SQL queries, file paths, and database schema structures to clients.
- **Confidence**: **HIGH**

---

## Document Status

Document created and saved to [`docs/backend/error-handling/doc.md`](file:///f:/JustUS/docs/backend/error-handling/doc.md).

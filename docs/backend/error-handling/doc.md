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
  (Backend errorHandler.js ──► JSON: { success: false, request_id, error: { code, message, details?, stack? } })
  (ENABLE_ERROR_DETAILS=true: raw message + details + stack | otherwise: generic message only)
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
- Factories `.network()` (code `LOCAL-NET-001`) and `.timeout()` (code `LOCAL-TIMEOUT-001`) build local transport errors; `ErrorHandler.toAppError(error)` normalizes every thrown value or repository result into an `AppError`: a `GenericError` carrying an `AppError` in `details` returns that `AppError` (how a repository-preserved code survives the wrapper), a bare `NetworkError` / `SocketException` / `HttpException` maps to `AppError.network()`, and a `TimeoutException` to `AppError.timeout()`.
- Method `userMessage(loc)` maps error code to localized string via `ErrorCodes.userMessage(code, loc)`.
- Flag `requiresReauth`: True for `AUTH-FAIL-001`, `002`, `003`, `006`, and the synthetic client code `"401"` (`ErrorCodes.httpUnauthorized`, raised when a token refresh fails). The client synthetic code `AUTH-FAIL-CRED` is deliberately **not** included.
- Auth mapping: a Supabase `AuthException` raised during **login/registration** is caught in `AuthState.login`/`register` and rethrown as `AppError(AUTH-FAIL-CRED)`; the same code covers the "no user/session" outcomes. A generic `AuthException` reaching `ErrorHandler._toAppError` (token/session validation) still maps to `AUTH-FAIL-001`.
- Flag `isCritical`: True if `requiresReauth` or `SEC-BLOCK-001` / `SEC-BLOCK-002`.

### 3. Database RPC validation errors (`API-VALIDATION-*`)

The Supabase RPCs raise validation failures as Postgres exceptions whose message starts with `API-VALIDATION-<id>`; PostgREST returns that message in its error envelope, and `ErrorCodes.resolveServerCode` only recognizes the codes on its `serverCodes` allowlist. The partnership-cancellation family is now recognized end to end:

- `-010` — request blocked: no `accepted` partnership with that id belongs to the caller (SQLSTATE `42501`).
- `-011` — revert blocked: no `cancelled` row for the caller (SQLSTATE `42501`).
- `-012` — accept blocked: wrong actor/status or requester (SQLSTATE `42501`); `partnership_accept` also raises it when the recipient already holds another accepted/cancelled pair.
- `-013` — request blocked by the 24-hour cooldown after a partner decline (SQLSTATE `P0001`).
- `-014` — accept blocked because the request expired (SQLSTATE `P0001`).

`API-VALIDATION-004` is shared by two `partnership_request` guards: the sender already holds a `pending`/`accepted`/`cancelled` row, or the recipient already holds an `accepted`/`cancelled` row. The client string is intentionally generic ("A partnership or request already exists."); the developer note on the raise says which side was refused.

All five constants (`apiValidation010`…`014`) map through `ErrorCodes.userMessage` to the EN/IT `error_apiValidation010`…`014` strings. A code outside the allowlist still reaches the UI as the raw message instead of a localized `userMessage`.

---

## User Presentation Controls

| Error Type | Presentation Mechanism | Behavior / Appearance |
|---|---|---|
| **Reauthentication Required** (`requiresReauth`) | Modal Alert Dialog | Barrier non-dismissible dialog explaining session expiration. Action button navigates to `/login` and wipes route stack. |
| **Critical System / Security Block** (`isCritical`) | Red Critical Dialog | Displayed via `DialogUtils.showError()`. Shows title, message, error code, and expandable debug details if present. |
| **Non-Critical API / Network Errors** | Floating Overlay Toast / Snackbar | Displayed via global `OverlayEntry`. Renders at bottom of screen above software keyboard in red background (`Colors.red.shade800`). Automatically auto-dismisses after 4s in production; remains open indefinitely in debug mode until closed manually. |

---

## Backend Logging Infrastructure & Supabase Tables

All structured logs are handled by [`logger.js`](file:///f:/JustUS/Backend/core/logger.js) and dispatched based on `SUPABASE_LOG_TO_DB === "true"`. Every function projects the record onto **exactly** the columns of its target table (`supabase/schemas/public/tables/logs_*.sql`); `id` and `created_at` are filled by the database.

| Table Name | Trigger / Log Function | Logged Data Fields | Sensitive Data Handling |
|---|---|---|---|
| `logs_api_access` | `logAccess(record)` | `request_id`, `method`, `path`, `status_code`, `duration_ms`, `device_id` | No payload logged. |
| `logs_api_errors` | `logError(record)` / `logAppError` | `request_id`, `path`, `method`, `device_id`, `error_json` (contains `error_code`, `error_message`, `user_id`, `ip_address`, `severity`, `error`, `stack`, `endpoint`, `payload` where present) | Payload is sanitized via `sanitizePayload()` before embedding in `error_json`. Stack included only in non-production. |
| `logs_auth_failures` | `logAuthFailure(record)` | `request_id`, `error_code`, `error_message`, `path`, `user_id`, `ip_address`, `reason`, `severity`, `payload`, `stack` | Payload sanitized via `sanitizePayload()`; email placed in payload when passed. |
| `logs_security_events` | `logSecurity(record)` | `request_id`, `type`, `path`, `device_id`, `error_json` (contains `error_code`, `error_message`, `user_id`, `ip_address`, `severity`, `type`, `payload`, `stack`, `endpoint`, `retry_after_seconds`, `strike_level`) | Payload sanitized via `sanitizePayload()`. |
| `logs_notifications` | `logNotification(record)` | `user_id`, `type`, `status` | Delivery audit trail. `type` is capped at the column's `varchar(50)` limit. |

Notes on the columns that constrain the record shape:

- `request_id` is a `uuid` column in `logs_api_access`, `logs_api_errors` and `logs_security_events`. `requestContext` only accepts a client `X-Request-Id` that is a valid uuid and generates one otherwise, so a bogus header can never make Postgres reject the whole row; the logger additionally nulls a non-uuid value. `logs_auth_failures.request_id` is `text` and keeps the raw value.
- `device_id` is the FK to `user_devices(id)`. The auth middleware resolves the device row of the request's auth session (`resolveDeviceId`, keyed on `user_devices.session_id`) and every log of that request carries it. Rows logged before a session exists (login anomalies, rate limits on anonymous calls) keep `device_id` null, and the FK is `ON DELETE SET NULL`, so a later device deletion nulls the pointer instead of dropping the audit row.
- `path` holds the request path only (`req.originalUrl`); the HTTP method is written to the `method` column.

---

## Discovered Vulnerabilities, Inconsistencies & Defective Patterns

### 1. BUG: In-Memory Provider Contamination & Swallowed Exceptions in `AuthState`
- **Finding**: In `AuthState.login()` and `AuthState.init()`, certain secondary fetch failures (such as partner details or FCM device token updates) wrap network calls in silent `try { ... } catch (_)` blocks without rethrowing or notifying the UI.
- **Impact**: Secondary failures leave `AuthState` in a partially populated state without alerting the user.
- **Confidence**: **HIGH**

### 2. BUG: UI Thread Crash Risk on Overlay Snackbar Placement
- **Finding**: In [`error_handler.dart:158-167`](file:///f:/JustUS/Flutter/lib/core/error_handling/error_handler.dart#L158-L167), `_showSnackBar()` checks `SchedulerBinding.instance.schedulerPhase` to defer execution if triggered during build/layout. However, `handleGlobal` calls `WidgetsBinding.instance.addPostFrameCallback`, but if an exception occurs inside a build method, `handle` called directly from UI widgets can attempt to manipulate `Overlay` state if `context` is stale.
- **Confidence**: **MEDIUM**

---

## Document Status

Document created and saved to [`docs/backend/error-handling/doc.md`](file:///f:/JustUS/docs/backend/error-handling/doc.md).

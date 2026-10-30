# Security Infrastructure & Controls Analysis

## Overview

This document provides a technical reverse-engineering analysis of the security architecture implemented in the JustUS Node.js/Express backend server. It covers authentication, session binding, request signing, replay protection, rate limiting, sanitization, response headers, and multi-instance deployment implications.

> [!IMPORTANT]
> **Deployment assumption — single instance.** The backend runs as a **single Node.js instance**. Controls that keep state in process memory by design — rate-limit buckets and bans (`rateLimit.js`), login strikes (`authRisk.service.js`) and idempotency responses (`idempotencyStore.js`) — are not shared between processes. Horizontal scaling would require a shared store and is **out of scope**; the per-process behavior recorded below is a documented constraint of the single-instance deployment, not an active defect.

---

## Global Request Pipeline Execution Order

The exact execution order of middleware in the application pipeline is determined directly from source code ([`app.js`](file:///f:/JustUS/Backend/app.js), [`routes/v1.js`](file:///f:/JustUS/Backend/routes/v1.js), [`features/media/media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js)):

```
 1. Request Context Init    (requestContext)
 2. Request Timeout         (timeoutMiddleware)
 3. Security Headers        (Helmet: CSP, HSTS, frameAncestors)
 4. CORS Filtering          (handleCors)
 5. Body Parsing            (express.json, express.urlencoded)
 6. Input Sanitization      (sanitizeRequest)
 7. Request Logging         (requestLogger)
 ----------------------- Route Level Chain -----------------------
 8. Authentication          (authenticateToken)
 9. RBAC Capabilities       (authorizeCapabilities / capability())
10. Composite Rate Limit    (createCompositeRateLimit / limited())
11. Idempotency Check       (withIdempotency)
12. HMAC Request Signing    (requireSignedRequest / signed())
    └── Nonce Check         (consumeNonce inside requireSignedRequest)
13. Input Validation        (validateRequest / validated(schema))
14. Route Handler           (deleteMediaController, etc.)
```

> [!IMPORTANT]
> **Key Finding on Order**: Input Sanitization occurs **before** Authentication, Rate Limiting, and HMAC Request Signing. HMAC verification occurs **after** Rate Limiting and Authentication, but **before** Schema Validation (`validateRequest`).

---

## Security Controls Analysis

### 1. HMAC-SHA256 Request Signing

- **Threat Addressed**: Man-in-the-middle (MITM) request tampering, payload alteration, unauthorized API execution using stolen session tokens.
- **Implementation Location**: [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js), [`services/requestSigningService.js`](file:///f:/JustUS/Backend/services/requestSigningService.js).
- **Request Flow & Validation Order**:
  1. Extract `X-Request-Timestamp`, `X-Request-Nonce`, `X-Request-Signature`.
  2. Verify `req.sessionBinding.bindingSecret` exists (populated by `authenticateToken`).
  3. Validate timestamp skew (`Math.abs(now - timestamp) <= env.requestSigningMaxSkewMs` [default 300,000ms / 5 min]).
  4. Compute expected HMAC: `HMAC-SHA256(secret, `${METHOD}.${path}.${timestamp}.${nonce}.${sha256(body)}`)`.
  5. String equality comparison (`expectedSignature === signature`).
  6. Call `consumeNonce` to record nonce usage.
- **Failure Behavior**: Throws `SEC-AUTH-002` (401: missing session binding/headers, expired timestamp, invalid signature), `API-VALIDATION-001` (400: non-numeric timestamp) or `SEC-BLOCK-001` (429: replayed nonce).
- **Storage & Expiration**: Session secret stored in PostgreSQL `session_bindings.binding_secret`.
- **Bypass Possibilities**: Requests on routes not wrapped with `signed(...)` skip HMAC verification. Every authenticated mutating route is signed; the only unsigned mutating routes are `/auth/login-risk-check` and `/auth/login-attempt` (pre-auth by necessity) and `/auth/session-bind` (uses `freshNonce` and is the call that creates the signing secret). `Backend/test/signing-boundary.test.js` pins the full mutating route table, including these exceptions, so a new route cannot join the wrong set silently.
- **Multi-Instance Behavior**: HMAC verification is stateless given the session `bindingSecret` in database/request; works across multi-instance nodes.

---

### 2. Timestamp Skew & Replay Protection

- **Threat Addressed**: Replay attacks where an attacker intercepts a valid signed HTTP request and re-sends it later.
- **Implementation Location**: [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js#L50), [`middleware/requireFreshNonce.js`](file:///f:/JustUS/Backend/middleware/requireFreshNonce.js#L17).
- **Request Flow**: Parses `x-request-timestamp`. Rejects request if `Math.abs(Date.now() - timestamp) > env.requestSigningMaxSkewMs` (5 minutes).
- **Failure Behavior**: Returns `SEC-AUTH-002` ("Signed request expired") or `SEC-AUTH-001` ("Request timestamp expired") for an expired skew, and `API-VALIDATION-001` ("Invalid request timestamp") for a non-numeric one.
- **Multi-Instance Behavior**: Depends on server clock synchronization (NTP across instances). Clock drift between instances can cause legitimate requests to fail skew checks.

---

### 3. Nonce Store & Replay Prevention

- **Threat Addressed**: Rapid duplication of valid requests within the 5-minute timestamp skew window.
- **Implementation Location**: [`core/infra/nonceStore.js`](file:///f:/JustUS/Backend/core/infra/nonceStore.js), [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js#L20), [`middleware/requireFreshNonce.js`](file:///f:/JustUS/Backend/middleware/requireFreshNonce.js#L22).
- **Request Flow & Validation Order**:
  1. Form key: `${namespace}:${userId}:${nonce}`.
  2. Check in-memory `Map` (`consumedNonces`) as a fast path. If key exists and `expiresAt > now`, reject.
  3. Insert record into PostgreSQL `request_nonces` table — the authoritative replay check.
  4. Treat the DB unique-violation error (`23505`) as a replay and reject.
  5. Only after the insert is accepted (or the database is unreachable) record the nonce in the in-memory map.
- **Storage & Expiration**: Dual-layer (PostgreSQL `request_nonces` store of record + in-memory `Map` cache with 10-minute sweep interval `_sweepExpiredNonces`).
- **Failure Behavior**: Throws `SEC_BLOCK_001` ("Replay request detected" / "Duplicate request nonce").
- **Multi-Instance Behavior**: **Synchronized via the PostgreSQL `UNIQUE (nonce)` constraint** (`request_nonces_nonce_key`) on `request_nonces`. The database insert is the authoritative check, so a nonce already reserved by any instance — including a cold node whose in-memory map is empty — is rejected; the in-memory map is only a cache of nonces this process has already accepted.

---

### 4. JWT Verification & Session Binding

- **Threat Addressed**: Stolen JWT tokens used on unauthorized devices/IPs; session hijacking.
- **Implementation Location**: [`middleware/authMiddleware.js`](file:///f:/JustUS/Backend/middleware/authMiddleware.js), [`utils/auth/tokenUtils.js`](file:///f:/JustUS/Backend/utils/auth/tokenUtils.js), [`supabase/schemas/public/functions/session_is_live.sql`](file:///f:/JustUS/supabase/schemas/public/functions/session_is_live.sql).
- **Request Flow & Validation Order**:
  1. Extract Bearer token from `Authorization` header.
  2. Validate token via Supabase Auth API `authSupabase.auth.getUser(token)`. GoTrue verifies the JWT and rejects a token whose `session_id` no longer resolves to an `auth.sessions` row, so a deleted session stops working before the JWT expires.
  3. Validate token lifetime against `env.maxAccessTokenLifetimeSec`.
  4. Fetch user profile from `users` table.
  5. Fetch the session binding from `session_bindings` matching `session_id` or `${profile.id}:${clientContext.deviceFingerprintHash}`, and call `session_is_live(session_id)` in parallel.
  6. Reject with `AUTH-FAIL-001` when `session_is_live` returns false: the function reads `auth.sessions.not_after` (the Supabase session timebox) and catches an expiry GoTrue only enforces at token refresh. An RPC error fails open — GoTrue already enforces session existence, so this is defence in depth.
  7. Enforce session binding: verify `device_fingerprint_hash` (`AUTH-FAIL-006`).
  8. Attach `req.user` (with `profileId`, `role`, `capabilities`) and `req.sessionBinding` (`bindingSecret`).
- **Failure Behavior**: Returns `AUTH-FAIL-001` (invalid/expired token or expired server-side session), `AUTH-FAIL-002` (missing token), `AUTH-FAIL-004` (invalid role), `AUTH-FAIL-005` (no profile), `AUTH-FAIL-006` (device binding mismatch).
- **Storage**: `session_bindings` (device binding and signing secret) plus Supabase `auth.sessions` (session existence and `not_after`).
- **Multi-Instance Behavior**: Fully stateful via PostgreSQL queries; consistent across instances.

---

### 5. RBAC & Capabilities System

- **Threat Addressed**: Unauthorized access to specific endpoints (e.g. media uploads, profile updates, admin features).
- **Implementation Location**: [`middleware/authorizeCapabilities.js`](file:///f:/JustUS/Backend/middleware/authorizeCapabilities.js), [`features/auth/authorization.service.js`](file:///f:/JustUS/Backend/features/auth/authorization.service.js).
- **Request Flow**: `authenticateToken` resolves user role from `user_roles` table, maps role to capabilities array (e.g. `user` $\rightarrow$ `['can_media_upload', 'can_profile_update']`). `authorizeCapabilities(...requiredCapabilities)` checks if `req.user.capabilities` contains all required permissions.
- **Failure Behavior**: Throws `AppError({ errorKey: "SEC_AUTH_001", message: "Missing capability" })`.
- **Multi-Instance Behavior**: Fully stateless per-request based on authenticated user context.

---

### 6. Composite Rate Limiting & Penalty Escalation

- **Threat Addressed**: Brute-force attacks, API abuse, Denial of Service (DoS).
- **Implementation Location**: [`middleware/rateLimit.js`](file:///f:/JustUS/Backend/middleware/rateLimit.js), [`utils/auth/rateLimitKeys.js`](file:///f:/JustUS/Backend/utils/auth/rateLimitKeys.js), [`utils/auth/rateLimitPresets.js`](file:///f:/JustUS/Backend/utils/auth/rateLimitPresets.js).
- **Request Flow**:
  1. For each rule in composite limiter (e.g. IP rule, User rule, Endpoint rule):
     - Check penalty map (`penalties.get('${name}:${rule.name}:${key}')`). If `bannedUntil > now`, enforce block.
     - Increment sliding window count in `buckets.get('${name}:${rule.name}:${key}')`.
     - If `count > max`: trigger `applyPenalty()`.
  2. **Penalty Escalation**:
     - Increment `strikes` for penalty key.
     - Strike 1: 200ms delay penalty.
     - Strike 2: 1000ms delay penalty.
     - Strike 4+: 15-minute hard ban (`bannedUntil = Date.now() + 15 * 60_000`).
- **Storage & Sweeping**: Stored in NodeJS process memory (`buckets = new Map()`, `penalties = new Map()`). Swept every 15 minutes by `_sweepRateLimitMaps`.
- **Failure Behavior**: Sets `Retry-After` header, logs security event, returns `SEC-BLOCK-001` (429 Too Many Requests).
- **Multi-Instance Behavior**: `buckets` and `penalties` are **process-local**, so rate limits and bans are not shared across instances and are wiped on restart or deploy. Under horizontal scaling an attacker could distribute requests across N nodes for roughly N× the allowance, and a ban recorded on one node would be unknown to the others. **Accepted** under the single-instance deployment assumption (see Overview) — this is a documented per-process constraint of severity **HIGH**, not a defect to be remediated with a shared store.

---

### 7. Input Sanitization

- **Threat Addressed**: Control character injection, null-byte injection, whitespace pollution in request body/query/params.
- **Implementation Location**: [`middleware/sanitizeRequest.js`](file:///f:/JustUS/Backend/middleware/sanitizeRequest.js).
- **Request Flow**: Executes globally before routes. Recursively iterates through `req.body`, `req.query`, `req.params`. For string values, strips control characters `[\u0000-\u001f\u007f]` and applies `.trim()`.
- **Failure Behavior**: Mutates request payload in place, passes control to `next()`.
- **Multi-Instance Behavior**: Fully stateless; works identically on all instances.

---

### 8. Request Timeout

- **Threat Addressed**: Slowloris attacks, hanging backend operations consuming connection pools.
- **Implementation Location**: [`middleware/timeoutMiddleware.js`](file:///f:/JustUS/Backend/middleware/timeoutMiddleware.js), [`app.js`](file:///f:/JustUS/Backend/app.js#L22).
- **Request Flow**: Applies `req.setTimeout(timeoutMs)` and `res.setTimeout(timeoutMs)` using `env.requestTimeoutMs` (default 15,000ms).
- **Failure Behavior**: If timeout triggers before headers sent, passes `AppError({ errorKey: "API_TIMEOUT_001" })` to error handler (504 Gateway Timeout).

---

### 9. Idempotency

- **Threat Addressed**: Duplicate execution of critical operations (e.g. login-attempt reporting) caused by network retries.
- **Implementation Location**: [`middleware/idempotencyMiddleware.js`](file:///f:/JustUS/Backend/middleware/idempotencyMiddleware.js), [`core/infra/idempotencyStore.js`](file:///f:/JustUS/Backend/core/infra/idempotencyStore.js).
- **Request Flow**:
  1. Checks `Idempotency-Key` or `X-Idempotency-Key` header. If absent, proceeds.
  2. Constructs cache key: `${namespace}:${userId ?? "anonymous"}:${key}`.
  3. Checks in-memory store (`responses.get(cacheKey)`). If valid entry exists, returns cached response immediately.
  4. Otherwise, wraps `res.json()` to intercept and store response status code and body for 24 hours (`Date.now() + 24 * 60 * 60_000`).
- **Multi-Instance Behavior**: Idempotency responses are stored **exclusively in an in-memory `Map`** (`responses = new Map()`), so the guarantee is **per instance**: a retried request hitting a different instance bypasses the cache and re-executes the operation, and a restart erases every cached entry. **Accepted** under the single-instance deployment assumption (see Overview) — severity **HIGH**, a documented per-process constraint rather than a defect to be remediated with a shared store. Within one instance a retried key returns the first response and is executed once.

---

### 10. Turnstile Cloudflare Captcha Verification

- **Threat Addressed**: Automated bot registration, credential stuffing, brute-force auth attempts.
- **Implementation Location**: Native Supabase Auth CAPTCHA integration + Flutter client [`CaptchaService`](file:///f:/JustUS/Flutter/lib/features/auth/captcha_service.dart). The Cloudflare Turnstile secret key is configured in the Supabase Auth dashboard (**not** in this repository or the Node backend).
- **Request Flow**:
  1. `CaptchaService.getCaptchaToken()` renders the Turnstile widget in **Managed** mode: normal users pass automatically (no interaction); Cloudflare surfaces an interactive challenge only for suspicious traffic.
  2. The single-use token is passed to Supabase Auth (`sbClient.auth.signInWithPassword(captchaToken:)` / `signUp(captchaToken:)`).
  3. Supabase Auth validates the token against Cloudflare at sign-in/sign-up time.
- **Failure Behavior**: Missing/invalid token aborts the Supabase auth call (`AuthException`); the client surfaces `authFailCred` / `localUnknown` ("Captcha failed"). Suspicious clients that fail the challenge receive no token and cannot authenticate.
- **Note**: The token is **single-use**, so verification must happen on exactly one side. Verification lives only on Supabase Auth; the Node backend must not consume it. A former dead backend client (`services/turnstileService.js`) was removed — it was never wired to any route/middleware.

---

### 11. Helmet & Content Security Policy (CSP)

- **Threat Addressed**: XSS, clickjacking, MIME-sniffing, framing attacks.
- **Implementation Location**: [`app.js:45-68`](file:///f:/JustUS/Backend/app.js#L45-L68).
- **Configuration**:
  - `contentSecurityPolicy`: `default-src 'none'`, `base-uri 'none'`, `frame-ancestors 'none'`, `form-action 'self'`.
  - `crossOriginResourcePolicy`: `false`.
  - `hsts`: Enabled in production (`maxAge: 31536000`, `includeSubDomains: true`, `preload: true`).
  - `referrerPolicy`: `no-referrer`.
  - `x-powered-by`: Disabled via `app.disable("x-powered-by")`.

---

### 12. Cross-Origin Resource Sharing (CORS)

- **Threat Addressed**: Cross-domain unauthorized browser requests.
- **Implementation Location**: [`utils/http/corsUtils.js`](file:///f:/JustUS/Backend/utils/http/corsUtils.js), [`app.js:24`](file:///f:/JustUS/Backend/app.js#L24).
- **Request Flow**: Checks `Origin` header. Compares against `env.allowedOrigins`.
- **Allowed Headers**: `Authorization`, `Content-Type`, `X-Request-Id`, `X-Request-Timestamp`, `X-Request-Nonce`, `X-Request-Signature`, `X-Idempotency-Key`, `Idempotency-Key`, `X-Device-Fingerprint`, `X-Client-User-Agent`, `X-Client-User-Agent-Hash`.
- **Failure Behavior**: If origin not allowed, returns `AppError({ errorKey: "SEC_AUTH_001", message: "Origin not allowed" })`.

---

## Multi-Instance Vulnerability Analysis Matrix

> Levels describe behavior **if** the single-instance deployment assumption (see Overview) were violated by horizontal scaling. Under the assumed single-instance deployment, the per-process rows below are accepted constraints, not active defects.

| Security Control | Storage Mechanism | Multi-Instance Behavior | Vulnerability Level |
|---|---|---|---|
| **Rate Limiter & Bans** | In-Memory `Map` (`buckets`, `penalties`) | **Isolated per node** (accepted — single instance). Limits scale linearly with worker instance count; strikes/bans are bypassed across nodes under horizontal scaling. | **HIGH** |
| **Login-Attempt Strikes** | In-Memory `Map` (`loginAttempts`) | **Isolated per node** (accepted — single instance). Credential-stuffing failures and the 10/30-minute lockouts do not accumulate across nodes; within one instance the documented threshold still applies. | **HIGH** |
| **Idempotency Cache** | In-Memory `Map` (`responses`) | **Isolated per node** (accepted — single instance). Retried requests on different instances bypass the cache and re-execute; within one instance a retried key returns the first response and runs once. | **HIGH** |
| **Nonce Deduplication** | In-Memory `Map` + PostgreSQL `request_nonces` | **Multi-Instance Safe**. The DB `UNIQUE (nonce)` insert is the authoritative replay check; the memory map is only a cache. | **LOW (SAFE)** |
| **JWT & Session Binding** | PostgreSQL `session_bindings` + Supabase `auth.sessions` | **Multi-Instance Safe**. Database backed. | **LOW (SAFE)** |
| **HMAC Verification** | Request Payload + DB Session Secret | **Multi-Instance Safe**. Stateless computation per request. | **LOW (SAFE)** |
| **Cloudflare Turnstile** | External API | **Multi-Instance Safe**. Verified natively by Supabase Auth at sign-in/sign-up; no per-instance state. | **LOW (SAFE)** |

---

## Document Status

Document created and saved to [`docs/backend/security/doc.md`](file:///f:/JustUS/docs/backend/security/doc.md).

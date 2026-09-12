# Security Infrastructure & Controls Analysis

## Overview

This document provides a technical reverse-engineering analysis of the security architecture implemented in the JustUS Node.js/Express backend server. It covers authentication, session binding, request signing, replay protection, rate limiting, sanitization, response headers, and multi-instance deployment implications.

---

## Global Request Pipeline Execution Order

The exact execution order of middleware in the application pipeline is determined directly from source code ([`app.js`](file:///f:/JustUS/Backend/app.js), [`routes/v1.js`](file:///f:/JustUS/Backend/routes/v1.js), [`features/ai/ai.routes.js`](file:///f:/JustUS/Backend/features/ai/ai.routes.js)):

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
14. Route Handler           (generateQuestionController, etc.)
```

> [!IMPORTANT]
> **Key Finding on Order**: Input Sanitization occurs **before** Authentication, Rate Limiting, and HMAC Request Signing. HMAC verification occurs **after** Rate Limiting and Authentication, but **before** Schema Validation (`validateRequest`).

---

## Security Controls Analysis

### 1. HMAC-SHA256 Request Signing

- **Threat Addressed**: Man-in-the-middle (MITM) request tampering, payload alteration, unauthorized API execution using stolen session tokens.
- **Implementation Location**: [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js), [`utils/security/requestSigner.js`](file:///f:/JustUS/Backend/utils/security/requestSigner.js).
- **Request Flow & Validation Order**:
  1. Extract `X-Request-Timestamp`, `X-Request-Nonce`, `X-Request-Signature`.
  2. Verify `req.sessionBinding.bindingSecret` exists (populated by `authenticateToken`).
  3. Validate timestamp skew (`Math.abs(now - timestamp) <= env.requestSigningMaxSkewMs` [default 300,000ms / 5 min]).
  4. Compute expected HMAC: `HMAC-SHA256(secret, `${METHOD}.${path}.${timestamp}.${nonce}.${sha256(body)}`)`.
  5. Constant-time string equality comparison (`expectedSignature === signature`).
  6. Call `consumeNonce` to record nonce usage.
- **Failure Behavior**: Throws `AppError({ errorKey: "SEC_AUTH_002" })` or `SEC_BLOCK_001` (401/403).
- **Storage & Expiration**: Session secret stored in PostgreSQL `auth_sessions.binding_secret`.
- **Bypass Possibilities**: Requests on routes not wrapped with `signed(...)` helper skip HMAC verification completely.
- **Multi-Instance Behavior**: HMAC verification is stateless given the session `bindingSecret` in database/request; works across multi-instance nodes.

---

### 2. Timestamp Skew & Replay Protection

- **Threat Addressed**: Replay attacks where an attacker intercepts a valid signed HTTP request and re-sends it later.
- **Implementation Location**: [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js#L50), [`middleware/requireFreshNonce.js`](file:///f:/JustUS/Backend/middleware/requireFreshNonce.js#L17).
- **Request Flow**: Parses `x-request-timestamp`. Rejects request if `Math.abs(Date.now() - timestamp) > env.requestSigningMaxSkewMs` (5 minutes).
- **Failure Behavior**: Returns `SEC_AUTH_002` ("Signed request expired") or `API_VALIDATION_001` ("Invalid request timestamp").
- **Multi-Instance Behavior**: Depends on server clock synchronization (NTP across instances). Clock drift between instances can cause legitimate requests to fail skew checks.

---

### 3. Nonce Store & Replay Prevention

- **Threat Addressed**: Rapid duplication of valid requests within the 5-minute timestamp skew window.
- **Implementation Location**: [`core/infra/nonceStore.js`](file:///f:/JustUS/Backend/core/infra/nonceStore.js), [`middleware/requireSignedRequest.js`](file:///f:/JustUS/Backend/middleware/requireSignedRequest.js#L20), [`middleware/requireFreshNonce.js`](file:///f:/JustUS/Backend/middleware/requireFreshNonce.js#L22).
- **Request Flow & Validation Order**:
  1. Form key: `${namespace}:${userId}:${nonce}`.
  2. Check in-memory `Map` (`consumedNonces`). If key exists and `expiresAt > now`, reject.
  3. Set key in-memory with `expiresAt`.
  4. Insert record into PostgreSQL `request_nonces` table.
  5. Catch DB duplicate key error. If duplicate, return `false` (reject).
- **Storage & Expiration**: Dual-layer (In-memory `Map` with 10-minute sweep interval `_sweepExpiredNonces` + PostgreSQL `request_nonces` table).
- **Failure Behavior**: Throws `SEC_BLOCK_001` ("Replay request detected" / "Duplicate request nonce").
- **Multi-Instance Behavior**: **Synchronized via PostgreSQL primary key constraint** on `request_nonces.nonce`. If Instance A inserts the nonce, Instance B's insert will fail on database duplicate key constraint, maintaining multi-instance safety despite in-memory map isolation.

---

### 4. JWT Verification & Session Binding

- **Threat Addressed**: Stolen JWT tokens used on unauthorized devices/IPs; session hijacking.
- **Implementation Location**: [`middleware/authMiddleware.js`](file:///f:/JustUS/Backend/middleware/authMiddleware.js), [`utils/security/tokenUtils.js`](file:///f:/JustUS/Backend/utils/security/tokenUtils.js).
- **Request Flow & Validation Order**:
  1. Extract Bearer token from `Authorization` header.
  2. Validate token via Supabase Auth API `authSupabase.auth.getUser(token)`.
  3. Validate token lifetime against `env.maxAccessTokenLifetimeSec`.
  4. Fetch user profile from `users` table.
  5. Fetch session binding record from `auth_sessions` table matching `session_id` or `${profile.id}:${clientContext.deviceFingerprintHash}`.
  6. Enforce session binding: verify `device_fingerprint_hash`, `user_agent_hash`, and check if `revoked_at` is null.
  7. Detect subnet/IP range changes (`isIpRangeChanged`) and log security events.
  8. Attach `req.user` (with `profileId`, `role`, `capabilities`) and `req.sessionBinding` (`bindingSecret`).
- **Failure Behavior**: Returns `AUTH_FAIL_002` (missing token), `AUTH_FAIL_004` (invalid role), `AUTH_FAIL_005` (no profile/invalid session binding).
- **Storage**: `auth_sessions` table in Supabase PostgreSQL.
- **Multi-Instance Behavior**: Fully stateful via PostgreSQL queries; consistent across instances.

---

### 5. RBAC & Capabilities System

- **Threat Addressed**: Unauthorized access to specific endpoints (e.g. AI calls, media uploads, admin features).
- **Implementation Location**: [`middleware/authorizeCapabilities.js`](file:///f:/JustUS/Backend/middleware/authorizeCapabilities.js), [`utils/security/roleResolver.js`](file:///f:/JustUS/Backend/utils/security/roleResolver.js).
- **Request Flow**: `authenticateToken` resolves user role from `user_roles` table, maps role to capabilities array (e.g. `user` $\rightarrow$ `['can_ai_call', 'can_media_upload']`). `authorizeCapabilities(...requiredCapabilities)` checks if `req.user.capabilities` contains all required permissions.
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
- **Failure Behavior**: Sets `Retry-After` header, logs security event, returns `SEC_BLOCK_001` (429 Too Many Requests).
- **Multi-Instance Weakness**: **CRITICAL MULTI-INSTANCE DEFECT**: Because `buckets` and `penalties` maps are **purely in-memory**, rate limits and bans are **NOT shared across cluster instances**. An attacker can bypass rate limits and strike bans by distributing requests across multiple backend worker nodes (e.g., N instances multiplier).

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
- **Request Flow**: Applies `req.setTimeout(timeoutMs)` and `res.setTimeout(timeoutMs)` using `env.requestTimeoutMs` (default 30,000ms).
- **Failure Behavior**: If timeout triggers before headers sent, passes `AppError({ errorKey: "API_TIMEOUT_001" })` to error handler (504 Gateway Timeout).

---

### 9. Idempotency

- **Threat Addressed**: Duplicate execution of critical operations (e.g. AI question generation) caused by network retries.
- **Implementation Location**: [`middleware/idempotencyMiddleware.js`](file:///f:/JustUS/Backend/middleware/idempotencyMiddleware.js), [`core/infra/idempotencyStore.js`](file:///f:/JustUS/Backend/core/infra/idempotencyStore.js).
- **Request Flow**:
  1. Checks `Idempotency-Key` or `X-Idempotency-Key` header. If absent, proceeds.
  2. Constructs cache key: `${namespace}:${userId ?? "anonymous"}:${key}`.
  3. Checks in-memory store (`responses.get(cacheKey)`). If valid entry exists, returns cached response immediately.
  4. Otherwise, wraps `res.json()` to intercept and store response status code and body for 24 hours (`Date.now() + 24 * 60 * 60_000`).
- **Multi-Instance Weakness**: **CRITICAL MULTI-INSTANCE DEFECT**: Idempotency responses are stored **exclusively in an in-memory `Map`** (`responses = new Map()`). A retried request hitting a different instance will bypass idempotency cache and re-execute the operation.

---

### 10. Turnstile Cloudflare Captcha Verification

- **Threat Addressed**: Automated bot registration, credential stuffing, brute-force auth attempts.
- **Implementation Location**: [`services/turnstileService.js`](file:///f:/JustUS/Backend/services/turnstileService.js).
- **Request Flow**: `verifyTurnstileToken({ token, remoteIp })` sends POST request to `https://challenges.cloudflare.com/turnstile/v0/siteverify`. Skipped if `env.turnstileEnabled` is `false`.
- **Failure Behavior**: Returns verification response object from Cloudflare.
- **Bypass / Deficiency**: The service is implemented in [`turnstileService.js`](file:///f:/JustUS/Backend/services/turnstileService.js), but **it is not wired into any active route controller or middleware** (e.g. auth routes do not call `verifyTurnstileToken`).

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

| Security Control | Storage Mechanism | Multi-Instance Behavior | Vulnerability Level |
|---|---|---|---|
| **Rate Limiter & Bans** | In-Memory `Map` (`buckets`, `penalties`) | **Isolated per node**. Limits scale linearly with worker instance count. Strikes/Bans are bypassed across nodes. | **HIGH** |
| **Idempotency Cache** | In-Memory `Map` (`responses`) | **Isolated per node**. Retried requests on different instances bypass cache and re-execute. | **HIGH** |
| **Nonce Deduplication** | In-Memory `Map` + PostgreSQL `request_nonces` | **Multi-Instance Safe**. DB primary key constraint prevents cross-node replays. | **LOW (SAFE)** |
| **JWT & Session Binding** | PostgreSQL `auth_sessions` | **Multi-Instance Safe**. Database backed. | **LOW (SAFE)** |
| **HMAC Verification** | Request Payload + DB Session Secret | **Multi-Instance Safe**. Stateless computation per request. | **LOW (SAFE)** |
| **Cloudflare Turnstile** | External API | **Not Integrated**. Dead code; not attached to auth routes. | **HIGH** |

---

## Document Status

Document created and saved to [`docs/backend/security/doc.md`](file:///f:/JustUS/docs/backend/security/doc.md).

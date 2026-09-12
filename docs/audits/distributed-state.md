# Distributed State & In-Memory Mechanism Security Audit

## Executive Summary

This audit evaluates all security and reliability mechanisms in the JustUS Node.js backend that maintain state in process memory (`Map` data structures). 

When running multiple backend instances (e.g. horizontal scaling, round-robin load balancers, or serverless/multi-container deployments), in-memory state is **not shared across processes**. This causes severe security, rate-limiting, and consistency bypasses.

---

## Detailed In-Memory Mechanisms Analysis

### 1. Request Nonce Store (`nonceStore.js`)

* **File**: [`Backend/core/infra/nonceStore.js`](file:///f:/JustUS/Backend/core/infra/nonceStore.js#L3)
* **Data Structure**: `const consumedNonces = new Map();`
* **Purpose**: Prevents replay attacks by checking if a request signature nonce has already been consumed.
* **Lifecycle & Expiration**: Items stored in memory with timestamp; swept every 10 minutes via `_sweepExpiredNonces()`.
* **Persistence Layer**: Dual storage — checks memory first, then attempts DB fallback via `adminSupabase.from("request_nonces").insert(...)`.
* **Process Restart Behavior**: In-memory map is wiped, relying entirely on DB fallback.
* **Multi-Instance Behavior**: **PARTIALLY SAFE WITH CONCURRENCY RISK**. If Instance A receives a nonce, it stores it in memory and inserts to Supabase. If Instance B receives the same nonce concurrently before Instance A completes the DB insert, both instances may process the request.
* **Failure Mode**: Replay attacks are possible under high concurrency across distinct instance nodes due to race conditions prior to database lock/insertion.

---

### 2. Composite Rate Limiter & Penalty Strikes (`rateLimit.js`)

* **File**: [`Backend/middleware/rateLimit.js`](file:///f:/JustUS/Backend/middleware/rateLimit.js#L3-L4)
* **Data Structure**:
  - `const buckets = new Map();` (Tracks request counts per IP/user window)
  - `const penalties = new Map();` (Tracks strike escalation levels and 15-minute ban windows)
* **Purpose**: Protects API routes against brute-force attacks, denial-of-service, and abuse.
* **Lifecycle & Expiration**: Swept every 15 minutes via `_sweepRateLimitMaps()`.
* **Persistence Layer**: **NONE** (100% in-memory).
* **Process Restart Behavior**: Completely wiped on restart. All rate limits and active 15-minute IP bans are immediately reset.
* **Multi-Instance Behavior**: **UNSAFE (CRITICAL)**. Request volume is split across backend nodes. An attacker submitting 100 requests across 4 load-balanced instances will only trigger 25 requests per instance, completely bypassing configured rate limits and penalty strike bans.
* **Failure Mode**: Complete rate-limiting bypass under horizontally scaled environments.

---

### 3. Auth Risk & Login Attempt Tracking (`authRisk.service.js`)

* **File**: [`Backend/features/auth/authRisk.service.js`](file:///f:/JustUS/Backend/features/auth/authRisk.service.js#L11)
* **Data Structure**: `const loginAttempts = new Map();`
* **Purpose**: Tracks failed login attempts per device/IP/email, applies progressive strike levels, and enforces 10-to-30 minute IP/account lockouts.
* **Lifecycle & Expiration**: Individual keys expire after 15 minutes of inactivity (`now + 15 * 60_000`).
* **Persistence Layer**: **NONE** (100% in-memory).
* **Process Restart Behavior**: All strike levels and active login blocks are lost upon process restart.
* **Multi-Instance Behavior**: **UNSAFE (HIGH)**. Brute-force credential stuffing attacks spread across multiple backend instances will fail to accumulate strikes on any single node, allowing attackers substantially more password guesses before triggering a lockout.
* **Failure Mode**: Credential stuffing protection bypass in multi-instance deployments.

---

### 4. Idempotency Cache (`idempotencyStore.js`)

* **File**: [`Backend/core/infra/idempotencyStore.js`](file:///f:/JustUS/Backend/core/infra/idempotencyStore.js#L1)
* **Data Structure**: `const responses = new Map();`
* **Purpose**: Caches API responses for 24 hours (`Date.now() + 24 * 60 * 60_000`) based on namespace, user ID, and idempotency key to prevent duplicate processing of unsafe operations.
* **Lifecycle & Expiration**: Retained for 24 hours; expired entries deleted lazily on lookup (`getEntry()`).
* **Persistence Layer**: **NONE** (100% in-memory).
* **Process Restart Behavior**: All cached idempotent responses are erased on backend deployment or crash.
* **Multi-Instance Behavior**: **UNSAFE (HIGH)**. If a client retries a request and the retry hits Instance B instead of Instance A, Instance B will re-execute the operation instead of returning the cached result, potentially causing duplicate database mutations.
* **Failure Mode**: Duplicate side-effects (e.g. duplicate payments, duplicate records) on retried requests hitting different backend nodes.

---

### 5. AI Token Quota Manager (`quotaService.js`)

* **File**: [`Backend/core/infra/quotaService.js`](file:///f:/JustUS/Backend/core/infra/quotaService.js#L3)
* **Data Structure**: `const aiDailyUsage = new Map();`
* **Purpose**: Enforces daily per-user token limits (`env.aiDailyTokenLimit = 4000`) for AI prompt operations.
* **Lifecycle & Expiration**: Keys structured as `${userId}:${YYYY-MM-DD}`. Can be reset via `resetQuotaState()`.
* **Persistence Layer**: **NONE** (100% in-memory).
* **Process Restart Behavior**: Daily usage counts reset to 0 upon process restart.
* **Multi-Instance Behavior**: **UNSAFE (HIGH)**. A user can consume up to N times their daily quota (where N is the number of backend instances), incurring unexpected LLM API costs on OpenRouter.
* **Failure Mode**: Financial exhaustion / API quota bypass across multiple backend nodes.

---

### 6. AI Circuit Breaker (`circuitBreaker.js`)

* **File**: [`Backend/core/infra/circuitBreaker.js`](file:///f:/JustUS/Backend/core/infra/circuitBreaker.js#L3)
* **Data Structure**: `const circuits = new Map();`
* **Purpose**: Monitors OpenRouter API failures; opens the circuit for a cooldown period (`env.aiCircuitBreakerCooldownMs = 60s`) when failures exceed threshold (`env.aiCircuitBreakerThreshold = 5`).
* **Lifecycle & Expiration**: Resets failures on success; opens circuit for 60 seconds on threshold breach.
* **Persistence Layer**: **NONE** (100% in-memory).
* **Process Restart Behavior**: Resets circuit state to healthy on restart.
* **Multi-Instance Behavior**: **PARTIALLY INCOMPLETE**. If upstream OpenRouter experiences an outage, Instance A will open its circuit, but Instance B will continue attempting failed API requests until it independently encounters 5 failures.
* **Failure Mode**: Increased downstream latency and redundant failed API calls across un-synchronized instances during upstream outages.

---

## Summary Matrix of In-Memory State Mechanisms

| Mechanism | File | Storage Type | Multi-Instance Safe? | Risk / Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Request Nonce Store** | `core/infra/nonceStore.js` | In-Memory + DB Fallback | **PARTIALLY** | Race condition replay attacks under concurrent loads |
| **Composite Rate Limiter** | `middleware/rateLimit.js` | 100% In-Memory | **UNSAFE** | Rate limits & IP bans bypassed completely across multi-node cluster |
| **Login Risk & Strikes** | `features/auth/authRisk.service.js` | 100% In-Memory | **UNSAFE** | Brute-force credential stuffing bypass |
| **Idempotency Cache** | `core/infra/idempotencyStore.js` | 100% In-Memory | **UNSAFE** | Duplicate processing on retried requests routed to different nodes |
| **AI Daily Quota** | `core/infra/quotaService.js` | 100% In-Memory | **UNSAFE** | Users can exceed daily token budget N-fold across N instances |
| **AI Circuit Breaker** | `core/infra/circuitBreaker.js` | 100% In-Memory | **PARTIALLY INCOMPLETE** | Delayed failure propagation during third-party API outages |

---

## Recommended Remediation Architecture

To make the backend multi-instance ready, safe for horizontal scaling, and resilient against process crashes:

1. **Redis / KeyDB Integration**:
   - Replace in-memory `Map` structures in `rateLimit.js`, `authRisk.service.js`, `quotaService.js`, and `idempotencyStore.js` with an external distributed key-value store (e.g. Redis / Upstash Redis / Valkey).
   - Use atomic operations (`INCRBY`, `EXPIRE`, `SETNX`) for rate limiting and token quota tracking.

2. **Atomic Nonce Reservation**:
   - Shift `nonceStore.js` logic to rely strictly on atomic database constraints (`UNIQUE` index on `(namespace, user_id, nonce)`) or Redis `SET key value NX EX duration` to eliminate race conditions between memory checks and DB inserts.

3. **Distributed Circuit Breaker**:
   - Store circuit state in Redis or broadcast circuit status changes via Pub/Sub so all backend instances immediately halt requests when an upstream provider fails.

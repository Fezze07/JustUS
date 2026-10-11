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
* **Persistence Layer**: Postgres-first — the insert into `request_nonces` is the authoritative replay check; the memory map is only a cache set **after** the insert is accepted. `request_nonces.nonce` carries a `UNIQUE` constraint.
* **Process Restart Behavior**: In-memory cache is wiped on restart; the database table remains the store of record and continues to reject replays.
* **Multi-Instance Behavior**: **SAFE**. The `request_nonces` insert is the authoritative check and `nonce` is `UNIQUE`, so concurrent inserts of the same nonce from different instances resolve atomically in the database — exactly one succeeds, the other fails with `23505` and is rejected. The memory map is only a cache of nonces already accepted by this process, so a cold node cannot accept a nonce the database already holds.
* **Failure Mode**: If the database is unreachable, protection degrades to memory-only (fail-open on non-`23505` DB errors), bounded by the accepted single-instance deployment assumption.

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
* **Multi-Instance Behavior**: **UNSAFE (HIGH)**. Request volume is split across backend nodes. An attacker submitting 100 requests across 4 load-balanced instances will only trigger 25 requests per instance, completely bypassing configured rate limits and penalty strike bans. Severity aligned with `docs/backend/security/doc.md`; the single-instance deployment is accepted.
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
| **Request Nonce Store** | `core/infra/nonceStore.js` | Postgres-first (`request_nonces`) + Memory cache | **SAFE** | Single-winner atomic reservation via DB `UNIQUE (nonce)`; memory-only fallback when the DB is unreachable |
| **Composite Rate Limiter** | `middleware/rateLimit.js` | 100% In-Memory | **UNSAFE** | Rate limits & IP bans bypassed completely across multi-node cluster |
| **Login Risk & Strikes** | `features/auth/authRisk.service.js` | 100% In-Memory | **UNSAFE** | Brute-force credential stuffing bypass |
| **Idempotency Cache** | `core/infra/idempotencyStore.js` | 100% In-Memory | **UNSAFE** | Duplicate processing on retried requests routed to different nodes |
| **AI Daily Quota** | `core/infra/quotaService.js` | 100% In-Memory | **UNSAFE** | Users can exceed daily token budget N-fold across N instances |
| **AI Circuit Breaker** | `core/infra/circuitBreaker.js` | 100% In-Memory | **PARTIALLY INCOMPLETE** | Delayed failure propagation during third-party API outages |

---

## Recommended Remediation Architecture

> **Decision:** no shared store (Redis/KeyDB) is adopted. The backend runs as a single instance, so the per-process mechanisms below are accepted constraints rather than defects. This section is retained as the reference design that horizontal scaling would require — it is not an active work item.

To make the backend multi-instance ready, safe for horizontal scaling, and resilient against process crashes:

1. **Redis / KeyDB Integration**:
   - Replace in-memory `Map` structures in `rateLimit.js`, `authRisk.service.js`, `quotaService.js`, and `idempotencyStore.js` with an external distributed key-value store (e.g. Redis / Upstash Redis / Valkey).
   - Use atomic operations (`INCRBY`, `EXPIRE`, `SETNX`) for rate limiting and token quota tracking.

2. **Atomic Nonce Reservation** (**implemented 2026-10-11 — no shared store needed**): `nonceStore.js` inserts into `request_nonces` first and treats the DB `UNIQUE (nonce)` violation (`23505`) as a replay, so the atomicity no longer depends on the memory check.

3. **Distributed Circuit Breaker**:
   - Store circuit state in Redis or broadcast circuit status changes via Pub/Sub so all backend instances immediately halt requests when an upstream provider fails.

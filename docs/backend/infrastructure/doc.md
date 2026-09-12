# Backend Infrastructure & Operations Analysis

## Overview

This document provides a reverse-engineering analysis of the Node.js/Express infrastructure layer in JustUS, covering application initialization, middleware registration, background retention jobs, schedule sweeps, environment loading, barrel exports, and infrastructure discrepancy verification.

---

## Application Startup & Initialization Sequence

The application initialization sequence follows a strict synchronous-to-asynchronous progression ([`index.js`](file:///f:/JustUS/Backend/index.js), [`app.js`](file:///f:/JustUS/Backend/app.js), [`config/env.js`](file:///f:/JustUS/Backend/config/env.js)):

```
1. Environment Resolution (config/loadEnv.js)
   └── Reads JUSTUS_ENV_FILE or NODE_ENV (.env / .env.test) via dotenv.config()
2. Configuration Object Initialization (config/env.js)
   └── Parses numbers, lists, defaults (e.g. port: 5001, requestTimeoutMs: 15,000)
3. Barrel Import Resolution (all_imports.js)
   └── Exposes lazy getters for 138 modules avoiding circular dependency deadlocks
4. Express App Instantiation (app.js: createApp())
   ├── Disable 'x-powered-by'
   ├── Set 'trust proxy' (env.trustProxy = 1)
   ├── app.use(requestContext)               [Generates requestId]
   ├── app.use(timeoutMiddleware)            [req/res timeout 15s]
   ├── app.use(configureSecurityHeaders)     [Helmet: CSP, HSTS, referrer]
   ├── app.use(handleCors)                   [Origin validation]
   ├── app.use(express.json / urlencoded)    [Body limit 1mb]
   ├── app.use(sanitizeRequest)              [Control-character stripping]
   ├── app.use(requestLogger)                [Access logging]
   ├── app.use('/auth', authCallbackRoutes)  [HTML Email callback pages]
   ├── app.use('/api', createApiRouter())    [Mounts /api/v1 routes]
   └── app.use(errorHandler)                 [Global Express error handler]
5. Server Binding & Listener (index.js)
   └── app.listen(env.port, "0.0.0.0")
6. Background Retention Jobs Launch (core/jobs/retentionJob.js: startRetentionJobs())
   ├── Immediate initial sweeps (Nonces, Logs, R2 Multipart)
   └── Timed interval registrations (setInterval)
```

---

## Background Maintenance & Retention Jobs

Background retention tasks are managed by [`retentionJob.js`](file:///f:/JustUS/Backend/core/jobs/retentionJob.js) and spawned when `startRetentionJobs()` is called at server startup.

### 1. Nonce Sweep (`sweepExpiredNonces`)
- **Target Table**: `public.request_nonces`.
- **Interval**: Every 6 hours (`NONCE_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000`).
- **Logic**: Executes `DELETE FROM request_nonces WHERE expires_at < NOW()`.
- **In-Memory Component**: `nonceStore.js` also runs an in-memory `Map` sweep every 10 minutes (`_sweepExpiredNonces`) to clear in-process JavaScript maps.

### 2. Log Sweep (`sweepOldLogs`)
- **Target Tables**: `logs_security_events`, `logs_api_access`, `logs_api_errors`.
- **Retention Period**: Configured via `LOG_RETENTION_DAYS` env var (default: **90 days**).
- **Interval**: Every 24 hours (`LOG_SWEEP_INTERVAL_MS = 24 * 60 * 60 * 1000`).
- **Logic**: Calculates cutoff date (`Date.now() - LOG_RETENTION_DAYS * 86,400,000`). Executes `DELETE FROM <table> WHERE created_at < cutoff`.

### 3. R2 Incomplete Multipart Upload Abort (`sweepStalMultipartUploads`)
- **Target**: Cloudflare R2 bucket (`env.r2BucketName`).
- **Interval**: Every 6 hours (`MULTIPART_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000`).
- **Threshold**: Aborts uploads initiated more than 48 hours ago (`MULTIPART_MAX_AGE_MS = 48 * 60 * 60 * 1000`).
- **Logic**: Invokes AWS S3 SDK `ListMultipartUploadsCommand`, inspects `Initiated` timestamp, and sends `AbortMultipartUploadCommand` for expired uploads.

---

## Discrepancy & Verification Matrix

| Infrastructure Mechanism | Configured / Intended Behavior | Actual Runtime Behavior | Discrepancy Level | Impact |
|---|---|---|---|---|
| **PostgreSQL `pg_cron` vs. Node Retention** | `SKILL.md` mentions database cron job `cleanup_old_logs` (30 days retention). | Node.js `retentionJob.js` executes daily deletion with `LOG_RETENTION_DAYS` (default **90 days**). | **MEDIUM** | Duplicate cleanup logic; DB retention (30d) conflicts with Node retention (90d). Database cron will delete logs before Node job reaches 90 days. |
| **Nonce Memory Sweep vs. DB Sweep** | `nonceStore.js` sweeps memory every 10 min. `retentionJob.js` sweeps DB every 6h. | Memory sweep deletes in-process key after expiry; DB sweep deletes rows every 6h. | **NONE (SAFE)** | Dual-layer cleanup functions correctly. |
| **In-Memory Rate Limiting Map Sweeping** | `rateLimit.js` sweeps buckets/penalties every 15 min. | `_sweepRateLimitMaps()` deletes expired window entries. | **NONE (SAFE)** | Prevents unbounded memory growth. |
| **Module Barrel Export Pattern** | `all_imports.js` provides single import interface using ES5 getters. | 138 modules registered as dynamic getters (`get AppError() { return require(...); }`). | **NONE (SAFE)** | Prevents circular dependency deadlocks at startup. |
| **HTML Callback Pages** | `/auth/callback` & `/auth/invite-callback` serve static HTML pages. | Defined in `routes/authCallbacks.js` using `templates/callbackPage.js`. | **NONE (SAFE)** | Serves friendly confirmation UI when deep links fail on desktop browsers. |

---

## Document Status

Document created and saved to [`docs/backend/infrastructure/doc.md`](file:///f:/JustUS/docs/backend/infrastructure/doc.md).

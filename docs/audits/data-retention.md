# Data Retention Mechanisms & Policy Discrepancy Audit

## Executive Summary

This audit evaluates all automated data retention and cleanup mechanisms across the JustUS platform (Node.js backend, PostgreSQL / Supabase, Cloudflare R2 storage, and Flutter client caches).

It specifically resolves the reported discrepancy between PostgreSQL log retention (30 days) and Node.js backend retention (90 days).

---

## Data Retention Policy & Discrepancy Matrix

| Component | Target Artifact / Table | Scheduled Trigger / Interval | Retention Policy | Active Status | Conflict / Discrepancy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Node.js Log Sweep** | `logs_security_events`<br>`logs_api_access`<br>`logs_api_errors` | Daily via `retentionJob.js` (`sweepOldLogs`) | **90 days** (`LOG_RETENTION_DAYS`) | **ACTIVE** | **YES (Overridden)** |
| **PostgreSQL `cleanup_old_logs()`** | `logs_api_access`<br>`logs_api_errors`<br>`logs_security_events`<br>`logs_notifications` | Stored procedure (`cleanup_old_logs.sql`) | **30 days** (`now() - interval '30 days'`) | **MANUAL / INACTIVE CRON** | **YES (Code Conflict)** |
| **Node.js Nonce Sweep** | `request_nonces` | Every 6h via `retentionJob.js` (`sweepExpiredNonces`) | Expired timestamp (`lt("expires_at", now)`) | **ACTIVE** | None |
| **Node.js In-Memory Nonce Sweep** | `consumedNonces` Map | Every 10 min via `_sweepExpiredNonces()` | Expired timestamp | **ACTIVE** | None (Dual-layer) |
| **Node.js R2 Multipart Sweep** | Cloudflare R2 incomplete multipart uploads | Every 6h via `retentionJob.js` (`sweepStalMultipartUploads`) | **48 hours** (`MULTIPART_MAX_AGE_MS`) | **ACTIVE** | None |
| **Flutter Media Cache** | Local R2 image/video files | Automated via `MediaCacheManager` (`flutter_cache_manager`) | **30 days** (`stalePeriod`) / **300 objects** | **ACTIVE** | None |
| **Flutter Local Checkpoints** | `SharedPreferences` checkpoint keys | Cleared on user logout / data wipe | Indefinite until manual clear or logout | **ACTIVE** | None |

---

## Detailed Investigation: 30-Day (PostgreSQL) vs 90-Day (Node) Discrepancy

### 1. PostgreSQL Function Analysis

* **SQL File**: [`supabase/schemas/public/functions/cleanup_old_logs.sql`](file:///f:/JustUS/supabase/schemas/public/functions/cleanup_old_logs.sql)
* **Defined Policy**:
  ```sql
  DECLARE
    v_cutoff timestamp with time zone := now() - interval '30 days';
  BEGIN
    DELETE FROM public.logs_api_access WHERE created_at < v_cutoff;
    DELETE FROM public.logs_api_errors WHERE created_at < v_cutoff;
    DELETE FROM public.logs_security_events WHERE created_at < v_cutoff;
    DELETE FROM public.logs_notifications WHERE created_at < v_cutoff;
  END;
  ```
* **Cron Registration**: No `pg_cron` schedule migration is committed in `supabase/` (the extension function exists, but `cron.schedule` is not executed via migration script).

### 2. Node.js Retention Job Analysis

* **File**: [`Backend/core/jobs/retentionJob.js`](file:///f:/JustUS/Backend/core/jobs/retentionJob.js#L21-L48)
* **Defined Policy**:
  ```javascript
  const LOG_RETENTION_DAYS = Number(process.env.LOG_RETENTION_DAYS) || 90;
  const cutoff = new Date(Date.now() - LOG_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  ```
* **Execution**: Started automatically in `index.js` on server startup via `startRetentionJobs()`. Runs every 24 hours.

### 3. Resolution of Discrepancy

* **Which behavior is actually active?**
  - **Node.js 90-day retention is currently ACTIVE** at runtime because `retentionJob.js` runs automatically on server initialization.
  - The PostgreSQL `cleanup_old_logs()` SQL function exists in the database schema, but is **NOT actively scheduled via `pg_cron`** in code.
* **What happens if `cleanup_old_logs()` is scheduled in Supabase (`pg_cron`)?**
  - If a DBA or Supabase administrator manually triggers `SELECT public.cleanup_old_logs();` or schedules `pg_cron`, **the 30-day SQL cutoff will silently delete all logs older than 30 days**.
  - When the Node.js `sweepOldLogs()` job subsequently runs expecting a 90-day window, it will find 0 records to delete between 30 and 90 days, effectively shortening the log retention window to 30 days without backend awareness.

---

## Technical Analysis of All Data Retention Layers

### 1. Database & Security Log Cleanup
* **Target Tables**: `logs_security_events`, `logs_api_access`, `logs_api_errors`.
* **Current Active Mechanism**: Node.js `sweepOldLogs()` in `retentionJob.js`.
* **Execution Schedule**: Executed once immediately on server startup, then every 24 hours via `setInterval`.
* **Configuration**: `LOG_RETENTION_DAYS` environment variable (defaults to `90`).
* **Failure Mode**: If `LOG_RETENTION_DAYS` is set higher than 30 and PostgreSQL `cleanup_old_logs()` is enabled via `pg_cron`, PostgreSQL truncates logs at 30 days, violating the backend's configured retention requirement.

---

### 2. Nonce Retention (Replay Attack Prevention)
* **Target Table & Memory**: Supabase `request_nonces` table & `consumedNonces` Map in `nonceStore.js`.
* **Memory Cleanup**: Dual-layer architecture:
  - In-memory `consumedNonces` Map swept every 10 minutes via `_sweepExpiredNonces()` in `nonceStore.js`.
  - Database table `request_nonces` swept every 6 hours via `sweepExpiredNonces()` in Node.js `retentionJob.js` using `.lt("expires_at", now)`.
* **Effectiveness**: **SAFE & CONSISTENT**. Dual-layer cleanup prevents memory leaks while ensuring stale database nonces are purged.

---

### 3. Cloudflare R2 Stale Multipart Upload Cleanup
* **Target Bucket**: Cloudflare R2 `just-us` storage bucket.
* **Mechanism**: `sweepStalMultipartUploads()` using AWS S3 SDK (`ListMultipartUploadsCommand` and `AbortMultipartUploadCommand`).
* **Execution Schedule**: Runs every 6 hours (`MULTIPART_SWEEP_INTERVAL_MS`).
* **Cutoff Period**: 48 hours (`MULTIPART_MAX_AGE_MS = 48 * 60 * 60 * 1000`).
* **Effectiveness**: **ACTIVE & NECESSARY**. Prevents abandoned or interrupted chunked file uploads from consuming storage quota indefinitely.

---

### 4. Client-Side Media & Storage Cache Retention (Flutter)
* **Media Cache**: Managed by `MediaCacheManager` ([`media_cache_manager.dart`](file:///f:/JustUS/Flutter/lib/core/media/media_cache_manager.dart#L15)).
  - **Stale Period**: 30 days (`stalePeriod: Duration(days: 30)`).
  - **Object Cap**: Maximum 300 objects (`maxNrOfCacheObjects: 300`).
  - **Behavior**: Downloads and caches signed R2 media locally. Older files are automatically purged when exceeding 30 days or when the 300 object limit is breached.
* **Local Checkpoints**: Managed by `CacheService` ([`cache_service.dart`](file:///f:/JustUS/Flutter/lib/core/local_storage/cache_service.dart)).
  - **Keys**: `chk_game_answers`, `chk_moods`, `chk_bucket_items`, `chk_drive_items`, `chk_miss_you`.
  - **Retention**: Persisted in `SharedPreferences` until explicitly cleared via `LogoutUtils.performLogout()` or user data wipe (`ProfileState.debugWipeData()`).

---

## Recommended Remediation Plan

1. **Unify Log Retention Standard**:
   - Align PostgreSQL `cleanup_old_logs.sql` and Node.js `LOG_RETENTION_DAYS` to a single authoritative retention policy.
   - Update `cleanup_old_logs.sql` to accept an explicit interval parameter or default to 90 days matching `LOG_RETENTION_DAYS`:
     ```sql
     CREATE OR REPLACE FUNCTION public.cleanup_old_logs(p_days integer DEFAULT 90)
       RETURNS void
       LANGUAGE plpgsql
       AS $function$
     BEGIN
       DELETE FROM public.logs_api_access WHERE created_at < (now() - (p_days || ' days')::interval);
       DELETE FROM public.logs_api_errors WHERE created_at < (now() - (p_days || ' days')::interval);
       DELETE FROM public.logs_security_events WHERE created_at < (now() - (p_days || ' days')::interval);
       DELETE FROM public.logs_notifications WHERE created_at < (now() - (p_days || ' days')::interval);
     END;
     $function$;
     ```

2. **Single Primary Driver**:
   - Prefer executing retention cleanup either purely in PostgreSQL (`pg_cron`) OR purely in Node.js (`retentionJob.js`) to avoid redundant database round-trips.

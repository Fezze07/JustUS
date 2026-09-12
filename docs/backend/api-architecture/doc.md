# System Communication Architecture & Service Dependency Map

## Overview

This document provides a reverse-engineering analysis of the communication topology, service interaction patterns, API endpoints, backend middleware chains, external third-party integrations, and direct Supabase database access boundaries in JustUS.

---

## High-Level Communication Topology

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                      Flutter Client                     │
                  └──────────┬──────────────────┬─────────────────┬─────────┘
                             │                  │                 │
              Direct RLS API │                  │ Custom Express  │ WebSocket
              (PostgREST /   │                  │ API (/api/v1)   │ Realtime
              Stored RPCs)   │                  │                 │ Channel
                             ▼                  ▼                 │
                   ┌──────────────────┐  ┌───────────────┐        │
                   │ Supabase Cloud   │  │ Node.js/      │        │
                   │ PostgreSQL /     │  │ Express       │        │
                   │ Auth Service     │  │ Backend Server│        │
                   └─────────▲────────┘  └───────┬───────┘        │
                             │                   │                │
                             │ Admin ServiceRole │                │
                             └───────────────────┼────────────────┘
                                                 │
                   ┌─────────────────────────────┼──────────────────────────────┐
                   │                             │                              │
                   ▼                             ▼                              ▼
      ┌─────────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────┐
      │   Cloudflare R2 Bucket   │   │   OpenRouter AI API      │   │ Firebase Admin FCM API   │
      │  (Pre-signed PUT / GET) │   │ (Chat Completions LLM)   │   │ (Push Notification SDK)  │
      └─────────────────────────┘   └──────────────────────────┘   └──────────────────────────┘
```

---

## Service Inventory & Base URLs

| Service / System | Role / Purpose | Base URL / Entry Point | Auth Mechanism |
|---|---|---|---|
| **Node.js Express Backend** | Custom API business logic, media signing, AI proxies, push dispatch | `https://api.justus.app/api/v1` (or local port) | Supabase JWT Bearer + HMAC Signatures |
| **Supabase Auth & Database** | Primary DB, Auth sessions, Row Level Security (RLS), Realtime WS | `https://<ref>.supabase.co` | JWT Bearer (`anon` / `authenticated` / `service_role`) |
| **Cloudflare R2 Storage** | Object storage for Drive media & Profile pictures | `https://<bucket>.<account>.r2.cloudflarestorage.com` | AWS S3 V4 Pre-signed URLs |
| **OpenRouter AI Gateway** | Multi-model LLM API gateway for relationship question generation | `https://openrouter.ai/api/v1/chat/completions` | API Key (`Bearer ${OPENROUTER_API_KEY}`) |
| **Firebase Cloud Messaging** | Mobile Push Notifications (Android/iOS) | Firebase Admin Node.js SDK v14 | Service Account Private Key JSON |

---

## Hybrid Architectural Boundary: Direct Supabase vs. Backend API

The Flutter client uses a **hybrid architecture** by design:

1. **Direct Supabase Access (PostgREST / RLS / RPC)**:
   - Used for domain CRUD operations that map directly to single tables or PostgreSQL views with strict Row-Level Security (RLS) policies.
   - **Direct Access Features**: Mood tracking (`moods`, RPC `set_mood`), Miss-You signals (`missyou`, RPC `send_missyou`), Bucket List (`bucket_items`), Game answers/history (`game_answers`, `v_game_dashboard`), Drive metadata & favorites (`drive_items`, `favorites`, `v_drive_dashboard`, RPC `get_or_create_emoji`), Partnership requests (`rpc/request_partnership`, `rpc/accept_partnership`).
   - **Architectural Justification**: Eliminates backend boilerplate for simple CRUD while leveraging PostgreSQL RLS for multi-tenant isolation.

2. **Node.js Express Backend API (`/api/v1`)**:
   - Used for operations requiring elevated privileges, third-party API orchestration, HMAC signing, heavy rate limiting, or atomic domain wipes.
   - **Backend API Features**: AI question generation (`POST /api/v1/ai/question`), Pre-signed media upload/download (`/api/v1/media/*`), Push notification dispatch (`/api/v1/notify/*`), Device token registration (`/api/v1/auth/device-token`), Session binding (`/api/v1/auth/session-sync`), Account data wipe (`/api/v1/users/wipe`).

---

## Endpoints Inventory (`/api/v1`)

### 1. AI Feature Endpoints

#### `POST /api/v1/ai/question`
- **Controller**: `generateQuestionController` ([`ai.routes.js`](file:///f:/JustUS/Backend/features/ai/ai.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_ai_call")` $\rightarrow$ `limited(aiRateLimit)` $\rightarrow$ `withIdempotency("ai-question")` $\rightarrow$ `signed("ai-question")` $\rightarrow$ `validated({ body: aiSchema })`
- **Rate Limit**: Composite (`ip`: 10/min, `user`: 6/min, `endpoint`: 20/10min).
- **Idempotency**: 24-hour in-memory cache on `Idempotency-Key` header.
- **External Dependencies**: OpenRouter API (`https://openrouter.ai/api/v1/chat/completions`). Models: `openrouter/free`, `openai/gpt-oss-120b:free`, `nvidia/nemotron-3-super:free`.
- **Database Dependencies**: `get_partnership_names` RPC via `adminSupabase`. Inserts generated question into `game_questions`.

---

### 2. Media & Cloudflare R2 Endpoints

#### `POST /api/v1/media/upload-url`
- **Controller**: `presignUploadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_media_upload")` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `signed("media-upload-url")` $\rightarrow$ `validated({ body: presignSchema })`
- **Request Body**: `{ type, filename, mimeType, size, folder }`.
- **Response**: `{ success: true, uploadUrl, filename, expiresIn }`.
- **External Dependencies**: AWS S3 SDK / Cloudflare R2 API generating pre-signed `PUT` URL.

#### `POST /api/v1/media/complete`
- **Controller**: `completeUploadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `capability("can_media_upload")` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `signed("media-complete")` $\rightarrow$ `validated({ body: completeSchema })`
- **Behavior**: If `kind === "profile"`, updates `user_profiles.profile_pic_url`. Otherwise inserts record into `drive_items`.

#### `GET /api/v1/media/file`
- **Controller**: `redirectToSignedDownloadController` ([`media.routes.js`](file:///f:/JustUS/Backend/features/media/media.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(mediaRateLimit)` $\rightarrow$ `validated({ query: fileQuerySchema })`
- **Behavior**: Verifies user access in `drive_items`, generates S3/R2 pre-signed download URL, and responds with HTTP 302 redirect.

---

### 3. Authentication & Device Endpoints

#### `POST /api/v1/auth/device-token`
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `signed("auth-device-token")` $\rightarrow$ `validated({ body: updateDeviceTokenSchema })`
- **Database Behavior**: Upserts `user_devices` table with `device_token`, `user_id`, `locale`, `user_agent`, `last_ip`.

#### `POST /api/v1/auth/session-sync`
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(authRateLimit)` $\rightarrow$ `freshNonce("auth-session-sync")` $\rightarrow$ `validated({ body: sessionSyncSchema })`
- **Behavior**: Generates `binding_secret` UUID, hashes `device_fingerprint`, upserts `auth_sessions`, returns `{ bindingSecret }`.

#### `POST /api/v1/auth/refresh`
- **Middleware Chain**: `limited(authRefreshRateLimit)` $\rightarrow$ `validated({ body: refreshTokenSchema })`
- **External Dependency**: Calls `authSupabase.auth.refreshSession({ refreshToken })`.

---

### 4. Push Notification Endpoints

#### `POST /api/v1/notify/partner` / `POST /api/v1/notify/:type`
- **Controller**: `sendNotificationController` ([`notify.routes.js`](file:///f:/JustUS/Backend/features/notifications/notify.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(notifyRateLimit)` $\rightarrow$ `validated({ body: notifySchema })`
- **External Dependencies**: Firebase Admin SDK (`messaging.sendEachForMulticast`). Resolves partner FCM token from `user_devices` table and dispatches localized push notification.

---

### 5. User Domain Operations

#### `POST /api/v1/users/wipe`
- **Controller**: `wipeUserDataController` ([`user.routes.js`](file:///f:/JustUS/Backend/features/user/user.routes.js))
- **Middleware Chain**: `authenticated()` $\rightarrow$ `limited(userRateLimit)`
- **Database Dependencies**: Invokes `adminSupabase.rpc("debug_wipe_user_data", { p_user_id: userId })`.

---

### 6. System & Health Routes

#### `GET /api/v1/ping`
- Returns `{ status: "ok" }` health check.

#### `GET /api/v1/app-version`
- Queries `app_versions` table for latest app version info and minimum supported build number.

---

## Document Status

Document created and saved to [`docs/backend/api-architecture/doc.md`](file:///f:/JustUS/docs/backend/api-architecture/doc.md).

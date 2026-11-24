---
name: security-hardening
description: Comprehensive security architecture for JustUS, covering Flutter, Node backend, Supabase, R2, and AI integration. Enforces request signing, JWT validation, RBAC, and abuse controls.
risk: unknown
source: local
version: "1.0"
tags: [security, hardening, architecture, auth, jwt, rbac, supabase, cloudflare, r2, ai-security]
---

# Security Hardening

## Scope

This document describes the current security architecture of the project across:

- `Flutter_app`
- `Backend`
- `supabase`
- Cloudflare R2
- Resend
- the isolated AI integration path

It reflects the current application design and separates:

- controls already enforced in code
- controls that depend on external configuration
- controls that are recommended but not yet fully automated

## Current Architecture

### Trust Boundaries

The stack is intentionally split into two paths:

1. `Flutter -> Supabase` only for operations that are safe under Row Level Security
2. `Flutter -> Backend` for any request that can be abused, replayed, escalated, or used to access privileged services

Current rule:

- if a request is safe with RLS and only needs user-scoped data, it can stay client-side
- if a request can be abused, trigger costs, send email, upload files, call AI, or expose infrastructure, it must go through the backend

### High-Level Flow

#### Client-side safe path

`Flutter -> Supabase Auth / PostgREST / Realtime`

Allowed only when all of the following are true:

- the client uses the public anon key
- the table is protected with RLS
- the operation is user-scoped
- no privileged side effect is involved

#### Sensitive path

`Flutter -> Node backend -> Supabase / R2 / Resend / AI service`

Used for:

- AI requests
- signed media uploads
- signed media downloads
- email sending
- session/device synchronization
- anomaly logging
- any privileged or billable logic

## Authentication and Session Model

### Authentication Source

Supabase Auth is the only authentication system.

Implemented behavior:

- Flutter authenticates users with Supabase Auth
- Node verifies Supabase JWTs on protected routes
- backend resolves the current app user and security context after JWT validation

### Backend JWT Validation

Protected backend endpoints validate:

- bearer token presence
- JWT integrity
- authenticated Supabase user identity
- current application user/profile lookup

The backend is the policy enforcement point for privileged operations.

### Short-Lived Token Policy

The backend enforces a maximum accepted access-token lifetime using environment configuration.

Current behavior:

- the backend inspects token issue/expiry timestamps
- tokens exceeding the configured max lifetime are rejected

This complements Supabase Auth configuration but does not replace it. Supabase must still be configured to issue short-lived access tokens.

### Token Binding

The backend applies soft token binding for authenticated backend traffic.

Binding signals currently used:

- `device fingerprint`
- `user-agent hash`
- `IP range` as a soft heuristic

Current behavior:

- session sync stores binding metadata in `auth_sessions`
- later protected requests compare the active request with stored binding data
- a hard mismatch on device or user-agent binding can force re-authentication
- an IP-range change is treated as a soft anomaly signal instead of an immediate hard failure

This reduces the value of a stolen bearer token outside the original client context.

### Session and Device Tracking

The backend stores security session metadata, including:

- `userId`
- device fingerprint
- user-agent hash
- IP
- IP range
- country when available
- login timestamp
- last seen timestamp
- request profile hash
- binding secret used for request signing

This supports:

- remote invalidation patterns
- suspicious access detection
- login anomaly detection
- stronger request binding

## Request Security Model

### Signed Requests

Critical backend requests are signed by the Flutter app using a session-scoped secret returned by the backend after session synchronization.

Signed request inputs:

- request payload
- request timestamp
- request nonce
- route/action identifier
- session binding secret

The backend verifies the HMAC before continuing.

This is currently used for sensitive authenticated flows such as:

- device/session binding bootstrap
- AI requests
- media upload URL generation
- media upload completion

### Replay Protection

Replay protection uses:

- unique nonce per request
- timestamp freshness window
- backend nonce persistence

Current behavior:

- duplicate nonce usage is rejected
- stale signed requests are rejected
- public sensitive endpoints can require a fresh nonce even when they do not use the authenticated session-signing flow

This reduces replay of AI, email, or other critical requests.

### Idempotency

The backend supports idempotency for side-effecting operations.

Purpose:

- prevent duplicate email sends
- reduce duplicate AI execution caused by retries
- protect sensitive flows from accidental double submission

Idempotency and replay protection are complementary:

- idempotency controls duplicate intent
- nonce/signature validation controls tampering and replay

## Authorization Model

### RBAC

The backend now supports application roles beyond a simple `user/admin` model.

Current role model is stored at the app-data layer and includes support for roles such as:

- `user`
- `premium`
- `system`
- `ai-worker`
- `moderator`

### Capability-Based Access Control

Capability checks are enforced per endpoint where finer control is needed.

Examples of capabilities already reflected by backend policy:

- `can_ai_call`
- `can_media_upload`
- `can_upload_large`

Current behavior:

- routes can require explicit capabilities
- large upload behavior depends on capability instead of role alone
- authorization is evaluated server-side on each privileged request

## Backend Security Controls

### HTTP Layer

The Node backend currently includes:

- `helmet`
- CSP and other hardened security headers
- HSTS
- `X-Content-Type-Options`
- `Referrer-Policy`
- `x-powered-by` disabled
- restricted CORS allowlist
- JSON/body size limit
- request timeout

### Validation and Sanitization

The backend validates request input and sanitizes inbound data before business logic.

Controls in place:

- schema validation for body, params, and query
- inbound sanitization middleware
- centralized error handling

### Rate Limiting and Abuse Controls

The backend includes layered abuse protection by:

- IP
- userId
- endpoint

AI routes are intentionally more restrictive than generic authenticated routes.

Progressive throttling behavior is implemented as an escalation path:

1. first abuse signals add a short delay
2. repeated abuse increases response delay
3. continued abuse triggers limiting
4. repeated violations lead to temporary ban

This is designed to slow automation without immediately harming legitimate users.

### Logging and Monitoring

The backend captures:

- API access logs
- error logs
- failed login attempts
- anomaly events
- rate-limit and abuse events

The system is designed for operational visibility, not just request handling.

## Supabase Security Model

### Public vs Privileged Keys

Key separation is mandatory:

- `anon key` stays in the client
- `service_role` stays only on the backend

The Flutter app must never contain:

- Supabase service role
- R2 credentials
- Resend secrets
- internal AI secrets

### Row Level Security

RLS is the foundation for all direct client-side Supabase access.

Current expectation:

- all client-accessed tables are protected by RLS
- backend-only tables remain inaccessible to the client
- sensitive operational tables are readable/writable only by backend service context

### Security Tables and Metadata

The current schema design includes security-supporting tables and fields such as:

- `auth_sessions`
- `auth_login_attempts`
- `request_nonces`
- app-level role and capability fields on the user record

These support:

- anomaly detection
- signed request validation
- token binding
- authorization

## Storage Security (Cloudflare R2)

### Access Model

R2 is treated as private storage.

Current behavior:

- uploads are brokered by the backend
- downloads are brokered by signed URLs generated by the backend
- the Flutter app no longer needs raw bucket credentials

### Upload Validation

Before an upload is accepted, the backend can validate:

- MIME type
- size
- file naming

The backend also normalizes file naming to avoid trusting client-provided names.

Large uploads can be restricted behind dedicated capability checks.

## Email Security (Resend)

### Email Sending is backend-only

Current protection layers:

- rate limiting
- CAPTCHA on sensitive auth-adjacent flows
- nonce freshness / anti-replay for public or abuse-prone requests
- idempotency support for duplicate submission control

The Flutter app must never talk directly to Resend.

## AI Security Model

### AI Path

The intended path is:

`Flutter -> Backend gateway -> isolated AI service`

The backend mediates every AI call.

### Protections Already Reflected

AI requests are protected by:

- JWT validation
- capability checks
- per-user restriction
- stricter rate limiting
- quota enforcement
- max-token limits
- request timeout
- circuit-breaker protection
- idempotency support
- signed request verification

### Isolation Goal

The architecture is designed so the AI layer can be isolated from:

- the main app database
- core backend services
- public client traffic

This means the AI service should not become a privileged shortcut into the main application stack.

## Cloudflare Edge Security

The codebase assumes Cloudflare provides an additional edge layer, especially for:

- WAF
- bot filtering
- edge rate limits
- country metadata headers

Some anomaly detection logic already benefits from headers like Cloudflare country information when available.

These protections are not fully enabled by code alone and must be configured in Cloudflare.

## Response Watermarking

Sensitive backend responses can include response watermark metadata tied to the active user/session context.

Purpose:

- support leak investigation
- help trace internal or privileged data exposure

This is currently a lightweight response-layer measure, not a full forensic watermarking system.

## What Is Enforced in Code vs External Configuration

### Enforced in Code

- Supabase JWT validation on backend routes
- session tracking and anomaly logging
- token binding checks
- signed requests for critical flows
- nonce-based replay protection
- RBAC and capability checks
- input validation and sanitization
- progressive throttling and temporary bans
- CORS, headers, body-size limit, timeout
- backend-brokered R2 access
- backend-only email sending
- AI quotas, limits, timeout, and circuit breaker

### Requires External Configuration

- short Supabase access-token lifetime
- refresh-token rotation
- one-time-use refresh tokens
- Cloudflare WAF and bot protection
- Cloudflare edge rate limits
- private R2 bucket settings
- R2 versioning
- Resend domain verification
- production API key management
- database backups / PITR
- deployment rollback strategy

### Recommended but Not Fully Automated

- stronger AI prompt-injection filtering
- more advanced behavioral anomaly scoring
- remote session-management UI
- full disaster-recovery runbooks
- richer watermarking for exported sensitive datasets

## Operational Rule

The governing rule for this project remains:

- if a request can be abused, it must go through the backend
- if it is safe under RLS and fully user-scoped, it can remain client-side

That rule should be applied consistently whenever new features are added.

# Email Functionality & Dispatch Architecture Audit

## Executive Summary

This audit evaluates all email-related declarations, capabilities, endpoints, templates, and dispatch mechanisms in the JustUS codebase across the Flutter client, Node.js Express backend, and Supabase database infrastructure.

### Core Finding

**Actual Email Dispatch from Backend/Node.js is COMPLETELY ABSENT / DECLARED BUT UNUSED.**

* No SMTP client, mailer SDK (Nodemailer, Resend, SendGrid, Mailgun), or email service module exists in the Node.js backend (`Backend/`).
* The system role capability `can_send_email` is declared in `authorization.service.js`, but has **zero consumers or middleware enforcement in code**.
* Partner invitations (`POST /api/v1/auth/invite`) store rows in Postgres via Supabase RPC (`request_partnership`), but **do not dispatch any email notification**.
* Email verification relies entirely on Supabase's native built-in Auth SMTP service (or local Supabase Inbucket in development).

---

## Technical Investigation by Component

### 1. `can_send_email` Capability Declaration

* **File**: [`Backend/features/auth/authorization.service.js`](file:///f:/JustUS/Backend/features/auth/authorization.service.js#L25)
* **Declaration**:
  ```javascript
  system: [
    "can_media_upload",
    "can_profile_update",
    "can_ai_call",
    "can_upload_large",
    "can_send_email",
    "can_system_access",
  ]
  ```
* **Investigation**:
  - `can_send_email` is defined as a capability string assigned strictly to the `system` role.
  - A project-wide code search reveals **zero usages** of `can_send_email` in route middleware (`authorizeCapabilities`), controllers, or background jobs.
* **Status**: **DECLARED BUT UNUSED**.

---

### 2. Partner Invitation Flow (`invitePartnerController`)

* **File**: [`Backend/features/auth/auth.controller.js`](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L164-L182)
* **Endpoint**: `POST /api/v1/auth/invite`
* **Incoming Payload**: `{ email: "partner@example.com", partnershipCode: "JUST-1234" }`
* **Flow Trace**:
  1. Calls `resolveRequestedPartnerOrNull(email, partnershipCode)` to resolve the recipient user and profile in Supabase.
  2. Executes `adminSupabase.rpc("request_partnership", { partner_email: email, partner_code: partnershipCode, override_sender_id: user.profileId })`.
  3. Returns JSON response `{ success: true, data }`.
* **Mail Dispatch Verification**:
  - **No email is dispatched** during the invitation flow.
  - The database RPC creates a pending row in `partnership_invitations` and registers an in-app notification in `notifications`.
* **Status**: **PARTIALLY IMPLEMENTED (In-App Database Record Only; No Outbound Email Dispatch)**.

---

### 3. Auth Callback Pages & HTML Templates

* **Files**:
  - [`Backend/routes/authCallbacks.js`](file:///f:/JustUS/Backend/routes/authCallbacks.js)
  - [`Backend/templates/callbackPage.js`](file:///f:/JustUS/Backend/templates/callbackPage.js)
* **Endpoints**:
  - `GET /callback` (Web callback for email confirmation fallback)
  - `GET /invite-callback` (Web callback for partner invitation deep link fallback)
* **Functionality**:
  - Renders a responsive, mobile-friendly HTML landing page ("Email Confermata!" / "Invito Accettato!").
  - Used as HTTP redirect targets when deep-linking from native mobile apps to web browsers fails.
* **Status**: **IMPLEMENTED (HTML Presentation Pages)**.

---

### 4. Supabase Native Email Verification (Auth Subsystem)

* **Files**:
  - [`Flutter/lib/features/auth/auth_state.dart`](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L331)
  - [`Backend/routes/authCallbacks.js`](file:///f:/JustUS/Backend/routes/authCallbacks.js#L22)
* **Mechanism**:
  - User registration (`registerWithEmail`) delegates authentication directly to Supabase Auth (`supabase.auth.signUp()`).
  - Supabase handles outbound email verification links natively using its configured SMTP server or local Inbucket interface.
  - Clicking the link verifies the user's email in `auth.users` and redirects to `/callback` or the deep link scheme (`justus://`).
* **Status**: **IMPLEMENTED (Offloaded to Supabase Auth Managed Infrastructure)**.

---

## Detailed Callers & Implementation Status Matrix

| Component / Flow | File Path | Direct Callers | Mailer Implementation | Status |
| :--- | :--- | :--- | :--- | :--- |
| **`can_send_email` Capability** | `Backend/features/auth/authorization.service.js` | None | None | **DECLARED BUT UNUSED** |
| **Partner Invitation Endpoint** | `Backend/features/auth/auth.controller.js` | `POST /api/v1/auth/invite` | Inserts DB record via Supabase RPC; no email sent | **PARTIALLY IMPLEMENTED** |
| **Email Signup & Verification** | `Flutter/lib/features/auth/auth_state.dart` | `RegisterScreen` | Offloaded to Supabase Auth managed SMTP | **IMPLEMENTED (Supabase)** |
| **Web Callback HTML Templates** | `Backend/templates/callbackPage.js` | `Backend/routes/authCallbacks.js` | Serves HTML page for browser redirects | **IMPLEMENTED (Static HTML)** |
| **Backend Mailer Service / SDK** | N/A | None | No Nodemailer / Resend / SendGrid / SMTP integration | **COMPLETELY ABSENT** |

---

## Architectural Findings & Recommendations

1. **Absence of Backend Mail Transport**:
   - The backend contains no Nodemailer or email provider SDK. All partner invitations require users to already have an active account or share their `partnershipCode` manually or via in-app notification.
   - If transactional invitation emails are desired for unregistered recipients, a mailer service (e.g. Resend / Nodemailer) must be integrated into `invitePartnerController`.

2. **Unused `can_send_email` Capability**:
   - `can_send_email` should either be bound to an authorization middleware guarding mail endpoints or pruned from `authorization.service.js` to eliminate dead configuration declarations.

# Email Functionality & Dispatch Architecture Audit

## Executive Summary

This audit evaluates all email-related declarations, capabilities, endpoints, templates, and dispatch mechanisms in the JustUS codebase across the Flutter client, Node.js Express backend, and Supabase database infrastructure.

### Core Finding

**Actual Email Dispatch from Backend/Node.js is COMPLETELY ABSENT / DECLARED BUT UNUSED.**

* The project uses **Supabase Auth SMTP** (configured with Resend in the online Supabase project) for Auth emails (confirm sign-up, invite user, reset password, password changed, etc.). The custom SMTP sender is `team@mail.justus.serverfede.eu` via `smtp.resend.com:465`.
* No additional mailer SDK (Nodemailer, Resend SDK, SendGrid, Mailgun) is installed or used by the Node.js backend (`Backend/`).
* Partner invitations (`POST /api/v1/auth/invite`) store rows in Postgres via Supabase RPC (`request_partnership`) and do **not** dispatch any email notification. The code-sharing flow is manual (partners must share the 6-char `partnershipCode`). There is no Supabase Auth "invite" email triggered by the custom `invite-partner` endpoint in this codebase.
* Email verification for Supabase Auth is handled by Supabase's configured SMTP (or local Supabase Inbucket in development).

---

## Technical Investigation by Component

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
  - The database RPC creates a pending row in `public.partnerships` (`status = 'pending'`). Neither `partnership_invitations` nor `notifications` tables exist in the schema.
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
| **Partner Invitation Endpoint** | `Backend/features/auth/auth.controller.js` | `POST /api/v1/auth/invite` | Inserts DB record via Supabase RPC; no email dispatched | **IMPLEMENTED (no email)** |
| **Email Signup & Verification** | `Flutter/lib/features/auth/auth_state.dart` | `RegisterScreen` | Offloaded to Supabase Auth SMTP (Resend) | **IMPLEMENTED (Supabase)** |
| **Web Callback HTML Templates** | `Backend/templates/callbackPage.js` | `Backend/routes/authCallbacks.js` | Serves HTML page for browser redirects | **IMPLEMENTED (Static HTML)** |
| **Backend Mailer Service / SDK** | N/A | None | No Nodemailer/Resend/SendGrid SDK in Node backend (emails go via Supabase SMTP for Auth events) | **NOT USED (Supabase SMTP)** |

---

## Architectural Findings & Recommendations

1. **No Email Sent for Partnership Invites**:
   - Supabase Auth SMTP (Resend) handles Auth transactional emails (confirm sign-up, invite user, reset password, password changed, etc.). The custom `POST /api/v1/auth/invite` (partner invite) does not trigger an email; it only creates a pending `partnerships` row via `request_partnership` RPC. Users must share the 6-char `partnershipCode` manually or out-of-band. No mailer SDK is present in the Node backend.
   - If transactional invitation emails are desired for unregistered recipients, a mailer service (e.g. Resend / Nodemailer) must be integrated into `invitePartnerController`.

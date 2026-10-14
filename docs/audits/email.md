# Email Functionality & Dispatch Architecture Audit

## Executive Summary

This audit evaluates all email-related declarations, capabilities, endpoints, templates, and dispatch mechanisms in the JustUS codebase across the Flutter client, Node.js Express backend, and Supabase database infrastructure.

### Core Finding

**The Node.js backend sends exactly one kind of email, and it does so through Supabase Auth, not a mailer SDK.**

* The project uses **Supabase Auth SMTP** (configured with Resend in the online Supabase project) for Auth emails (confirm sign-up, invite user, reset password, password changed, etc.). The custom SMTP sender is `team@mail.justus.serverfede.eu` via `smtp.resend.com:465`.
* No additional mailer SDK (Nodemailer, Resend SDK, SendGrid, Mailgun) is installed or used by the Node.js backend (`Backend/`).
* Partner **pairing requests** (`POST /api/v1/auth/invite`) store rows in Postgres via the Supabase RPC `request_partnership` and deliberately do **not** dispatch an email: the recipient must already have a JustUs account, so delivery is in-app (PartnerScreen + push notification) and the 6-char `partnershipCode` is shared out-of-band.
* Partner **account invites** (`POST /api/v1/auth/invite-user`, added 2026-10-12) call `adminSupabase.auth.admin.inviteUserByEmail()`, which is what triggers the hosted Supabase Auth **"Invite user"** email (custom Italian template, `{{ .Email }}` / `{{ .ConfirmationURL }}`). The invitee's Auth account is created by GoTrue; no `partnerships` row is written.
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
* **Status**: **PARTIALLY IMPLEMENTED (In-App Database Record Only; No Outbound Email by Design)**.

---

### 2b. Account Invite Flow (`inviteUserController`)

* **File**: [`Backend/features/auth/auth.controller.js`](file:///f:/JustUS/Backend/features/auth/auth.controller.js) (`inviteUserController`)
* **Endpoint**: `POST /api/v1/auth/invite-user`
* **Middleware Chain**: `authenticated()` → `limited(inviteUserRateLimit)` → `signed("auth-invite-user")` → `validated({ body: inviteUserSchema })`
* **Incoming Payload**: `{ email: "partner@example.com", redirectTo: "justus://auth/callback" }`
* **Flow Trace**:
  1. Calls `adminSupabase.auth.admin.inviteUserByEmail(email, { redirectTo })`.
  2. GoTrue creates the invitee's `auth.users` row (`handle_new_auth_user` provisions `public.users` / `user_profiles`) and sends the hosted **"Invite user"** template through Supabase Auth SMTP.
  3. GoTrue's `email_exists` / `user_already_exists` becomes `409 API-VALIDATION-002`; any other failure becomes `500 API-FAIL-001`.
* **Mail Dispatch Verification**:
  - The email is dispatched by GoTrue (Supabase Auth), triggered by the backend admin call. No mailer SDK.
  - **Account-only**: no `partnerships` row is inserted; pairing still needs the invitee's 6-char code after registration.
* **Status**: **IMPLEMENTED (Supabase Auth admin invite)**.

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
| **Partner Pairing Request Endpoint** | `Backend/features/auth/auth.controller.js` | `POST /api/v1/auth/invite` | Inserts DB record via Supabase RPC; no email by design | **IMPLEMENTED (no email, in-app + push)** |
| **Partner Account Invite Endpoint** | `Backend/features/auth/auth.controller.js` | `POST /api/v1/auth/invite-user` | `admin.inviteUserByEmail()` → GoTrue sends the hosted "Invite user" email | **IMPLEMENTED (Supabase Auth SMTP)** |
| **Email Signup & Verification** | `Flutter/lib/features/auth/auth_state.dart` | `RegisterScreen` | Offloaded to Supabase Auth SMTP (Resend) | **IMPLEMENTED (Supabase)** |
| **Web Callback HTML Templates** | `Backend/templates/callbackPage.js` | `Backend/routes/authCallbacks.js` | Serves HTML page for browser redirects | **IMPLEMENTED (Static HTML)** |
| **Backend Mailer Service / SDK** | N/A | None | No Nodemailer/Resend/SendGrid SDK in Node backend (emails go via Supabase SMTP for Auth events) | **NOT USED (Supabase SMTP)** |

---

## Architectural Findings & Recommendations

1. **Two Channels, One Policy (2026-10-12)**:
   - Supabase Auth SMTP (Resend) handles Auth transactional emails (confirm sign-up, invite user, reset password, password changed, etc.). Two partner-related endpoints exist:
     - `POST /api/v1/auth/invite` (pairing request, email + 6-char code) only creates a pending `partnerships` row; the recipient already has an account and is reached in-app / by push.
     - `POST /api/v1/auth/invite-user` (account invite, email only) triggers the hosted Supabase Auth "Invite user" email and creates the invitee's Auth account.
   - No mailer SDK is present in the Node backend; every email the product sends is a Supabase Auth template.
   - Residual: the invite email's landing depends on the client-supplied `redirectTo` being in the Supabase redirect allow-list, and GoTrue's own email rate limits (per-hour, per-project) apply on top of the backend's `inviteUserRateLimit`.

# Login & Registration Flow - JustUS

## Overview

This document provides a comprehensive reverse-engineered analysis of the **Login** and **Registration** flows in the JustUS application. It traces the complete execution paths from the Flutter mobile frontend UI through client-side validation, Cloudflare Turnstile CAPTCHA challenges, backend middleware and security risk services, to Supabase Auth and database trigger executions.

The authentication subsystem in JustUS relies on a hybrid architecture:
- **Client Application**: Flutter (Android, iOS, Web, Desktop) utilizing Provider (`AuthState`, `AuthRepository`, `CaptchaService`).
- **Identity Provider & Auth DB**: Supabase Auth (`supabase_flutter` SDK) managing credentials, JWT generation, email redirects, and PostgreSQL user profile triggers (`handle_new_auth_user`).
- **Security & Risk Backend**: Node.js / Express API (`Backend/features/auth`) enforcing IP and device rate limiting, pre-login risk assessment, device token updates, and session binding tracking.

---

## Registration Flow

### Complete Execution Trace

```
Flutter UI (RegisterScreen)
   │
   ├── 1. Form Input & Parsing (name, email, password)
   │
   ├── 2. Client Validation (Validators.validateRequired, validateEmail, validatePassword)
   │
   ├── 3. CAPTCHA Verification (CaptchaService.getCaptchaToken -> Cloudflare Turnstile modal)
   │
   ├── 4. Supabase Auth Registration (sbClient.auth.signUp)
   │        │
   │        ▼
   │     Supabase Auth Server
   │        │
   │        ├── Inserts record into auth.users
   │        └── Triggers PostgreSQL AFTER INSERT (`handle_new_auth_user`)
   │               │
   │               ├── Inserts public.users (auth_id, email, username)
   │               ├── Inserts public.user_profiles (display_name, partnership_code)
   │               └── Assigns role 'user' in public.user_roles
   │
   ├── 5. Response Processing (AuthResponse returned to Flutter)
   │
   └── 6. State & Navigation Decision
            │
            ├── If authState.isLoggedIn (Token present): Navigate to PartnerScreen
            └── Else (Default): Show VPDialog ("Confirm Email") -> Pop to LoginScreen
```

### Detailed Component Steps

1. **User Interface (`RegisterScreen`)**
   - File: [register_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/register_screen.dart)
   - Controls three input fields (`VPTextField`): Name, Email, and Password.
   - On tapping "Create Account" (`VPButton`), inputs are trimmed and validated.

2. **Client-Side Validation**
   - File: [validators.dart](file:///f:/JustUS/Flutter/lib/shared/utils/ui/validators.dart#L5-L54)
   - Executes three synchronous validation checks:
     - `Validators.validateRequired(context, name, 'Name')`
     - `Validators.validateEmail(context, email)`
     - `Validators.validatePassword(context, password)`
   - If any validation fails, the first encountered error message is displayed via `UIUtils.showSnackBar` (isError: true) and the flow aborts before making any network calls.

3. **Cloudflare Turnstile CAPTCHA Challenge**
   - File: [captcha_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/captcha_service.dart#L10-L104)
   - `AuthState.register` calls `_getCaptchaToken()`.
   - Reads `TURNSTILE_PUB_SITE_KEY` from environment variables (`flutter_dotenv`).
   - Opens an invisible Turnstile challenge modal dialog (`CloudflareTurnstile.invisible`).
   - If token generation succeeds within 30 seconds, returns the string token.
   - If missing site key, timed out, canceled by user, or exception thrown, returns `null` and throws `AppError`.

4. **Supabase Auth Request**
   - File: [auth_repository.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L42-L44)
   - Calls `sbClient.auth.signUp(...)` passing:
     - `email`: user's email address
     - `password`: user's raw password
     - `data`: metadata map `{'username': name}`
     - `emailRedirectTo`: deep link (`justus://auth/callback` on native mobile; web callback URL on web/desktop)
     - `captchaToken`: token from Turnstile

5. **Database Trigger & Profile Provisioning**
   - Documentation: [supabase-triggers](file:///f:/JustUS/.agents/skills/supabase-triggers/SKILL.md#L16-L20) & [supabase-functions](file:///f:/JustUS/.agents/skills/supabase-functions/SKILL.md#L51-L55)
   - Table: `auth.users`
   - Trigger Event: `AFTER INSERT` calling `handle_new_auth_user()`
   - Operation: Atomically creates public user records:
     - Inserts into `public.users` with `auth_id = NEW.id`
     - Inserts into `public.user_profiles` generating an automatic unique `partnership_code` and setting `display_name = NEW.raw_user_meta_data->>'username'`
     - Inserts into `public.user_roles` with role `'user'`

6. **Frontend State & Navigation Post-Registration**
   - File: [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L303-L333)
   - `AuthState.register` receives `AuthResponse`. If `res.user == null`, throws `AppError(authFail001)`.
   - **Crucial Behavior**: `AuthState.register` does **not** invoke `setLoginData`.
   - In `RegisterScreen` ([register_screen.dart:106](file:///f:/JustUS/Flutter/lib/features/auth/screens/register_screen.dart#L106)), `authState.isLoggedIn` is checked:
     - Since `setLoginData` was not called, `isLoggedIn` evaluates to `false`.
     - The screen displays a non-dismissible `VPDialog` informing the user that a confirmation email has been sent to their email address.
     - Upon tapping "Go to Login", the dialog pops and the navigator pops back to `LoginScreen`.

---

## Login Flow

### Complete Execution Trace

```
Flutter UI (LoginScreen)
   │
   ├── 1. Form Input & Parsing (email, password)
   │
   ├── 2. Client Validation (Validators.validateEmail, validatePassword)
   │
   ├── 3. Pre-Login Risk Assessment (Backend POST /api/v1/auth/login-risk-check)
   │        │
   │        ├── Evaluates IP + Device Fingerprint + Email in-memory strikes
   │        └── If blocked: Throws AppError (secBlock002 - HTTP 429) & Aborts
   │
   ├── 4. CAPTCHA Verification (CaptchaService.getCaptchaToken)
   │
   ├── 5. Supabase Auth Authentication (sbClient.auth.signInWithPassword)
   │        │
   │        └── Validates credentials + Turnstile against Supabase Auth
   │
   ├── 6. Profile Fetching (UserRepository.fetchProfileByAuthId)
   │        │
   │        └── Queries public.users + user_profiles via auth_id (UUID)
   │
   ├── 7. Session Storage (AuthState.setLoginData)
   │        │
   │        └── Saves accessToken, refreshToken, username, userId to StorageService
   │
   ├── 8. Backend Session Sync (Backend POST /api/v1/auth/session-sync)
   │        │
   │        ├── Generates bindingSecret & tracks auth_sessions
   │        └── Clears failed login counters on backend (clearFailedLogins)
   │
   ├── 9. FCM Device Token Registration (Backend POST /api/v1/auth/device-token)
   │
   ├── 10. Partnership Resolution (PartnershipRepository.getPartnership)
   │
   └── 11. Navigation Routing
            │
            ├── If hasPartner == true  -> Navigator.pushReplacement(MainShell)
            └── If hasPartner == false -> Navigator.pushReplacement(PartnerScreen)
```

### Detailed Component Steps

1. **User Interface (`LoginScreen`)**
   - File: [login_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/login_screen.dart)
   - User inputs Email and Password.
   - On tapping "Login", client-side validation runs.

2. **Pre-Login Risk Assessment**
   - File: [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L479-L495) & [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L57-L79)
   - Before attempting authentication, Flutter requests `_checkLoginRisk(email)`.
   - Sends HTTP `POST /api/v1/auth/login-risk-check` with body `{ email, deviceFingerprint }`.
   - Backend rate-limiting middleware (`loginRiskRateLimit`) and `checkLoginRisk()` service check if the IP / Device / Email key is currently blocked.
   - If blocked, backend returns `429` with error key `SEC_BLOCK_002` ("Login temporarily blocked"). Flutter receives this and aborts authentication immediately.

3. **CAPTCHA Challenge**
   - File: [captcha_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/captcha_service.dart#L10)
   - Flutter displays the Turnstile challenge modal to acquire a fresh `captchaToken`.

4. **Supabase Authentication**
   - File: [auth_repository.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart#L38-L40)
   - Invokes `sbClient.auth.signInWithPassword(email: email, password: password, captchaToken: captchaToken)`.
   - Returns a Supabase `AuthResponse` containing `res.user` and `res.session`.

5. **Profile Resolution**
   - File: [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L255-L263)
   - Calls `_userRepo.fetchProfileByAuthId(res.user.id)` querying the PostgreSQL `public.users` table.
   - Converts `auth_id` to internal integer `user.id`.

6. **Local Token & Session Persistence**
   - File: [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L413-L429)
   - Invokes `setLoginData()`:
     - Sets in-memory variables (`_accessToken`, `_refreshToken`, `_username`, `_userId`).
     - Persists values securely via `StorageService` (`saveAccessToken`, `saveRefreshToken`, `saveUsername`, `saveUserId`).
     - Calls `notifyListeners()`.

7. **Backend Session Synchronization**
   - File: [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L497-L521) & [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js#L108-L131)
   - Sends `POST /api/v1/auth/session-sync` with `deviceFingerprint` and `deviceLabel`.
   - Backend `trackSession()` creates or updates an `auth_sessions` table entry and returns a `bindingSecret`.
   - Backend calls `clearFailedLogins()` to delete any recorded failed attempt counters for this email/device/IP key.
   - Flutter stores `bindingSecret` in `StorageService` for signing subsequent API requests.

8. **FCM Device Token & Partnership Lookup**
   - Registers FCM token via `POST /api/v1/auth/device-token`.
   - Calls `_partnershipRepo.getPartnership()` querying view `v_active_partnership`.

9. **Navigation Routing**
   - File: [login_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/login_screen.dart#L105-L116)
   - Checks `AuthState.hasPartner` (`_partnerId != null`):
     - `true`: Replaces stack with `MainShell(key: MainShell.shellKey)`.
     - `false`: Replaces stack with `PartnerScreen()`.

---

## Password Validation

Password requirements and their enforcement locations were empirically verified across all application layers:

### Validation Rules Matrix

| Rule | Requirement | Enforced in Flutter | Enforced in Backend | Enforced in Supabase |
|---|---|---|---|---|
| Minimum Length | >= 8 characters | YES (`password.length < 8`) | NO | YES (Configurable, default >= 6/8) |
| Lowercase Letter | Must contain `[a-z]` | YES (`RegExp(r'[a-z]')`) | NO | NO |
| Uppercase Letter | Must contain `[A-Z]` | YES (`RegExp(r'[A-Z]')`) | NO | NO |
| Number | Must contain `[0-9]` | YES (`RegExp(r'[0-9]')`) | NO | NO |
| Special Symbol | Must contain `[!@#\$%^&*(),.?":{}|<>]` | YES (`RegExp(r'[!@#\$%^&*(),.?":{}|<>]')`) | NO | NO |

### Layer Details

1. **Flutter Frontend**
   - File: [validators.dart](file:///f:/JustUS/Flutter/lib/shared/utils/ui/validators.dart#L20-L41)
   - `Validators.validatePassword` runs sequential regex matchers:
     ```dart
     if (password == null || password.isEmpty) return context.loc.auth_validationPasswordRequired;
     if (password.length < 8) return context.loc.auth_validationPasswordMinLength;
     if (!RegExp(r'[a-z]').hasMatch(password)) return context.loc.auth_validationPasswordLowercase;
     if (!RegExp(r'[A-Z]').hasMatch(password)) return context.loc.auth_validationPasswordUppercase;
     if (!RegExp(r'[0-9]').hasMatch(password)) return context.loc.auth_validationPasswordNumber;
     if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) return context.loc.auth_validationPasswordSymbol;
     return null;
     ```

2. **Backend Node.js API**
   - Files: [auth.schemas.js](file:///f:/JustUS/Backend/features/auth/auth.schemas.js) & [auth.routes.js](file:///f:/JustUS/Backend/features/auth/auth.routes.js)
   - The Node backend does **not** process user password inputs during registration or login. Zod schemas (`loginRiskSchema`, `loginAttemptSchema`, `sessionSyncSchema`) do not include password fields.

3. **Supabase Auth**
   - Handles password storage and hash generation (Bcrypt/Argon2). Complex character rules (uppercase, digit, symbol) are not natively evaluated by default Supabase GoTrue unless custom Auth Hooks or client-side checks are enforced.

---

## Turnstile

Cloudflare Turnstile protection is implemented as an invisible challenge in the Flutter frontend and verified server-side during Supabase Auth transactions.

### Key Characteristics

- **Token Origin**: Generated on the client using the `cloudflare_turnstile` package (`CloudflareTurnstile.invisible`).
- **Configuration Key**: `TURNSTILE_PUB_SITE_KEY` loaded via `flutter_dotenv` from `.env`.
- **Target Base URL**: `${ApiConfig.appOrigin}/`.
- **Challenge Lifecycle**:
  - `CaptchaService.getCaptchaToken()` displays a modal `AlertDialog` with a spinner.
  - Runs `_runInvisibleChallenge()` with a 30-second timeout (`.timeout(const Duration(seconds: 30))`).
  - Upon token acquisition or cancellation, closes the dialog and returns the token string (or `null`).
- **Token Transit**: Passed in `sbClient.auth.signInWithPassword(captchaToken:)` and `sbClient.auth.signUp(captchaToken:)`.
- **Backend Service**:
  - File: [turnstileService.js](file:///f:/JustUS/Backend/services/turnstileService.js)
  - Backend contains `verifyTurnstileToken({ token, remoteIp })` which calls `https://challenges.cloudflare.com/turnstile/v0/siteverify`.
  - **Observation**: Backend auth routes (`/login-risk-check`, `/login-attempt`, `/session-sync`) do **not** wire `verifyTurnstileToken` as middleware. Turnstile validation relies strictly on Supabase Auth's native Turnstile integration.

---

## Login Risk Assessment

JustUS features a backend in-memory risk tracking service designed to prevent brute-force attacks via progressive strikes and temporary IP/device blocks.

### Risk Service Specification

- File: [authRisk.service.js](file:///f:/JustUS/Backend/features/auth/authRisk.service.js)
- Storage Mechanism: In-memory `Map` (`loginAttempts = new Map()`). State expires after 15 minutes of inactivity (`15 * 60_000` ms).
- Attempt Key Composition:
  ```js
  const key = [
    sha256(normalizedEmail || "anonymous"),
    sha256(normalizedDevice || "unknown-device"),
    ipAddress || "unknown-ip"
  ].join(":");
  ```

### Progressive Strike Levels & Lockout Schedule

| Total Failures | Strike Level | Action / Lockout Duration | Log Security Event |
|---|---|---|---|
| 0 – 2 | 0 | Allowed | No |
| 3 – 4 | 1 | Allowed (Monitored) | Yes (`login_anomaly`) |
| 5 – 7 | 2 | **Blocked for 10 minutes** (`10 * 60_000` ms) | Yes (`login_anomaly`) |
| 8+ | 3 | **Blocked for 30 minutes** (`30 * 60_000` ms) | Yes (`login_anomaly`) |

### Blocking & Evaluation Order

- Pre-login check (`POST /api/v1/auth/login-risk-check`): Evaluates risk **before** credential verification. If `blocked` is true, throws `AppError(SEC_BLOCK_002)` with HTTP 429 status code.

---

## Error Handling

### Error Transmission Matrix

| Error Scenario | Originating Layer | Backend / Client Exception | Map Code | User Feedback |
|---|---|---|---|---|
| Invalid Email Format | Flutter UI | `Validators.validateEmail` | N/A | Form error SnackBar |
| Invalid Password Format | Flutter UI | `Validators.validatePassword` | N/A | Form error SnackBar |
| Missing Turnstile Config | Flutter Client | `CaptchaService` | `API_VALIDATION_001` | SnackBar error |
| Turnstile Cancel / Timeout | Flutter Client | `CaptchaService` | `LOCAL_UNKNOWN` | SnackBar ("Captcha failed") |
| Risk Blocked (Brute-force) | Backend Node API | `checkLoginRiskController` | `SEC_BLOCK_002` | SnackBar ("Troppi tentativi di login. Riprova tra poco.") |
| Invalid Credentials | Supabase Auth | `AuthException` | `AUTH_FAIL_001` | ErrorHandler Reauth Dialog / SnackBar |
| Profile Missing in DB | Flutter AuthState | `UserRepository` | `DB_NOT_FOUND_001` | SnackBar ("Profilo utente non trovato nel database") |
| Backend Sync Network Error | Node API / Http | `NetworkError` | N/A | Silent log / SnackBar |

---

## Potential Bugs and Inconsistencies

During the reverse-engineering analysis, the following structural bugs, security flaws, and implementation inconsistencies were discovered:

### 1. CRITICAL BUG: Failed Login Attempts Are Never Reported to Risk Engine
- **Finding**: In `Backend/features/auth/auth.routes.js`, endpoint `POST /api/v1/auth/login-attempt` exists to increment failed attempts via `recordFailedLogin()`. In `Flutter/lib/features/auth/auth_repository.dart`, function `reportFailedLogin()` is defined.
- **Defect**: `AuthState.login()` in [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L229-L301) **never calls `reportFailedLogin()`** when Supabase `signInWithPassword()` fails or throws an `AuthException`.
- **Impact**: Failed login attempts are never recorded in `authRisk.service.js`. `loginAttempts` counter stays at 0, strike levels never increment, and brute-force protection through failed attempts is **completely non-functional** in production.

### 2. BUG: Reauth Dialog Infinite Loop / Misleading UI on Login Failure
- **Finding**: When a user enters incorrect credentials on `LoginScreen`, Supabase throws an `AuthException` which `ErrorHandler` maps to `ErrorCodes.authFail001`.
- **Defect**: `ErrorHandler` treats `authFail001` as a critical session expiration error requiring reauthentication, opening a modal `VPDialog` ("Session Expired") on top of `LoginScreen`. Confirming the dialog calls `Navigator.pushNamedAndRemoveUntil('/login')`.
- **Impact**: Entering a wrong password triggers a "Session Expired" pop-up over the login screen itself and reloads the login route.

### 3. BUG: Dead Execution Branch in `RegisterScreen`
- **Finding**: In [register_screen.dart:106](file:///f:/JustUS/Flutter/lib/features/auth/screens/register_screen.dart#L106), registration completion contains an `if (authState.isLoggedIn)` check intended to navigate directly to `PartnerScreen`.
- **Defect**: `AuthState.register()` ([auth_state.dart:303-333](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart#L303-L333)) only invokes `sbClient.auth.signUp()` and never calls `setLoginData()`.
- **Impact**: `isLoggedIn` is guaranteed to be `false`. Even if Supabase Auth is configured for instant auto-confirmation without email verification, new users are always forced into the "Confirm Email" dialog and sent back to `LoginScreen`.

### 4. INCONSISTENCY: Password Validation Rules Enforced Only on Client
- **Finding**: Strict regex rules for uppercase, lowercase, numeric, and symbol characters are enforced solely in Flutter's `Validators.validatePassword`.
- **Defect**: Neither the Node backend nor Supabase Auth database rules validate complex password character patterns on registration.
- **Impact**: Any registration request bypassing the Flutter client (e.g., via direct REST API calls) can register accounts with weak passwords.

### 5. SECURITY RISK: Unprotected Backend Risk Check Endpoints
- **Finding**: The Node backend risk check endpoints (`/login-risk-check` and `/login-attempt`) do not verify Turnstile tokens or require request signing (`signed()` middleware is absent on these routes in `auth.routes.js`).
- **Impact**: An attacker can flood `/login-risk-check` or `/login-attempt` with arbitrary email strings to manipulate strike counters or exhaustion limits.

---

## Edge Cases

1. **Network Disconnection During Session Sync**: If Supabase Auth succeeds but the subsequent call to `_syncBackendSession()` fails due to network loss, `AuthState` retains the Supabase session locally. However, `bindingSecret` is not retrieved from the backend, causing subsequent signed backend requests to return `AUTH_FAIL_006` ("Client binding mismatch").
2. **Database Trigger Latency/Failure**: If Supabase Auth creates an `auth.users` row but the PostgreSQL `handle_new_auth_user()` trigger fails or experiences delay, `fetchProfileByAuthId` returns null, triggering `AppError(DB_NOT_FOUND_001)` and halting login despite valid Supabase credentials.

---

## Known Issues

- **Forgot Password Button is a No-Op**: The "Forgot Password?" button in `LoginScreen` ([login_screen.dart:68](file:///f:/JustUS/Flutter/lib/features/auth/screens/login_screen.dart#L68)) has an empty `onPressed: () {}` callback.
- **In-Memory Risk State Reset on Server Restart**: Node backend risk state (`loginAttempts`) is held in Node process memory. Backend restarts clear all active lockout counters and strike levels.

---

## Files and Functions

### Flutter Frontend
- [login_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/login_screen.dart): UI rendering for login form, input controllers, submit triggers.
- [register_screen.dart](file:///f:/JustUS/Flutter/lib/features/auth/screens/register_screen.dart): UI rendering for registration form and email confirmation modal.
- [auth_state.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_state.dart): State management methods `login()`, `register()`, `_checkLoginRisk()`, `_syncBackendSession()`, `setLoginData()`.
- [auth_repository.dart](file:///f:/JustUS/Flutter/lib/features/auth/auth_repository.dart): API wrapper methods `signInWithPassword()`, `signUp()`, `checkLoginRisk()`, `reportFailedLogin()`.
- [captcha_service.dart](file:///f:/JustUS/Flutter/lib/features/auth/captcha_service.dart): Turnstile invisible challenge modal runner `getCaptchaToken()`.
- [validators.dart](file:///f:/JustUS/Flutter/lib/shared/utils/ui/validators.dart): Client input validation regex methods `validateEmail()`, `validatePassword()`, `validateRequired()`.

### Backend Node.js
- [auth.routes.js](file:///f:/JustUS/Backend/features/auth/auth.routes.js): Express routes for `/login-risk-check`, `/login-attempt`, `/session-sync`, `/device-token`.
- [auth.controller.js](file:///f:/JustUS/Backend/features/auth/auth.controller.js): Route handlers `checkLoginRiskController`, `registerFailedLoginController`, `syncSessionController`.
- [authRisk.service.js](file:///f:/JustUS/Backend/features/auth/authRisk.service.js): In-memory risk engine `checkLoginRisk()`, `recordFailedLogin()`, `clearFailedLogins()`.
- [turnstileService.js](file:///f:/JustUS/Backend/services/turnstileService.js): Cloudflare siteverify API client `verifyTurnstileToken()`.

### Supabase / Database
- `auth.users`: Core identity table managed by Supabase Auth.
- `public.users` & `public.user_profiles`: Public profile tables populated by trigger.
- `handle_new_auth_user()`: Stored procedure triggered `AFTER INSERT` on `auth.users`.

---

## Implementation Status

| Feature / Subsystem | Implementation Status | Notes / Caveats |
|---|---|---|
| Registration UI & Form Input | **IMPLEMENTED** | `RegisterScreen` |
| Client Input & Password Validation | **IMPLEMENTED** | `Validators` (Client-side regex) |
| Turnstile CAPTCHA Integration | **IMPLEMENTED** | `CaptchaService` modal challenge |
| Supabase Auth Registration | **IMPLEMENTED** | `signUp()` with metadata & redirect |
| PostgreSQL Profile Trigger | **IMPLEMENTED** | `handle_new_auth_user()` trigger |
| Login Risk Pre-Check | **IMPLEMENTED** | `checkLoginRiskController` & `/login-risk-check` |
| Progressive Strike Engine | **BROKEN / DEFECTIVE** | `reportFailedLogin` is never called by Flutter on login failure |
| Backend Session Sync & Binding | **IMPLEMENTED** | `syncSessionController` & `auth_sessions` |
| FCM Device Token Registration | **IMPLEMENTED** | `updateDeviceToken` |
| Post-Login Navigation Routing | **IMPLEMENTED** | Routes to `MainShell` if partnered, else `PartnerScreen` |
| Forgot Password Flow | **NOT IMPLEMENTED** | Button exists with empty callback |

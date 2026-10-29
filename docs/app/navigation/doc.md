# Flutter Navigation System - JustUS

## Overview

The JustUS Flutter app uses **imperative navigation by name**: `MaterialApp.onGenerateRoute` maps the `AppRoutes` constants to screens, and call sites use `Navigator.pushNamed` / `pushReplacementNamed` / `pushNamedAndRemoveUntil`. There is **no routing package** (`go_router`, `auto_route`) and no `Router`/`onGenerateInitialRoutes`; the route table in `main.dart` is the single source of named destinations. Unknown names return `null`; Flutter's built-in deep-link routing is disabled, so auth callbacks are handled by Supabase instead of the Navigator.

The post-authentication decision (which screen to show after startup, login or password reset) is centralized in `AuthNavigationUtils.determinePostAuthRouteName` / `determinePostAuthDestination`, which return one of `AppRoutes.mainShell`, `AppRoutes.partner` or `AppRoutes.login`. Runtime partnership loss adds a reverse redirect in `MainShell` and `PartnerState`. No `AuthState`/`PartnerState` provider performs forward navigation - the state layer stops at exposing `isLoggedIn` / `hasPartner`, and the callers navigate after awaiting them. The only state-layer navigation is the cancellation reverse teleport in `PartnerState` (through the global navigator key) and the password-recovery push in `AuthState`.

The navigation graph consists of exactly two "shells":

- **Auth shell**: `LoginScreen` / `RegisterScreen` / `SplashScreen` / `PartnerScreen`.
- **App shell**: `MainShell` with a 7-tab `IndexedStack`; it publishes `MainShellScope` so descendants call `MainShell.of(context)?.switchToTab(...)`.

Everything else (`LocalizationScreen`, `ChangePasswordScreen`, `ProfileScreen` pushed from the home menu, `DriveItemScreen`) is pushed **on top** of `MainShell` or `PartnerScreen` and has a back affordance (`VPHeader.onBack`/`Navigator.pop`).

---

## Navigation technology

| Mechanism | Used for | Evidence |
|---|---|---|
| `MaterialApp.home` | `home: SplashScreen()` | `main.dart` |
| `MaterialApp.onGenerateRoute` | `AppRoutes` table: `/`, `/login`, `/register`, `/reset-password`, `/change-password`, `/localization`, `/partner`, `/main`, `/drive/item` (integer argument) | `main.dart` `generateAppRoute` |
| `pushNamed` | `/register`, `/reset-password` (password-recovery event), `/localization`, `/change-password`, `/drive/item` | login_screen.dart, auth_state.dart, profile_screen.dart, drive_screen.dart, favorites_screen.dart |
| `pushReplacementNamed` | Splash/Login/ResetPassword -> post-auth destination; Profile cancellation request -> PartnerScreen; PartnerScreen restore/decline -> MainShell | splash_screen.dart, login_screen.dart, reset_password_screen.dart, profile_screen.dart, partner_screen.dart |
| `pushNamedAndRemoveUntil` | Logout -> LoginScreen; reauth -> LoginScreen; runtime partnership loss -> PartnerScreen (`MainShell`/`PartnerState`, through the global navigator) | logout_utils.dart, error_handler.dart, main_shell.dart, partner_state.dart |
| `pop` | Back buttons, dialogs, register->login footer | register_screen.dart, profile_screen.dart, etc. |
| `MainShell.of(context)` | Cross-tab jumps from content screens (`MainShellScope`) | main_shell.dart, homepage_screen.dart |

Every screen push is by name; the only `MaterialPageRoute` in `lib/` is the one `generateAppRoute` returns. Unknown names return `null`.

`MaterialApp.navigatorKey` is `ErrorHandler.navigatorKey` (error_handler.dart:27) - used by `ErrorHandler` and `CaptchaService` to navigate/show dialogs without a widget context, and by `PartnerState` for the cancellation reverse teleport above pushed routes.

---

## Application entry

`Flutter/lib/main.dart`:

1. `main()` -> `runZonedGuarded` -> ensures binding, `dotenv`, `StorageService.init`, `SupabaseService.initialize`, optional Firebase, `NotificationService.init`, `LanguageProvider.loadSavedLocale`.
2. `runApp(JustUsApp(...))` -> `MultiProvider` (11 eager states) -> `RealtimeSyncScope` -> `Selector2` -> `MaterialApp`.
3. `MaterialApp`: `home: SplashScreen()`, `navigatorKey: ErrorHandler.navigatorKey`, `onGenerateRoute: generateAppRoute`. **Every app start begins at `SplashScreen`**; `initState` fires `unawaited(_checkAuth())`.

There is no `onGenerateInitialRoutes`; a cold-start deep link would be resolved by the default initial-route algorithm, but Flutter's built-in deep-link routing is disabled on Android (`flutter_deeplinking_enabled=false`) so the Supabase SDK's `app_links` listener consumes auth callbacks instead of the Navigator. No `FirebaseMessaging` "getInitialMessage" consumption exists at startup (only local-notification `getNotificationAppLaunchDetails`, and its payload goes to the unlistened `onNotificationTap` stream - see Notification-driven navigation).

---

## SplashScreen

`splash_screen.dart:15-41`:

```
initState -> unawaited(_checkAuth())
_checkAuth:
  try { await authState.init().timeout(8s) } catch { log only }
  if !mounted return
  destination = await AuthNavigationUtils.determinePostAuthRouteName(context)
  if !mounted return
  pushReplacementNamed(destination)
```

Observations:

- The splash **blocks navigation until `AuthState.init()` completes** (secure-storage reads + optional session-bind + optional device-token registration), capped at 8 s.
- `_checkAuth()` wraps only `init()` in a `try/catch`: an initialization error (slow session-bind, lost connection) is **logged and then routed by the same post-auth decision as the happy path**. The catch does **not** force `LoginScreen`; the session state decides. A user whose local session is still valid keeps it (the runtime symptom of the old forced-login was a slow `/auth/session-bind` timing out at 8 s while the JWT was still good).
- The 8 s cap does not cancel the in-flight `init()`: the abandoned future still completes, and a later `session-bind` response is still stored.
- `fetchPartnership()` failures are handled by `runSafe` -> `ErrorHandler` (snackbar/dialog), **and `partner` stays null** -> the splash **navigates to `PartnerScreen` even when a partnership actually exists**. This is a navigation decision based on failed data. `PartnerScreen` self-heals: it shows the existing-partner card (its own `ProfileState` load) whose tap goes to `MainShell`.
- Navigates by name: `AuthNavigationUtils.determinePostAuthRouteName` returns `AppRoutes.mainShell`, `AppRoutes.partner` or `AppRoutes.login`, and the splash calls `pushReplacementNamed`.

### Failed session restoration behavior (reconstruction)

- `init()` (auth_state.dart:80-179): storage reads parallelized; if `Supabase` session is null but a local access token exists -> `logout()` (auth_state.dart:116). Then `isLoggedIn == false` -> splash routes to `LoginScreen`. (Reachable, correct.)
- If session exists but username missing -> `fetchProfileByAuthId`; on **network failure** `user` stays null (auth_state.dart:122), but `isLoggedIn` remains **true** (token based). Splash then calls `fetchPartnership()` (likely also failing) -> `partner null` -> `PartnerScreen`. The user lands on partnering UI with no visible session data until `loadProfile` catches up.
- The 401/refresh-failure path never reaches the splash (see Authentication-driven navigation).

---

## Session-based routing

The destination decision ("MainShell vs PartnerScreen vs LoginScreen") is centralized in `AuthNavigationUtils` and used by every forward auth flow:

| Site | Condition | Destination | Evidence |
|---|---|---|---|
| SplashScreen._checkAuth | `init()` completes, then `determinePostAuthRouteName` | MainShell / PartnerScreen / LoginScreen via `pushReplacementNamed` | splash_screen.dart |
| LoginScreen onPressed | `login()` success, then `determinePostAuthRouteName` | MainShell / PartnerScreen via `pushReplacementNamed` | login_screen.dart |
| ResetPasswordScreen onPressed | `updatePasswordNew()` success, then `determinePostAuthRouteName` | MainShell / PartnerScreen / LoginScreen via `pushReplacementNamed` | reset_password_screen.dart |
| PartnerScreen accept invitation | acceptInvitation success | MainShell via `pushReplacementNamed` | partner_screen.dart |
| PartnerScreen existing-partner card tap | partner != null | MainShell via `pushReplacementNamed` | partner_screen.dart |
| RegisterScreen onPressed | register() success | confirm-email dialog -> pop,pop -> Login (email verification mandatory) | register_screen.dart |

Conditions map to the getters `AuthState.isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty` (auth_state.dart:61) and `AuthState.hasPartner => _partnerId != null` (auth_state.dart:62). Requirement: **an authenticated user without partnership goes to `PartnerScreen`; with partnership goes to `MainShell`.** This holds on every site only if the underlying data succeeded.

**Covered at runtime**: a partnership that stops being active (cancellation requested, accepted and deleted, or otherwise removed) makes `AuthState.hasPartner` false. `MainShell` watches that getter and replaces the stack with `PartnerScreen` through `ErrorHandler.navigatorKey`; `PartnerState` also teleports when a known cancellation resolves to no partner, which covers pushed routes where the shell is offstage. Forward one-shot decisions remain as described above.

---

## LoginScreen

`login_screen.dart`:

- Footer `VPAuthLink` -> `Navigator.pushNamed(AppRoutes.register)` (line 33). Return path: `RegisterScreen` footer pops back (register_screen.dart:34); the confirm-email dialog pops twice (line 125-126).
- "Forgot Password" `TextButton` has an **empty `onPressed: () {}`** (line 68) - no forgot-password flow or navigation.
- On successful `AuthState.login(...)`: `AuthNavigationUtils.determinePostAuthRouteName` decides `AppRoutes.mainShell` or `AppRoutes.partner` (lines 108-115) and the screen calls `pushReplacementNamed`.
- `LoginScreen` never re-runs `AuthState.init()`; it relies on `login()` doing full bootstrap (profile fetch + session sync + device token). When the screen is reached via the **reauth dialog** while `AuthState` is still logged in, `login()` re-runs cleanly (init-like steps are idempotent).
- No "already logged in" redirect: visiting `/login` while authenticated is possible via the reauth dialog; nothing bounces authed users away.

---

## RegisterScreen

`register_screen.dart`:

- Footer -> `Navigator.pop(context)` back to Login (line 34).
- On successful `register(...)` (`register_screen.dart:97-130`): always shows the non-dismissible "confirm your email" `VPDialog`; OK pops the dialog then pops **the register route** ("Torna al login", line 118-119) -> back to `LoginScreen`. Email verification is mandatory by product decision: `AuthState.register()` never auto-logs-in; if Supabase returns a session anyway, the session is immediately revoked via `signOut()`, so the verify-email -> login path can never be bypassed (`auth_state.dart:344-401`).

---

## PartnerScreen

`partner_screen.dart`:

- `initState` post-frame: `ProfileState.loadProfile()`, `fetchSentInvitations()`, `fetchReceivedInvitations()` (lines 25-29).
- **Existing-partner card** tap -> `pushReplacementNamed(AppRoutes.mainShell)` (line 113-118). This is the self-heal path for users miss-routed by a failed splash `fetchPartnership`.
- **Add-partner card** -> `DialogUtils.showPartnerInvite(context)` (line 129) - a dialog, no route.
- **Invitation accept** (line 344-368): `AuthState.acceptInvitation` -> `fetchPartnership` -> `ProfileState.loadProfile(force:true)` -> `pushReplacementNamed(AppRoutes.mainShell)`. On failure shows snackbar, stays.
- **Invitation reject** (line 370-371): direct state call, no navigation.
- **Cancellation cards**: while `PartnerState.cancellation != null`, the normal pairing content is hidden. The requester sees the waiting card; `Restore partnership` calls `revertCancellation` -> refresh -> `pushReplacementNamed(AppRoutes.mainShell)`. The partner sees the reusable `InvitationTile`; decline follows the same restore path, while accept confirms, calls the signed endpoint, shows the ended copy and stays on `PartnerScreen` (now empty, ready for a new pairing). The requester never sees the accept action.
- **Logout** is available in the footer on every `PartnerScreen` state, including while cancelled.

---

## MainShell

`main_shell.dart`:

- `MainShellScope` (an `InheritedWidget`) exposes the live `MainShellState`; `MainShell.of(context)` reads it. No global `GlobalKey` is used.
- `_currentIndex` (0-6) + `TabIndexNotifier` + `Set<int> _builtPages = {0}`.
- `switchToTab(int index)` (line 18): marks built, notifies notifier, setState. Used by content screens via `MainShell.of(context)?.switchToTab`.
- Build: `Stack[ Padding(bottom:110) > IndexedStack(index:_currentIndex, children: List.generate(7,...)), Positioned HomeBottomNav ]`.
- Tab mapping (line 24-34): 0 Homepage (const, no notifier), 1 Game, 2 Mood, 3 BucketList, 4 Drive, 5 Favorites (each `TabScreen(tabIndex, tabNotifier)`), 6 Profile (const, no notifier).
- **System back**: no `PopScope`/`PopScope` handling. `MainShell` is the root route after `pushReplacementNamed`, so Android back at tab 0 exits the app; at other tabs, back **switches nothing** (the OS back is not wired to tab switching, unlike typical bottom-nav apps).

---

## IndexedStack

- `IndexedStack` keeps all **visited** tabs alive (state preserved; disposed only when `MainShell` is disposed). Unvisited tabs are represented by `SizedBox.shrink()` (main_shell.dart:47-48).
- The `HomeBottomNav` is a **custom overlay** in the same `Stack` (bottom-aligned, height 90 + margin, main_shell.dart:51-63) - not a `BottomNavigationBar`. The `IndexedStack` content is padded by 110px (bottom) to avoid the floating nav (line 44).
- `HomeBottomNav` (home_bottom_nav.dart) renders 7 items: Games(1) Mood(2) List(3) [center Home(0)] Drive(4) Favorites(5) Profile(6). The center home is a raised circle that doubles as the Home tab.

---

## Lazy tab loading

- **Widget / data laziness**: `_builtPages` starts `{0}`; a tab's widget subtree is only materialized (and its state's `initState`/`loadData` run) the first time it is selected. `TabScreenMixin` (tab_screen.dart) loads on first activation AND on every **switch-back** (`_onTabChanged` sets `_dataLoadedOnce=false`), so returning tabs refresh - except Homepage(0) and Profile(6), which **do not use the mixin**:
  - `HomepageScreen.initState` post-frame fires `_loadData()` once (homepage_screen.dart:50-56); it never reloads on switch-back (stale data - covered in Findings).
  - `ProfileScreen` runs its own post-frame `loadProfile()` (profile_screen.dart:31-34), no switch-back reload.
- **State is NOT lazy**: all 11 feature states are created eagerly in `MultiProvider` at startup (main.dart:96-111), each instantiating repositories and `http.Client`s. Lazy tab wiring only defers data fetching.
- Profile lives in exactly one place: `ProfileScreen` is the resident `Tab 6` inside `MainShell` (main_shell.dart:122); the home menu reaches it via `MainShell.of(context)?.switchToTab(6)` (homepage_screen.dart:160), not a second route. Both `HomepageScreen` and `ProfileScreen` call `ProfileState.loadProfile()` on startup; `ProfileState` coalesces concurrent loads (one cache read + fetch shared, every caller awaits the same result), so the double call leaves both screens with a populated state.

---

## Named routes and route arguments

Declared in `AppRoutes` and mapped by `generateAppRoute` (main.dart): `/` (splash), `/login`, `/register`, `/reset-password`, `/change-password`, `/localization`, `/partner`, `/main` (MainShell), `/drive/item`.

`/drive/item` is the only route with an argument: `generateAppRoute` accepts an `int` (or a string that parses to one) and builds `DriveItemScreen(itemId:)`; a missing or non-numeric argument leaves the route unrecognised (`null`). All other screens take zero-argument `const` constructors and read their data from providers.

Unknown names return `null`. A programmatic `pushNamed` of an unknown name is a developer error and Flutter reports the missing generator; an unknown cold-start deep link falls back to the home route.

---

## Redirects

- **No auth-guard/router redirect layer.** `AuthNavigationUtils` centralizes the forward post-auth decision; each caller performs the navigation by name.
- A screen entered with the wrong auth state is not auto-redirected:
  - An authenticated user reaching `/login` (via the reauth dialog) stays on `LoginScreen`.
  - `/main` and `/partner` are reachable by name; nothing guards them.

---

## Deep links / Android App Links

- **Custom Scheme & HTTPS App Links**: the app receives URLs through the custom scheme `justus://auth/callback` and the Android App Link (HTTPS) `https://justus.serverfede.eu/auth/callback`, both declared in `AndroidManifest.xml` (`android:autoVerify="true"`).
- Flutter's built-in deep-link routing is disabled (`flutter_deeplinking_enabled=false`), so the Navigator never pushes `/callback` as an app route. `supabase_flutter` owns the callback through its `app_links` listener and emits the corresponding auth events; `AuthState` listens for `passwordRecovery` and pushes `AppRoutes.resetPassword`.
- No external routing package (`go_router`, `uni_links`) is used for deep-link navigation.

---

## Notification-driven navigation

**Not implemented.**

- `NotificationService` exposes `Stream<String?> get onNotificationTap` (notification_service.dart:29-31). Payloads are pushed from launch details and `onDidReceiveNotificationResponse`.
- `MainShellState` subscribes to `onNotificationTap`, parsing destination tabs/routes from payload JSON and navigating dynamically when notifications are tapped.

---

## Authentication-driven navigation

Two mechanisms:

1. **Session expiry via `ApiService` (auth-driven, navigates):** on 401 after a failed refresh, `ApiService._safeCall` calls `ApiService.onSessionExpired?.call()` (api_service.dart:230). `AuthState.init` registers that callback as `() => logout()` (auth_state.dart:81-86). `logout()` clears storage/caches/state (auth_state.dart:535-550) but does **not** navigate itself. The resulting `GenericError(code: 401)` — carrying `AppError(authFail001)` in `details` (api_service.dart:232-233) — then propagates through `BaseState.handleResult`/`runSafe` -> `ErrorHandler.handle`:
   - `toAppError` resolves the `details` `AppError(authFail001)` -> `AppError(code: "AUTH-FAIL-001")` (error_handler.dart:72-84),
   - `ErrorCodes.requiresReauth("AUTH-FAIL-001") == true` (error_codes.dart),
   - -> **reauth dialog** (error_handler.dart:145-146) -> OK -> `pushNamedAndRemoveUntil('/login', (r)=>false)` (error_handler.dart:249-273).

   **Effect**: after a session expiry the user is logged out (state cleared) and shown a non-dismissible "Session expired" dialog whose action redirects to `LoginScreen`, clearing the stale `MainShell` stack. (todo# 1.3)

2. **Reauth dialog (auth-driven, navigates):** triggered for `AppError.code` in {`"401"`, `authFail001`, `authFail002`, `authFail003`, `authFail006`} (error_codes.dart; error_handler.dart:145-146). The `authFailXXX` codes originate from backend auth endpoint errors / `AuthException` mapping (`_toAppError`, error_handler.dart:83-89); `"401"` is the synthetic code for a failed refresh. Flow: `showDialog` (non-dismissible) -> OK -> `navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (r)=>false)` (error_handler.dart:249-273).
   - Credential failures during login/registration are **excluded** from this path: `AuthState.login`/`register` catch the Supabase `AuthException` (and the "no user/session" outcomes) and rethrow `AppError(authFailCred)` — a client-only code that is not in `requiresReauth`, so `ErrorHandler` shows a plain SnackBar on the form instead of the "session expired" dialog and never replaces the stack with the LoginScreen itself. Genuine token/session validation failures keep mapping to `authFail001`/`"401"`.
   - The comment at error_handler.dart:261 claims "l'AuthState gestirà il logout vero e proprio", but `logout()` is only wired to `onSessionExpired`; a `authFailXXX` error arriving from a non-ApiService source does **not** reset `AuthState`, so after navigation the `LoginScreen` may be shown while the user is still logically logged in.

---

## Partnership-driven navigation

- Forward: accept invitation or tap existing-partner card on `PartnerScreen` -> `pushReplacementNamed(AppRoutes.mainShell)` (partner_screen.dart). The cancellation request from Profile is also forward: `pushReplacementNamed(AppRoutes.partner)` after `partnership_request_cancel` succeeds; restore/decline later replaces it with `AppRoutes.mainShell`.
- Reverse: a `partnerships` realtime event refreshes `PartnerState` + `AuthState`; once the pair stops being active (cancellation requested or row deleted) `AuthState.hasPartner` turns false. `MainShell.build` schedules a `pushNamedAndRemoveUntil(AppRoutes.partner)` through `ErrorHandler.navigatorKey`; `PartnerState` performs the same redirect (`_teleportIfEnded`, after both reads) when a known cancellation resolves to no partner, so it also works above pushed routes such as `ProfileScreen`. No dialog is shown. `PartnerScreen` then renders the cancellation card from `PartnerState.cancellation` (requester sees the waiting card; the partner can accept or decline). Revert, decline and lazy expiry restore the accepted pair and no redirect fires.
- Homepage cross-tab jumps use `MainShell.of(context)?.switchToTab(2|3|5)` (homepage_screen.dart) through `MainShellScope`.

---

## Logout navigation

- Single official path: `ProfileScreen._logout()` (profile_screen.dart:59-62) -> `LogoutUtils.showLogoutDialog` -> `LogoutUtils.performLogout` (logout_utils.dart:39-48): `await AuthState.logout()` then `pushNamedAndRemoveUntil(AppRoutes.login, (r)=>false)` - clears the whole stack.
- Mandatory-force-update may indirectly send the user to the store via `launchUrl`, but does not log out.
- Session-expiry "logout" (see Authentication-driven navigation) also navigates: the 401 maps to the reauth dialog, which redirects to `LoginScreen`.

---

## Navigation after account wipe

- `ProfileScreen._showWipeConfirmation()` (debug-only, profile_screen.dart:64-110): confirm dialog -> `RealtimeSyncService.suppress()` -> `ProfileState.wipeAppData()` (which wipes, clears its own cache, reloads the profile, and sets `profile_dataWiped`) -> clears the sibling feature states -> `rt.refreshChannel()`. The confirmation snackbar is shown by the state's listener.
- **No navigation**: the user stays on the current `ProfileScreen`/`MainShell`; the same session/partnership continues. (Wipe clears app data, not the account partnership.)

---

## Navigation after password change

- `ChangePasswordScreen` (change_password_screen.dart): reached via `/change-password` (profile_screen.dart:327). On submit: validates inputs, reauthenticates with current password, invokes `AuthState.changePassword(...)`, shows success snackbar, and pops back to Profile.

---

## Required flow reconstruction

| # | Flow | Path | Status |
|---|---|---|---|
| 1 | Application startup | main() bootstrap -> SplashScreen -> init -> route by state | IMPLEMENTED |
| 2 | Authenticated user with partnership | Splash -> AuthState.init OK -> fetchPartnership OK -> `pushReplacement` MainShell | IMPLEMENTED |
| 3 | Authenticated user without partnership | Splash -> Main... -> partner null -> `pushReplacement` PartnerScreen | IMPLEMENTED |
| 4 | Unauthenticated user | Splash -> init isLoggedIn false -> `pushReplacement` LoginScreen | IMPLEMENTED |
| 5 | Fresh registration | Register -> confirm-email dialog -> pop,pop -> Login | IMPLEMENTED (email verification mandatory) |
| 6 | Login success | Login -> based on hasPartner -> `pushReplacement` (MainShell|PartnerScreen) | IMPLEMENTED |
| 7 | Invitation accept | PartnerScreen -> accept -> fetch -> `pushReplacement` MainShell | IMPLEMENTED |
| 8 | Notification tap (foreground/background) | tap -> payload on `onNotificationTap` -> `MainShellState` listener -> tab switch / route | IMPLEMENTED |
| 9 | Launch-from-notification | `getNotificationAppLaunchDetails` -> payload stream -> `MainShellState` listener -> tab switch | IMPLEMENTED |
| 10 | Logout (Profile button) | dialog -> AuthState.logout -> `pushAndRemoveUntil` LoginScreen | IMPLEMENTED |
| 11 | Session expiry (401, refresh failed) | onSessionExpired -> logout (state) -> GenericError(401) -> reauth dialog -> `pushNamedAndRemoveUntil('/login')` | IMPLEMENTED |
| 12 | Reauth-required error (authFail001/002/003/006 or "401") | ErrorHandler dialog -> `pushNamedAndRemoveUntil('/login')` | IMPLEMENTED |
| 13 | Forced update | Homepage post-frame -> checkVersion -> non-dismissible VPDialog -> `launchUrl` (external) | IMPLEMENTED (no in-app nav) |
| 14 | Failed session restoration (no session) | init -> logout -> LoginScreen | IMPLEMENTED |
| 15 | Failed session restoration (network) | init partial -> still isLoggedIn -> PartnerScreen (possible mis-route + degraded UI) | IMPLEMENTED (edge behavior) |
| 16 | Partnership cancelled/ended at runtime | realtime status/DELETE -> refresh -> `MainShell`/`PartnerState` redirect -> PartnerScreen (cancellation card or ended state) | IMPLEMENTED |
| 17 | Account wipe | no navigation; stays in shell | IMPLEMENTED |
| 18 | Password change | submit form -> reauthenticate -> `changePassword` -> pop | IMPLEMENTED |

---

## Centralized navigation

**Centralized forward decision, imperative call sites.** `AuthNavigationUtils.determinePostAuthRouteName` is the single source of truth for the post-auth destination and is used by `SplashScreen`, `LoginScreen` and `ResetPasswordScreen`. `PartnerScreen` navigates directly to `AppRoutes.mainShell` on accept / existing-partner because the partnership is already known there. The reverse redirect lives in `MainShell` (`hasPartner == false`) and `PartnerState._teleportIfEnded` (cancellation teleport through the global navigator).

There is no `NavigationService` and no router. The decision reads `AuthState.hasPartner` and `PartnerState.partner` after `fetchPartnership`, so a failed fetch can still strand a legitimately paired user on `PartnerScreen`; the existing-partner card is the self-heal path.

---

## Findings

---

## Implementation status

| Component | Status |
|---|---|
| Root `MaterialApp` + navigator key | IMPLEMENTED |
| Named routes | IMPLEMENTED (`AppRoutes` + `MaterialApp.onGenerateRoute`) |
| Route arguments | IMPLEMENTED (`/drive/item` takes an integer) |
| Redirects | IMPLEMENTED (`AuthNavigationUtils` centralized post-auth decision) |
| Deep links / App links | IMPLEMENTED (`justus://` custom scheme + Android App Links; Supabase `app_links`, Flutter's built-in handler disabled) |
| Notification-driven navigation | IMPLEMENTED (`NotificationService.onNotificationTap` -> `MainShell`) |
| Launch-from-notification navigation | IMPLEMENTED (`getNotificationAppLaunchDetails` + `getInitialMessage`) |
| Session-expiry redirect | IMPLEMENTED (401 -> reauth dialog -> `/login`) |
| Reauth dialog navigation | IMPLEMENTED |
| Partnership-driven navigation (forward) | IMPLEMENTED |
| Partnership-driven navigation (reverse) | IMPLEMENTED (`MainShell` + `PartnerState` redirect to `PartnerScreen` on cancellation/loss) |
| Logout navigation | IMPLEMENTED |
| Wipe navigation | IMPLEMENTED (stays in shell) |
| Password-change navigation | IMPLEMENTED |
| Lazy tab building | IMPLEMENTED (widgets) |
| Tab switch-back reload | IMPLEMENTED (all tabs including `HomepageScreen` use `TabScreenMixin`) |
| Forced-update dialog | IMPLEMENTED (external launch) |

---

## Notes

- All main destination screens are pushed by name; the only `MaterialPageRoute` in `lib/` is the one `generateAppRoute` returns.
- The **only** navigation that originates outside widgets is `ErrorHandler._showReauthDialog`, the cancellation reverse teleport in `PartnerState`, and the password-recovery push in `AuthState` (all use `ErrorHandler.navigatorKey`). Feature state classes otherwise never navigate - which is correct. The session-expiry path funnels into that same dialog: the synthetic `"401"` code is classified as `requiresReauth`, so `logout()` (state) is followed by the reauth dialog + redirect to `LoginScreen`.
- `CaptchaService.getCaptchaToken()` uses `ErrorHandler.navigatorKey.currentContext` to host the Turnstile (Managed-mode) dialog - a second core-layer consumer of the global navigator.
- `Flutter/test/app_routes_test.dart` covers the route table: a known name builds its real screen, an unknown name returns `null`, and `/drive/item` requires an integer argument.
- Recommendation if navigation is ever refactored: introduce a single `go_router` (or a `navigator` service) with auth/partner redirect rules as the single source of truth for "MainShell vs PartnerScreen vs LoginScreen", use `MainShellScope.of(context)` for tab switching, and subscribe to `onNotificationTap` to apply content navigation.
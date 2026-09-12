# Flutter Navigation System - JustUS

## Overview

The JustUS Flutter app uses **imperative, widget-driven navigation**: plain `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` with inline `MaterialPageRoute` builders. There is **no routing package** (no `go_router`, `auto_route`, `uni_links`, or `app_links` in `pubspec.yaml` dependencies), no `onGenerateRoute`, no `onGenerateInitialRoutes`, and no centralized navigation service.

Navigation **decision logic** (which screen to show after login/register/startup) is duplicating in four widget files (`SplashScreen`, `LoginScreen`, `RegisterScreen`, `PartnerScreen`), plus `LogoutUtils`. No `AuthState`/`PartnerState` provider performs navigation - the state layer stops at exposing `isLoggedIn` / `hasPartner`, and the widgets react to those getters synchronously after awaited actions.

The navigation graph consists of exactly two "shells":

- **Auth shell**: `LoginScreen` / `RegisterScreen` / `SplashScreen` / `PartnerScreen`.
- **App shell**: `MainShell` with a 7-tab `IndexedStack`, exclusively reached with `MainShell(key: MainShell.shellKey)` (a global `static` key shared by 3 call sites).

Everything else (`LocalizationScreen`, `ChangePasswordScreen`, `ProfileScreen` pushed from the home menu, `DriveItemScreen`) is pushed **on top** of `MainShell` or `PartnerScreen` and has a back affordance (`VPHeader.onBack`/`Navigator.pop`).

---

## Navigation technology

| Mechanism | Used for | Evidence |
|---|---|---|
| `MaterialApp.home` | `home: SplashScreen()` | `main.dart:135` |
| `routes:` map (named) | `/login`, `/register`, `/homepage`, `/partner`, `/localization`, `/change-password` | `main.dart:136-143` |
| `pushNamed` | `/localization` (profile_screen.dart:270), `/change-password` (profile_screen.dart:327), `/login` (error_handler.dart:262) | |
| `push` + `MaterialPageRoute` | Login->Register; HomepageMenu->ProfileScreen; Drive->DriveItemScreen; Favorites->DriveItemScreen | login_screen.dart:33, homepage_screen.dart:167, drive_screen.dart:290, favorites_screen.dart:100 |
| `pushReplacement` + `MaterialPageRoute` | Splash->{MainShell,PartnerScreen,Login}; Login->{MainShell,PartnerScreen}; PartnerScreen->MainShell (2 sites) | splash_screen.dart:37-53, login_screen.dart:108, partner_screen.dart:113,358 |
| `pushAndRemoveUntil((r)=>false)` | Register->PartnerScreen; Logout->LoginScreen; Reauth->LoginScreen | register_screen.dart:107, logout_utils.dart:43, error_handler.dart:262 |
| `pop` | Back buttons, dialogs, register->login footer | register_screen.dart:34, profile_screen.dart:134, etc. |
| Static `GlobalKey<MainShellState>` | Cross-tab jumps from content screens | main_shell.dart:5, homepage_screen.dart:193/369/471/530 |

`MaterialApp.navigatorKey` is `ErrorHandler.navigatorKey` (error_handler.dart:27) - used by `ErrorHandler` and `CaptchaService` to navigate/show dialogs without a widget context.

---

## Application entry

`Flutter/lib/main.dart`:

1. `main()` -> `runZonedGuarded` -> ensures binding, `dotenv`, `StorageService.init`, `SupabaseService.initialize`, optional Firebase, `NotificationService.init`, `LanguageProvider.loadSavedLocale`.
2. `runApp(JustUsApp(...))` -> `MultiProvider` (11 eager states) -> `RealtimeSyncScope` -> `Selector2` -> `MaterialApp`.
3. `MaterialApp.empty: home: SplashScreen()`. **Every app start begins at `SplashScreen`**; `initState` fires `unawaited(_checkAuth())`.

No `onGenerateInitialRoutes`, no deep-link startup handling, and no `FirebaseMessaging` "getInitialMessage" consumption at startup (only local-notification `getNotificationAppLaunchDetails`, and its payload goes to the unlistened `onNotificationTap` stream - see Notification-driven navigation).

---

## SplashScreen

`splash_screen.dart:17-55`:

```
initState -> unawaited(_checkAuth())
_checkAuth:
  await authState.init()
  if !mounted return
  if authState.isLoggedIn:
    await partnerState.fetchPartnership()
    if !mounted return
    if partnerState.partner != null:
      pushReplacement MainShell(MainShell.shellKey)     // line 37-40
    else:
      pushReplacement PartnerScreen()                    // line 43-46
  else:
    pushReplacement LoginScreen()                        // line 50-53
```

Observations:

- The splash **blocks navigation until `AuthState.init()` completes** (secure-storage reads + optional session-sync + optional device-token registration).
- `_checkAuth()` has **no try/catch** and is `unawaited`; a throw (e.g. storage error, logout during init) escapes to the zone -> `ErrorHandler.handleGlobal` -> post-frame overlay. The splash spinner remains forever with no navigation (stuck screen).
- `fetchPartnership()` failures are handled by `runSafe` -> `ErrorHandler` (snackbar/dialog), **and `partner` stays null** -> the splash **navigates to `PartnerScreen` even when a partnership actually exists**. This is a navigation decision based on failed data. `PartnerScreen` self-heals: it shows the existing-partner card (its own `ProfileState` load) whose tap goes to `MainShell`.
- Uses inline `MaterialPageRoute`, ignoring the declared `/homepage` and `/partner` named routes.

### Failed session restoration behavior (reconstruction)

- `init()` (auth_state.dart:80-179): storage reads parallelized; if `Supabase` session is null but a local access token exists -> `logout()` (auth_state.dart:116). Then `isLoggedIn == false` -> splash routes to `LoginScreen`. (Reachable, correct.)
- If session exists but username missing -> `fetchProfileByAuthId`; on **network failure** `user` stays null (auth_state.dart:122), but `isLoggedIn` remains **true** (token based). Splash then calls `fetchPartnership()` (likely also failing) -> `partner null` -> `PartnerScreen`. The user lands on partnering UI with no visible session data until `loadProfile` catches up.
- The 401/refresh-failure path never reaches the splash (see Authentication-driven navigation).

---

## Session-based routing

The destination decision ("MainShell vs PartnerScreen vs LoginScreen") is reimplemented at **five** sites:

| Site | Condition | Destination | Evidence |
|---|---|---|---|
| SplashScreen._checkAuth | isLoggedIn && partner!=null / isLoggedIn && partner==null / !isLoggedIn | MainShell / PartnerScreen / LoginScreen | splash_screen.dart:28-53 |
| LoginScreen onPressed | login() success && hasPartner | MainShell / PartnerScreen | login_screen.dart:105-115 |
| RegisterScreen onPressed | register() success && isLoggedIn | PartnerScreen (`pushAndRemoveUntil`) | register_screen.dart:105-111 |
| PartnerScreen accept invitation | acceptInvitation success | MainShell | partner_screen.dart:358-363 |
| PartnerScreen existing-partner card tap | partner != null | MainShell | partner_screen.dart:113-118 |

Conditions map to the getters `AuthState.isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty` (auth_state.dart:61) and `AuthState.hasPartner => _partnerId != null` (auth_state.dart:62). Requirement: **an authenticated user without partnership goes to `PartnerScreen`; with partnership goes to `MainShell`.** This holds on all five sites only if the underlying data succeeded.

**Not covered**: there is no session-based redirect when the *auth state changes at runtime* (e.g. partnership deleted while inside `MainShell`) - navigation is a one-shot decision performed after an awaited action, never a reaction to provider changes (see Partnership-driven navigation and Findings).

---

## LoginScreen

`login_screen.dart`:

- Footer `VPAuthLink` -> `Navigator.push(RegisterScreen)` (line 33). Return path: `RegisterScreen` footer pops back (register_screen.dart:34); the confirm-email dialog pops twice (line 125-126).
- "Forgot Password" `TextButton` has an **empty `onPressed: () {}`** (line 68) - no forgot-password flow or navigation.
- On successful `AuthState.login(...)`: `hasPartner` decides `pushReplacement(MainShell|PartnerScreen)` (lines 108-115). Uses inline route, NOT the `/homepage`/`/partner` names.
- `LoginScreen` never re-runs `AuthState.init()`; it relies on `login()` doing full bootstrap (profile fetch + session sync + device token). When the screen is reached via the **reauth dialog** while `AuthState` is still logged in, `login()` re-runs cleanly (init-like steps are idempotent).
- No "already logged in" redirect: visiting `/login` while authenticated is possible via the reauth dialog; nothing bounces authed users away.

---

## RegisterScreen

`register_screen.dart`:

- Footer -> `Navigator.pop(context)` back to Login (line 34).
- On successful `register(...)`:
  - `if (authState.isLoggedIn)` -> `pushAndRemoveUntil(PartnerScreen, (r)=>false)` (line 107-111).
  - else -> non-dismissible "confirm your email" `VPDialog`; OK pops the dialog then pops **the register route** ("Torna al login", line 125-126) -> back to `LoginScreen`.
- **Dead branch**: `AuthState.register()` (auth_state.dart:303-333) only calls Supabase `signUp` and never calls `setLoginData`; even when Supabase auto-confirms and returns a session, `isLoggedIn` stays **false**. Therefore the `isLoggedIn` branch at register_screen.dart:106 is effectively unreachable, and every registration goes through the "confirm email" dialog. (If the account is actually auto-confirmed, the user is told to check their email and must log in manually.)

---

## PartnerScreen

`partner_screen.dart`:

- `initState` post-frame: `ProfileState.loadProfile()`, `fetchSentInvitations()`, `fetchReceivedInvitations()` (lines 25-29).
- **Existing-partner card** tap -> `pushReplacement(MainShell)` (line 113-118). This is the self-heal path for users miss-routed by a failed splash `fetchPartnership`.
- **Add-partner card** -> `DialogUtils.showPartnerInvite(context)` (line 129) - a dialog, no route.
- **Invitation accept** (line 344-368): `AuthState.acceptInvitation` -> `fetchPartnership` -> `ProfileState.loadProfile(force:true)` -> `pushReplacement(MainShell)`. On failure shows snackbar, stays.
- **Invitation reject** (line 370-371): direct state call, no navigation.
- There is **no "skip" or logout affordance** on `PartnerScreen` (no way to leave authentic different from login): the only exits are accept/tap-partner (->MainShell) or OS back (-> previous route; at cold start the previous route is the splash, long gone via pushReplacement, so back exits the app).

---

## MainShell

`main_shell.dart`:

- `static final GlobalKey<MainShellState> shellKey` (line 5). Constructed at 3 sites with the **same** key: the `/homepage` named route (main.dart:139), splash pushReplacement (splash_screen.dart:39), login pushReplacement (login_screen.dart:112).
- `_currentIndex` (0-6) + `TabIndexNotifier` + `Set<int> _builtPages = {0}`.
- `switchToTab(int index)` (line 18): marks built, notifies notifier, setState. Used by content screens via `MainShell.shellKey.currentState?.switchToTab`.
- Build: `Stack[ Padding(bottom:110) > IndexedStack(index:_currentIndex, children: List.generate(7,...)), Positioned HomeBottomNav ]`.
- Tab mapping (line 24-34): 0 Homepage (const, no notifier), 1 Game, 2 Mood, 3 BucketList, 4 Drive, 5 Favorites (each `TabScreen(tabIndex, tabNotifier)`), 6 Profile (const, no notifier).
- **System back**: no `PopScope`/`PopScope` handling. `MainShell` is the root route after `pushReplacement`, so Android back at tab 0 exits the app; at other tabs, back **switches nothing** (the OS back is not wired to tab switching, unlike typical bottom-nav apps).

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
- Profile is duplicated: `Tab 6` keeps a resident `ProfileScreen` inside `MainShell`, while the home menu pushes a **separate** `ProfileScreen` route on the root stack (homepage_screen.dart:167-170). Both share the same `ProfileState` singleton (data consistent), but they are independent `State` objects (independent post-frame `loadProfile` calls; `ProfileState.loadProfile` has an `isLoading` guard at profile_state.dart:37 that silently skips the second call).

---

## Named routes and route arguments

Declared routes (main.dart:136-143): `/login`, `/register`, `/homepage`, `/partner`, `/localization`, `/change-password`.

Actually used (grep of `pushNamed`):

- `/localization` - profile_screen.dart:270.
- `/change-password` - profile_screen.dart:327.
- `/login` - error_handler.dart:262 (reauth dialog).

**Route arguments: none.** All route builders take zero-argument `const` constructors; nothing reads `ModalRoute.settings.arguments`. Feature screens that need data receive it through provider singletons, not route args. (e.g. `DriveItemScreen(itemId:)` uses the **widget constructor parameter**, set inline in the `MaterialPageRoute` builder at drive_screen.dart:290-295 - a constructor arg, not a route argument.)

---

## Redirects

- **No centralized redirects.** Flutter's `onGenerateRoute`/`onGenerateInitialRoutes` are unused; there are no auth-guard wrappers, no `redirect:` equivalents, no named-route redirects.
- Redirection is performed imperatively inside the four auth/partner screens as described above. If a screen is entered with the wrong auth state, nothing redirects it:
  - Authenticated user reaching `/login` (via reauth) stays on LoginScreen.
  - Unauthenticated/non-partner user has no public path into `/homepage` or `/partner` (they are unreachable by name anyway).

---

## Deep links

**Not implemented** - no evidence of in-app deep-link handling:

- No `go_router`, `uni_links`, `app_links`, `firebase_dynamic_links` in `pubspec.yaml` dependencies (grep). (`app_links` appears only in `pubspec.lock` and native plugin registrants as a transitive dependency; no Dart source imports or uses it - grep over `lib/**/*.dart` returns nothing.)
- No custom scheme/intent-filter handling code. `justus://` appears only in `AuthState._emailRedirectTo` (auth_state.dart:65-78) as the Supabase **email-confirmation redirect URI**, whose target is a static server-side HTML `callbackPage` (not app navigation).
- Launch-from-notification is handled via local notifications `getNotificationAppLaunchDetails` (notification_service.dart:51-59) and **does not perform navigation** (see below).

---

## Notification-driven navigation

**Not implemented.**

- `NotificationService` exposes `Stream<String?> get onNotificationTap` (notification_service.dart:29-31). Payloads are pushed from: launch details (line 53-58), `onDidReceiveNotificationResponse` (line 107-108).
- **There are no listeners/subscribers to `onNotificationTap` anywhere** (grep). Foreground `onMessage` only renders a local notification (line 69-74).
- Consequently: tapping a notification while the app is in background opens the app to whatever screen the cold/resume flow shows (normally `MainShell`); the notification payload is never interpreted and never navigates to a relevant screen.
- Notification payloads carry `notificationKey`, ids etc. but no routing directive.

---

## Authentication-driven navigation

Two mechanisms:

1. **Session expiry via `ApiService` (auth-driven, state-only):** on 401 after a failed refresh, `ApiService._safeCall` calls `ApiService.onSessionExpired?.call()` (api_service.dart:178). `AuthState.init` registers that callback as `() => logout()` (auth_state.dart:81-86). `logout()` clears storage/caches/state (auth_state.dart:534-549) but does **not navigate**. The resulting `GenericError(code:401)` (api_service.dart:180-181) then propagates through `BaseState.handleResult`/`runSafe` -> `ErrorHandler.handle`:
   - `_toAppError` -> `AppError(code: "401")` (error_handler.dart:76-79),
   - `ErrorCodes.requiresReauth("401") == false` (error_codes.dart:118-123),
   - `isCritical("401") == false` -> **snackbar** (error_handler.dart:145-150).
   
   **Effect**: after a session expiry the user is effectively logged out but **stays on the current screen (e.g. Homepage/Profile inside MainShell) with cleared state and no redirect to LoginScreen.** Stale-screen-after-state-change (Findings).

2. **Reauth dialog (auth-driven, navigates):** triggered only for `AppError.code` in {`authFail001`,`authFail002`,`authFail003`,`authFail006`} (error_codes.dart:118-123; error_handler.dart:145-146). Those codes originate from backend auth endpoint errors / `AuthException` mapping (`_toAppError`, error_handler.dart:83-89). Flow: `showDialog` (non-dismissible) -> OK -> `navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (r)=>false)` (error_handler.dart:249-273).
   - **Loop risk**: `AuthState.login` runs inside `runSafe`; a **wrong-password `AuthException`** on the LoginScreen is mapped to `authFail001` -> the reauth dialog appears **on top of the LoginScreen itself**, then replaces the stack with... the LoginScreen. Self-referential navigation makes the login error look like a session expiry. Same for `register` captcha/user-create failures.
   - The comment at error_handler.dart:261 claims "l'AuthState gestirà il logout vero e proprio", but `logout()` is only wired to `onSessionExpired`; a `authFailXXX` error arriving from a non-ApiService source does **not** reset `AuthState`, so after navigation the `LoginScreen` may be shown while the user is still logically logged in.

---

## Partnership-driven navigation

- Forward: accept invitation or tap existing-partner card on `PartnerScreen` -> `pushReplacement(MainShell)` (partner_screen.dart:113,358).
- Reverse: **nothing navigates away from `MainShell` when the partnership is removed/ended at runtime.** A `partnerships` realtime delete only triggers data refresh through `RealtimeSyncService` (and `AuthState.isPartner...` refresh); no redirect to `PartnerScreen`. The user remains in app UI showing a null partner (stale screen; Findings).
- Homepage cross-tab jumps use `MainShell.shellKey.currentState?.switchToTab(2|3|5)` (homepage_screen.dart:193/369/471/530) - a child content screen reaching into its parent shell through a global static key (inappropriate layer, Findings).

---

## Logout navigation

- Single official path: `ProfileScreen._logout()` (profile_screen.dart:59-62) -> `LogoutUtils.showLogoutDialog` -> `LogoutUtils.performLogout` (logout_utils.dart:39-48): `await AuthState.logout()` then `pushAndRemoveUntil(LoginScreen, (r)=>false)` - clears the whole stack.
- Mandatory-force-update may indirectly send the user to the store via `launchUrl`, but does not log out.
- Session-expiry "logout" (see Authentication-driven navigation) does **not** navigate.

---

## Navigation after account wipe

- `ProfileScreen._showWipeConfirmation()` (debug-only, profile_screen.dart:64-110): confirm dialog -> `RealtimeSyncService.suppress()` -> `ProfileState.wipeAppData()` -> clears all feature states -> snackbar -> `loadProfile(force:true)` -> `rt.refreshChannel()`.
- **No navigation**: the user stays on the current `ProfileScreen`/`MainShell`; the same session/partnership continues. (Wipe clears app data, not the account partnership.)

---

## Navigation after password change

- `ChangePasswordScreen` (change_password_screen.dart): reached via `/change-password` (profile_screen.dart:327). On submit: local `Form` validation -> success snackbar -> `Navigator.pop(context)` (lines 92-97) back to Profile.
- **The screen is a stub**: it never invokes `AuthState.changePassword` or any repository call - no password is actually changed. Consequently no session refresh/logout is performed after "change" (there is nothing to refresh).
- No deep-link/token path: Supabase would require a one-time token via email; nothing handles such a link (see Deep links).

---

## Required flow reconstruction

| # | Flow | Path | Status |
|---|---|---|---|
| 1 | Application startup | main() bootstrap -> SplashScreen -> init -> route by state | IMPLEMENTED |
| 2 | Authenticated user with partnership | Splash -> AuthState.init OK -> fetchPartnership OK -> `pushReplacement` MainShell | IMPLEMENTED |
| 3 | Authenticated user without partnership | Splash -> Main... -> partner null -> `pushReplacement` PartnerScreen | IMPLEMENTED |
| 4 | Unauthenticated user | Splash -> init isLoggedIn false -> `pushReplacement` LoginScreen | IMPLEMENTED |
| 5 | Fresh registration | Register -> confirm-email dialog -> pop,pop -> Login | IMPLEMENTED (isLoggedIn branch effectively dead) |
| 6 | Login success | Login -> based on hasPartner -> `pushReplacement` (MainShell|PartnerScreen) | IMPLEMENTED |
| 7 | Invitation accept | PartnerScreen -> accept -> fetch -> `pushReplacement` MainShell | IMPLEMENTED |
| 8 | Notification tap (foreground/background) | tap -> payload on `onNotificationTap` -> **no listener** -> no navigation | NOT IMPLEMENTED |
| 9 | Launch-from-notification | `getNotificationAppLaunchDetails` -> payload stream -> no listener -> splash default route | NOT IMPLEMENTED (payload ignored) |
| 10 | Logout (Profile button) | dialog -> AuthState.logout -> `pushAndRemoveUntil` LoginScreen | IMPLEMENTED |
| 11 | Session expiry (401, refresh failed) | onSessionExpired -> logout (state only) -> GenericError(401) -> snackbar -> **no navigation** | PARTIALLY IMPLEMENTED (missing redirect) |
| 12 | Reauth-required error (authFailXXX) | ErrorHandler dialog -> `pushNamedAndRemoveUntil('/login')` | IMPLEMENTED (see loop risk) |
| 13 | Forced update | Homepage post-frame -> checkVersion -> non-dismissible VPDialog -> `launchUrl` (external) | IMPLEMENTED (no in-app nav) |
| 14 | Failed session restoration (no session) | init -> logout -> LoginScreen | IMPLEMENTED |
| 15 | Failed session restoration (network) | init partial -> still isLoggedIn -> PartnerScreen (possible mis-route + degraded UI) | IMPLEMENTED (edge behavior) |
| 16 | Partnership ended at runtime | delete event -> data refresh only -> stays in MainShell | NOT IMPLEMENTED (no redirect) |
| 17 | Account wipe | no navigation; stays in shell | IMPLEMENTED |
| 18 | Password change | stub; pop only | NOT IMPLEMENTED (no actual change) |

---

## Centralized vs duplicated navigation

**Duplicated.** The destination-decision logic ("logged-in-with-partner -> MainShell") exists in four widgets plus helpers:

- splash_screen.dart:28-54 (decision + navigate),
- login_screen.dart:105-115 (decision + navigate) - reads `AuthState.hasPartner` instead of re-fetching,
- register_screen.dart:105-111 (decision + navigate),
- partner_screen.dart:113-118 and 358-363 (navigate only, no decision).

There is no `NavigationService`, no router, and no single function like `navigateToDestination(authState)`. Consequences: the decision is re-evaluated from *different* data sources (`partnerState.partner` vs `AuthState.hasPartner` vs `ProfileState.partnerProfile`), so the same logical state can produce different routes depending on which call site happens to have fresh data. (A splash `fetchPartnership` failure and a login `hasPartner` false can both strand legitimately-paired users on `PartnerScreen`.)

---

## Findings

### F-N1: Session expiry leaves the user on a stale screen (no redirect)

**What**: 401-refresh-failure path: `ApiService` -> `onSessionExpired` -> `AuthState.logout()` (clears all state, no navigation) while the returned `GenericError(code:401)` maps to a plain snackbar (`requiresReauth("401")==false`, `isCritical("401")==false`).
**Where**: api_service.dart:178-181; auth_state.dart:81-86,534-549; error_handler.dart:145-150; error_codes.dart:118-128.
**Why**: the "401" code string was never added to the `requiresReauth` list (which only covers `authFail001/002/003/006`).
**When**: any signed API call that fails refresh while the user is inside MainShell.
**Impact**: user is de facto logged out but continues browsing a UI with empty data; any subsequent action re-fails. Confusing and security-relevant (no re-login barrier).
**Confidence**: HIGH.

### F-N2: Reauth dialog fires on top of the LoginScreen for ordinary login failures

**What**: wrong-password/login errors raise `AuthException`, mapped to `authFail001` (error_handler.dart:83-89), which is `requiresReauth` -> `_showReauthDialog` -> `pushNamedAndRemoveUntil('/login', (r)=>false)`.
**Where**: error_handler.dart:83-89,249-273; auth_state.dart:229-252 (login inside `runSafe`); base_state.dart:79-98.
**Why**: the mapping to `authFail001` is used both for genuine session-expiry cases and for simple credential errors, without distinguishing where they originate.
**When**: every failed login attempt on the LoginScreen.
**Impact**: misleading dialog ("session expired / reauthentication required") and self-referential navigation: the stack is replaced by the very screen that was showing the error. Inconsistent UX; potential repeat-loop if the underlying call keeps failing.
**Confidence**: HIGH (code path is deterministic).

### F-N3: Named routes `/homepage`, `/partner`, `/register` are unreachable

**What**: declared (main.dart:136-143) but never `pushNamed`-ed; the screens they point to are always reached via inline `MaterialPageRoute`.
**Where**: main.dart:136-143; grep of `pushNamed` call sites.
**Impact**: dead routes; two routing styles coexist for the same destinations. If a deep link or notification ever uses these names they would work, but nothing does.
**Confidence**: HIGH.

### F-N4: No deep links

**What**: no routing package, no scheme handling, no intent-filter logic; `justus://` is only the email-verification redirect target rendered as a remote HTML page.
****Where**: pubspec.yaml; auth_state.dart:65-78.
**Impact**: no shareable links, no password-reset/magic-link navigation support, no notification-to-content links.
**Confidence**: HIGH.

### F-N5: Notification taps never navigate

**What**: `onNotificationTap` has zero subscribers.
**Where**: notification_service.dart:29-31,53-64,107-108.
**Impact**: notification payloads are dead data; deep-linking from notifications impossible by design.
**Confidence**: HIGH.

### F-N6: Partnership removal at runtime does not navigate to PartnerScreen

**What**: `partnerships` realtime delete triggers data refresh only; `MainShell` persists with a null partner and no redirect.
**Where**: realtime_sync_service.dart (partnership routing); main_shell.dart (no auth/partner listeners).
**Impact**: stale UI and no onboarding path back to `PartnerScreen` for the affected user.
**Confidence**: HIGH (no navigation call exists anywhere for partnership delete).

### F-N7: Nav decay toward stale home tab

**What**: `HomepageScreen` (tab 0) does not use `TabScreenMixin`; it loads once on `initState` and never on switch-back. Homepage always shows stale miss-you/bucket/mood data after the user returns from another tab.
**Where**: homepage_screen.dart:47-56 vs tab_screen.dart:49-61.
**Impact**: miss-you count and bucket previews lag until manual pull-to-refresh.
**Confidence**: HIGH.

### F-N8: `MainShell.shellKey` shared by three construction sites + cross-tab calls from content screens

**What**: one global key used for `/homepage` route (main.dart:139), splash (splash_screen.dart:39), login (login_screen.dart:112); `switchToTab` invoked through it from a content screen (homepage_screen.dart:193/369/471/530).
**Where**: main_shell.dart:5.
**Impact**: if two MainShells were ever mounted concurrently -> "Multiple widgets used the same GlobalKey" crash; couples feature widgets to the specific shell key (inappropriate layering).
**Confidence**: HIGH.

### F-N9: Dual ProfileScreen instances

**What**: resident tab-6 `ProfileScreen` inside MainShell vs pushed `ProfileScreen` from the home menu (homepage_screen.dart:167-170). Both run post-frame `loadProfile`; `ProfileState.loadProfile`'s `isLoading` guard silently skips the concurrent second call (profile_state.dart:37).
**Impact**: benign but wasteful; one of the two loads is dropped silently.
**Confidence**: HIGH.

### F-N10: Navigation decisions read different data sources (possible mis-route)

**What**: splash uses `partnerState.partner`, login uses `AuthState.hasPartner` (`_partnerId`), register uses `isLoggedIn`; failures of `fetchPartnership` at splash route a paired user to PartnerScreen.
**Where**: splash_screen.dart:31, auth_state.dart:62, partner_screen.dart:113.
**Impact**: inconsistent destinations for the same logical state depending on which fetch failed; PartnerScreen self-heals only if its own profile load succeeds.
**Confidence**: MEDIUM-HIGH.

### F-N11: `_checkAuth` unguarded + stuck splash

**What**: no try/catch, unawaited; any throw leaves the spinner with no navigation (handled only by `handleGlobal` overlay).
**Where**: splash_screen.dart:19,22-55.
**Confidence**: HIGH.

### F-N12: ChangePasswordScreen is a stub

**What**: no state/repository call; validates locally, snackbar, pop.
**Where**: change_password_screen.dart:92-97.
**Impact**: feature appears to work but nothing changes; no navigation complexity justified.
**Confidence**: HIGH.

### F-N13: Register `isLoggedIn` branch is unreachable

**What**: `register()` never sets login data/session.
**Where**: auth_state.dart:303-333; register_screen.dart:106.
**Impact**: auto-confirmed accounts are told to verify email and must log in manually; contradictory UX.
**Confidence**: HIGH.

### F-N14: Forgot-password button is a no-op

**What**: empty `onPressed` at login_screen.dart:68.
**Confidence**: HIGH.

---

## Implementation status

| Component | Status |
|---|---|
| Root `MaterialApp` + navigator key | IMPLEMENTED |
| Named routes | IMPLEMENTED (3/6 used) |
| Route arguments | NOT IMPLEMENTED |
| Redirects | NOT IMPLEMENTED (decentralized, imperative) |
| Deep links | NOT IMPLEMENTED |
| Notification-driven navigation | NOT IMPLEMENTED (payload ignored) |
| Launch-from-notification navigation | NOT IMPLEMENTED |
| Session-expiry redirect | PARTIALLY IMPLEMENTED (state reset, no redirect) |
| Reauth dialog navigation | IMPLEMENTED (with loop risk) |
| Partnership-driven navigation (forward) | IMPLEMENTED |
| Partnership-driven navigation (reverse) | NOT IMPLEMENTED |
| Logout navigation | IMPLEMENTED |
| Wipe navigation | IMPLEMENTED (stays in shell) |
| Password-change navigation | STUB (no real change) |
| Lazy tab building | IMPLEMENTED (widgets) |
| Tab switch-back reload | PARTIALLY IMPLEMENTED (Homepage/Profile excluded) |
| Forced-update dialog | IMPLEMENTED (external launch) |

---

## Notes

- All main destination screens are pushed with inline `MaterialPageRoute` even though `routes` defines corresponding names - inconsistent and blocks cleaner redirect/deep-link logic later.
- The **only** navigation that originates outside widgets is `ErrorHandler._showReauthDialog` (core). Feature **State** classes never navigate - which is correct - but this is exactly why the session-expiry path (state-side logout only) leaves the UI stranded.
- `CaptchaService.getCaptchaToken()` uses `ErrorHandler.navigatorKey.currentContext` to host the Turnstile dialog - a second core-layer consumer of the global navigator.
- No widget/route tests exist for any navigation scenario (no golden/route tests in `Flutter/test/`).
- Recommendation if navigation is ever refactored: introduce a single `go_router` (or a `navigator` service) with auth/partner redirect rules as the single source of truth for "MainShell vs PartnerScreen vs LoginScreen", replace `MainShell.shellKey` with a route-level tab mechanism, subscribe to `onNotificationTap` to apply content navigation, and add `401` to the `requiresReauth` set (or navigate explicitly in the `onSessionExpired` callback).
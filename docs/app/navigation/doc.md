# Flutter Navigation System - JustUS

## Overview

The JustUS Flutter app uses **imperative, widget-driven navigation**: plain `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` with inline `MaterialPageRoute` builders. There is **no routing package** (no `go_router`, `auto_route`, `uni_links`, or `app_links` in `pubspec.yaml` dependencies), no `onGenerateRoute`, no `onGenerateInitialRoutes`, and no centralized navigation service.

Navigation **decision logic** (which screen to show after login/register/startup) is duplicating in four widget files (`SplashScreen`, `LoginScreen`, `RegisterScreen`, `PartnerScreen`), plus `LogoutUtils`. Runtime partnership loss adds a reverse redirect in `MainShell` and `PartnerState`. No `AuthState`/`PartnerState` provider performs forward navigation - the state layer stops at exposing `isLoggedIn` / `hasPartner`, and the widgets react to those getters synchronously after awaited actions. The only state-layer navigation is the cancellation reverse teleport in `PartnerState` (through the global navigator key).

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
| `pushReplacement` + `MaterialPageRoute` | Splash->{MainShell,PartnerScreen,Login}; Login->{MainShell,PartnerScreen}; PartnerScreen->MainShell (2 sites) | splash_screen.dart:37-40, login_screen.dart:108, partner_screen.dart:113,358 |
| `pushReplacementNamed` | Profile cancellation request -> PartnerScreen; PartnerScreen restore/decline -> MainShell; PartnerScreen accept -> stays (cancellation branch) | profile_screen.dart (cancellation request), partner_screen.dart (restore/decline) |
| `pushAndRemoveUntil((r)=>false)` | Register->PartnerScreen; Logout->LoginScreen; Reauth->LoginScreen; runtime partnership loss->PartnerScreen (`MainShell`/`PartnerState`, through the global navigator) | register_screen.dart:107, logout_utils.dart:43, error_handler.dart:262, main_shell.dart:130-147, partner_state.dart:_teleportIfEnded |
| `pop` | Back buttons, dialogs, register->login footer | register_screen.dart:34, profile_screen.dart:134, etc. |
| Static `GlobalKey<MainShellState>` | Cross-tab jumps from content screens | main_shell.dart:5, homepage_screen.dart:193/369/471/530 |

`MaterialApp.navigatorKey` is `ErrorHandler.navigatorKey` (error_handler.dart:27) - used by `ErrorHandler` and `CaptchaService` to navigate/show dialogs without a widget context, and by `PartnerState` for the cancellation reverse teleport above pushed routes.

---

## Application entry

`Flutter/lib/main.dart`:

1. `main()` -> `runZonedGuarded` -> ensures binding, `dotenv`, `StorageService.init`, `SupabaseService.initialize`, optional Firebase, `NotificationService.init`, `LanguageProvider.loadSavedLocale`.
2. `runApp(JustUsApp(...))` -> `MultiProvider` (11 eager states) -> `RealtimeSyncScope` -> `Selector2` -> `MaterialApp`.
3. `MaterialApp.empty: home: SplashScreen()`. **Every app start begins at `SplashScreen`**; `initState` fires `unawaited(_checkAuth())`.

No `onGenerateInitialRoutes`, no deep-link startup handling, and no `FirebaseMessaging` "getInitialMessage" consumption at startup (only local-notification `getNotificationAppLaunchDetails`, and its payload goes to the unlistened `onNotificationTap` stream - see Notification-driven navigation).

---

## SplashScreen

`splash_screen.dart:15-41`:

```
initState -> unawaited(_checkAuth())
_checkAuth:
  try { await authState.init().timeout(8s) } catch { log only }
  if !mounted return
  destination = await AuthNavigationUtils.determinePostAuthDestination(context)
  if !mounted return
  pushReplacement destination
```

Observations:

- The splash **blocks navigation until `AuthState.init()` completes** (secure-storage reads + optional session-bind + optional device-token registration), capped at 8 s.
- `_checkAuth()` wraps only `init()` in a `try/catch`: an initialization error (slow session-bind, lost connection) is **logged and then routed by the same post-auth decision as the happy path**. The catch does **not** force `LoginScreen`; the session state decides. A user whose local session is still valid keeps it (the runtime symptom of the old forced-login was a slow `/auth/session-bind` timing out at 8 s while the JWT was still good).
- The 8 s cap does not cancel the in-flight `init()`: the abandoned future still completes, and a later `session-bind` response is still stored.
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
| SplashScreen._checkAuth | isLoggedIn && partner!=null / isLoggedIn && partner==null / !isLoggedIn | MainShell / PartnerScreen / LoginScreen | splash_screen.dart:30-40 |
| LoginScreen onPressed | login() success && hasPartner | MainShell / PartnerScreen | login_screen.dart:105-115 |
| RegisterScreen onPressed | register() success | confirm-email dialog -> pop,pop -> Login (email verification mandatory) | register_screen.dart:96-130 |
| PartnerScreen accept invitation | acceptInvitation success | MainShell | partner_screen.dart:358-363 |
| PartnerScreen existing-partner card tap | partner != null | MainShell | partner_screen.dart:113-118 |

Conditions map to the getters `AuthState.isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty` (auth_state.dart:61) and `AuthState.hasPartner => _partnerId != null` (auth_state.dart:62). Requirement: **an authenticated user without partnership goes to `PartnerScreen`; with partnership goes to `MainShell`.** This holds on all five sites only if the underlying data succeeded.

**Covered at runtime**: a partnership that stops being active (cancellation requested, accepted and deleted, or otherwise removed) makes `AuthState.hasPartner` false. `MainShell` watches that getter and replaces the stack with `PartnerScreen` through `ErrorHandler.navigatorKey`; `PartnerState` also teleports when a known cancellation resolves to no partner, which covers pushed routes where the shell is offstage. Forward one-shot decisions remain as described above.

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
- On successful `register(...)` (`register_screen.dart:97-130`): always shows the non-dismissible "confirm your email" `VPDialog`; OK pops the dialog then pops **the register route** ("Torna al login", line 118-119) -> back to `LoginScreen`. Email verification is mandatory by product decision: `AuthState.register()` never auto-logs-in; if Supabase returns a session anyway, the session is immediately revoked via `signOut()`, so the verify-email -> login path can never be bypassed (`auth_state.dart:344-401`).

---

## PartnerScreen

`partner_screen.dart`:

- `initState` post-frame: `ProfileState.loadProfile()`, `fetchSentInvitations()`, `fetchReceivedInvitations()` (lines 25-29).
- **Existing-partner card** tap -> `pushReplacement(MainShell)` (line 113-118). This is the self-heal path for users miss-routed by a failed splash `fetchPartnership`.
- **Add-partner card** -> `DialogUtils.showPartnerInvite(context)` (line 129) - a dialog, no route.
- **Invitation accept** (line 344-368): `AuthState.acceptInvitation` -> `fetchPartnership` -> `ProfileState.loadProfile(force:true)` -> `pushReplacement(MainShell)`. On failure shows snackbar, stays.
- **Invitation reject** (line 370-371): direct state call, no navigation.
- **Cancellation cards**: while `PartnerState.cancellation != null`, the normal pairing content is hidden. The requester sees the waiting card; `Restore partnership` calls `revertCancellation` -> refresh -> `pushReplacementNamed(MainShell)`. The partner sees the reusable `InvitationTile`; decline follows the same restore path, while accept confirms, calls the signed endpoint, shows the ended copy and stays on `PartnerScreen` (now empty, ready for a new pairing). The requester never sees the accept action.
- **Logout** is available in the footer on every `PartnerScreen` state, including while cancelled.

---

## MainShell

`main_shell.dart`:

- `static final GlobalKey<MainShellState> shellKey` (line 5). Constructed at 3 sites with the **same** key: the `/homepage` named route (main.dart:139), splash pushReplacement (splash_screen.dart:37), login pushReplacement (login_screen.dart:112).
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
- Profile lives in exactly one place: `ProfileScreen` is the resident `Tab 6` inside `MainShell` (main_shell.dart:122); the home menu reaches it via `MainShell.of(context)?.switchToTab(6)` (homepage_screen.dart:160), not a second route. Both `HomepageScreen` and `ProfileScreen` call `ProfileState.loadProfile()` on startup; `ProfileState` coalesces concurrent loads (one cache read + fetch shared, every caller awaits the same result), so the double call leaves both screens with a populated state.

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

## Deep links / Android App Links

- **Custom Scheme & HTTPS App Links**: L'app supporta la ricezione di URL sia via schema personalizzato `justus://auth/callback` che via Android App Links (HTTPS) `https://justus.serverfede.eu/auth/callback` configurati in `AndroidManifest.xml` con `android:autoVerify="true"`.
- `main.dart` gestisce l'arrivo dei link tramite `onGenerateRoute`, instanziando `SplashScreen` e lasciando la gestione dei parametri URL del callback all'SDK di Supabase Auth (`onAuthStateChange`).
- Nessun pacchetto di routing esterno (`go_router`, `uni_links`) è utilizzato per la navigazione interna dai deep link.

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

- Forward: accept invitation or tap existing-partner card on `PartnerScreen` -> `pushReplacement(MainShell)` (partner_screen.dart:113,358). The cancellation request from Profile is also forward: `pushReplacementNamed(PartnerScreen)` after `partnership_request_cancel` succeeds; restore/decline later replaces it with `MainShell`.
- Reverse: a `partnerships` realtime event refreshes `PartnerState` + `AuthState`; once the pair stops being active (cancellation requested or row deleted) `AuthState.hasPartner` turns false. `MainShell.build` schedules a `pushNamedAndRemoveUntil(AppRoutes.partner)` through `ErrorHandler.navigatorKey`; `PartnerState` performs the same redirect (`_teleportIfEnded`, after both reads) when a known cancellation resolves to no partner, so it also works above pushed routes such as `ProfileScreen`. No dialog is shown. `PartnerScreen` then renders the cancellation card from `PartnerState.cancellation` (requester sees the waiting card; the partner can accept or decline). Revert, decline and lazy expiry restore the accepted pair and no redirect fires.
- Homepage cross-tab jumps use `MainShell.shellKey.currentState?.switchToTab(2|3|5)` (homepage_screen.dart:193/369/471/530) - a child content screen reaching into its parent shell through a global static key (inappropriate layer, Findings).

---

## Logout navigation

- Single official path: `ProfileScreen._logout()` (profile_screen.dart:59-62) -> `LogoutUtils.showLogoutDialog` -> `LogoutUtils.performLogout` (logout_utils.dart:39-48): `await AuthState.logout()` then `pushAndRemoveUntil(LoginScreen, (r)=>false)` - clears the whole stack.
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

## Centralized vs duplicated navigation

**Duplicated.** The destination-decision logic ("logged-in-with-partner -> MainShell") exists in four widgets plus helpers:

- splash_screen.dart:30-40 (decision + navigate),
- login_screen.dart:105-115 (decision + navigate) - reads `AuthState.hasPartner` instead of re-fetching,
- register_screen.dart:105-111 (decision + navigate),
- partner_screen.dart:113-118 and 358-363 (navigate only, no decision),
- main_shell.dart:130-147 (runtime `hasPartner == false` -> PartnerScreen) and partner_state.dart `_teleportIfEnded` (cancellation teleport through the global navigator).

There is no `NavigationService`, no router, and no single function like `navigateToDestination(authState)`. Consequences: the decision is re-evaluated from *different* data sources (`partnerState.partner` vs `AuthState.hasPartner` vs `ProfileState.partnerProfile`), so the same logical state can produce different routes depending on which call site happens to have fresh data. (A splash `fetchPartnership` failure and a login `hasPartner` false can both strand legitimately-paired users on `PartnerScreen`.)

---

## Findings

---

## Implementation status

| Component | Status |
|---|---|
| Root `MaterialApp` + navigator key | IMPLEMENTED |
| Named routes | REMOVED (single imperative routing style) |
| Route arguments | NOT IMPLEMENTED |
| Redirects | IMPLEMENTED (`AuthNavigationUtils` centralized post-auth decision) |
| Deep links / App links | IMPLEMENTED (`justus://` custom scheme + Android App Links) |
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

- All main destination screens are pushed with inline `MaterialPageRoute` - a single consistent routing style across the app.
- The **only** navigation that originates outside widgets is `ErrorHandler._showReauthDialog` and the cancellation reverse teleport in `PartnerState` (both use `ErrorHandler.navigatorKey`). Feature state classes otherwise never navigate - which is correct. The session-expiry path funnels into that same dialog: the synthetic `"401"` code is classified as `requiresReauth`, so `logout()` (state) is followed by the reauth dialog + redirect to `LoginScreen`.
- `CaptchaService.getCaptchaToken()` uses `ErrorHandler.navigatorKey.currentContext` to host the Turnstile (Managed-mode) dialog - a second core-layer consumer of the global navigator.
- No widget/route tests exist for any navigation scenario (no golden/route tests in `Flutter/test/`).
- Recommendation if navigation is ever refactored: introduce a single `go_router` (or a `navigator` service) with auth/partner redirect rules as the single source of truth for "MainShell vs PartnerScreen vs LoginScreen", use `MainShellScope.of(context)` for tab switching, and subscribe to `onNotificationTap` to apply content navigation.
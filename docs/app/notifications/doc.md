# Push Notifications (FCM + Local Notifications) — JustUS

## Overview

JustUS delivers partner-to-partner push notifications using **Firebase Cloud Messaging (FCM)** for delivery tokens plus the **Firebase Admin SDK** on the backend to multicast messages, with **flutter_local_notifications** for custom foreground rendering and stable notification IDs on Android/iOS.

The system operates in three OS presentation modes:

1. **Foreground** (Android/iOS): the Dart `FirebaseMessaging.onMessage` handler re-localizes and renders a local notification via `flutter_local_notifications`.
2. **Background / killed** (Android/iOS): the OS system tray renders the notification built from the FCM `notification` field, using the icon/channel metadata declared in the Android manifest and the server-localized title/body.
3. **Background isolate handler** (`main.dart`): registered with `@pragma('vm:entry-point')` for data-only messages — **currently unreachable with the production payload** because the backend always includes a `notification` field (F-PN3).

**Two localization passes** exist:

1. **Server-side** (`notification.service.js`): the per-device `locale` stored in `user_devices` selects localized title/body from a `LOCALIZATIONS[locale]` map.
2. **Client-side** (`notification_service.dart`): in foreground, the `notificationKey` is resolved against `LanguageHelper.appLoc` (ARB strings), so the notification text follows the in-app language preference.

The client path wins in foreground; the server path matters only for the system-tray background/killed rendering (F-PN6).

Eight event types are defined: `requestAccepted`, `missyou`, `moodUpdated`, `answerSubmitted`, `newQuestion`, `driveItemAdded`, `reactionAdded`, `bucketItemAdded`. Each is sent fire-and-forget after a successful Supabase mutation via `unawaited(notifyPartnerOnce(...))`.

---

## The Pipeline

```
Feature action (Supabase mutation succeeds)
  └─ unawaited(notifyPartnerOnce(notificationKey, params))      base_repository.dart:163-174
        └─ transient ApiService.notifyPartner()                 api_service.dart:387-399
              └─ POST /api/v1/notify/partner (JWT + rate limit 12/min)   notify.routes.js:33-39
                    └─ sendNotificationController
                          └─ dispatchNotification(type='partner', senderId)   notify.controller.js
                                └─ resolveNotificationTarget → get_accepted_partner(senderId)  service:378-403
                                      └─ sendNotificationToUser(receiverId, type, key, params)  service:241-354
                                            ├─ fetchUserDevices → isDeliverableDevice filter   service:200-211,40-46
                                            ├─ group tokens by device.locale ('en' default)    service:257-265
                                            ├─ per-locale batch ≤ 500 tokens                   service:275
                                            │     └─ sendMulticastNotification(buildFcmMessage)  fcm-key.js
                                            │           - localizes title/body (LOCALIZATIONS) service:152-198
                                            │           - android: priority high, apns: priority 10
                                            │           - retry up to 3x (500ms * attempt)      service:282-298
                                            └─ deleteInvalidTokens(post-delivery)              service:213-226,317
                                                  └─ logs_notifications + notification.delivery_summary
Receiver device (FCM delivery):
  ├─ Foreground (Android/iOS): onMessage → showRemoteMessage
  │     ├─ localize via LanguageHelper.appLoc (notificationKey, params)
  │     └─ _notifications.show(id: stable hash, payload: jsonEncode(data))
  └─ Background / Killed (Android/iOS): OS system tray renders
       └─ uses server-localized title/body from the FCM `notification` field
```

---

## Platform Support

| Platform | FCM token source | `device_type` stored | Foreground rendering | Background/killed rendering | Push functional? |
|---|---|---|---|---|---|
| Android | `FirebaseMessaging.getToken()` | `android` | ✅ `flutter_local_notifications` on channel `justus_channel` | ✅ OS system tray (`default_notification_channel_id=justus_channel`) | **Yes** |
| iOS | `FirebaseMessaging.getToken()` | `ios` | ✅ `flutter_local_notifications` (Darwin) — double-presentation risk (F-PN1) | ✅ OS system tray | **Yes** (minor issues) |
| Web | `FirebaseMessaging.getToken()` | `web` | ❌ early return on `kIsWeb` (`notification_service.dart:146`) | ❌ no service worker | **No** (F-PN2) |
| Windows | persistent UUID fingerprint | `windows` | Plugin configured, never triggered by FCM | No FCM; token filtered server-side | **No** |
| macOS | `UNKNOWN_DEVICE_TOKEN` (10 chars) | `macos` | Plugin configured, never triggered by FCM | No FCM; token filtered server-side | **No** |
| Linux | `UNKNOWN_DEVICE_TOKEN` | `linux` | Plugin configured, never triggered by FCM | No FCM; token filtered server-side | **No** |

- `Firebase.initializeApp` runs only on Android/iOS/web (`main.dart:54-67`). On Linux `DefaultFirebaseOptions.currentPlatform` throws `UnsupportedError` (`firebase_options.dart:32-35`).
- `supportsFcm` is `defaultTargetPlatform == android || ios || kIsWeb` (`device_token_service.dart:6-9`).
- The backend treats a token as deliverable only when `device.device_type` is `android`, `ios`, or `web` — or missing entirely (`isDeliverableDevice`, `notification.service.js:40-46`). Desktop devices are therefore registered but never delivered to.

**Desktop note**: Windows/macOS/Linux never receive remote push notifications by design. `flutter_local_notifications` Windows/Linux/Darwin settings exist but no code path ever calls `showNotification` on those platforms.

---

## Lifecycle States

### Foreground (app in focus)

`FirebaseMessaging.onMessage` fires (`notification_service.dart:67-75`) → `showRemoteMessage(message)`:

1. Read `message.data['notificationKey']` (e.g. `moodUpdated`).
2. Decode `message.data['params']` (JSON string → `Map<String, dynamic>`).
3. Resolve ARB string via `_localizeNotification(key, params)`.
4. Render with `_notifications.show(id: _notificationId(message), payload: jsonEncode(data))`.

On iOS the OS may additionally present the notification itself (F-PN1).

### Background / Killed (app not in focus)

The FCM payload always carries a `notification` field (`buildFcmMessage`), so Android/iOS render a system-tray notification using the server-localized title/body and the Android manifest default channel/icon metadata.

`_firebaseMessagingBackgroundHandler` (`main.dart:13-34`) returns immediately when `message.notification != null` (`main.dart:15-16`) → no custom Dart rendering occurs in this state.

### Background isolate handler (data-only messages)

`@pragma('vm:entry-point')` handler intended for data-only messages:

```
message.notification != null → return (line 15-16)
WidgetsFlutterBinding.ensureInitialized()
Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)  (try/catch)
LanguageHelper.initFromSystemLocale()
NotificationService().initLocalNotifications(isBackground: true)
NotificationService().showRemoteMessage(message, isBackground: true)
```

**Unreachable with the current backend** — the backend always sends `notification` (F-PN3).

---

## Device Token Registration

### Token acquisition (`device_token_service.dart`)

| Platform | Token value | Length | Validation (schema: 16–512) |
|---|---|---|---|
| Android/iOS/Web | FCM token | ~152+ chars | ✅ |
| Windows | `getOrCreateDeviceFingerprint()` UUID | 36 | ✅ (but filtered server-side) |
| macOS/Linux | `'UNKNOWN_DEVICE_TOKEN'` | 10 | ❌ fails `z.string().min(16)` → HTTP 400 |

`onTokenRefresh` stream is empty on non-FCM platforms; `getDeviceFingerprint()` powers session binding and login-risk checks separately.

### Registration triggers (Flutter)

| Trigger | Location | Guard | Notes |
|---|---|---|---|
| App startup with a session | `auth_state.dart:157-173` | `isLoggedIn && supportsFcm` | Skips desktop entirely |
| Successful login | `auth_state.dart:315-329` | **none** | F-PN5 (inconsistent gating) |
| FCM token rotation | `auth_state.dart:200-207` | `token.isNotEmpty && isLoggedIn` | Re-registers new token |
| App resume / locale change | `auth_state.dart:215-261` | `supportsFcm && token != UNKNOWN_DEVICE_TOKEN` | Debounced 500 ms; updates `locale` |
| **Logout** | `auth_state.dart:753-768` (`_revokeDeviceToken()`) | `isLoggedIn && token != UNKNOWN_DEVICE_TOKEN` | Deletes the row; see below |

### Backend upsert — `POST /api/v1/auth/device-token`

`updateDeviceToken` (`auth.controller.js:17-54`):

```js
assertDbSuccess(await adminSupabase.from("user_devices").upsert(
  { user_id, device_token, user_agent, device_type, last_ip, ...(locale && { locale }) },
  { onConflict: "device_token" }
));
```

- `device_token` is `UNIQUE` — if a token is registered by a different user, the `user_id` of the existing row is overwritten (a device transfer reassigns ownership).
- `device_type` is inferred from `x-client-user-agent`/`user-agent` when the body omits it.
- Route chain: `authenticated()` → `limited(authRateLimit)` → `signed("auth-device-token")` → `validated({body})` (`auth.routes.js:53-62`). This is a **signed** endpoint (unlike notify).

`authRateLimit`: `{ipMax: 20, userMax: 10, window: 60_000 ms}`.

### Backend revocation — `POST /api/v1/auth/device-token-revoke`

Registration is undone on logout, so a device that is later handed to another account cannot keep receiving the previous account's pushes.

`revokeDeviceToken` (`auth.controller.js:56-77`):

```js
await adminSupabase
  .from("user_devices")
  .delete()
  .eq("device_token", deviceToken)
  .eq("user_id", userId);
```

- Route chain: `authenticated()` → `limited(authRateLimit)` → `signed("auth-device-token-revoke")` → `validated({body: revokeDeviceTokenSchema })` (`auth.routes.js:64-73`), sharing `authRateLimit`.
- **Row delete, not a flag**: `user_devices` has no `is_active`/`revoked_at` column and `fetchUserDevices` reads every row for the user, so removing the row is the deactivation. The `logs_api_access` / `logs_api_errors` / `logs_security_events` FKs are `ON DELETE SET NULL`, so audit rows survive the delete.
- **Scoped by `user_id`**: `device_token` is `UNIQUE`, so an unscoped delete could drop a row another account has already re-registered on this device.
- Idempotent — a missing row answers `200 { success: true }`; a DB failure raises `500 DB-WRITE-001`.
- Client side: `AuthRepository.revokeDeviceToken()` → `ApiService.revokeDeviceToken()`, called by `AuthState._revokeDeviceToken()` as step 0 of `logout()`, while the JWT/binding secret still exist. It is best-effort (5 s cap, errors swallowed) and its `401` path deliberately does not fire `ApiService.onSessionExpired`, which would re-enter `logout()`.
- Unrevoked stale rows (e.g. offline logout, session expiration, or a password-change revoke-all that could not land) converge through the periodic retention job (`sweepStaleUserDevices` in `retentionJob.js`). Every registration records the session that created it (`user_devices.session_id`, from `req.auth.claims.session_id`), so the sweep first runs the `purge_user_devices_dead_sessions()` RPC to delete rows whose session is gone from `auth.sessions` or past its `not_after` — those cases die at the next sweep run instead of waiting out the window — then the age purge (`updated_at` older than `USER_DEVICE_RETENTION_DAYS = 30`) as the fallback for sessionless registrations and for app kills before `signOut()`.
- The local FCM registration is **not** deleted (`FirebaseMessaging.deleteToken()` is never called): with no row the backend has nothing to target, and the next login re-registers the same token via the upsert.

### Backend other-device revocation — `POST /api/v1/auth/device-token-revoke-all`

A password change kills every *other* session of the account ([account-lifecycle — Other-Session Revocation](../features/authentication/account-lifecycle/doc.md#other-session-revocation)), and the `user_devices` rows must die with them: otherwise a stolen or abandoned device keeps receiving the account's pushes until it 401s or ages out.

`revokeOtherDeviceTokens` (`auth.controller.js:79-101`):

```js
await adminSupabase
  .from("user_devices")
  .delete()
  .eq("user_id", userId)
  .neq("device_token", deviceToken);
```

- Route chain: `authenticated()` → `limited(authRateLimit)` → `signed("auth-device-token-revoke-all")` → `validated({body: revokeDeviceTokenSchema })` (`auth.routes.js:79-89`), sharing `authRateLimit`.
- **Keeps the caller's own row**: the `device_token` in the body is the one to keep, so the device changing the password does not lose its pushes.
- **The delete is durable**: the registration route is `authenticated()`, and the other devices' Supabase sessions were already revoked by `signOut(scope: others)`, so a deleted device cannot re-register — its requests answer `401`.
- Idempotent and fail-safe: nothing to delete answers `200 { success: true }`; a DB failure raises `500 DB-WRITE-001`.
- Client side: `AuthRepository.revokeOtherDeviceTokens()` → `ApiService.revokeOtherDeviceTokens()`, called by `AuthState._revokeOtherDeviceTokens()` (`auth_state.dart:797-817`) immediately after `_revokeOtherSessions()` on both password writes (`changePassword`, `updatePasswordNew`). Best-effort like the logout revoke: 5 s cap, errors swallowed, `401` does not re-enter the teardown, and an unresolvable token skips the call — the retention sweep above is the backstop (session-linked prune at the next run, 30-day age purge as fallback).

---

## Endpoint Contract — `POST /api/v1/notify/partner`

### Route (`notify.routes.js:33-40`)

```js
router.post("/partner",
  ...chain(
    authenticated(),
    limited(notifyRateLimit),               // {ipMax: 30, userMax: 12, window: 60_000 ms}
    validated({ body: notifySchema })
  ),
  sendNotificationController);
```

A second route `POST /api/v1/notify/:type` exists for explicit-`receiverId` sends (same middleware, plus `paramsSchema`).

Notably the notify route chain has **no `signed()` / `freshNonce()`** — unlike the device-token route (F-PN10).

### Validation (`notify.schemas.js`)

```js
notifySchema = z.object({
  notificationKey: z.string().min(1).max(80),
  params: z.record(z.string()).optional(),
  receiverId: z.number().int().optional(),
});
```

### Behavior table

| Scenario | HTTP | Error code | Client-side effect |
|---|---|---|---|
| Unauthenticated | 401 | `AUTH-FAIL-002` | Silently ignored (fire-and-forget) |
| Rate limited (13th in window) | 429 | `SEC-BLOCK-001` | Silently ignored |
| Invalid payload (missing/empty `notificationKey`) | 400 | `API-VALIDATION-001` | Silently ignored |
| Receiver has no registered device | 200 dispatch, then controller **throws** `DB_NOT_FOUND_001` when `deviceCount === 0` | `DB-NOT-FOUND-001` | Logged only; no retry |
| FCM not configured (no service account) | 200 | — | Status `skipped_firebase_not_configured`; logged only |

---

## Backend Dispatch

`notification.service.js`:

1. **`resolveNotificationTarget(type='partner', body, senderId)`** (`:378-403`)
   - Resolves the receiver through RPC `get_accepted_partner(target_user_id=senderId)` (`partnershipUtils.js:3-10`).
   - `type === 'partner'` → receiver is the active partner; otherwise `receiverId` must be supplied and must equal the partner id.

2. **`sendNotificationToUser(...)`** (`:241-354`)
   - `fetchUserDevices(userId)` (`:200-211`): selects `device_token, device_type, locale` where the row has a non-null token, then filters via `isDeliverableDevice` (drops empty/`UNKNOWN_DEVICE_TOKEN`/`windows`/`macos`/`linux`).
   - Tokens grouped by `device.locale || 'en'` (`:257-265`) — per-locale messages.
   - Delivery in batches of `FCM_BATCH_SIZE = 500` (`:275`).
   - Retry loop: 3 attempts, `500ms * attempt` backoff, only for transient errors; permanent invalid-token codes abort immediately (`:282-298`).
   - `configured` flag from the FCM response; if Firebase admin is not initialized the loop aborts with status `skipped_firebase_not_configured`.
   - Post-send: `deleteInvalidTokens(...)` removes rows whose token returned an invalid-FCM error (`:317`, `:332`).

3. **`buildFcmMessage(...)`** (`:152-198`)
   - `localizeNotificationText(notificationKey, params, locale)` via the server `LOCALIZATIONS` map (fallback locale `'en'`).
   - Output: FCM multicast message containing:
     - `notification: {title, body}` — used by the OS for background/killed rendering.
     - `data` — `{type, title, body, source: 'justus-backend', notificationId, notificationKey, params, senderId}`.
     - `android: {priority: 'high'}`, `apns: {headers: {'apns-priority': '10'}, payload: {aps: {alert, sound: 'default', badge: 1}}}`, `webpush` block.
   - `notificationId` = `` `${Date.now()}-${Math.random().toString(36).slice(2, 10)}` `` — unique per dispatch.

4. **Logging**: `logNotification` → `logs_notifications` (statuses: `no_devices`, `sent`, `partial`, `skipped_firebase_not_configured`); `logInfo` → `notification.delivery_summary` with delivered/failed/invalid-removed counts.

### Invalid token cleanup

- `INVALID_FCM_TOKEN_CODES = { messaging/invalid-registration-token, messaging/registration-token-not-registered, messaging/invalid-recipient }` (`:13-17`).
- Cleanup is a **global** delete on `device_token` (row-level), which under the UNIQUE constraint can delete a *different user's* reassigned row (F-PN8).

---

## Notification Types

| # | Key | Event source | Triggering mutation | Params sent | ARB keys | Implemented |
|---|---|---|---|---|---|---|
| 1 | `requestAccepted` | PartnershipRepository | `acceptPartnerRequest` after RPC `accept_partnership` (`partnership_repository.dart:101-104`) | `{partnerName}` | `notif_requestAccepted_title/body({partnerName})` | PARTIALLY IMPLEMENTED |
| 2 | `missyou` | MissYouRepository | `sendMissYou` after RPC `send_missyou` (`missyou_repository.dart:12-15`) | `{partnerName}` | `notif_missyou_title/body({partnerName})` | PARTIALLY IMPLEMENTED |
| 3 | `moodUpdated` | MoodRepository | `updateMood` after RPC `set_mood` (`mood_repository.dart:15-21`) | `{partnerName, emojiChar}` | `notif_moodUpdated_title/body({partnerName})` — emoji param unused | PARTIALLY IMPLEMENTED |
| 4 | `answerSubmitted` | GameRepository | `submitAnswer` after `game_answers` upsert (`game_repository.dart:51-54`) | `{partnerName}` | `notif_answerSubmitted_title/body({partnerName})` | PARTIALLY IMPLEMENTED |
| 5 | `newQuestion` | GameRepository | `fetchNewGameQuestion` after `game_questions` insert (`game_repository.dart:120-123`) | `{}` (no name) | `notif_newQuestion_title/body` (no params) | PARTIALLY IMPLEMENTED |
| 6 | `driveItemAdded` | DriveRepository | `uploadDriveItemToR2` after successful upload (`drive_repository.dart:73-76`) | `{partnerName}` | `notif_driveItemAdded_title/body({partnerName})` | PARTIALLY IMPLEMENTED |
| 7 | `reactionAdded` | DriveRepository | `addReaction` after `drive_item_reactions` insert (`drive_repository.dart:139-145`) | `{partnerName, emojiChar}` | `notif_reactionAdded_title/body({partnerName, emojiChar})` | PARTIALLY IMPLEMENTED |
| 8 | `bucketItemAdded` | BucketRepository | `addBucketItem` after `bucket_items` insert (`bucket_repository.dart:49-52`) | `{partnerName}` | `notif_bucketItemAdded_title/body({partnerName})` | PARTIALLY IMPLEMENTED |

- All sends are fire-and-forget (`unawaited(notifyPartnerOnce(...))`) and swallow errors (`base_repository.dart:163-174`). No notification is retried, and the sender gets no feedback that the delivery failed.
- **No destination screen / deep link is attached to any type** (cross-doc navigation F-N5; tap handling section below).
- **No duplicate suppression**: each send yields a distinct notification with a unique server `notificationId`.

### Per-type notes

- **`requestAccepted`**: fired from `acceptPartnerRequest` (rpc), a UI-triggered accept. The request *creation* (`requestPartnership`/`invite`) and **rejection do not notify** — the architecture doc (F11) records the rejection asymmetry.
- **`missyou`**: no throttling client-side; holding the miss-you button queues one `notifyPartnerOnce` per `sendMissYou` RPC success — the 12/min user rate limit is the only cap.
- **`moodUpdated`**: `emojiChar` is passed in params but the ARB body `notif_moodUpdated_body({partnerName})` does not interpolate it, and the server template omits it too — the emoji payload is effectively unused in both localization passes.
- **`newQuestion`**: the only type sent with **no** `partnerName`; the ARB body is parameter-less (`Una nuova domanda ti aspetta!` / `A new question awaits you!`). Fired on `fetchNewGameQuestion` only when the sender's client actually creates the `game_questions` row; a partner's client that discovers the row (Realtime insert or cold-start read) returns the existing question without notifying.
- **`reactionAdded`**: the only type whose ARB body uses two params (`{partnerName}`, `{emojiChar}`); rendered with the actual reaction emoji.

---

## Client Rendering

### `NotificationService.init()` (`notification_service.dart:33-76`)

1. `_requestRemoteNotificationPermission()` (`:301-313`): `FirebaseMessaging.instance.requestPermission()` on web/Android/iOS only.
2. `initLocalNotifications()`.
3. `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` for Android/iOS non-web (`:40-47`) — this is iOS foreground-presentation relevant (F-PN1).
4. Launch payload detection: `getNotificationAppLaunchDetails()` → if `didNotificationLaunchApp`, push the payload to `_onNotificationTapController` after a 500 ms delay (`:50-64`).
5. Foreground handler registered once: `FirebaseMessaging.onMessage.listen(showRemoteMessage)` (`:67-75`).

### `initLocalNotifications({isBackground})` (`:83-141`)

- `kIsWeb` → no-op.
- Wire formats: `AndroidInitializationSettings('ic_notification')`, `DarwinInitializationSettings`, `LinuxInitializationSettings(defaultActionName: 'Open notification')`, `WindowsInitializationSettings(appName: 'JustUs', appUserModelId: 'com.justus.app', guid: ...)`.
- `_notifications.initialize(onDidReceiveNotificationResponse: (r) => _onNotificationTapController.add(r.payload))`.
- Android: `requestNotificationsPermission()` + create channel `justus_channel` / `'JustUs Notifications'` / `importance: Importance.high` — only when NOT in a background isolate (`:119-141`).

### `showRemoteMessage(message, {isBackground})` (`:144-203`)

1. `kIsWeb` → no-op.
2. Load locale from `SharedPreferences` (`LanguageHelper.storageKey = 'app_language_code'`), else `initFromSystemLocale()`.
3. If `notificationKey` present → `_localizeNotification(key, params)`.
4. Else fall back to `data['title']/['body']` or `message.notification`; if neither present → silently return (notification not shown).
5. `_notifications.show(id: _notificationId(message), payload: jsonEncode(message.data))`.

### `_localizeNotification` (`:205-258`)

Switch over the 8 keys resolving ARB getters (e.g. `loc.notif_missyou_body(partnerName)`). Defaults for missing params: `partnerName = 'Your partner'`, `emojiChar = '❤️'`. Unknown key → `(title: 'JustUS', body: '')` (F-PN7).

### `showNotification` (`:260-299`)

Channel `justus_channel`, `importance: high`, `priority: high` (Android); Darwin present-all options; Linux/Windows details.

---

## Tap & Deep-Link Handling

### Stream

```dart
final StreamController<String?> _onNotificationTapController = StreamController<String?>.broadcast();
Stream<String?> get onNotificationTap => _onNotificationTapController.stream;   // :29-31
```

Payloads are pushed from two places:

| Source | Location | Payload |
|---|---|---|
| `onDidReceiveNotificationResponse` (local notification tap) | `notification_service.dart:107-108` | `jsonEncode(message.data)` from the foreground local notification |
| `getNotificationAppLaunchDetails` (app launched by a local notification) | `notification_service.dart:50-64` | `jsonEncode(response.payload)` after 500 ms |

### Consumers

**There are no subscribers to `onNotificationTap` anywhere in the codebase** (grep shows only the definition and the two push sites). The payload is dead data.

Cross-doc: this is navigation doc finding **F-N5** ("Notification taps never navigate").

### Behavior on tap today

| Scenario | What happens |
|---|---|
| Foreground tap on local notification | `onNotificationTap` emits the payload → nothing consumes it; app stays on the current screen |
| Background/killed tap on OS notification | App launches → `SplashScreen` → `AuthState.init()` → `MainShell` (or `PartnerScreen`/`LoginScreen`); the payload is not recovered (`getNotificationAppLaunchDetails` may not even report the FCM-originated launch — F-PN4) |
| `FirebaseMessaging.getInitialMessage` | **Not consumed anywhere** (`main.dart` never reads it) |

---

## Localization

### Pass 1 — Server (`notification.service.js:56-198`)

`LOCALIZATIONS = { it: {...}, en: {...} }` with one entry per notification key plus a `default` entry. The per-device `user_devices.locale` (fallback `'en'` for null/unknown) selects the language; `params` are merged into the template (`p.partnerName`, `p.emojiChar`).

### Pass 2 — Client (`notification_service.dart:144-258`)

`LanguageHelper` holds a static `appLoc`, initialized from the saved `app_language_code` pref or the system locale; `_localizeNotification` maps the key to an ARB getter. Client fallback locale is `it` (`language_helper.dart:27`).

### Fallback asymmetry

| Path | Known key | Unknown key | Unknown locale |
|---|---|---|---|
| Server | localized string | `lang.default` → `'Hai una nuova notifica'` / `'You have a new notification'` | English (`LOCALIZATIONS[locale] ? locale : 'en'`, `:145`) |
| Client | ARB string | `(title: 'JustUS', body: '')` — shown with empty body (F-PN7) | `it` |

Consequence: a key deployed server-side but not yet in the client switch shows an empty-body `JustUS` notification in foreground (F-PN7), and the Norwegian/unknown-locale device gets English while the app UI falls back to Italian (F-PN6).

### Params sent but unused

- `moodUpdated.emojiChar` is passed but never interpolated in either the ARB or the server template.
- `newQuestion` sends `params: {}`, so `partnerName` defaults (`'Your partner'` / server fallback) never surface.

---

## Stable IDs & Deduplication

### Notification ID (`notification_service.dart:326-335`)

```dart
final raw = (message.data['notificationId'] ?? message.messageId)?.toString();
if (raw == null || raw.isEmpty) → in-process counter (_nextNotificationId++, wraps at 2^31)
else → _stableStringHash(raw) & 0x7fffffff   // djb2 variant, 31-bit positive
```

The server generates `notificationId` per dispatch (`Date.now()-random`), so nearly every message yields a distinct positive int → each notification is separate, and re-delivery of the *same* message would replace the previous one (same id).

### Deduplication

**No dedup exists.** Rapid identical actions (5× miss-you taps, 3× mood updates in a minute up to the rate limit) produce 5/3 distinct notifications. FCM multicast sends once per registered token; `sendNotificationToUser` dedups tokens only within a single send (`new Set`).

---

## Findings

Findings use the `F-PN` prefix (Push Notifications); navigation findings use `F-N` (navigation doc), storage `F-SC`, realtime `F-RT`, state-management `F-SM`, design-system `F-DS`.

### F-PN1: iOS foreground may present the notification twice (MEDIUM)

- **WHAT**: On iOS, `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` asks the OS to present notification-type messages while the app is foreground; the `onMessage` handler **also** posts a distinct local notification via `flutter_local_notifications`. The device can show two alerts for one event.
- **WHERE**: `notification_service.dart:40-47` (presentation options), `:67-75` (onMessage → `showRemoteMessage`), `:260-299` (`showNotification`).
- **WHY**: firebase_messaging v16.6 uses a `UNUserNotificationCenter` delegate that presents foreground messages according to those options; the app's own flutter_local_notifications render is independent of it.
- **WHEN**: Every foreground FCM delivery on iOS (the backend always includes the `notification` field).
- **IMPACT**: Duplicate banners/badges in foreground on iOS. Cosmetic; not yet observed in testing.
- **CONFIDENCE**: MEDIUM — documented plugin behavior; not device-verified.

### F-PN2: Web push is non-functional (LOW)

- **WHAT**: `supportsFcm` includes web and the FCM token is registered, but rendering is a no-op (`initLocalNotifications` and `showRemoteMessage` both early-return on `kIsWeb`) and **no service worker** (`firebase-messaging-sw.js`) exists in `web/`, which the web SDK needs to obtain a token.
- **WHERE**: `device_token_service.dart:6-9`, `notification_service.dart:84,146`, `web/index.html` (no SW registration).
- **WHY**: flutter_local_notifications does not support web; the service-worker file was never added.
- **WHEN**: Any web launch that calls `getDeviceToken()`.
- **IMPACT**: If a token is obtained it is stored with `device_type: 'web'` and delivers server-side sends to a client that cannot render them — wasted FCM quota and stale rows; token retrieval itself likely fails without the SW.
- **CONFIDENCE**: HIGH.

### F-PN3: Background isolate handler is unreachable with the current payload (INFO)

- **WHAT**: `_firebaseMessagingBackgroundHandler` returns when `message.notification != null` (`main.dart:15-16`), and `buildFcmMessage` always includes a `notification` field — so the background handler never executes for production messages.
- **WHERE**: `main.dart:13-34`; `notification.service.js:165-170`.
- **WHY**: The backend intentionally includes `notification` so the OS renders the system tray; the handler was written for data-only messages that are never produced.
- **WHEN**: Every background/killed delivery.
- **IMPACT**: None today — system-tray rendering works. The custom Dart background path (`showRemoteMessage(isBackground: true)`) is dead code.
- **CONFIDENCE**: HIGH (code-path analysis).

### F-PN4: `getNotificationAppLaunchDetails` may not detect FCM-originated launches (LOW)

- **WHAT**: The launch-details check (`notification_service.dart:50-64`) relies on flutter_local_notifications having created the launching intent. System-tray notifications rendered by FCM do not carry the plugin's extras, so `didNotificationLaunchApp` is likely false for those launches and no payload is pushed.
- **WHERE**: `notification_service.dart:50-64`.
- **WHEN**: App launched by tapping a background/killed FCM notification.
- **IMPACT**: Currently zero (the stream has no consumers anyway — F-N5 navigation). Relevant if tap-driven navigation is ever added.
- **CONFIDENCE**: LOW — depends on plugin intent-detection internals; not device-verified.

### F-PN5: `login()` registers the token without the `supportsFcm` guard (INFO)

- **WHAT**: `AuthState.login()` (`auth_state.dart:315-329`) calls `updateDeviceToken(fcmToken)` unconditionally, while `AuthState.init()` gates on `DeviceTokenService.supportsFcm` (`auth_state.dart:158`). On Windows a UUID fingerprint passes validation and is stored as `windows` (filtered server-side); on macOS/Linux `'UNKNOWN_DEVICE_TOKEN'` (10 chars) fails the 16-char schema minimum → HTTP 400, swallowed by try/catch.
- **WHERE**: `auth_state.dart:158-173` vs `:315-329`; `auth.schemas.js:4`.
- **WHY**: The login path predates the guard added later to `init()`.
- **WHEN**: Desktop logins.
- **IMPACT**: One logged 400 per session on macOS/Linux; a harmless extra row on Windows. Inconsistent gating only.
- **CONFIDENCE**: HIGH.

### F-PN6: Default-locale asymmetry between server and client (INFO)

- **WHAT**: The server falls back to `'en'` for unknown/empty `device.locale` (`notification.service.js:145`); the client falls back to `it` for unknown `app_language_code` (`language_helper.dart:27`).
- **WHERE**: `notification.service.js:145`, `language_helper.dart:27`.
- **WHEN**: Legacy rows with `locale = null`, or a locale not in `{it, en}`.
- **IMPACT**: Background system-tray text in English while foreground/in-app strings are Italian (or vice-versa). Minor.
- **CONFIDENCE**: HIGH.

### F-PN7: Unknown `notificationKey` shows an empty-body notification (LOW)

- **WHAT**: `_localizeNotification` returns `(title: 'JustUS', body: '')` for unhandled keys (`notification_service.dart:255-256`) and `showRemoteMessage` shows it as-is.
- **WHERE**: `notification_service.dart:255-256`.
- **WHEN**: A new key is deployed server-side before the app switch is updated (or a client crafts an arbitrary key — see F-PN10).
- **IMPACT**: The user sees a `JustUS` notification with an empty body. No data exposure.
- **CONFIDENCE**: HIGH.

### F-PN8: Invalid-token cleanup deletes globally, ignoring `user_id` (LOW)

- **WHAT**: `deleteInvalidTokens` runs `user_devices.delete().in('device_token', tokens)` (`notification.service.js:213-226`). Because `device_token` is UNIQUE, a token invalidated for user A but re-registered by user B before the cleanup runs deletes **user B's** row too.
- **WHERE**: `notification.service.js:213-226`; constraint `user_devices_device_token_key`.
- **WHEN**: An FCM invalidation and a device transfer overlapping a notification send.
- **IMPACT**: User B's registration disappears; their push stops until the next app start/token refresh re-registers it. Self-healing.
- **CONFIDENCE**: LOW (occurrence), HIGH (cleanup mechanism is global).

### F-PN9: iOS badge is hardcoded to 1 and never cleared (LOW)

- **WHAT**: `buildFcmMessage` sets `aps.badge: 1` (`notification.service.js:187`) — *set*, not increment, per notification. No `clearBadge`/`setBadge(0)` exists on app foreground.
- **WHERE**: `notification.service.js:187`; dashboard/native code has no `UIApplication.applicationIconBadgeNumber = 0`.
- **WHEN**: Every notification on iOS.
- **IMPACT**: App icon badge sticks at "1" after the first notification, never incrementing or clearing.
- **CONFIDENCE**: HIGH.

### F-PN10: Notify endpoint carries no request signature (INFO)

- **WHAT**: `POST /api/v1/notify/partner` is protected only by `authenticated()` + rate limit; there is no `signed()`/`freshNonce()` middleware, unlike the device-token route (`signed("auth-device-token")`). An authenticated user can send arbitrary `notificationKey` strings (1–80 chars) to their own partner up to the 12/min user cap.
- **WHERE**: `notify.routes.js:33-40` vs `auth.routes.js:53-62`.
- **WHY**: fire-and-forget design; the rate limit is the chosen abuse control.
- **IMPACT**: A partner can be spammed with up to 12 notifications/min with arbitrary keys (unknown keys → empty-body `JustUS`, F-PN7). Costs FCM quota. No session/data risk.
- **CONFIDENCE**: HIGH (that signing is absent), MEDIUM (that 12/min is a sufficient cap).

---

## Implementation Status

| Component | Status |
|---|---|
| FCM token acquisition (Android/iOS) | IMPLEMENTED |
| FCM token acquisition (web) | PARTIALLY IMPLEMENTED (token retrieval depends on missing SW; rendering absent — F-PN2) |
| Token registration at startup (`init`) | IMPLEMENTED (gated on `supportsFcm`) |
| Token registration at login | IMPLEMENTED (ungated — F-PN5) |
| Token refresh re-registration | IMPLEMENTED |
| Locale sync on resume / language change | IMPLEMENTED |
| Token revocation at logout (`POST /auth/device-token-revoke`) | IMPLEMENTED (best-effort row delete, scoped to the caller) |
| Other-device token revocation on password write (`POST /auth/device-token-revoke-all`) | IMPLEMENTED (best-effort, keeps caller's row, every other row deleted) |
| Stale registration cleanup (dead-session prune + age fallback) | IMPLEMENTED (`purge_user_devices_dead_sessions()` RPC via the retention job, `USER_DEVICE_RETENTION_DAYS = 30` age purge as fallback) |
| Backend `POST /notify/partner` route + zod validation | IMPLEMENTED |
| JWT auth + rate limiting (30/ip, 12/user per 60 s) | IMPLEMENTED |
| Request signing on notify endpoint | NOT IMPLEMENTED (F-PN10) |
| Partner resolution via `get_accepted_partner` RPC | IMPLEMENTED |
| Server-side localization (server map, it/en) | IMPLEMENTED |
| FCM multicast with 500-token batching | IMPLEMENTED |
| FCM retry (3 attempts, backoff) | IMPLEMENTED |
| Invalid-token cleanup | IMPLEMENTED (global delete — F-PN8) |
| `notification` field for OS system-tray rendering | IMPLEMENTED |
| Client-side ARB localization (8 keys) | IMPLEMENTED (unknown-key gap — F-PN7; emoji param unused for `moodUpdated`) |
| Foreground local-notification rendering | IMPLEMENTED (iOS double-presentation risk — F-PN1) |
| Stable notification IDs (hash of server `notificationId`) | IMPLEMENTED |
| Notification tap → destination navigation | IMPLEMENTED (`onNotificationTap` listener in `MainShellState`) |
| `getNotificationAppLaunchDetails` payload consumption | IMPLEMENTED (read at launch, routes via `onNotificationTap`) |
| `FirebaseMessaging.getInitialMessage` consumption | IMPLEMENTED (read at launch, routes via `onNotificationTap`) |
| Web push rendering | NOT IMPLEMENTED (F-PN2) |
| Desktop (Windows/macOS/Linux) push delivery | NOT IMPLEMENTED (local plugin configured; no remote trigger) |
| Background isolate custom rendering | NOT IMPLEMENTED (dead code — F-PN3) |

---

## Tests

### Backend (`Backend/test/notify.routes.test.js`)

Three negative-path tests exercise `POST /api/v1/notify/partner`:

1. Rejects unauthenticated requests (401, `AUTH-FAIL-002`).
2. Rejects invalid payloads (400, `API-VALIDATION-001`) — sends the legacy `{title, body}` shape, which fails the `notificationKey`-required schema.
3. Rate limit: 12 requests succeed, the 13th is blocked (429, `SEC-BLOCK-001`).

`Backend/test/auth.routes.test.js` covers the token lifecycle endpoints: the `POST /auth/device-token-revoke` delete is asserted to be scoped by both `device_token` and `user_id`, a DB failure surfaces `500 DB-WRITE-001`, and a malformed token is rejected with `400 API-VALIDATION-001`. `POST /auth/device-token-revoke-all` is asserted to delete every row but the one whose token is in the body (`eq user_id`, `neq device_token`), with the same failure and validation cases; `POST /auth/device-token` is asserted to register the row with the caller's `session_id` so the retention sweep can prune it later. The retention sweep itself (`Backend/test/retentionJob.test.js`) asserts the job calls `purge_user_devices_dead_sessions()` and still ages out unrefreshed rows, and `supabase/test/prune_user_devices_dead_sessions.test.sql` proves the RPC keeps live/sessionless rows and deletes gone/expired-session rows.

The `sendNotificationController` is fully mocked — no test covers the real dispatch, FCM multicast, retry/backoff, token cleanup, locale grouping, invalid-token deletion, or `resolveNotificationTarget`. The payloads in the tests predate the `notificationKey` schema migration and pass only because validation rejects the legacy shape before the controller runs.

### Flutter

`Flutter/test/logout_device_token_revoke_test.dart` covers the client half of the revocation: `logout()` issues the revoke **before** `signOut()`, skips it when no session or no token exists, and still completes the teardown when the revoke fails or never answers (bounded by the injected timeout). `Flutter/test/api_service_test.dart` asserts the revoke's `401` does not re-enter the `onSessionExpired` logout callback.

No tests reference `NotificationService`, `onNotificationTap`, `showRemoteMessage`, `_localizeNotification`, or `_notificationId` (grep of `test/`).

**Not covered**: FCM token acquisition and rotation, permission flows, foreground/background rendering, stable-ID hashing, tap/launch detection, iOS double-presentation (F-PN1), and web behavior (F-PN2).

---

## Notes

- **Fire-and-forget**: every repository notification is `unawaited(notifyPartnerOnce(...))` and creates a transient `ApiService` (`base_repository.dart:167`). Failures are logged with `AnsiLogger` only; there is no retry, queue, or offline-outbox. Mutation visibility is instead guaranteed by Supabase Realtime echoes.
- **iOS push certificates**: the OS FCM flow (background-killed) requires APNs credentials configured in Firebase; they are assumed by the backend config and not verifiable from code.
- **`user_devices` live schema**: contains `locale`, `updated_at` and `session_id` columns, which are missing from the schema-reference skill (`supabase-schema/SKILL.md`) — that table predates these columns. The live `information_schema` is authoritative.
- **Cross-doc references**:
  - Navigation **F-N5**: notification taps never navigate (this section and `navigation/doc.md:332-338`).
  - Storage **F-SC4** (resolved): `app_language_code` is preserved across logout (`StorageService.clearAll()` re-persists it), so notification localization keeps working after re-login.
  - Architecture **F11**: partnership rejection fires no notification (functional asymmetry).
  - Realtime: mutations that trigger notifications also flow back over the channel — no double-processing arises there (realtime doc, self-echo note).
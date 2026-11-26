# JustUS — Fixing Phase · Master Todo List

> **Purpose**: the live worklist for verified defects. Everything already closed is archived in [`docs/fixing-phase-log.md`](docs/fixing-phase-log.md) (→ Outcome by phase, → Item index, → Decisions of record).
> **This file is tracked and committed with each fix.** Rules for working an item: `.agents/skills/fix-workflow/SKILL.md`.
> **How to use**: tick `[ ]` → `[x]` as you complete an item. Each item lists the source doc(s), target `file:line`, the exact defect, the concrete fix and acceptance criteria.
> **Finding-ID prefixes**: `17.x` media delivery, `18.x` retention/backend safety, `21.x` schema/RLS/DB invariants, `22.x` docs/dead code, `23.x` regression tests, `24.x` first-use correctness/security, `25.x` validation and CI.
>
> **Priority tags**:
> - 🔴 `CRITICAL` — breaks core flows or leaks data for real users
> - 🟠 `HIGH` — significant functional defect / security gap
> - 🟡 `MEDIUM` — degraded UX / correctness under specific conditions
> - 🟢 `LOW` — cleanup, dead code, docs, test coverage

**Latest audit baseline (2026-11-24, branch `dev`)**: Flutter analysis clean and **439 tests passed**; `Backend/npm test` **305 passed / 27 suites**, lint 0 errors / 4 warnings; backend syntax and circular-dependency checks passed; duplication scan exited 0 (with reported clones). `npm run validate` could not start in this Windows PowerShell environment because `bash` is unavailable. SQL scripts were not run locally (no `bash` or `psql`); read-only checks against the linked Supabase project are documented in the audit. The Android debug build did not complete with the installed JDK 26; a build on the CI's JDK 21 and a signed release build remain unverified.

---

## Phase 0 — Ground truth & safety net

- [ ] **0.1 Re-run the baseline before touching anything**
  - Commands: `cd Flutter && flutter analyze && flutter test`; `cd Backend && npm test && npm run check && npm run madge:circular`; root `npm run scan:duplicates`.
  - Latest observed: 439 Flutter tests pass and analysis is clean; 305 backend tests / 27 suites pass, lint has 0 errors / 4 warnings; syntax, circular-dependency and duplication commands exit 0.
  - `npm run validate` currently stops before checks on this Windows host because it invokes `bash`; SQL tests were not run locally.
  - Acceptance: the baseline is reproducible in the chosen CI environment, including SQL tests, and any runner limitations are resolved or documented.

- [ ] **0.2 Confirm the migration/apply path before any SQL item**
  - `supabase/schemas/**` is the source of truth; there are no tracked migrations. Applying a schema change means `npx supabase@3.4.0 db query --remote --yes --file <script>.sql` (fix-workflow §1.9).
  - Acceptance: the linked project is reachable, or every Phase 21 item is explicitly left `Unverified` with the query that still needs to run.

---
## Phase 25 — Hand rewiew of app

### 25.1 Prevent MainShell from redirecting to PartnerScreen after logout (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-26, on `dev`) — `MainShell.build()` now redirects only when `isLoggedIn && !hasPartner`, and the post-frame callback revalidates both flags (and `mounted`) before navigating, so a stale callback cannot redirect a logged-out user (`Flutter/lib/features/home/screens/main_shell.dart:130-137`). · **Verification**: `flutter analyze` clean; `flutter test` 454 pass, including the 3 new tests in `Flutter/test/main_shell_partner_redirect_test.dart` (the logout and stale-callback tests both fail against the pre-fix code). · **Residual**: 25.2 (logout navigation still depends on the caller's `BuildContext` lifecycle) remains open and out of scope.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/home/screens/main_shell.dart:130-147, Flutter/lib/features/auth/auth_state.dart (isLoggedIn, hasPartner, logout()), Flutter/lib/shared/utils/auth/logout_utils.dart:39-48, Flutter/lib/features/settings/screens/profile_screen.dart (_logout()), Flutter/test/logout_unconditional_test.dart.
- **Defect**: MainShell.build() redirects to PartnerScreen whenever hasPartner == false, regardless of whether the user is still authenticated. During logout, both isLoggedIn and hasPartner become false, potentially causing a redirect that conflicts with the navigation to LoginScreen. A previously scheduled post-frame callback can also execute after the authentication state changes.
- **Fix**: redirect only when isLoggedIn && !hasPartner. Recheck both conditions inside the post-frame callback before navigating, so a stale callback cannot redirect a logged-out user.
- **Acceptance**: a widget test performs logout from ProfileScreen inside the real MainShell and verifies that the final destination is LoginScreen, never PartnerScreen. Another test verifies that an authenticated user who loses their partner is redirected to PartnerScreen. A previously scheduled redirect must not override logout navigation.

### 25.2 Keep logout navigation independent of caller lifecycle (🟡 MEDIUM)
- [x] **Status**: ✅ FIXED (2026-11-26, on `dev`) — `LogoutUtils.performLogout()` now reads `AuthState` from the caller, awaits `logout()`, then replaces the stack with `AppRoutes.login` through `ErrorHandler.navigatorKey.currentState`; the caller's `context.mounted` gate was removed, so navigation still runs if the initiating screen is disposed mid-teardown (`Flutter/lib/shared/utils/auth/logout_utils.dart:37-47`). · **Verification**: `flutter analyze` clean; `flutter test` 455 pass, including the new `Flutter/test/logout_navigation_lifecycle_test.dart` (fails against the pre-fix code because the disposed caller skipped navigation) and the updated `Flutter/test/logout_unconditional_test.dart`. · **Residual**: if the root navigator is not attached (`navigatorKey.currentState == null`), the redirect is skipped; session-expiry navigation still uses the separate reauth dialog. 25.3–25.5 remain open.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/shared/utils/auth/logout_utils.dart:39-48, Flutter/lib/features/auth/auth_state.dart (logout()), Flutter/lib/features/home/screens/main_shell.dart:130-147, Flutter/lib/main.dart (MaterialApp.navigatorKey), Flutter/test/logout_unconditional_test.dart.
- **Defect**: logout navigation depends on the lifecycle of the BuildContext that initiated it. If the calling screen is disposed during the asynchronous teardown, performLogout() returns without navigating to LoginScreen. This can leave the final navigation destination dependent on competing redirects.
- **Fix**: after authState.logout() completes, navigate through ErrorHandler.navigatorKey.currentState using pushNamedAndRemoveUntil(AppRoutes.login, (route) => false). Do not depend on the original BuildContext or its mounted state after the teardown.
- **Acceptance**: a widget test starts logout, disposes the calling screen while AuthState.logout() is still running, then completes the teardown and verifies that LoginScreen is always the final destination. No previous route remains in the navigation stack.

### 25.3 Prevent PartnerScreen from loading private data without an active session (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Confirmed in the current code: PartnerScreen.initState() schedules all three loading operations without checking authentication. PartnerState.fetchPartnership() and ProfileState.loadProfile() can initiate partnership queries without verifying that a session exists. AuthState.fetchInvitations() has a partial _userId == null guard, but does not check isLoggedIn.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/partnership/screens/partner_screen.dart:25-30 (initial loading), Flutter/lib/features/partnership/partner_state.dart (fetchPartnership, fetchCancellation), Flutter/lib/features/settings/profile_state.dart (loadProfile, _loadProfile, clear), Flutter/lib/features/auth/auth_state.dart (fetchInvitations, _fetchInvitations, logout), Flutter/lib/features/partnership/partnership_repository.dart (getPartnership, getCancellation), supabase/schemas/public/functions/partnership_get_pending_invitations.sql (RPC restricted to authenticated users), Flutter/test/partner_screen_test.dart.
- **Defect**: PartnerScreen starts private-data loading regardless of authentication state. Even after logout, ProfileState and PartnerState can initiate Supabase partnership reads without a valid session. During the logout transition, fetchInvitations() can also run while _userId has not yet been cleared, despite the Supabase session already being invalidated. Pending operations may additionally complete after the session is lost.
- **Fix**: prevent PartnerScreen from starting initial or refresh requests when AuthState.isLoggedIn is false. Add authentication guards to the relevant state-level loading methods so other callers cannot bypass them. Recheck session validity during asynchronous loading, stop subsequent requests after session loss and discard stale results. Preserve the existing cache-generation protection in ProfileState.clear().
- **Acceptance**: opening PartnerScreen without an authenticated session starts no private Supabase requests. Simulating logout during initialization prevents further requests and prevents late responses from repopulating cleared state. Existing authenticated PartnerScreen flows continue to load correctly.

### 25.4 Prevent stale PartnerState requests from restoring cleared data (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — Both defects are confirmed in the current code. handleResult() handles failed results without throwing or indicating failure, so fetchPartnership() continues to fetchCancellation(). PartnerState.clear() does not invalidate pending requests or prevent their results from being applied.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/features/partnership/partner_state.dart:18-58,70-105, Flutter/lib/shared/utils/state/base_state.dart:67-86 (handleResult), Flutter/lib/features/settings/profile_state.dart:41-111,182-192 (generation-based invalidation reference), Flutter/test/partner_state_test.dart.
- **Defect**: fetchPartnership() and refreshFromRealtime() call fetchCancellation() even when getPartnership() returns an error, causing unnecessary requests after the initial lookup has already failed. Additionally, clear() only resets in-memory fields. A pending request can therefore complete afterwards, repopulate _partnershipInfo or _cancellation, and write stale partnership data back to local storage.
- **Fix**: stop the loading sequence when getPartnership() does not return Success, without treating a failed lookup as an empty partnership. Introduce a generation counter, following ProfileState, and invalidate it in clear(). Check the generation after asynchronous operations and before applying results or persisting data, so obsolete requests cannot restore cleared state.
- **Acceptance**: a test makes getPartnership() fail and verifies that getCancellation() is never called. Another starts a pending partnership request, calls clear(), completes the request and verifies that _partnershipInfo, _cancellation and persisted partner data remain cleared. Apply the same invalidation guarantees to realtime refreshes. Existing partnership and cancellation tests continue to pass.

### 25.5 Prevent RealtimeSync from reconnecting or polling after signedOut (🟡 MEDIUM)
- [ ] Status: 🔴 OPEN — Confirmed in the current code: the auth listener handles signedOut like any other event except tokenRefreshed. While _session.userId still contains the previous ID, it can schedule a reconnect. The disconnect path also does not immediately stop polling.
- **Sources**: no doc — current-code review.
- **Files**: Flutter/lib/core/realtime/realtime_connection.dart:49-67,107-116,164-190,193-209,225-263,281-295, Flutter/lib/core/realtime/realtime_sync_service.dart:151-187, Flutter/test/realtime_sync_service_test.dart:340-364.
- **Defect**: signedOut can schedule another subscription attempt before configure(userId: null) updates the session. If the failure counter reaches the fallback threshold, this event can also activate polling and immediately trigger _refreshAll(). An already-running subscribe() can pass its post-await unsubscribe() check because the old user ID is still present. unsubscribe() cancels the reconnect timer but does not stop polling or invalidate pending subscription work.
- **Fix**: handle signedOut as an immediate disconnect: cancel pending debounce and reconnect timers, deactivate polling fallback, invalidate pending subscription attempts and remove the active channel. Prevent reconnects, subscriptions, channel-status callbacks and polling from starting further work while signed out. Re-enable them only when a subsequent authenticated configure() supplies a non-null user ID.
- **Acceptance**: a test emits signedOut while the previous user ID is still configured, before calling configure(userId: null). It verifies immediate channel removal and, after advancing timers beyond the reconnect and polling intervals, no new subscriptions, reconnect attempts or polling refreshes. Also verify that an in-flight subscription cannot create a channel after signedOut, and that a subsequent authenticated configuration can reconnect normally.

### 24.7 Prefill the login email after signup confirmation (🟡 MEDIUM)
- [ ] **Status**: 🔴 OPEN — The mobile signup redirect is configured as justus://auth/callback, but the current auth callback listener does not handle signup confirmation or transfer the confirmed email to LoginScreen. Its email controller starts empty.
- **Sources**: docs/features/authentication/login-registration/doc.md — mandatory email confirmation flow; current-code review.
- **Files**: Flutter/lib/features/auth/auth_state.dart:88-95,172-190, Flutter/lib/features/auth/screens/register_screen.dart:21-28,133-154, Flutter/lib/features/auth/screens/login_screen.dart:20-27,45-53, Flutter/lib/main.dart:191-207 (AuthMessageHost), Flutter/lib/shared/utils/state/base_state.dart:36-48,118-156.
- **Defect**: after the confirmation link reopens the app, the confirmed email is not passed to the login form and no success feedback is displayed. Users must manually enter the same email they used during registration.
- **Fix**: capture the confirmed email from the signup confirmation callback/session and expose it as pending data for LoginScreen. Prefill its email controller and display a localized success toast using the existing AuthState.setMessage() and AuthMessageHost mechanism. Consume the pending email and message once, avoiding repeated notifications or unintended prefilling on later visits.
- **Acceptance**: completing signup confirmation on the same device reopens the app on LoginScreen, with the registered email already filled in and a single success toast. The password remains empty. The behavior works whether the app was already running or had to be launched again, and does not trigger on unrelated auth events.


-- Raw
CORREZIONI DOPO FULL TEST MANUALE:

-- arriva la mail dell'invito, ma se nella mail clicco sul sito justus.serverfede.eu non mi da nulla, infatti da come come errore " CANNOT GET /" non mostrando nulla. servirebbe una pagina statica con delle info (a cui in seguito inseriremo privacy, policy e altre cose)

-- dopo che l'utente ha cliccato l'email per completare la registrazione il sito riapre l'app (se l'utente fa tutto dallo stesso dispositivo). sarebbe bello se dopo il redirect automatico venisse riempito automaticamente il campo email, e un messaggio toast apparisse.

-- in release mode, quando l'utente non ha un partner collegato viene mostrato l'errore generico "Risorsa non trovata", in questo caso si può mostrare "Partner non trovato"

-- in PartnerScreen puoi invitare ("il tuo partner non ha ancora JustUS? Invia un invito) un utente che ha già un account su JustUS, questo non dovrebbe essere permesso, in quanto un utente con l'app già installata potrebbe ricevere una nuova mail per reinstallare l'app.

-- il realtime non aggiorna automaticamente PartnerScreen, quindi un utente per vedere in tempo reale le richieste deve aggiornare forzatamente. (lo stesso anche quando la richiesta viene accettata/rifiutata). e questo rende fa capire uno stato in stallo nel dispositivo che manda la richiesta

-- verificare perché RealtimeSync.configure() viene invocato ripetutamente con gli stessi parametri, senza cambiamenti effettivi di stato. controllare se queste chiamate ridondanti causano riconfigurazioni, sottoscrizioni o riconnessioni Realtime non necessarie.

-- Bucket list in italiano diventa "la nostra lista dei desideri", troppo lungo, optiamo per qualcosa di più corto.

-- nello splash screen iniziale dell'app vorrei qualcosa di diverso, non quel cuore emoji e il nome e basta

-- dopo essere entrato in profile_screen ho ottenuto questo errore sul pulsante per "Richiedi la cancellazione della partnership" eccede i bordi e il pulsante: I/flutter (13683): [ErrorHandler] ┌── AppError ──────────────────────────────
I/flutter (13683): [ErrorHandler] │  code:     LOCAL-UNKNOWN
I/flutter (13683): [ErrorHandler] │  message:  A RenderFlex overflowed by 99 pixels on the right.
I/flutter (13683): [ErrorHandler] │  stack:
I/flutter (13683): #0      main.<anonymous closure>.<anonymous closure> (package:justus/main.dart:44:60)
I/flutter (13683): #1      FlutterError.reportError (package:flutter/src/foundation/assertions.dart:1193:14)
I/flutter (13683): #2      DebugOverflowIndicatorMixin._reportOverflow (package:flutter/src/rendering/debug_overflow_indicator.dart:259:18)
I/flutter (13683): #3      DebugOverflowIndicatorMixin.paintOverflowIndicator (package:flutter/src/rendering/debug_overflow_indicator.dart:329:7)
I/flutter (13683): #4      RenderFlex.paint.<anonymous closure> (package:flutter/src/rendering/flex.dart:1449:7)
I/flutter (13683): #5      RenderFlex.paint (package:flutter/src/rendering/flex.dart:1457:6)
I/flutter (13683): #6      RenderObject._paintWithContext (package:flutter/src/rendering/object.dart:3580:7)
I/flutter (13683): #7      PaintingContext.paintChild (package:flutter/src/rendering/object.dart:265:13)
I/flutter (13683): #8      RenderShiftedBox.paint (package:flutter/src/rendering/shifted_box.dart:98:15)
I/flutter (13683): #9      RenderObject._paintWithContext (package:flutter/src/rendering/object.dart:3580:7)
I/flutter (13683): #10     PaintingContext.paintChild (package:flu
I/flutter (13683): [ErrorHandler] └──────────────────────────────────────────

-- in game_screen nel momento in cui la coppia è appena creata il messaggio è "pronti per una nuova domanda?", e poi viene quasi subito automaticamente cambiato in "Nessuna nuova domanda disponibile". dovremmo cambiare questo comportamento per fare in modo che anche nel coldstart abbiamo il testo "Nessuna nuova domanda disponibile", cosi da risparmiare questo brutto comportamento

-- la schermata dei preferiti, a differenza delle altre (game,mood,bucket,home,bucket) ha sempre un caricamento quando viene cliccata causato da: 
I/flutter (13683): [SupabaseService] ---> REST GET v_drive_dashboard select(*) where(is_favorite=eq.true) order(created_at.desc.nullslast,id.desc.nullslast) limit(30) started...
I/flutter (13683): [SupabaseService] <----- 200 - (1497ms) REST GET v_drive_dashboard select(*) where(is_favorite=eq.true) order(created_at.desc.nullslast,id.desc.nullslast) limit(30), mentre il drive ha: I/flutter (13683): [SupabaseService] ---> RPC POST drive_change_probe body(null) started...
I/flutter (13683): [SupabaseService] <----- 200 - (203ms) RPC POST drive_change_probe body(null)

-- togliere il toogle alle notifiche fa partire due chiamate uguali: 
I/flutter (13683): [ApiService] ---> POST https://justus-dev.serverfede.eu/api/v1/auth/installation-id started...
I/flutter (13683): [ApiService] ---> POST https://justus-dev.serverfede.eu/api/v1/auth/installation-id started...
I/flutter (13683): [ApiService] <----- 200 - (1156ms) POST https://justus-dev.serverfede.eu/api/v1/auth/installation-id
I/flutter (13683): [ApiService] <----- 200 - (1164ms) POST https://justus-dev.serverfede.eu/api/v1/auth/installation-id

-- quando un utente cambia la data dell'anniversario, l'altro utente non lo vede dal realtime ma deve refreshare la pagina (lo stesso vale per il nome visualizzato del partner che viene aggiornato con il realtime solo in profile_screen e non in homepage)

-- dopo aver provato a cancellare una partnership da un account ed averla rifiutata dall'altro l'utente che manda la richiesta rimane in uno stato di stallo e deve uscire e rientrare dall'app per fixare il comportamento, infatti l'app al momento gli dice: non hai nessuna partnership attiva, anche se non è cosi.

-- la prima volta che ho aggiunto un mood ho avuto un bug, infatti risultava nella timeline dove il codice doveva mettere il mese "Nessun mood inserito", anche se era appena stato inserito. un refresh ha fixato tutto.

-- in game_screen il codice continua a far vedere domande all'infinito una volta che sono finite quelle giò giocate. non voglio questo comportamento, piuttosto vorrei una frase onesta che dice "avete terminato tutte le domande, attendete nuovi aggiornamenti".

-- anche se ho usato l'app in release mode, non ho ottenuti dati nelle tabelle logs_x su supabase.

-- quando l'app chiede di scattare una foto, non dobbiamo aggiungere il permesso dell'utente? o è già accettato prima? potremmo aggiungerlo quando chiediamo all'utente di dare il permesso delle notifiche

-- ogni volta che apro o chiudo il selezionatore per foto/video/audio/pdf l'app fa un full refresh, perché?
I/flutter (13683): [RealtimeSync] lifecycle state=AppLifecycleState.inactive foreground=true userId=52
I/FA      (13683): Application backgrounded at: timestamp_millis: 1795653282172
D/WindowOnBackDispatcher(13683): setTopOnBackInvokedCallback (unwrapped): android.app.Activity$$ExternalSyntheticLambda0@e8e2cd1
I/flutter (13683): [RealtimeSync] lifecycle state=AppLifecycleState.resumed foreground=true userId=52
D/InsetsController(13683): hide(ime())
I/ImeTracker(13683): com.fezze.justus:be2efef2: onCancelled at PHASE_CLIENT_ALREADY_HIDDEN
I/flutter (13683): [RealtimeSync] _scheduleReconnect() - attempt=1 delay=846ms refreshAfterSubscribe=true
I/flutter (13683): [RealtimeSync] _scheduleReconnect() - timer fired, calling _subscribe
I/flutter (13683): [RealtimeSync] _subscribe() - subscribing generation=11 userId=52 refreshAfterSubscribe=true
I/flutter (13683): [RealtimeSync] _unsubscribe() - removing channel
I/flutter (13683): [RealtimeSync] channel status=RealtimeSubscribeStatus.closed (stale gen=10, current=11) - ignoring
I/flutter (13683): [RealtimeSync] _unsubscribe() - channel removed
I/flutter (13683): [RealtimeSync] channel status=RealtimeSubscribeStatus.subscribed
I/flutter (13683): [RealtimeSync] _refreshAll() - refreshing all states
I/flutter (13683): [SupabaseService] ---> RPC POST drive_change_probe body(null) started...
I/flutter (13683): [SupabaseService] ---> REST HEAD missyou where(partnership_id=eq.387) started...
I/flutter (13683): [SupabaseService] ---> REST GET bucket_items select(id,text,done,created_at,updated_at,category,partnership_id) where(partnership_id=eq.387) order(created_at.desc.nullslast) limit(50) started...
I/flutter (13683): [SupabaseService] ---> REST GET game_questions select(id,question_code,created_at,game_answers(selected_option,user_id)) where(user_id_a=in.(52,116)) order(created_at.desc.nullslast) limit(5) started...  
I/flutter (13683): [SupabaseService] ---> REST GET game_questions select(id,question_code,status,user_id_a,user_id_b,created_at) where(partnership_id=eq.387, status=neq.both_answered) order(created_at.desc.nullslast) limit(1) started...
I/flutter (13683): [SupabaseService] ---> REST GET moods select(emojis(emoji_char)) where(user_id=in.(52,116)) order(created_at.desc.nullslast) limit(10) started...
I/flutter (13683): [SupabaseService] ---> REST GET moods select(id,user_id,created_at,emojis(emoji_char)) where(user_id=in.(52,116)) order(created_at.desc.nullslast) limit(4) started...
I/flutter (13683): [SupabaseService] ---> REST GET moods select(id,created_at,emojis(emoji_char)) where(user_id=eq.52) order(created_at.desc.nullslast) limit(1) started...
I/flutter (13683): [SupabaseService] ---> REST GET moods select(id,created_at,emojis(emoji_char)) where(user_id=eq.116) order(created_at.desc.nullslast) limit(1) started...
I/flutter (13683): [SupabaseService] ---> RPC POST partnership_get_cancellation body(null) started...
I/flutter (13683): [RealtimeSync] configure called - userId=52 partnerId=116 partnershipId=387
I/om.fezze.justus(13683): Background young concurrent mark compact GC freed 2241KB AllocSpace bytes, 46(2496KB) LOS objects, 49% free, 4839KB/9582KB, paused 1.563ms,5.739ms total 18.013ms
I/flutter (13683): [SupabaseService] <----- 200 - (295ms) RPC POST drive_change_probe body(null)
I/flutter (13683): [SupabaseService] ---> REST GET v_drive_dashboard select(*) order(created_at.desc.nullslast,id.desc.nullslast) limit(30) started...
I/flutter (13683): [SupabaseService] <----- 200 - (292ms) REST GET bucket_items select(id,text,done,created_at,updated_at,category,partnership_id) where(partnership_id=eq.387) order(created_at.desc.nullslast) limit(50)     
I/flutter (13683): [SupabaseService] <----- 200 - (290ms) REST GET game_questions select(id,question_code,status,user_id_a,user_id_b,created_at) where(partnership_id=eq.387, status=neq.both_answered) order(created_at.desc.nullslast) limit(1)
I/flutter (13683): [SupabaseService] <----- 200 - (290ms) REST GET moods select(id,created_at,emojis(emoji_char)) where(user_id=eq.52) order(created_at.desc.nullslast) limit(1)
I/flutter (13683): [SupabaseService] <----- 200 - (295ms) REST GET moods select(emojis(emoji_char)) where(user_id=in.(52,116)) order(created_at.desc.nullslast) limit(10)
I/flutter (13683): [SupabaseService] <----- 200 - (292ms) REST GET moods select(id,created_at,emojis(emoji_char)) where(user_id=eq.116) order(created_at.desc.nullslast) limit(1)
I/flutter (13683): [SupabaseService] <----- 200 - (314ms) REST HEAD missyou where(partnership_id=eq.387)
I/flutter (13683): [SupabaseService] <----- 200 - (300ms) REST GET moods select(id,user_id,created_at,emojis(emoji_char)) where(user_id=in.(52,116)) order(created_at.desc.nullslast) limit(4)
I/flutter (13683): [SupabaseService] ---> REST GET game_questions select(created_at) where(partnership_id=in.(387)) order(created_at.desc.nullslast) limit(1) started...
I/flutter (13683): [SupabaseService] <----- 200 - (312ms) REST GET game_questions select(id,question_code,created_at,game_answers(selected_option,user_id)) where(user_id_a=in.(52,116)) order(created_at.desc.nullslast) limit(5)
I/flutter (13683): [SupabaseService] <----- 200 - (302ms) RPC POST partnership_get_cancellation body(null)
I/flutter (13683): [SupabaseService] ---> REST GET game_answers select(updated_at) where(user_id=in.(52,116)) order(updated_at.desc.nullslast) limit(1) started...
I/flutter (13683): [RealtimeSync] configure called - userId=52 partnerId=116 partnershipId=387
I/flutter (13683): [SupabaseService] <----- 200 - (86ms) REST GET v_drive_dashboard select(*) order(created_at.desc.nullslast,id.desc.nullslast) limit(30)
I/flutter (13683): [SupabaseService] <----- 200 - (107ms) REST GET game_questions select(created_at) where(partnership_id=in.(387)) order(created_at.desc.nullslast) limit(1)
I/flutter (13683): [SupabaseService] <----- 200 - (117ms) REST GET game_answers select(updated_at) where(user_id=in.(52,116)) order(updated_at.desc.nullslast) limit(1)
I/flutter (13683): [RealtimeSync] _refreshAll() - done

-- batch presigned URL generation: Replace the two /media/upload-url requests with one /media/upload-urls request that generates URLs for both the original photo and thumbnail.

-- improve upload logging: Add distinct logs for compression, original photo upload, thumbnail upload, metadata registration and notification. Include duration, file size and upload ID.

-- optimize RealtimeSync: Avoid refreshing all application states after every reconnection. Refresh only what is necessary and prevent redundant subscriptions or refreshes.

-- decouple notifications: Move partner notification dispatch into the backend's media completion flow, using reliable background processing.

-- in drive screen posso solo selezionare foto o video o like, no audio o pdf.

-- posso reagire alle foto solo con un set di 8 emoji predefinite, io vorrei lo stesso emoji picker personalizzabile del mood, possiamo riutilizzare lo stesso.

-- non c'è la possibilità di scaricare gli item dal drive

-- gli oggetti all'interno di cloudflare vengono divisi per userid, non per partnershipId, quindi ogni utente ha il proprio spazio privato, questo non serve, lo spazio deve essere di copia, così tutto è più ordinato.

-- quando provo ad aprire un pdf/audio dall'app non vedo nulla, la sola scritta "file"

-- un file audio viene catalogato come pdf e la miniatura corretta

-- non c'è nessun resize image prima del caricamento, questo deve essere implementato soppratutto per le foto profilo.

## Known non-bugs & deliberate decisions

- **Shared media rate-limit bucket (40/user/min for reads, uploads and deletes)** — deliberate, recorded in `docs/audits/media-delete-audit.md` §F-5. Do not "fix" without a product decision.
- **15 MB pre-compression upload cap** — deliberate (phase 5.4).
- **Fingerprint survives logout** — deliberate (phase 10.1); `docs/app/storage-and-caching/doc.md:51,207` is correct.
- **Notification preference is device-level across accounts** — documented in `storage_service.dart:446-452`; distinct from the background-delivery bug archived as 19.7.
- **Homepage does not use `TabScreenMixin`; Profile is not wired to realtime** — documented in `docs/app/architecture/doc.md:460-464` and `docs/app/state-management/doc.md:140`.
- **`debug_` table/function prefix** — deliberate (phase 10.17).
- **Nonce fail-open, `session_is_live` fail-open, orphan-sweep read-failure skip** — accepted decisions #36, #37, #45 in `docs/fixing-phase-log.md`.
- **Authenticated `SECURITY DEFINER` partnership read RPCs** — the live advisor flags `partnership_get_cancellation()` and `partnership_get_pending_invitations()`, but both functions filter through `user_current_id()` (`users.auth_id = auth.uid()`) and return only the caller's own partnership rows; anonymous execution is revoked. Do not revoke without preserving the client flow.
- **Supabase RLS status** — a read-only live catalog query found RLS enabled on all 26 public tables. This does not replace per-policy behavior tests.
- **Unused-index advisor notices** — not treated as removal tasks: low/zero usage on this project's current traffic is not proof an index is dead.

---

## Not confirmed (do not track as fixes until reproduced)

S6 mood recent chips · S7 first drive tile highlight · S9 302 forwards `Authorization` to R2 · S11 cancellation cleanup race · S12 timeout double-response · S13 idempotency caches errors · S14 custom rate-limit window · S15 logger stdout before sanitization · S16 pre-relationship moods · S17 crafted `drive_items` key (closed by 17.2)· S19 hosted SQL test privileges · S20 `game_questions` FKs without `ON DELETE`